if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
out <- file.path(root, "HW3", "results")
for (part in c("02", "03", "04")) {
  path <- file.path(out, paste0("intraday_daily_", part, ".csv"))
  d <- read.csv(path, colClasses = c(code = "character"))
  if ("pcm_denominator_version" %in% names(d)) {
    stopifnot(all(d$pcm_denominator_version == "classified"))
    next
  }
  eligible <- d$transactions - d$unclassified
  numerator <- d$pcm_market_adjusted * d$transactions
  d$pcm_market_adjusted <- ifelse(eligible > 0,
                                   numerator / eligible, NA_real_)
  d$pcm_denominator_version <- "classified"
  stopifnot(all(d$pcm_market_adjusted[is.finite(d$pcm_market_adjusted)] >= 0),
            all(d$pcm_market_adjusted[is.finite(d$pcm_market_adjusted)] <=
                  1 + 1e-8))
  d$pcm_market_adjusted <- pmin(d$pcm_market_adjusted, 1)
  write.csv(d, path, row.names = FALSE)
  cat(part, "corrected PCM denominator; stock-days", nrow(d),
      "unclassified trades", sum(d$unclassified), "\n")
}
