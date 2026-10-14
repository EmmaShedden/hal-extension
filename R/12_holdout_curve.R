# Part 2c: cell-holdout error as a function of the holdout fraction, plus a run-to-run noise floor.
# DESIGN.md "Added analysis (2026-10-14): holdout-fraction curve (Part 2c)".
# Usage: ./run_R.sh R/12_holdout_curve.R [n_cores] [topup]
#   topup: optional "frac:extra_reps,..." (e.g. "0.9:20") applying the pre-registered SE top-up rule; extra splits get
#   the next seeds after the main grid and are appended to the existing results.
source("R/common.R"); source("R/metrics.R"); source("R/candidates.R")
suppressPackageStartupMessages(library(parallel))
args <- commandArgs(TRUE)
ncores <- if (length(args) >= 1) as.integer(args[1]) else 60
topup <- if (length(args) >= 2) args[2] else ""
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
f <- as.formula(readLines(path("results/selected_formula.txt"))[2])
full <- readRDS(path("fits/selected_model.Rds"))
d$p_full <- predict(full, newdata = d, type = "response", allow.new.levels = TRUE)
outdir <- path("results/part2_curve"); dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
fitdir <- path("fits/holdout_curve"); dir.create(fitdir, recursive = TRUE, showWarnings = FALSE)

cells <- levels(droplevels(d$cell))
cell_info <- unique(d[, .(cell, benchmark, provider, effort, reasoning_model, generalist)])
COVER <- c("benchmark", "provider", "effort", "reasoning_model", "generalist")

# ---- grid: Part 2 splits (seeds 1..60) reproduced, the rest seeded 3001.. in grid order -------------------
reps <- c(`0.05` = 120, `0.1` = 60, `0.2` = 30, `0.25` = 30, `0.4` = 20, `0.5` = 20, `0.6` = 20, `0.75` = 20, `0.8` = 20, `0.9` = 20)
p2 <- expand.grid(rep = 1:20, frac = c(0.10, 0.25, 0.50)); p2$seed <- seq_len(nrow(p2))
grid <- do.call(rbind, lapply(names(reps), function(fr) data.frame(rep = seq_len(reps[[fr]]), frac = as.numeric(fr))))
grid <- merge(grid, p2, by = c("frac", "rep"), all.x = TRUE, sort = FALSE)
grid <- grid[order(grid$frac, grid$rep), ]
grid$seed[is.na(grid$seed)] <- 3000 + seq_len(sum(is.na(grid$seed)))
if (nzchar(topup)) {  # extra splits: reps continue after the existing ones, seeds after the largest used
  prev <- fread(file.path(outdir, "holdout_metrics.csv"))
  tu <- do.call(rbind, lapply(strsplit(strsplit(topup, ",")[[1]], ":"), function(x) {
    fr <- as.numeric(x[1]); r0 <- max(prev[frac == fr]$rep)
    data.frame(frac = fr, rep = r0 + seq_len(as.integer(x[2])))
  }))
  tu$seed <- max(prev$seed) + seq_len(nrow(tu)); grid <- tu
}
cat("splits to fit:", nrow(grid), "\n"); print(table(grid$frac))

naive_preds <- function(train, test) {
  # Part 2 baselines (benchmark mean; additive logit benchmark + model) and Part 2c's grand mean and same model x benchmark mean
  ca <- train[, .(acc = mean(success)), by = .(cell, benchmark, model)]
  bm <- ca[, .(b = mean(acc)), by = benchmark]
  p_b <- bm$b[match(test$benchmark, bm$benchmark)]
  ca[, lacc := qlogis(pmin(pmax(acc, 0.005), 0.995))]
  lm1 <- lm(lacc ~ benchmark + model, data = ca)
  nd <- test[, .(benchmark, model)]
  ok <- nd$model %in% ca$model
  p_a <- p_b
  p_a[ok] <- plogis(predict(lm1, newdata = nd[ok]))
  mb <- ca[, .(mb = mean(acc)), by = .(model, benchmark)]
  key <- paste(test$model, test$benchmark); p_mb <- mb$mb[match(key, paste(mb$model, mb$benchmark))]
  fb <- is.na(p_mb); p_mb[fb] <- p_a[fb]
  list(bench_mean = p_b, additive = p_a, grand_mean = rep(mean(ca$acc), nrow(test)), model_bench = p_mb, model_bench_fallback = fb)
}

