if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !args[1] %in% c("02", "03", "04"))
  stop("Usage: Rscript analysis/hw3_intraday_batch.R 02|03|04")
part <- args[1]
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
out <- file.path(root, "HW3", "results")
sample <- read.csv(file.path(out, "sample_600_proposed.csv"),
                   colClasses = c(code = "character"))
raw_daily <- read.delim(file.path(root, "HW3", "TEJ20261031102337", "20261031102349.txt"),
                        fileEncoding = "UTF-16LE", check.names = FALSE,
                        colClasses = "character")
raw_daily$code <- sub(" .*", "", raw_daily[["證券代碼"]])
raw_daily$return <- as.numeric(raw_daily[["報酬率％"]]) / 100
e <- new.env(parent = emptyenv())
object_name <- load(file.path(root, "HW3", paste0("mth2019-", part, ".rdata")),
                    envir = e)
x <- e[[object_name]]
stock_runs <- rle(x$StkNo)
if (anyDuplicated(stock_runs$values))
  stop("Source is not stock-contiguous; explicit stock indexing is required")
ends <- cumsum(stock_runs$lengths)
starts <- ends - stock_runs$lengths + 1L
market_return <- tapply(raw_daily$return, raw_daily[["年月日"]], mean)
raw_daily$surprise <- raw_daily$return - market_return[raw_daily[["年月日"]]]
surprise_lookup <- setNames(raw_daily$surprise,
                            paste(raw_daily$code, raw_daily[["年月日"]], sep = "|"))
cat("Loaded", part, "with", length(starts), "stock blocks\n")
flush.console()

