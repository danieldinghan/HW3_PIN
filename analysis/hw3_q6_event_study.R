if (.Platform$OS.type == "windows")
  invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- normalizePath(file.path(dirname(sub("^--file=", "", script_arg)), ".."),
                      winslash = "/")
out <- file.path(root, "HW3", "results")
sample <- read.csv(file.path(out, "sample_600_final.csv"),
                   colClasses = c(code = "character"))
codes <- sample$code
stopifnot(length(codes) == 600L, !anyDuplicated(codes))

raw <- read.delim(file.path(root, "HW3", "TEJ20261031102337",
                            "20261031102349.txt"),
                  fileEncoding = "UTF-16LE", check.names = FALSE,
                  colClasses = "character", na.strings = c("", "."))
d <- data.frame(code = sub(" .*", "", raw[["證券代碼"]]),
                date = as.Date(raw[["年月日"]], "%Y%m%d"),
                ret = as.numeric(raw[["報酬率％"]]) / 100,
                turnover = as.numeric(raw[["週轉率％"]]),
                value = as.numeric(raw[["成交值(千元)"]]),
                cap = as.numeric(raw[["市值(百萬元)"]]))
d <- d[d$code %in% codes, ]
dates <- sort(unique(d$date))
T <- length(dates)
N <- length(codes)
d <- d[order(match(d$code, codes), d$date), ]
stopifnot(T == 162L, nrow(d) == N * T,
          identical(d$code, rep(codes, each = T)),
          identical(d$date, rep(dates, times = N)))
to_matrix <- function(z) matrix(z, nrow = N, ncol = T, byrow = TRUE,
                                dimnames = list(codes, as.character(dates)))
ret <- to_matrix(d$ret)
turnover <- to_matrix(d$turnover)
value <- to_matrix(d$value)
cap <- to_matrix(d$cap)
amihud <- abs(ret) / ifelse(value > 0, value / 1000, NA_real_)
market_ret <- colMeans(ret)

read_codes <- function(name) read.csv(file.path(out, name),
                                      colClasses = c(code = "character"))
keyed_matrix <- function(frame, key, date_format = "%Y%m%d") {
  z <- matrix(NA_real_, N, T, dimnames = list(codes, as.character(dates)))
  day <- as.Date(as.character(frame$date), format = date_format)
  row <- match(frame$code, codes)
  col <- match(day, dates)
  ok <- is.finite(row) & is.finite(col)
  stopifnot(!anyDuplicated(paste(row[ok], col[ok])))
  z[cbind(row[ok], col[ok])] <- as.numeric(frame[[key]][ok])
  z
}
intra <- read_codes("intraday_daily_all.csv")
vpin_daily <- do.call(rbind, lapply(paste0("vpin_daily_", c("02", "03", "04"),
                                          ".csv"), read_codes))
share <- read_codes("vcv_daily_share.csv")
measures <- list(
  VPIN = keyed_matrix(vpin_daily, "vpin"),
  AOIB = keyed_matrix(intra, "aoib"),
  PCM = keyed_matrix(intra, "pcm_market_adjusted"),
  VCV20 = NULL,
  GH = keyed_matrix(intra, "gh_adverse_cost"),
  NONSYNCH40 = NULL,
  C2_60 = NULL,
  LAMBDA_OIB = keyed_matrix(intra, "pi_abs")
)
share_m <- keyed_matrix(share, "share_used_pct", date_format = "%Y-%m-%d")
rolling_vcv <- matrix(NA_real_, N, T)
rolling_nonsynch <- matrix(NA_real_, N, T)
rolling_c2 <- matrix(NA_real_, N, T)
for (i in seq_len(N)) {
  for (t in 20:T) {
    w <- share_m[i, (t - 19):t]
    w <- w[is.finite(w)]
    if (length(w) >= 15L && mean(w) > 0) rolling_vcv[i, t] <- sd(w) / mean(w)
  }
  for (t in 40:T) {
    w <- (t - 39):t
    if (sum(is.finite(ret[i, w])) >= 30L && sd(ret[i, w], na.rm = TRUE) > 0)
      rolling_nonsynch[i, t] <- 1 - cor(ret[i, w], market_ret[w],
                                        use = "complete.obs")^2
  }
  for (t in 61:T) {
    w <- (t - 60):(t - 1)
    y <- ret[i, w + 1L]
    x1 <- ret[i, w]
    x2 <- x1 * turnover[i, w]
    good <- is.finite(y) & is.finite(x1) & is.finite(x2)
    if (sum(good) < 40L || sd(x2[good]) == 0) next
    fit <- lm.fit(cbind(1, x1[good], x2[good]), y[good])
    if (fit$rank == 3L) rolling_c2[i, t] <- fit$coefficients[3]
  }
}
measures$VCV20 <- rolling_vcv
measures$NONSYNCH40 <- rolling_nonsynch
measures$C2_60 <- rolling_c2