covered <- function(held) {
  tr <- cell_info[!cell %in% held]
  all(vapply(COVER, function(v) all(unique(cell_info[[v]]) %in% tr[[v]]), TRUE))
}

one <- function(i) {
  g <- grid[i, ]; set.seed(g$seed)
  redraws <- 0L
  repeat { held <- sample(cells, round(g$frac * length(cells))); if (covered(held)) break; redraws <- redraws + 1L }
  train <- droplevels(d[!cell %in% held]); test <- d[cell %in% held]
  # pre-registered fallback chain for fits that error (small training sets at high fractions): default CTRL, then bobyqa, then nAGQ = 0
  fit_try <- list(default = list(control = CTRL, nAGQ = 1L), bobyqa = list(control = glmerControl(optimizer = "bobyqa"), nAGQ = 1L),
                  nAGQ0 = list(control = CTRL, nAGQ = 0L))
  errs <- character(0); m <- NULL
  for (fit_method in names(fit_try)) {
    warns <- character(0)
    m <- tryCatch(withCallingHandlers(glmer(f, data = train, family = binomial, control = fit_try[[fit_method]]$control, nAGQ = fit_try[[fit_method]]$nAGQ),
                                      warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") }),
                  error = function(e) { errs <<- c(errs, paste0(fit_method, ": ", conditionMessage(e))); NULL })
    if (!is.null(m)) break
  }
  if (is.null(m)) stop(paste(errs, collapse = " | "))
  saveRDS(m, file.path(fitdir, sprintf("holdout_f%02d_r%03d.Rds", round(100 * g$frac), g$rep)))
  test$p <- predict(m, newdata = test, type = "response", allow.new.levels = TRUE)
  nv <- naive_preds(train, test)
  test$p_bench <- nv$bench_mean; test$p_add <- nv$additive; test$p_grand <- nv$grand_mean; test$p_mb <- nv$model_bench
  pcs <- c(refit = "p", full_model = "p_full", naive_bench_mean = "p_bench", naive_additive = "p_add",
           naive_grand_mean = "p_grand", naive_model_bench = "p_mb")
  rows <- lapply(pcs, function(pc) {
    tmet <- task_metrics(test[[pc]], test$success)
    rl <- run_level(test, pc)
    cbind(tmet, run_mae_pp = mean(rl$abs_err_pp), run_rmse_pp = sqrt(mean(rl$abs_err_pp^2)), n_runs = nrow(rl))
  })
  res <- do.call(rbind, Map(function(nm, r) cbind(predictor = nm, r), names(rows), rows))
  res$frac <- g$frac; res$rep <- g$rep; res$seed <- g$seed; res$n_held_cells <- length(held); res$redraws <- redraws; res$fit_method <- fit_method; res$fit_errors <- paste(errs, collapse = " | ")
  res$model_bench_fallback_share <- mean(tapply(nv$model_bench_fallback, as.character(test$cell), `[`, 1))
  res$singular <- is_singular2(m); res$warnings <- paste(unique(c(warns, m@optinfo$conv$lme4$messages)), collapse = " | ")
  per_run <- rbindlist(lapply(names(pcs), function(nm) { r <- run_level(test, pcs[[nm]]); r$predictor <- nm; r }))
  per_run$frac <- g$frac; per_run$rep <- g$rep; per_run$seed <- g$seed
  list(res = res, per_run = per_run)
}
t0 <- Sys.time()
R <- mclapply(seq_len(nrow(grid)), function(i) tryCatch(one(i), error = function(e) structure(conditionMessage(e), class = "try-error", i = i)),
              mc.cores = min(ncores, nrow(grid)), mc.preschedule = FALSE)
bad <- vapply(R, inherits, TRUE, "try-error")
if (any(bad)) { cat("FAILED splits:", sum(bad), "\n"); print(cbind(grid[bad, ], msg = unlist(R[bad]))) }
fwrite(grid[bad, ], file.path(outdir, if (nzchar(topup)) "failed_splits_topup.csv" else "failed_splits.csv"))
R <- R[!bad]
cat("holdout wall time (min):", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "\n")
res <- rbindlist(lapply(R, `[[`, "res")); pr <- rbindlist(lapply(R, `[[`, "per_run"))
if (nzchar(topup)) { res <- rbind(fread(file.path(outdir, "holdout_metrics.csv")), res, fill = TRUE)
                     pr <- rbind(fread(file.path(outdir, "holdout_per_run.csv.gz")), pr, fill = TRUE) }
fwrite(res, file.path(outdir, "holdout_metrics.csv")); fwrite(pr, file.path(outdir, "holdout_per_run.csv.gz"))

summ <- res[, .(run_mae_pp = mean(run_mae_pp), run_mae_sd = sd(run_mae_pp), run_mae_se = sd(run_mae_pp) / sqrt(.N),
                brier = mean(brier), err01 = mean(err01), logloss = mean(logloss), auc = mean(auc, na.rm = TRUE),
                n_held_cells = mean(n_held_cells), mean_redraws = mean(redraws), mb_fallback = mean(model_bench_fallback_share),
                n_singular = sum(singular), n_fallback_fit = sum(fit_method != "default"), n = .N), by = .(frac, predictor)]
summ[, `:=`(ci_lo = run_mae_pp - qt(0.975, n - 1) * run_mae_se, ci_hi = run_mae_pp + qt(0.975, n - 1) * run_mae_se)]
setorder(summ, predictor, frac); fwrite(summ, file.path(outdir, "holdout_summary.csv")); print(summ)
cat("\nfractions with refit SE > 0.35 pp (pre-registered top-up rule):\n"); print(summ[predictor == "refit" & run_mae_se > 0.35, .(frac, run_mae_se, n)])

# ---- reproduction check against Part 2 (same seeds) -----------------------------------------------------
p2r <- fread(path("results/part2/main/holdout_metrics.csv"))
chk <- merge(p2r[, .(predictor, frac, rep, mae2 = run_mae_pp)], res[, .(predictor, frac, rep, mae = run_mae_pp)], by = c("predictor", "frac", "rep"))
cat("\nPart 2 reproduction: rows matched", nrow(chk), "of", nrow(p2r), "; max |diff| (pp):", signif(max(abs(chk$mae - chk$mae2)), 3), "\n")

# ---- run-to-run noise floor (fraction-independent) -----------------------------------------------------
if (!nzchar(topup)) {
  ra <- d[, .(acc = mean(success)), by = .(run, cell)]
  rp <- ra[cell %in% ra[, .N, by = cell][N == 2]$cell][, .(acc1 = 100 * acc[1], acc2 = 100 * acc[2], abs_diff_pp = 100 * abs(diff(acc))), by = cell]
  fwrite(rp, file.path(outdir, "replicate_pairs.csv")); cat("\nreplicate-run pairs:\n"); print(rp)
  bars <- lme4::findbars(f); keep <- bars[vapply(bars, function(b) deparse(b) != "1 | run", TRUE)]
  re_norun <- as.formula(paste("~", paste(sprintf("(%s)", vapply(keep, deparse, "")), collapse = " + ")))
  d$eta_norun <- predict(full, newdata = d, re.form = re_norun, type = "link")
  s_run <- attr(VarCorr(full)$run, "stddev")[[1]]
  set.seed(4242); K <- 4000
  fl <- d[, {
    u <- rnorm(K, 0, s_run); P <- plogis(outer(eta_norun, u, "+"))
    acc <- colMeans(matrix(rbinom(length(P), 1, P), nrow(P)))
    yb <- colMeans(matrix(rbinom(length(p_full) * K, 1, p_full), length(p_full)))
    .(floor_run_binom_pp = 100 * mean(abs(acc - mean(P))), floor_binom_only_pp = 100 * mean(abs(yb - mean(p_full))), n_tasks = .N)
  }, by = .(run, benchmark)]
  fwrite(fl, file.path(outdir, "noise_floor_per_run.csv"))
  nf <- data.table(quantity = c("floor_run_plus_binomial", "floor_binomial_only", "replicate_pairs_mean_abs_diff"),
                   mae_pp = c(mean(fl$floor_run_binom_pp), mean(fl$floor_binom_only_pp), mean(rp$abs_diff_pp)),
                   n = c(nrow(fl), nrow(fl), nrow(rp)), sigma_run = s_run)
  fwrite(nf, file.path(outdir, "noise_floor.csv")); cat("\nnoise floor:\n"); print(nf)
  print(fl[, .(floor_run_binom_pp = mean(floor_run_binom_pp), floor_binom_only_pp = mean(floor_binom_only_pp)), by = benchmark])
}
