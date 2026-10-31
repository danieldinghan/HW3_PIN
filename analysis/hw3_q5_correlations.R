if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
out <- file.path(root, "HW3", "results")
d <- read.csv(file.path(out, "firm_all_q3.csv"),
              colClasses = c(code = "character"))
stopifnot(nrow(d) == 600L, !anyDuplicated(d$code),
          all(is.finite(d$cap) & d$cap > 0))

# The first eight are the Q3 empirical columns; the last four are observed
# Q2/Q4 factors from the current HW3 daily file. No earlier-homework results enter.
keys <- c("vpin", "aoib", "pcm_market_adjusted", "vcv_162d",
          "gh_adverse_cost", "nonsynch_1mr2", "c2", "pi_abs",
          "log_cap", "return_sd", "turnover_mean_pct", "amihud_mean")
labels <- c("VPIN", "AOIB", "PCM", "VCV", "GH", "1-R2", "C2",
            "abs_lambda_OIB", "log_cap", "return_sd", "turnover", "Amihud")
d$log_cap <- log(d$cap)
x <- as.matrix(d[keys])
storage.mode(x) <- "double"
colnames(x) <- labels
stopifnot(!any(is.infinite(x)))

pair_n <- outer(seq_along(keys), seq_along(keys), Vectorize(function(i, j)
  sum(is.finite(x[, i]) & is.finite(x[, j]))))
dimnames(pair_n) <- list(labels, labels)
rho <- cor(x, use = "pairwise.complete.obs", method = "spearman")
stopifnot(isTRUE(all.equal(rho, t(rho))),
          all(abs(diag(rho) - 1) < 1e-12),
          all(pair_n == t(pair_n)),
          all(abs(rho) <= 1 + 1e-12))
write.csv(rho, file.path(out, "q5_spearman_matrix.csv"))
write.csv(pair_n, file.path(out, "q5_pair_counts.csv"))
write.csv(data.frame(key = keys, label = labels,
                     n = diag(pair_n)),
          file.path(out, "q5_variable_key.csv"), row.names = FALSE)

complete <- complete.cases(x)
rho_complete <- cor(x[complete, , drop = FALSE], method = "spearman")
write.csv(rho_complete, file.path(out, "q5_complete_case_spearman.csv"))

# Main table for insertion in the report.
md <- c(paste0("| 變數 | ", paste(labels, collapse = " | "), " |"),
        paste0("|---|", paste(rep("---:", length(labels)), collapse = "|"), "|"))
show_rho <- function(z) sprintf("%+.2f", ifelse(abs(z) < .005, 0, z))
for (i in seq_along(labels))
  md <- c(md, paste0("| ", labels[i], " | ",
                     paste(show_rho(rho[i, ]), collapse = " | "), " |"))
writeLines(md, file.path(out, "q5_spearman_table.md"), useBytes = TRUE)

png(file.path(out, "q5_spearman_heatmap.png"), width = 1600,
    height = 1450, res = 150)
par(mar = c(8.5, 8.5, 3.5, 2.4))
plot(NA, xlim = c(.5, length(labels) + .5),
     ylim = c(.5, length(labels) + .5), xaxt = "n", yaxt = "n",
     xlab = "", ylab = "", bty = "n",
     main = "HW3：資訊指標與可觀察因素的 Spearman 相關")
axis(1, at = seq_along(labels), labels = labels, las = 2,
     tick = FALSE, cex.axis = .82)
axis(2, at = rev(seq_along(labels)), labels = labels,
     las = 1, tick = FALSE, cex.axis = .82)
palette <- colorRampPalette(c("#2D6A9A", "#F7F7F7", "#C64B3E"))(201)
for (i in seq_along(labels)) for (j in seq_along(labels)) {
  v <- rho[i, j]
  idx <- max(1L, min(201L, as.integer(round((v + 1) * 100)) + 1L))
  rect(j - .49, length(labels) + 1 - i - .49,
       j + .49, length(labels) + 1 - i + .49,
       col = palette[idx], border = "white", lwd = 1)
  text(j, length(labels) + 1 - i,
       sprintf("%.2f", ifelse(abs(v) < .005, 0, v)),
       col = if (abs(v) > .55) "white" else "#242424", cex = .67)
}
mtext("成對有效公司數見 q5_pair_counts.csv；藍色為負、紅色為正。",
      side = 1, line = 7.2, cex = .78)
dev.off()

cat("Pairwise n range:", range(pair_n), "complete n:", sum(complete), "\n")
cat("Selected coefficients:\n")
print(round(rho[c("VPIN", "AOIB", "VCV", "GH", "abs_lambda_OIB"),
                c("VPIN", "AOIB", "VCV", "GH", "abs_lambda_OIB",
                  "log_cap", "Amihud")], 3))
cat("Max absolute change vs complete-case Spearman:",
    max(abs(rho - rho_complete)), "\n")
