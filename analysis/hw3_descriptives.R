if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
out <- file.path(root, "HW3", "results")
m <- read.csv(file.path(out, "vcv_monthly.csv"),
              colClasses = c(code = "character"))
stopifnot(length(unique(m$code)) == 600L)
med <- aggregate(vcv_volume_share ~ month, m, median)
cat("Monthly VCV medians:\n")
print(med)
