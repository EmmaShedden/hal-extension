# Extension 2: runtime of successful traces (TMS-style lmer on log runtime), same predictor set and
# candidate class as the success model; AIC selection among converged, non-singular fits.
source("R/common.R"); source("R/candidates.R"); source("R/metrics.R")
suppressPackageStartupMessages({library(parallel); library(moments)})
args <- commandArgs(TRUE); ncores <- if (length(args)) as.integer(args[1]) else 48
out <- path("results/ext2_runtime"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
fdir <- path("fits/runtime"); dir.create(fdir, recursive = TRUE, showWarnings = FALSE)
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds")))
d <- droplevels(L$d[success == 1 & !is.na(latency_s) & latency_s > 0])
cat("successful traces with latency:", nrow(d), "runs", nlevels(d$run), "\n")
print(d[, .(n = .N, runs = uniqueN(run), med_s = median(latency_s)), by = benchmark])
cands <- validity_filter(enumerate_candidates("log(latency_s)"), d)
cands <- cands[!duplicated(cands$formula), ]; cands$id <- sprintf("t%03d", seq_len(nrow(cands)))
fit_one <- function(i) {
  warns <- character(0)
  m <- withCallingHandlers(tryCatch(lmer(as.formula(cands$formula[i]), data = d, REML = FALSE), error = function(e) e),
                           warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") })
  if (inherits(m, "error")) return(data.frame(id = cands$id[i], AIC = NA, BIC = NA, singular = NA, conv_warning = TRUE, messages = conditionMessage(m)))
  saveRDS(m, file.path(fdir, paste0(cands$id[i], ".Rds")))
  conv <- c(warns, m@optinfo$conv$lme4$messages)
  data.frame(id = cands$id[i], AIC = AIC(m), BIC = BIC(m), singular = isSingular(m), conv_warning = length(conv) > 0, messages = paste(unique(conv), collapse = " | "))
}
vi <- which(cands$valid)
met <- merge(cands, do.call(rbind, mclapply(vi, fit_one, mc.cores = min(ncores, length(vi)), mc.preschedule = FALSE)), by = "id", all.x = TRUE)
met <- met[order(met$AIC), ]; met$eligible <- met$valid & !is.na(met$AIC) & !met$conv_warning & !met$singular
fwrite(met, file.path(out, "candidate_metrics.csv"))
sel <- met[met$eligible, ][1, ]; writeLines(c(sel$id, sel$formula), file.path(out, "selected_formula.txt"))
m <- readRDS(file.path(fdir, paste0(sel$id, ".Rds"))); saveRDS(m, path("fits/runtime_selected_model.Rds"))
cat("SELECTED runtime model:", sel$formula, "\n")
# TMS transform check: residual skewness of raw vs log outcome under the selected structure
m_raw <- lmer(update(formula(m), latency_s ~ .), data = d, REML = FALSE)
fwrite(data.frame(outcome = c("log(latency_s)", "latency_s"), resid_skewness = c(skewness(resid(m)), skewness(resid(m_raw)))),
       file.path(out, "skewness_check.csv"))
sink(file.path(out, "summary_selected.txt")); print(summary(m)); sink()
fe <- data.frame(term = names(fixef(m)), est = fixef(m), se = sqrt(diag(as.matrix(vcov(m)))))
fe$ratio <- exp(fe$est); fwrite(fe, file.path(out, "fixed_effects.csv"))
vc <- as.data.frame(VarCorr(m)); vc$share <- vc$vcov / sum(vc$vcov); fwrite(vc, file.path(out, "random_effects_variance.csv"))
r2 <- performance::r2_nakagawa(m); fwrite(data.frame(R2_marginal = r2$R2_marginal, R2_conditional = r2$R2_conditional), file.path(out, "r2.csv"))
# holdout (same cell design as Part 2, 20 reps x 3 fractions): log-runtime RMSE of held-out successful traces
f <- formula(m); cells <- levels(d$cell)
grid <- expand.grid(rep = 1:20, frac = c(0.10, 0.25, 0.50)); grid$seed <- seq_len(nrow(grid))
d$pred_full <- predict(m)
ho <- rbindlist(mclapply(seq_len(nrow(grid)), function(i) {
  set.seed(grid$seed[i]); held <- sample(cells, round(grid$frac[i] * length(cells)))
  tr <- droplevels(d[!cell %in% held]); te <- d[cell %in% held]
  mm <- lmer(f, data = tr, REML = FALSE)
  te$pred <- predict(mm, newdata = te, allow.new.levels = TRUE)
  bm <- tr[, .(b = mean(log(latency_s))), by = benchmark]; te$pred_b <- bm$b[match(te$benchmark, bm$benchmark)]
  data.frame(frac = grid$frac[i], rep = grid$rep[i],
             rmse_log_refit = sqrt(mean((te$pred - log(te$latency_s))^2)),
             rmse_log_full = sqrt(mean((te$pred_full - log(te$latency_s))^2)),
             rmse_log_bench_mean = sqrt(mean((te$pred_b - log(te$latency_s))^2)), n = nrow(te))
}, mc.cores = min(ncores, nrow(grid))))
fwrite(ho, file.path(out, "holdout_metrics.csv"))
print(ho[, lapply(.SD, mean), by = frac, .SDcols = c("rmse_log_refit", "rmse_log_full", "rmse_log_bench_mean")])