# Daily percentile ranks remove market-wide level shifts and preserve the
# within-day ordering. The rolling versions above are Q6 event-path versions,
# explicitly distinct from Q3 full-period VCV, 1-R2 and C2.
ranks <- lapply(measures, function(z) {
  ans <- matrix(NA_real_, N, T)
  for (t in seq_len(T)) {
    ok <- which(is.finite(z[, t]))
    if (length(ok) >= 20L)
      ans[ok, t] <- (rank(z[ok, t], ties.method = "average") - .5) / length(ok)
  }
  ans
})

event_raw <- read_codes("q6_2019q2_disclosure_events.csv")
event_raw$disclosure_date <- as.Date(as.character(event_raw$disclosure_date),
                                     "%Y%m%d")
stopifnot(nrow(event_raw) == 569L, !anyDuplicated(event_raw$code),
          all(event_raw$code %in% codes))
event_raw$firm_row <- match(event_raw$code, codes)
next_session <- function(day) {
  j <- which(dates > day)
  if (length(j)) min(j) else NA_integer_
}
same_session <- function(day) {
  j <- which(dates >= day)
  if (length(j)) min(j) else NA_integer_
}
event_raw$next_t0 <- vapply(event_raw$disclosure_date, next_session,
                            integer(1))
event_raw$same_t0 <- vapply(event_raw$disclosure_date, same_session,
                            integer(1))
stopifnot(all(is.finite(event_raw$next_t0)),
          all(event_raw$next_t0 >= 41L),
          all(event_raw$next_t0 <= T - 5L))
event_raw$next_session_date <- dates[event_raw$next_t0]
event_raw$same_or_next_date <- dates[event_raw$same_t0]
write.csv(event_raw[c("code", "disclosure_date", "next_session_date",
                      "same_or_next_date")],
          file.path(out, "q6_events_mapped.csv"), row.names = FALSE)

safe_mean <- function(x, min_n = 1L) {
  x <- x[is.finite(x)]
  if (length(x) < min_n) NA_real_ else mean(x)
}
covariates <- function(t0) {
  w <- (t0 - 40):(t0 - 11)
  x <- cbind(log_cap = log(cap[, t0 - 11]),
             log_vol = log(pmax(apply(ret[, w, drop = FALSE], 1, sd), 1e-6)),
             log_turnover = log(pmax(rowMeans(turnover[, w, drop = FALSE]),
                                     .001)),
             log_amihud = log(pmax(apply(amihud[, w, drop = FALSE], 1,
                                         safe_mean, min_n = 15L), 1e-6)))
  x
}
cluster_summary <- function(y, groups) {
  ok <- is.finite(y) & !is.na(groups)
  y <- y[ok]
  groups <- groups[ok]
  n <- length(y)
  g <- length(unique(groups))
  if (n < 10 || g < 5) return(c(n = n, clusters = g, mean = NA,
                                se = NA, lo = NA, hi = NA, p = NA))
  mu <- mean(y)
  s <- tapply(y - mu, groups, sum)
  se <- sqrt(g / (g - 1) * sum(s^2) / n^2)
  critical <- qt(.975, df = g - 1)
  p <- if (se > 0) 2 * pt(-abs(mu / se), df = g - 1) else NA_real_
  c(n = n, clusters = g, mean = mu, se = se,
    lo = mu - critical * se, hi = mu + critical * se, p = p)
}

