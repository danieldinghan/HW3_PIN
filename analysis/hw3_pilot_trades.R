if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
code <- 2330L
date <- 20191017L
e <- new.env(parent = emptyenv())
object_name <- load(file.path(root, "HW3", "mth2019-04.rdata"), envir = e)
x <- e[[object_name]]
rows <- which(x$StkNo == code & x$MthDate == date)
y <- x[rows, ]
cat("Raw stock-day rows:", nrow(y), "\n")
cat("TrdCode breakdown:\n")
print(table(y$TrdCode, useNA = "ifany"))
cat("Off-hours rows at 14:30/17:00:",
    sum(y$MthTime %in% c(14300000L, 17000000L)), "\n")
y <- y[y$TrdCode == 0 & y$MthTime < 13330000L, ]
groups <- split(seq_len(nrow(y)), y$TrdNo)
one <- lapply(groups, function(ii) {
  z <- y[ii, ]
  side <- if (any(z$BuySell == "B")) "B" else "S"
  selected <- z[z$BuySell == side, ]
  data.frame(trdno = z$TrdNo[1], time = z$MthTime[1],
             price = z$MthPr[1], shares = sum(selected$MthShr),
             buy_rows = sum(z$BuySell == "B"),
             sell_rows = sum(z$BuySell == "S"))
})
trades <- do.call(rbind, one)
rownames(trades) <- NULL
stopifnot(all(is.finite(trades$shares)), all(trades$shares > 0))
trades <- trades[order(trades$time, trades$trdno), ]
cat("Unique transactions:", nrow(trades), "shares:", sum(trades$shares), "\n")
cat("B/S record patterns:\n")
print(sort(table(paste(trades$buy_rows, trades$sell_rows, sep = "B/S")),
           decreasing = TRUE)[1:8])
batch_key <- paste(trades$time, trades$price, sep = "|")
batch_id <- match(batch_key, unique(batch_key))
batches <- aggregate(cbind(n = rep(1, nrow(trades)), shares = trades$shares),
                     by = list(batch_id = batch_id), FUN = sum)
batch_first <- match(batches$batch_id, batch_id)
batches$time <- trades$time[batch_first]
batches$price <- trades$price[batch_first]
batches <- batches[order(batches$time, batches$batch_id), ]
stopifnot(all(vapply(split(batches$price, batches$time),
                     function(p) length(unique(p)) == 1L, logical(1))))
batches$direction <- NA_integer_
last_direction <- NA_integer_
previous_price <- NA_real_
for (j in seq_len(nrow(batches))) {
  price <- batches$price[j]
  if (is.finite(previous_price)) {
    if (price > previous_price) last_direction <- 1L
    if (price < previous_price) last_direction <- -1L
    batches$direction[j] <- last_direction
  }
  previous_price <- price
}
cat("Batches:", nrow(batches), "classified:", sum(!is.na(batches$direction)),
    "unclassified:", sum(is.na(batches$direction)), "\n")
cat("Buy/sell transaction counts:",
    sum(batches$n[batches$direction == 1L], na.rm = TRUE),
    sum(batches$n[batches$direction == -1L], na.rm = TRUE), "\n")
cat("Buy/sell shares:",
    sum(batches$shares[batches$direction == 1L], na.rm = TRUE),
    sum(batches$shares[batches$direction == -1L], na.rm = TRUE), "\n")
out <- file.path(root, "HW3", "results")
dir.create(out, showWarnings = FALSE)
write.csv(batches, file.path(out, "pilot_2330_20191017_batches.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
