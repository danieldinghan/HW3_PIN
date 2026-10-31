if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
out <- file.path(root, "HW3", "results")
paths <- file.path(out, paste0("intraday_daily_", c("02", "03", "04"), ".csv"))
stopifnot(all(file.exists(paths)))
daily <- do.call(rbind, lapply(paths, read.csv,
                                colClasses = c(code = "character")))
daily <- daily[order(daily$code, daily$date), ]
stopifnot(!anyDuplicated(daily[c("code", "date")]))
cat("Intraday stock-days", nrow(daily), "stocks", length(unique(daily$code)),
    "side-volume mismatches", sum(daily$side_volume_mismatch), "\n")

daily$lambda_nonnegative <- ifelse(is.finite(daily$lambda_trade_price),
                                    pmax(daily$lambda_trade_price, 0), NA_real_)
expected_lambda <- function(x) {
  n <- length(x)
  y <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i == 1L) next
    w <- tail(x[max(1L, i - 40L):(i - 1L)], 20L)
    if (sum(is.finite(w)) >= 10L) y[i] <- mean(w[is.finite(w)])
  }
  y
}
daily$lambda_expected <- unlist(lapply(split(daily$lambda_nonnegative, daily$code),
                                        expected_lambda), use.names = FALSE)
# The split above follows the already sorted code/date order.
for (date in unique(daily$date)) {
  ii <- which(daily$date == date & is.finite(daily$lambda_expected))
  if (length(ii) >= 20L) {
    ceiling_95 <- as.numeric(quantile(daily$lambda_expected[ii], .95))
    daily$lambda_expected[ii] <- pmin(daily$lambda_expected[ii], ceiling_95)
  }
}
daily$pi_trade_proxy <- daily$lambda_expected * daily$oib_mntd
daily$pi_abs <- abs(daily$pi_trade_proxy)
write.csv(daily, file.path(out, "intraday_daily_all.csv"), row.names = FALSE)

mean_valid <- function(x) if (sum(is.finite(x)) >= 10L)
  mean(x[is.finite(x)]) else NA_real_
firm_intraday <- aggregate(cbind(aoib, pcm_market_adjusted,
                                  gh_adverse_cost, pi_abs) ~ code,
                            data = daily, FUN = mean_valid, na.action = na.pass)
coverage <- aggregate(cbind(transactions, unclassified, side_volume_mismatch) ~ code,
                      data = daily, FUN = sum)
days <- aggregate(date ~ code, data = daily, FUN = length)
names(days)[2] <- "intraday_days"
firm_intraday <- Reduce(function(a, b) merge(a, b, by = "code"),
                         list(firm_intraday, coverage, days))
firm_intraday$unclassified_fraction <- with(firm_intraday,
                                             unclassified / transactions)
write.csv(firm_intraday, file.path(out, "firm_intraday_measures.csv"),
          row.names = FALSE)
cat("Firm coverage:\n")
print(vapply(firm_intraday[c("aoib", "pcm_market_adjusted",
                             "gh_adverse_cost", "pi_abs")],
             function(x) sum(is.finite(x)), integer(1)))
cat("Intraday days quantiles:\n")
print(quantile(firm_intraday$intraday_days, c(0, .25, .5, .75, 1)))
