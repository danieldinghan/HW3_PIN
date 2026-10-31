if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
out <- file.path(root, "HW3", "results")
raw <- read.delim(file.path(root, "HW3", "TEJ20261031102337", "20261031102349.txt"),
                  fileEncoding = "UTF-16LE", check.names = FALSE,
                  colClasses = "character")
d <- data.frame(code = sub(" .*", "", raw[["證券代碼"]]),
                date = raw[["年月日"]],
                ret = as.numeric(raw[["報酬率％"]]) / 100,
                value_mntd = as.numeric(raw[["成交值(千元)"]]) / 1000,
                turnover_pct = as.numeric(raw[["週轉率％"]]))
market <- tapply(d$ret, d$date, mean)
d$market_ret <- market[d$date]
sample <- read.csv(file.path(out, "sample_600_proposed.csv"),
                   colClasses = c(code = "character"))
d <- d[d$code %in% sample$code, ]
measure <- function(z) {
  fit <- lm(ret ~ market_ret, data = z)
  liquid_days <- z$value_mntd > 0 & is.finite(z$value_mntd)
  amihud <- abs(z$ret[liquid_days]) / z$value_mntd[liquid_days]
  data.frame(code = z$code[1], n = nrow(z),
             nonsynch_1mr2 = 1 - summary(fit)$r.squared,
             idio_sd = sd(residuals(fit)),
             return_sd = sd(z$ret),
             turnover_mean_pct = mean(z$turnover_pct),
             amihud_n = length(amihud),
             amihud_mean = mean(amihud),
             amihud_median = median(amihud))
}
res <- do.call(rbind, lapply(split(d, d$code), measure))
rownames(res) <- NULL
res <- merge(sample, res, by = "code", sort = FALSE)
write.csv(res, file.path(out, "firm_covariates.csv"), row.names = FALSE)
cat("Stocks", nrow(res), "nonsynch quantiles:\n")
print(quantile(res$nonsynch_1mr2, c(0, .25, .5, .75, 1)))
cat("Spearman log cap vs nonsynch:",
    cor(log(res$cap), res$nonsynch_1mr2, method = "spearman"), "\n")
