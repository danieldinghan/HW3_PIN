if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
args <- commandArgs(trailingOnly = TRUE)
target_date <- if (length(args)) as.integer(args[1]) else 20191017L
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
sample <- read.csv(file.path(root, "HW3", "results", "sample_600_proposed.csv"),
                   colClasses = c(code = "character"))
raw_daily <- read.delim(file.path(root, "HW3", "TEJ20261031102337", "20261031102349.txt"),
                        fileEncoding = "UTF-16LE", check.names = FALSE,
                        colClasses = "character")
daily <- raw_daily[raw_daily[["年月日"]] == as.character(target_date), ]
daily$code <- sub(" .*", "", daily[["證券代碼"]])
market_return <- mean(as.numeric(daily[["報酬率％"]]) / 100)
daily$surprise <- as.numeric(daily[["報酬率％"]]) / 100 - market_return
surprise <- setNames(daily$surprise, daily$code)
file_num <- if (target_date < 20190701L) 2L else if (target_date < 20191001L) 3L else 4L
e <- new.env(parent = emptyenv())
object_name <- load(file.path(root, "HW3", sprintf("mth2019-%02d.rdata", file_num)),
                    envir = e)
x <- e[[object_name]]
z <- x[x$MthDate == target_date & as.character(x$StkNo) %in% sample$code &
         x$TrdCode == 0L & x$MthTime < 13330000L, ]
cat("Date", target_date, "retained raw rows", nrow(z), "stocks", length(unique(z$StkNo)), "\n")
rm(x, e)
invisible(gc())

process_stock <- function(y) {
  code <- as.character(y$StkNo[1])
  y <- y[order(y$TrdNo, y$BuySell), ]
  rl <- rle(y$TrdNo)
  ends <- cumsum(rl$lengths)
  starts <- ends - rl$lengths + 1L
  is_buy_record <- y$BuySell == "B"
  ccount <- c(0, cumsum(as.integer(is_buy_record)))
  cvolume_b <- c(0, cumsum(y$MthShr * is_buy_record))
  cvolume_s <- c(0, cumsum(y$MthShr * !is_buy_record))
  bcount <- ccount[ends + 1L] - ccount[starts]
  bvolume <- cvolume_b[ends + 1L] - cvolume_b[starts]
  svolume <- cvolume_s[ends + 1L] - cvolume_s[starts]
  shares <- ifelse(bcount > 0L, bvolume, svolume)
  trd <- data.frame(trdno = rl$values, time = y$MthTime[starts],
                    price = y$MthPr[starts], shares = shares)
  trd <- trd[order(trd$time, trd$trdno), ]
  batch_key <- paste(trd$time, trd$price, sep = "|")
  first <- !duplicated(batch_key)
  batch_price <- trd$price[first]
  batch_dir <- rep(NA_integer_, length(batch_price))
  prev <- NA_real_
  last <- NA_integer_
  for (i in seq_along(batch_price)) {
    if (is.finite(prev)) {
      if (batch_price[i] > prev) last <- 1L
      if (batch_price[i] < prev) last <- -1L
      batch_dir[i] <- last
    }
    prev <- batch_price[i]
  }
  trd$direction <- batch_dir[match(batch_key, batch_key[first])]
  buys <- sum(trd$direction == 1L, na.rm = TRUE)
  sells <- sum(trd$direction == -1L, na.rm = TRUE)
  unexpected <- surprise[[code]]
  medium <- trd$shares >= 1000 & trd$shares <= 9999
  contrarian <- if (is.finite(unexpected) && unexpected < 0)
    trd$direction == 1L else if (is.finite(unexpected) && unexpected > 0)
    trd$direction == -1L else rep(FALSE, nrow(trd))
  data.frame(code = code, date = target_date, raw_rows = nrow(y),
             transactions = nrow(trd), batches = length(batch_price),
             unclassified = sum(is.na(trd$direction)),
             buys = buys, sells = sells,
             buy_shares = sum(trd$shares[trd$direction == 1L], na.rm = TRUE),
             sell_shares = sum(trd$shares[trd$direction == -1L], na.rm = TRUE),
             aoib = if (buys + sells > 0) abs(buys - sells) / (buys + sells) else NA_real_,
             pcm = sum(medium & contrarian, na.rm = TRUE) / nrow(trd),
             surprise = unexpected)
}
res <- do.call(rbind, lapply(split(z, z$StkNo), process_stock))
rownames(res) <- NULL
out <- file.path(root, "HW3", "results")
write.csv(res, file.path(out, sprintf("intraday_pilot_%d.csv", target_date)),
          row.names = FALSE)
cat("Processed", nrow(res), "stocks; 2330 check:\n")
print(res[res$code == "2330", ])
