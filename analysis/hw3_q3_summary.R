if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
out <- file.path(root, "HW3", "results")
read_codes <- function(name) read.csv(file.path(out, name),
                                      colClasses = c(code = "character"))
sample <- read_codes("sample_600_proposed.csv")
stopifnot(nrow(sample) == 600L, !anyDuplicated(sample$code))
write.csv(sample, file.path(out, "sample_600_final.csv"), row.names = FALSE)
vcv <- read_codes("vcv_period.csv")
c2 <- read_codes("c2_raw_turnover_pct.csv")
covars <- read_codes("firm_covariates.csv")
intra <- read_codes("firm_intraday_measures.csv")
vpin_paths <- file.path(out, paste0("vpin_daily_", c("02", "03", "04"), ".csv"))
stopifnot(all(file.exists(vpin_paths)))
vpin_daily <- do.call(rbind, lapply(vpin_paths, read.csv,
                                    colClasses = c(code = "character")))
stopifnot(!anyDuplicated(vpin_daily[c("code", "date")]),
          all(is.finite(vpin_daily$vpin)),
          all(vpin_daily$vpin >= -1e-8 & vpin_daily$vpin <= 1 + 1e-8))
vpin <- aggregate(vpin ~ code, vpin_daily, mean)
vpin_days <- aggregate(date ~ code, vpin_daily, length)
names(vpin_days)[2] <- "vpin_days"

all <- Reduce(function(a, b) merge(a, b, by = "code", all.x = TRUE, sort = FALSE),
              list(sample, vcv[c("code", "vcv_162d")], c2[c("code", "c2")],
                   covars[c("code", "nonsynch_1mr2", "return_sd", "turnover_mean_pct",
                            "amihud_mean")],
                   intra[c("code", "aoib", "pcm_market_adjusted", "gh_adverse_cost",
                           "pi_abs", "intraday_days", "unclassified_fraction")],
                   vpin, vpin_days))
all <- all[match(sample$code, all$code), ]
stopifnot(nrow(all) == 600L, identical(all$code, sample$code))
write.csv(all, file.path(out, "firm_all_q3.csv"), row.names = FALSE)

measure <- c(vpin = "VPIN(BVC, 1分鐘)", aoib = "AOIB(tick推定)",
             pcm_market_adjusted = "PCM(市場調整報酬)",
             vcv_162d = "VCV(TEJ比重補值)",
             gh_adverse_cost = "GH式逆選擇成本(報價缺失替代)",
             nonsynch_1mr2 = "1-R²(非原AIV)",
             c2 = "C2(原始週轉率穩健版)",
             pi_abs = "|λ×OIB|(成交價代理)")
summarize <- function(key) {
  z <- all[[key]]
  z <- z[is.finite(z)]
  data.frame(key = key, measure = unname(measure[[key]]), n = length(z),
             mean = mean(z), sd = sd(z),
             p05 = unname(quantile(z, .05)),
             p25 = unname(quantile(z, .25)),
             median = median(z), p75 = unname(quantile(z, .75)),
             p95 = unname(quantile(z, .95)))
}
stats <- do.call(rbind, lapply(names(measure), summarize))
write.csv(stats, file.path(out, "q3_descriptive_stats.csv"), row.names = FALSE)
print(stats)

safe_spearman <- function(x, y) {
  ok <- is.finite(x) & is.finite(y)
  if (sum(ok) < 20 || sd(x[ok]) == 0 || sd(y[ok]) == 0) return(NA_real_)
  cor(x[ok], y[ok], method = "spearman")
}
associations <- do.call(rbind, lapply(names(measure), function(key)
  data.frame(key = key, measure = unname(measure[[key]]),
             rho_turnover = safe_spearman(all[[key]], all$turnover_mean_pct),
             rho_amihud = safe_spearman(all[[key]], all$amihud_mean),
             rho_return_sd = safe_spearman(all[[key]], all$return_sd))))
write.csv(associations, file.path(out, "q3_associations.csv"), row.names = FALSE)
print(associations)

png(file.path(out, "q3_factors_heatmap.png"), width = 1400, height = 850,
    res = 150)
par(mar = c(5.5, 10.5, 3.2, 1.2))
plot(NA, xlim = c(.5, 3.5), ylim = c(.5, 8.5),
     xlab = "", ylab = "", xaxt = "n", yaxt = "n", bty = "n",
     main = "八項實證欄位與可觀察因素的關聯")
axis(1, at = 1:3,
     labels = c("日報酬波動", "平均週轉率", "Amihud 非流動性"),
     tick = FALSE, cex.axis = .88)