run_alignment <- function(alignment, t0_column) {
  events <- event_raw
  events$t0 <- events[[t0_column]]
  event_t0_by_firm <- rep(Inf, N)
  event_t0_by_firm[events$firm_row] <- events$t0
  tau <- -10:5
  rows <- list()
  matches <- list()
  k <- 0L
  for (e in seq_len(nrow(events))) {
    i <- events$firm_row[e]
    t0 <- events$t0[e]
    if (t0 < 41L || t0 > T - 5L) next
    x <- covariates(t0)
    good <- apply(x, 1, function(z) all(is.finite(z)))
    pool <- which(good & (event_t0_by_firm < t0 - 40L |
                            event_t0_by_firm > t0 + 5L))
    if (length(pool) < 10L || !good[i]) next
    center <- colMeans(x[good, , drop = FALSE])
    spread <- apply(x[good, , drop = FALSE], 2, sd)
    if (any(!is.finite(spread) | spread <= 0)) next
    z <- sweep(sweep(x, 2, center), 2, spread, "/")
    dist <- rowSums((z[pool, , drop = FALSE] -
                       matrix(z[i, ], length(pool), ncol(x), byrow = TRUE))^2)
    controls <- pool[order(dist, codes[pool])[seq_len(5L)]]
    match_gap <- colMeans(abs(z[controls, , drop = FALSE] -
                               matrix(z[i, ], 5L, ncol(x), byrow = TRUE)))
    matches[[e]] <- data.frame(alignment = alignment, code = codes[i],
                               disclosure_date = events$disclosure_date[e],
                               t0 = dates[t0],
                               controls = paste(codes[controls], collapse = ";"),
                               pool_n = length(pool),
                               distance = mean(sqrt(dist[match(controls, pool)])),
                               gap_log_cap = match_gap[1],
                               gap_log_vol = match_gap[2],
                               gap_log_turnover = match_gap[3],
                               gap_log_amihud = match_gap[4])
    baseline <- (t0 - 30):(t0 - 11)
    for (metric in names(ranks)) {
      rr <- ranks[[metric]]
      base_i <- safe_mean(rr[i, baseline], 8L)
      base_c <- apply(rr[controls, baseline, drop = FALSE], 1,
                      safe_mean, min_n = 8L)
      if (!is.finite(base_i)) next
      for (tt in tau) {
        day <- t0 + tt
        control_change <- rr[controls, day] - base_c
        control_change <- control_change[is.finite(control_change)]
        treated <- rr[i, day]
        if (!is.finite(treated) || length(control_change) < 3L) next
        k <- k + 1L
        rows[[k]] <- data.frame(alignment = alignment,
                                code = codes[i],
                                disclosure_date = events$disclosure_date[e],
                                t0_date = dates[t0],
                                metric = metric, tau = tt,
                                effect_pp = 100 * (treated - base_i -
                                                   mean(control_change)),
                                treated_rank = 100 * treated,
                                control_rank = 100 *
                                  mean(rr[controls, day], na.rm = TRUE))
      }
    }
  }
  list(effects = do.call(rbind, rows), matches = do.call(rbind, matches))
}

main <- run_alignment("next_session", "next_t0")
alternative <- run_alignment("same_or_next", "same_t0")
effects <- rbind(main$effects, alternative$effects)
write.csv(main$matches, file.path(out, "q6_matched_controls.csv"),
          row.names = FALSE)
write.csv(effects, file.path(out, "q6_event_effects.csv"), row.names = FALSE)

