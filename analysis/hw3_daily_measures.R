if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
raw <- read.delim(file.path(root, "HW3", "TEJ20261031102337", "20261031102349.txt"),
                  fileEncoding = "UTF-16LE", check.names = FALSE,
                  colClasses = "character", na.strings = c("", "."))
d <- data.frame(code = sub(" .*", "", raw[["證券代碼"]]),
                date = as.Date(raw[["年月日"]], "%Y%m%d"),
                ret = as.numeric(raw[["報酬率％"]]) / 100,
                turnover_pct = as.numeric(raw[["週轉率％"]]),
                value = as.numeric(raw[["成交值(千元)"]]),
                cap = as.numeric(raw[["市值(百萬元)"]]))
stopifnot(!anyDuplicated(d[c("code", "date")]),
          all(is.finite(d$ret)), all(is.finite(d$turnover_pct)),
          all(is.finite(d$value)), all(is.finite(d$cap)))
share_raw <- read.delim(file.path(root, "HW3", "TEJ20261031123205",
                                 "20261031123216.txt"),
                        fileEncoding = "UTF-16LE", check.names = FALSE,
                        colClasses = "character")
share_code <- sub(" .*", "", share_raw[["證券代碼"]])
share_key <- paste(share_code, share_raw[["年月日"]], sep = "|")
daily_key <- paste(d$code, format(d$date, "%Y%m%d"), sep = "|")
stopifnot(!anyDuplicated(share_key), length(share_key) == length(daily_key),
          setequal(share_key, daily_key))
share_pct <- suppressWarnings(as.numeric(share_raw[["成交值比重％"]]))
d$tej_share_pct <- share_pct[match(daily_key, share_key)]
good_denominator <- is.finite(d$tej_share_pct) & d$tej_share_pct >= .05 &
  d$value > 0
implied_total <- d$value[good_denominator] * 100 /
  d$tej_share_pct[good_denominator]
denominator <- tapply(implied_total, d$date[good_denominator], median)
denominator_spread <- tapply(implied_total, d$date[good_denominator],
                             function(x) IQR(x) / median(x))
stopifnot(length(denominator) == length(unique(d$date)),
          all(is.finite(denominator)), max(denominator_spread) < .01)
d$share_used_pct <- d$tej_share_pct
d$share_filled <- !is.finite(d$tej_share_pct) |
  (d$tej_share_pct == 0 & d$value > 0)
d$share_used_pct[d$share_filled] <- d$value[d$share_filled] * 100 /
  denominator[as.character(d$date[d$share_filled])]
stopifnot(all(is.finite(d$share_used_pct)), all(d$share_used_pct >= 0))
cat("TEJ share field: missing", sum(!is.finite(d$tej_share_pct)),
    "rounded zeros with positive value", sum(d$tej_share_pct == 0 & d$value > 0,
                                               na.rm = TRUE),
    "median implied-denominator IQR/median", median(denominator_spread), "\n")
sample <- read.csv(file.path(root, "HW3", "results", "sample_600_proposed.csv"),
                   colClasses = c(code = "character"))
stopifnot(nrow(sample) == 600L, !anyDuplicated(sample$code))
d <- d[d$code %in% sample$code, ]
d <- d[order(d$code, d$date), ]

vcv <- function(x, min_days = 30L) {
  x <- x[is.finite(x)]
  if (length(x) >= min_days && mean(x) > 0) sd(x) / mean(x) else NA_real_
}
d$month <- format(d$date, "%Y-%m")
vcv_monthly <- aggregate(share_used_pct ~ code + month, data = d,
                         FUN = function(x) vcv(x, 10L))
names(vcv_monthly)[3] <- "vcv_volume_share"
vcv_period <- aggregate(share_used_pct ~ code, data = d, FUN = vcv)
names(vcv_period)[2] <- "vcv_162d"
vcv_period$period <- "2019-04-09_to_2019-11-29"
direct <- tapply(d$tej_share_pct, d$code, vcv)
observed <- tapply(is.finite(d$tej_share_pct), d$code, sum)
filled <- tapply(d$share_filled, d$code, sum)
vcv_period$vcv_tej_direct_only <- unname(direct[vcv_period$code])
vcv_period$tej_observed_days <- unname(observed[vcv_period$code])
vcv_period$tej_filled_days <- unname(filled[vcv_period$code])
vcv_period$tej_filled_fraction <- vcv_period$tej_filled_days / 162
cat("VCV direct-only finite", sum(is.finite(vcv_period$vcv_tej_direct_only)),
    "TEJ share filled finite", sum(is.finite(vcv_period$vcv_162d)), "\n")

fit_c2 <- function(z) {
  z <- z[order(z$date), ]
  lead_return <- c(tail(z$ret, -1L), NA_real_)
  x <- data.frame(y = lead_return, ret = z$ret,
                  interaction = z$ret * z$turnover_pct)
  x <- x[complete.cases(x), ]
  if (nrow(x) < 100L || sd(x$interaction) == 0)
    return(data.frame(n = nrow(x), c2 = NA_real_, se = NA_real_, t = NA_real_,
                      r2 = NA_real_))
  fit <- lm(y ~ ret + interaction, data = x)
  coef <- summary(fit)$coefficients
  data.frame(n = nrow(x), c2 = coef["interaction", "Estimate"],
             se = coef["interaction", "Std. Error"],
             t = coef["interaction", "t value"],
             r2 = summary(fit)$r.squared)
}
c2 <- do.call(rbind, lapply(split(d, d$code), fit_c2))
c2$code <- rownames(c2)
rownames(c2) <- NULL
c2 <- c2[, c("code", "n", "c2", "se", "t", "r2")]

out <- file.path(root, "HW3", "results")
vcv_daily <- d[c("code", "date", "value", "tej_share_pct",
                 "share_used_pct", "share_filled")]
vcv_daily$denominator_thousand_ntd <- unname(
  denominator[as.character(vcv_daily$date)])
write.csv(vcv_daily, file.path(out, "vcv_daily_share.csv"), row.names = FALSE)
write.csv(vcv_monthly, file.path(out, "vcv_monthly.csv"), row.names = FALSE)
write.csv(vcv_period, file.path(out, "vcv_period.csv"), row.names = FALSE)
write.csv(c2, file.path(out, "c2_raw_turnover_pct.csv"), row.names = FALSE)
cat("Monthly VCV:", nrow(vcv_monthly), "rows; period VCV:", nrow(vcv_period),
    "firms; C2:", sum(is.finite(c2$c2)), "firms\n")
cat("Period VCV quantiles:\n")
print(quantile(vcv_period$vcv_162d, c(0, .25, .5, .75, 1), na.rm = TRUE))
cat("C2 quantiles:\n")
print(quantile(c2$c2, c(0, .25, .5, .75, 1), na.rm = TRUE))