axis(2, at = 8:1, labels = associations$measure, las = 1,
     tick = FALSE, cex.axis = .75)
rho <- as.matrix(associations[c("rho_return_sd", "rho_turnover",
                                "rho_amihud")])
palette <- colorRampPalette(c("#2D6A9A", "#F7F7F7", "#C64B3E"))(201)
for (i in seq_len(nrow(rho))) for (j in seq_len(ncol(rho))) {
  v <- rho[i, j]
  idx <- max(1L, min(201L, as.integer(round((v + 1) * 100)) + 1L))
  rect(j - .49, 9 - i - .46, j + .49, 9 - i + .46,
       col = palette[idx], border = "white", lwd = 2)
  text(j, 9 - i, sprintf("%+.3f", v), cex = .85,
       col = if (abs(v) > .55) "white" else "#242424")
}
mtext("Spearman 等級相關；藍色為負，紅色為正。僅描述同期間關聯。",
      side = 1, line = 4.3, cex = .75)
dev.off()

png(file.path(out, "q3_measures_by_volatility.png"), width = 1800, height = 950,
    res = 150)
par(mfrow = c(2, 4), mar = c(4, 4.3, 2.2, .8), oma = c(0, 0, 1, 0))
for (key in names(measure)) {
  z <- all[[key]]
  x <- 100 * all$return_sd
  ok <- is.finite(x) & is.finite(z)
  limits <- as.numeric(quantile(z[ok], c(.02, .98)))
  y <- pmin(pmax(z[ok], limits[1]), limits[2])
  plot(x[ok], y, pch = 16, cex = .35, col = "#305C8A55",
       xlab = "日報酬標準差(百分點)", ylab = key,
       main = unname(measure[[key]]), cex.main = .86)
  if (sum(ok) > 30L) {
    fit <- loess(y ~ x, data = data.frame(x = x[ok], y = y),
                 span = .75, degree = 1,
                 control = loess.control(surface = "direct"))
    gx <- seq(min(x[ok]), max(x[ok]), length.out = 100L)
    lines(gx, predict(fit, data.frame(x = gx)),
          col = "#C64B3E", lwd = 2)
  }
  legend("topright", legend = paste0("n=", sum(ok)), bty = "n", cex = .7)
}
dev.off()

png(file.path(out, "q4_vcv_liquidity.png"), width = 1500, height = 700,
    res = 150)
par(mfrow = c(1, 2), mar = c(4, 4, 2, 1))
vcv_top <- as.numeric(quantile(all$vcv_162d, .99, na.rm = TRUE))
ok <- is.finite(all$vcv_162d) & is.finite(all$amihud_mean) & all$amihud_mean > 0
plot(log10(all$amihud_mean[ok]), pmin(all$vcv_162d[ok], vcv_top), pch = 16,
     cex = .55, col = "#305C8A66", xlab = "log10(Amihud 非流動性)",
     ylab = "VCV", main = "VCV 與非流動性")
legend("topright", legend = paste0("Spearman ρ=",
         round(safe_spearman(all$vcv_162d, all$amihud_mean), 3)),
       bty = "n")
ok <- is.finite(all$vcv_162d) & is.finite(all$turnover_mean_pct)
plot(log10(pmax(all$turnover_mean_pct[ok], .001)),
     pmin(all$vcv_162d[ok], vcv_top),
     pch = 16, cex = .55, col = "#305C8A66",
     xlab = "log10(平均日週轉率%, 下限 .001)", ylab = "VCV",
     main = "VCV 與交易活躍度")
legend("topright", legend = paste0("Spearman ρ=",
         round(safe_spearman(all$vcv_162d, all$turnover_mean_pct), 3)),
       bty = "n")
dev.off()

# Rank residual association is descriptive; it is not a causal identification.
keep <- complete.cases(all[c("vcv_162d", "amihud_mean",
                             "return_sd", "turnover_mean_pct")])
ranked <- lapply(all[keep, c("vcv_162d", "amihud_mean",
                              "return_sd", "turnover_mean_pct")], rank)
controls <- data.frame(volatility = ranked$return_sd,
                       turnover = ranked$turnover_mean_pct)
partial <- cor(resid(lm(ranked$vcv_162d ~ ., data = controls)),
               resid(lm(ranked$amihud_mean ~ ., data = controls)))
cat("Partial rank VCV-Amihud with vol, turnover:", partial, "n", sum(keep), "\n")
cat("VPIN stock-days", nrow(vpin_daily), "firms", nrow(vpin),
    "range", range(vpin_daily$date), "\n")
