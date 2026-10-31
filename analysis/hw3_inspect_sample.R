script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
daily_path <- file.path(root, "HW3", "TEJ20261031102337", "20261031102349.txt")
d <- read.delim(daily_path, fileEncoding = "UTF-16LE", check.names = FALSE,
                colClasses = "character", na.strings = c("", "."))
d$code <- sub(" .*", "", d[[1]])
d$date <- as.Date(d[[2]], "%Y%m%d")
all_dates <- sort(unique(d$date))
daily_counts <- table(d$code)
complete_codes <- names(daily_counts)[daily_counts == length(all_dates)]
cat("Daily:", nrow(d), "rows;", length(all_dates), "dates;",
    length(unique(d$code)), "stocks;", length(complete_codes), "complete stocks\n")

intraday_codes <- vector("list", 3)
for (i in seq_along(intraday_codes)) {
  path <- file.path(root, "HW3", sprintf("mth2019-%02d.rdata", i + 1))
  e <- new.env(parent = emptyenv())
  object_name <- load(path, envir = e)
  x <- e[[object_name]]
  intraday_codes[[i]] <- unique(as.character(x$StkNo))
  cat(basename(path), "codes:", length(intraday_codes[[i]]), "\n")
  rm(x, e)
  invisible(gc())
}
common <- Reduce(intersect, c(list(complete_codes), intraday_codes))
cat("Complete daily and present in all three intraday files:", length(common), "\n")
first_day <- d[d$date == min(all_dates) & d$code %in% common, ]
first_day$cap <- as.numeric(first_day[["市值(百萬元)"]])
first_day <- first_day[is.finite(first_day$cap) & first_day$cap > 0 &
                         grepl("^[0-9]{4}$", first_day$code), ]
cat("Positive initial cap and four-digit code:", nrow(first_day), "\n")
if (nrow(first_day) >= 600) {
  first_day <- first_day[order(first_day$cap, first_day$code), ]
  first_day$cap_rank <- seq_len(nrow(first_day))
  rank_index <- round(seq(1, nrow(first_day), length.out = 600))
  proposal <- first_day[rank_index, c("code", "cap", "cap_rank")]
  proposal$sample_rank <- seq_len(nrow(proposal))
  cat("Proposed rank-spaced sample:", nrow(proposal), "stocks;",
      "cap range (NTD millions):", paste(range(proposal$cap), collapse = ".."), "\n")
  cat("Cap quantiles (NTD millions):\n")
  print(quantile(proposal$cap, c(0, .25, .5, .75, 1)))
  dir.create(file.path(root, "HW3", "results"), showWarnings = FALSE)
  write.csv(proposal, file.path(root, "HW3", "results", "sample_600_proposed.csv"),
            row.names = FALSE, fileEncoding = "UTF-8")
}