path <- do.call(rbind, lapply(split(main$effects,
                                     interaction(main$effects$metric,
                                                 main$effects$tau,
                                                 drop = TRUE)), function(z) {
  s <- cluster_summary(z$effect_pp, z$t0_date)
  data.frame(metric = z$metric[1], tau = z$tau[1],
             n = s["n"], trading_dates = s["clusters"],
             effect_pp = s["mean"], se_pp = s["se"],
             ci_lo_pp = s["lo"], ci_hi_pp = s["hi"], p = s["p"])
}))
path <- path[order(match(path$metric, names(measures)), path$tau), ]
rownames(path) <- NULL
write.csv(path, file.path(out, "q6_event_path.csv"), row.names = FALSE)

window_summary <- function(z) {
  pre <- aggregate(effect_pp ~ code + disclosure_date + t0_date + metric + alignment,
                   data = z[z$tau %in% -5:-1, ],
                   FUN = function(x) safe_mean(x, 3L))
  names(pre)[6] <- "pre_pp"
  post <- aggregate(effect_pp ~ code + disclosure_date + t0_date + metric + alignment,
                    data = z[z$tau %in% 0:5, ],
                    FUN = function(x) safe_mean(x, 3L))
  names(post)[6] <- "post_pp"
  w <- merge(pre, post, by = c("code", "disclosure_date", "t0_date",
                                   "metric", "alignment"), all = TRUE)
  w$change_pp <- w$post_pp - w$pre_pp
  w
}
windows <- window_summary(effects)
write.csv(windows, file.path(out, "q6_event_windows_by_firm.csv"),
          row.names = FALSE)
tests <- do.call(rbind, lapply(split(windows,
                                      interaction(windows$alignment,
                                                  windows$metric,
                                                  drop = TRUE)), function(z) {
  do.call(rbind, lapply(c("pre_pp", "post_pp", "change_pp"), function(key) {
    s <- cluster_summary(z[[key]], z$t0_date)
    data.frame(alignment = z$alignment[1], metric = z$metric[1],
               window = key, n = s["n"],
               trading_dates = s["clusters"],
               effect_pp = s["mean"], se_pp = s["se"],
               ci_lo_pp = s["lo"], ci_hi_pp = s["hi"], p = s["p"])
  }))
}))
rownames(tests) <- NULL
tests <- tests[order(tests$alignment, match(tests$metric, names(measures)),
                     match(tests$window, c("pre_pp", "post_pp", "change_pp"))), ]
write.csv(tests, file.path(out, "q6_window_tests.csv"), row.names = FALSE)

# Regression sensitivity: for each disclosure date and firm, fit the normal
# change in same-calendar-date non-event firms using the four pre-event Q2
# covariates. This checks whether imperfect nearest-neighbor balance drives
# the matched-control result. All predictors stop at event time -11.
adjusted_rows <- list()
a <- 0L
event_t0_by_firm <- rep(Inf, N)
event_t0_by_firm[event_raw$firm_row] <- event_raw$next_t0
for (e in seq_len(nrow(event_raw))) {
  i <- event_raw$firm_row[e]
  t0 <- event_raw$next_t0[e]
  x <- covariates(t0)
  good <- apply(x, 1, function(z) all(is.finite(z)))
  pool <- which(good & (event_t0_by_firm < t0 - 40L |
                          event_t0_by_firm > t0 + 5L))
  if (!good[i] || length(pool) < 15L) next
  center <- colMeans(x[pool, , drop = FALSE])
  spread <- apply(x[pool, , drop = FALSE], 2, sd)
  if (any(!is.finite(spread) | spread <= 0)) next
  x_pool <- cbind(1, sweep(sweep(x[pool, , drop = FALSE], 2,
                                    center), 2, spread, "/"))
  x_i <- c(1, (x[i, ] - center) / spread)
  for (metric in names(ranks)) {
    rr <- ranks[[metric]]
    ids <- c(i, pool)
    base <- apply(rr[ids, (t0 - 30):(t0 - 11), drop = FALSE], 1,
                  safe_mean, min_n = 8L)
    if (!is.finite(base[1])) next
    for (window in c("pre_pp", "post_pp")) {
      days <- if (window == "pre_pp") (t0 - 5):(t0 - 1) else t0:(t0 + 5)
      avg <- apply(rr[ids, days, drop = FALSE], 1,
                   safe_mean, min_n = 3L)
      change <- 100 * (avg - base)
      eligible <- is.finite(change[-1])
      if (!is.finite(change[1]) || sum(eligible) < 15L) next
      fit <- lm.fit(x_pool[eligible, , drop = FALSE], change[-1][eligible])
      if (fit$rank < ncol(x_pool) || any(!is.finite(fit$coefficients))) next
      a <- a + 1L
      adjusted_rows[[a]] <- data.frame(code = codes[i],
                                       disclosure_date = event_raw$disclosure_date[e],
                                       t0_date = dates[t0],
                                       metric = metric, window = window,
                                       controls_n = sum(eligible),
                                       effect_pp = change[1] -
                                         sum(x_i * fit$coefficients))
    }
  }
}
adjusted <- do.call(rbind, adjusted_rows)
write.csv(adjusted, file.path(out, "q6_regression_adjusted_by_firm.csv"),
          row.names = FALSE)