process_stock <- function(y, target_date, surprise) {
  code <- as.character(y$StkNo[1])
  y <- y[order(y$TrdNo, y$BuySell), ]
  rl <- rle(y$TrdNo)
  ends <- cumsum(rl$lengths)
  starts <- ends - rl$lengths + 1L
  is_b <- y$BuySell == "B"
  c_b <- c(0, cumsum(as.integer(is_b)))
  c_s <- c(0, cumsum(as.integer(!is_b)))
  v_b <- c(0, cumsum(y$MthShr * is_b))
  v_s <- c(0, cumsum(y$MthShr * !is_b))
  b_count <- c_b[ends + 1L] - c_b[starts]
  s_count <- c_s[ends + 1L] - c_s[starts]
  b_volume <- v_b[ends + 1L] - v_b[starts]
  s_volume <- v_s[ends + 1L] - v_s[starts]
  shares <- ifelse(b_count > 0L, b_volume, s_volume)
  mismatch <- sum(b_count > 0L & s_count > 0L & b_volume != s_volume)
  trd <- data.frame(trdno = rl$values, time = y$MthTime[starts],
                    price = y$MthPr[starts], shares = shares)
  trd <- trd[order(trd$time, trd$trdno), ]
  key <- paste(trd$time, trd$price, sep = "|")
  first <- !duplicated(key)
  prices <- trd$price[first]
  dir <- rep(NA_integer_, length(prices))
  prev <- NA_real_
  last <- NA_integer_
  for (i in seq_along(prices)) {
    if (is.finite(prev)) {
      if (prices[i] > prev) last <- 1L
      if (prices[i] < prev) last <- -1L
      dir[i] <- last
    }
    prev <- prices[i]
  }
  trd$direction <- dir[match(key, key[first])]
  batch_id <- match(key, key[first])
  batch_shares <- as.numeric(rowsum(trd$shares, batch_id, reorder = TRUE))
  gh_z0 <- NA_real_
  gh_cost <- NA_real_
  if (length(prices) >= 32L) {
    gh <- data.frame(dp = diff(prices), q = dir[-1L],
                     dq = diff(dir),
                     qv = dir[-1L] * batch_shares[-1L] / 1e6,
                     dqv = diff(dir * batch_shares / 1e6))
    gh <- gh[complete.cases(gh), ]
    if (nrow(gh) >= 30L) {
      fit <- lm(dp ~ dq + dqv + q + qv, data = gh)
      gh_z0 <- unname(coef(fit)["q"])
      z1 <- unname(coef(fit)["qv"])
      gh_cost <- 2 * (gh_z0 + z1 * median(batch_shares) / 1e6)
    }
  }
  minute <- trd$time %/% 1000000L * 60L +
    (trd$time %/% 10000L) %% 100L
  bar <- (minute - 540L) %/% 5L
  bar_rows <- split(seq_len(nrow(trd)), bar)
  bar_id <- as.integer(names(bar_rows))
  bar_close <- vapply(bar_rows, function(ii) tail(trd$price[ii], 1L), numeric(1))
  bar_flow <- vapply(bar_rows, function(ii)
    sum(trd$direction[ii] * trd$shares[ii] * trd$price[ii] / 1e6,
        na.rm = TRUE), numeric(1))
  consecutive <- diff(bar_id) == 1L
  bar_return <- diff(log(bar_close))
  flow <- tail(bar_flow, -1L)
  valid_bar <- consecutive & is.finite(bar_return) & is.finite(flow)
  lambda_trade <- if (sum(valid_bar) >= 10L && sd(flow[valid_bar]) > 0)
    unname(coef(lm(bar_return[valid_bar] ~ flow[valid_bar]))[2]) else NA_real_
  oib_mntd <- sum(trd$direction * trd$shares * trd$price / 1e6, na.rm = TRUE)
  buys <- sum(trd$direction == 1L, na.rm = TRUE)
  sells <- sum(trd$direction == -1L, na.rm = TRUE)
  unexpected <- surprise
  medium <- trd$shares >= 1000 & trd$shares <= 9999
  contrarian <- if (is.finite(unexpected) && unexpected < 0)
    trd$direction == 1L else if (is.finite(unexpected) && unexpected > 0)
    trd$direction == -1L else rep(FALSE, nrow(trd))
  data.frame(code = code, date = target_date, raw_rows = nrow(y),
             transactions = nrow(trd), batches = length(prices),
             unclassified = sum(is.na(trd$direction)),
             side_volume_mismatch = mismatch,
             buys = buys, sells = sells,
             buy_shares = sum(trd$shares[trd$direction == 1L], na.rm = TRUE),
             sell_shares = sum(trd$shares[trd$direction == -1L], na.rm = TRUE),
             aoib = if (buys + sells > 0) abs(buys - sells) / (buys + sells) else NA_real_,
             pcm_market_adjusted = if (buys + sells > 0L)
               sum(medium & contrarian, na.rm = TRUE) / (buys + sells)
               else NA_real_,
             pcm_denominator_version = "classified",
             gh_style_q = gh_z0, gh_adverse_cost = gh_cost,
             lambda_trade_price = lambda_trade,
             lambda_bars = sum(valid_bar), oib_mntd = oib_mntd,
             surprise = unexpected)
}

result <- vector("list", length(starts))
for (j in seq_along(starts)) {
  code <- as.character(stock_runs$values[j])
  if (!code %in% sample$code) next
  z <- x[starts[j]:ends[j], ]
  z <- z[z$TrdCode == 0L & z$MthTime < 13330000L, ]
  by_date <- split(z, z$MthDate)
  result[[j]] <- do.call(rbind, lapply(names(by_date), function(date) {
    process_stock(by_date[[date]], as.integer(date),
                  surprise_lookup[[paste(code, date, sep = "|")]])
  }))
  if (j %% 50L == 0L || j == length(starts)) {
    cat(part, "processed", j, "/", length(starts), "stock blocks; last code", code, "\n")
    flush.console()
  }
}
res <- do.call(rbind, result)
rownames(res) <- NULL
path <- file.path(out, paste0("intraday_daily_", part, ".csv"))
write.csv(res, path, row.names = FALSE)
cat("Saved", nrow(res), "stock-days to", path, "\n")
