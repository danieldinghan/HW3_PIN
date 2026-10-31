if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L || length(args) > 2L || !args[1] %in% c("02", "03", "04"))
  stop("Usage: Rscript analysis/hw3_vpin_batch.R 02|03|04 [stock code]")
part <- args[1]
only_code <- if (length(args) == 2L) args[2] else NULL
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
out <- file.path(root, "HW3", "results")
sample <- read.csv(file.path(out, "sample_600_proposed.csv"),
                   colClasses = c(code = "character"))
if (!is.null(only_code)) sample <- sample[sample$code == only_code, ]
raw_daily <- read.delim(file.path(root, "HW3", "TEJ20261031102337", "20261031102349.txt"),
                        fileEncoding = "UTF-16LE", check.names = FALSE,
                        colClasses = "character")
raw_daily$code <- sub(" .*", "", raw_daily[["證券代碼"]])
first20 <- head(sort(unique(raw_daily[["年月日"]])), 20L)
calibration_end <- as.integer(tail(first20, 1L))
cal <- raw_daily[raw_daily[["年月日"]] %in% first20, ]
cal$shares <- as.numeric(cal[["成交量(千股)"]]) * 1000
average_volume <- tapply(cal$shares, cal$code, mean)
e <- new.env(parent = emptyenv())
object_name <- load(file.path(root, "HW3", paste0("mth2019-", part, ".rdata")),
                    envir = e)
x <- e[[object_name]]
stock_runs <- rle(x$StkNo)
if (anyDuplicated(stock_runs$values)) stop("Stock blocks are not contiguous")
ends <- cumsum(stock_runs$lengths)
starts <- ends - stock_runs$lengths + 1L
cat("Loaded", part, "stock blocks", length(starts), "\n")
flush.console()

dedup_day <- function(y) {
  y <- y[order(y$TrdNo, y$BuySell), ]
  rl <- rle(y$TrdNo)
  ends <- cumsum(rl$lengths)
  starts <- ends - rl$lengths + 1L
  is_b <- y$BuySell == "B"
  cb <- c(0, cumsum(as.integer(is_b)))
  vb <- c(0, cumsum(y$MthShr * is_b))
  vs <- c(0, cumsum(y$MthShr * !is_b))
  bc <- cb[ends + 1L] - cb[starts]
  bvol <- vb[ends + 1L] - vb[starts]
  svol <- vs[ends + 1L] - vs[starts]
  trd <- data.frame(date = y$MthDate[starts], time = y$MthTime[starts],
                    trdno = rl$values, price = y$MthPr[starts],
                    shares = ifelse(bc > 0L, bvol, svol))
  trd[order(trd$time, trd$trdno), ]
}

vpin_stock <- function(y, code) {
  v_bucket <- unname(average_volume[[code]]) / 50
  if (!is.finite(v_bucket) || v_bucket <= 0) return(NULL)
  y <- y[y$TrdCode == 0L & y$MthTime < 13330000L, ]
  by_date <- split(y, y$MthDate)
  trd <- do.call(rbind, lapply(by_date, dedup_day))
  trd <- trd[order(trd$date, trd$time, trd$trdno), ]
  minute <- trd$time %/% 1000000L * 60L +
    (trd$time %/% 10000L) %% 100L
  key <- paste(trd$date, minute, sep = "|")
  rl <- rle(key)
  ends <- cumsum(rl$lengths)
  starts <- ends - rl$lengths + 1L
  cvol <- c(0, cumsum(trd$shares))
  volume <- cvol[ends + 1L] - cvol[starts]
  price <- trd$price[ends]
  date <- trd$date[ends]
  time <- trd$time[ends]
  change <- c(NA_real_, diff(price))
  change[c(TRUE, diff(date) != 0)] <- NA_real_
  sigma <- rep(NA_real_, length(change))
  if (length(change) > 20L) {
    value <- ifelse(is.finite(change), change, 0)
    cs <- c(0, cumsum(value))
    cs2 <- c(0, cumsum(value * value))
    cc <- c(0, cumsum(as.integer(is.finite(change))))
    i <- 21:length(change)
    n <- cc[i] - cc[i - 20L]
    s <- cs[i] - cs[i - 20L]
    s2 <- cs2[i] - cs2[i - 20L]
    good <- n >= 10L
    variance <- pmax((s2[good] - s[good]^2 / n[good]) /
                       (n[good] - 1L), 0)
    sigma[i[good]] <- sqrt(variance)
  }
  bvc_buy <- volume / 2
  valid <- is.finite(change) & is.finite(sigma) & sigma > 0
  bvc_buy[valid] <- volume[valid] * pnorm(change[valid] / sigma[valid])
  cum_volume <- cumsum(volume)
  cum_buy <- cumsum(bvc_buy)
  k <- floor(tail(cum_volume, 1L) / v_bucket)
  if (k < 50L) return(NULL)
  boundaries <- seq_len(k) * v_bucket
  buy_at <- approx(c(0, cum_volume), c(0, cum_buy),
                   xout = c(0, boundaries), ties = "ordered")$y
  buy_bucket <- diff(buy_at)
  imbalance <- abs(2 * buy_bucket - v_bucket) / v_bucket
  vpin <- as.numeric(stats::filter(imbalance, rep(1 / 50, 50), sides = 1))
  idx <- findInterval(boundaries, cum_volume)
  exact <- idx > 0L & cum_volume[pmax(idx, 1L)] == boundaries
  idx[!exact] <- idx[!exact] + 1L
  idx <- pmin(idx, length(cum_volume))
  buckets <- data.frame(code = code, bucket = seq_len(k), date = date[idx],
                        time = time[idx], vpin = vpin,
                        imbalance = imbalance)
  buckets <- buckets[buckets$date > calibration_end & is.finite(buckets$vpin), ]
  if (!nrow(buckets)) return(NULL)
  daily <- aggregate(vpin ~ code + date, buckets, mean)
  daily$bvc_price_change <- "raw_price"
  list(daily = daily, buckets = if (code == "2330") buckets else NULL)
}

daily_result <- vector("list", length(starts))
case_buckets <- NULL
for (j in seq_along(starts)) {
  code <- as.character(stock_runs$values[j])
  if (!code %in% sample$code) next
  y <- x[starts[j]:ends[j], ]
  ans <- vpin_stock(y, code)
  if (!is.null(ans)) {
    daily_result[[j]] <- ans$daily
    if (!is.null(ans$buckets)) case_buckets <- ans$buckets
  }
  if (j %% 100L == 0L || j == length(starts)) {
    cat(part, "VPIN processed", j, "/", length(starts), "stock blocks\n")
    flush.console()
  }
}
res <- do.call(rbind, daily_result)
rownames(res) <- NULL
suffix <- if (is.null(only_code)) part else paste0(part, "_", only_code, "_test")
write.csv(res, file.path(out, paste0("vpin_daily_", suffix, ".csv")), row.names = FALSE)
if (!is.null(case_buckets))
  write.csv(case_buckets, file.path(out, paste0("vpin_2330_buckets_", suffix, ".csv")),
            row.names = FALSE)
cat("Saved VPIN", nrow(res), "stock-days for part", part, "\n")