adjusted_tests <- do.call(rbind, lapply(split(adjusted,
                                               interaction(adjusted$metric,
                                                           adjusted$window,
                                                           drop = TRUE)),
                                    function(z) {
  s <- cluster_summary(z$effect_pp, z$t0_date)
  data.frame(metric = z$metric[1], window = z$window[1],
             n = s["n"], trading_dates = s["clusters"],
             effect_pp = s["mean"], se_pp = s["se"],
             ci_lo_pp = s["lo"], ci_hi_pp = s["hi"], p = s["p"])
}))
adjusted_tests <- adjusted_tests[order(match(adjusted_tests$metric,
                                               names(measures)),
                                         match(adjusted_tests$window,
                                               c("pre_pp", "post_pp"))), ]
rownames(adjusted_tests) <- NULL
write.csv(adjusted_tests,
          file.path(out, "q6_regression_adjusted_tests.csv"), row.names = FALSE)

png(file.path(out, "q6_event_paths.png"), width = 1750, height = 1050,
    res = 150)
par(mfrow = c(2, 4), mar = c(4, 4.2, 2.7, .8), oma = c(0, 0, 2, 0))
for (metric in names(measures)) {
  z <- path[path$metric == metric, ]
  lim <- range(c(z$ci_lo_pp, z$ci_hi_pp, 0), na.rm = TRUE)
  plot(z$tau, z$effect_pp, type = "b", pch = 19, cex = .65,
       col = "#2D6A9A", ylim = lim, xlab = "相對公告後首個交易日",
       ylab = "相對對照組變化（百分位點）", main = metric)
  segments(z$tau, z$ci_lo_pp, z$tau, z$ci_hi_pp,
           col = "#2D6A9A88")
  abline(h = 0, col = "gray50", lty = 2)
  abline(v = 0, col = "#C64B3E", lty = 2)
  legend("topleft", legend = paste0("有效公司 ", max(z$n)),
         bty = "n", cex = .65)
}
mtext("2019 年第 2 季合併季報公告：同日百分位、公告前基準及相近公司對照",
      outer = TRUE, side = 3, line = .1, cex = 1.05)
dev.off()

cat("Events:", nrow(event_raw), "matched:", nrow(main$matches),
    "unique disclosure dates:", length(unique(event_raw$disclosure_date)),
    "unique next trading dates:", length(unique(event_raw$next_session_date)),
    "\n")
cat("Matching pool median/min:", median(main$matches$pool_n),
    min(main$matches$pool_n), "\n")
cat("Mean standardized matching gaps:\n")
print(colMeans(main$matches[grep("^gap_", names(main$matches))]))
cat("Main window results:\n")
print(tests[tests$alignment == "next_session",
            c("metric", "window", "n", "effect_pp", "p")],
      row.names = FALSE)
cat("Regression-adjusted window results:\n")
print(adjusted_tests[c("metric", "window", "n", "effect_pp", "p")],
      row.names = FALSE)
