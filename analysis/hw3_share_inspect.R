invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
new <- read.delim("HW3/TEJ20261031123205/20261031123216.txt",
                  fileEncoding = "UTF-16LE", check.names = FALSE,
                  colClasses = "character")
old <- read.delim("HW3/TEJ20261031102337/20261031102349.txt",
                  fileEncoding = "UTF-16LE", check.names = FALSE,
                  colClasses = "character")
new$code <- sub(" .*", "", new[["證券代碼"]])
old$code <- sub(" .*", "", old[["證券代碼"]])
z <- merge(new[c("code", "年月日", "成交值比重％")],
           old[c("code", "年月日", "成交值(千元)")],
           by = c("code", "年月日"))
z$share <- suppressWarnings(as.numeric(z[["成交值比重％"]]))
z$value <- as.numeric(z[["成交值(千元)"]])
cat("joined", nrow(z), "new", nrow(new), "old", nrow(old), "\n")
cat("missing share + zero value", sum(!is.finite(z$share) & z$value == 0), "\n")
cat("missing share + positive value", sum(!is.finite(z$share) & z$value > 0), "\n")
cat("zero share + positive value", sum(z$share == 0 & z$value > 0,
                                       na.rm = TRUE), "\n")
cat("date sums of share percent:\n")
print(summary(tapply(z$share, z[["年月日"]], sum, na.rm = TRUE)))
cat("value with missing share:\n")
print(summary(z$value[!is.finite(z$share)]))
cat("positive value with missing share examples:\n")
print(head(z[!is.finite(z$share) & z$value > 0,
             c("code", "年月日", "成交值比重％", "成交值(千元)")]))
cat("largest positive value with missing share:\n")
print(head(z[order(-ifelse(!is.finite(z$share), z$value, -1)),
             c("code", "年月日", "成交值比重％", "成交值(千元)")]))
sample <- read.csv("HW3/results/sample_600_final.csv",
                   colClasses = c(code = "character"))
a <- z[z$code %in% sample$code, ]
cat("sample missing share", sum(!is.finite(a$share)),
    "zeros", sum(a$share == 0, na.rm = TRUE), "\n")
print(summary(tapply(a$share, a$code, function(x) sum(is.finite(x)))))
cat("sample all-zero or missing codes:\n")
print(names(which(tapply(a$share, a$code,
                         function(x) sum(x > 0, na.rm = TRUE) == 0L))))
positive <- z[is.finite(z$share) & z$share >= .05 & z$value > 0, ]
positive$implied_total <- positive$value * 100 / positive$share
spread <- tapply(positive$implied_total, positive[["年月日"]],
                 function(x) IQR(x) / median(x))
cat("implied denominator IQR/median:\n")
print(summary(spread))
cat("20190409 implied denominator quantiles:\n")
print(quantile(positive$implied_total[positive[["年月日"]] == "20190409"],
               c(0, .25, .5, .75, 1)))
