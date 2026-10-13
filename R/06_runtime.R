# Extension 2: runtime of successful traces (TMS-style lmer on log runtime), same predictor set and
# candidate class as the success model; PF-3 selection (heredity, zero components kept, lowest AIC among converged fits).
# Outcome (AUDIT.md M2 fix): span_s = first LLM call start to last LLM call end, from HAL's per-call Weave logs
# (scripts/extract_call_timing.py -> data/processed/task_timing.csv.gz). HAL's own total_time stops at the *start* of
# the last call, so single-call tasks read ~0 s. Neither measure includes environment setup or evaluation.
source("R/common.R"); source("R/candidates.R"); source("R/metrics.R")
suppressPackageStartupMessages({library(parallel); library(moments)})
args <- commandArgs(TRUE); ncores <- if (length(args)) as.integer(args[1]) else 48
out <- path("results/ext2_runtime"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
fdir <- path("fits/runtime"); unlink(fdir, recursive = TRUE); dir.create(fdir, recursive = TRUE, showWarnings = FALSE)
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds")))
tim <- fread(path("data/processed/task_timing.csv.gz"), colClasses = list(character = "task_id"))
d0 <- merge(L$d, tim[, .(source_file, task_id, span_s, n_calls, llm_time_s)], by = c("source_file", "task_id"), all.x = TRUE)
cat("successful traces:", d0[success == 1, .N], " with span_s:", d0[success == 1 & !is.na(span_s), .N], "\n")
d <- droplevels(d0[success == 1 & !is.na(span_s) & span_s > 0])
d[, latency_s := span_s]
cat("successful traces with span:", nrow(d), "runs", nlevels(d$run), "\n")
print(d[, .(n = .N, runs = uniqueN(run), med_s = as.numeric(median(latency_s)), single_call = mean(n_calls == 1), under_1s = mean(latency_s < 1)), by = benchmark])
fwrite(d[, .(n = .N, runs = uniqueN(run), median_span_s = as.numeric(median(span_s)), median_calls = as.numeric(median(n_calls)), share_single_call = mean(n_calls == 1),
             share_under_1s = mean(span_s < 1)), by = .(benchmark, scaffold)][order(benchmark, scaffold)], file.path(out, "outcome_by_scaffold.csv"))
cands <- validity_filter(enumerate_candidates("log(latency_s)"), d)
cands <- cands[!duplicated(cands$formula), ]; cands$id <- sprintf("t%03d", seq_len(nrow(cands)))
v <- cands[cands$valid, ]
FR <- fit_and_reduce(setNames(v$formula, v$id), function(f) lmer(f, data = d, REML = FALSE),
                     mapper = function(x, f) mclapply(x, f, mc.cores = min(ncores, length(x)), mc.preschedule = FALSE), save_dir = fdir, reduce = FALSE, allow_singular = TRUE)
met <- FR$metrics
fwrite(met, file.path(out, "candidate_metrics.csv"))
cat("fits:", nrow(met), "; singular originals:", sum(met$singular[met$round == 0], na.rm = TRUE), "; eligible:", sum(met$eligible), "\n")
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
