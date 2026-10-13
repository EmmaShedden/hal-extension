# Part 2: cell-holdout refits with the fixed (selected) design. DESIGN.md "Part 2".
# Usage: ./run_R.sh R/04_holdout.R [n_cores] [variant]   variant: main (default) |
#        judge_both | judge_any | manual (Ext. 3; selected formula refit on judge-corrected data)
source("R/common.R"); source("R/metrics.R"); source("R/candidates.R")
suppressPackageStartupMessages(library(parallel))
args <- commandArgs(TRUE)
ncores <- if (length(args) >= 1) as.integer(args[1]) else 60
variant <- if (length(args) >= 2) args[2] else "main"
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
if (startsWith(variant, "judge") || variant == "manual") { source("R/judge.R"); d <- apply_judge_correction(d, variant) }
f <- as.formula(readLines(path("results/selected_formula.txt"))[2])
full <- if (variant == "main") readRDS(path("fits/selected_model.Rds")) else readRDS(path(sprintf("fits/selected_model_%s.Rds", variant)))
d$p_full <- predict(full, newdata = d, type = "response", allow.new.levels = TRUE)
outdir <- path("results/part2", variant); dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
fitdir <- path("fits/holdout", variant); dir.create(fitdir, recursive = TRUE, showWarnings = FALSE)

cells <- levels(droplevels(d$cell))
grid <- expand.grid(rep = 1:20, frac = c(0.10, 0.25, 0.50)); grid$seed <- seq_len(nrow(grid))

naive_preds <- function(train, test) {
  # (b) benchmark mean accuracy; (c) additive logit: benchmark + model effects fitted on training cell accuracies
  ca <- train[, .(acc = mean(success)), by = .(cell, benchmark, model)]
  bm <- ca[, .(b = mean(acc)), by = benchmark]
  p_b <- bm$b[match(test$benchmark, bm$benchmark)]
  ca[, lacc := qlogis(pmin(pmax(acc, 0.005), 0.995))]
  lm1 <- lm(lacc ~ benchmark + model, data = ca)
  nd <- test[, .(benchmark, model)]
  ok <- nd$model %in% ca$model
  p_a <- p_b
  p_a[ok] <- plogis(predict(lm1, newdata = nd[ok]))
  list(bench_mean = p_b, additive = p_a)
}

one <- function(i) {
  g <- grid[i, ]; set.seed(g$seed)
  held <- sample(cells, round(g$frac * length(cells)))
  train <- droplevels(d[!cell %in% held]); test <- d[cell %in% held]
  warns <- character(0)
  m <- withCallingHandlers(glmer(f, data = train, family = binomial, control = CTRL),
                           warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") })
  saveRDS(m, file.path(fitdir, sprintf("holdout_f%02d_r%02d.Rds", round(100 * g$frac), g$rep)))
  test$p <- predict(m, newdata = test, type = "response", allow.new.levels = TRUE)
  nv <- naive_preds(train, test); test$p_bench <- nv$bench_mean; test$p_add <- nv$additive
  rows <- lapply(c(refit = "p", full_model = "p_full", naive_bench_mean = "p_bench", naive_additive = "p_add"), function(pc) {
    tmet <- task_metrics(test[[pc]], test$success)
    rl <- run_level(test, pc)
    cbind(tmet, run_mae_pp = mean(rl$abs_err_pp), run_rmse_pp = sqrt(mean(rl$abs_err_pp^2)), n_runs = nrow(rl))
  })
  res <- do.call(rbind, Map(function(nm, r) cbind(predictor = nm, r), names(rows), rows))
  res$frac <- g$frac; res$rep <- g$rep; res$seed <- g$seed; res$n_held_cells <- length(held)
  res$singular <- is_singular2(m); res$warnings <- paste(unique(c(warns, m@optinfo$conv$lme4$messages)), collapse = " | ")
  per_run <- run_level(test, "p"); per_run$frac <- g$frac; per_run$rep <- g$rep
  list(res = res, per_run = per_run)
}
t0 <- Sys.time()
R <- mclapply(seq_len(nrow(grid)), one, mc.cores = min(ncores, nrow(grid)), mc.preschedule = FALSE)
bad <- vapply(R, inherits, TRUE, "try-error"); if (any(bad)) print(R[bad])
R <- R[!bad]
cat("holdout wall time (min):", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "\n")
res <- rbindlist(lapply(R, `[[`, "res")); fwrite(res, file.path(outdir, "holdout_metrics.csv"))
fwrite(rbindlist(lapply(R, `[[`, "per_run")), file.path(outdir, "holdout_per_run.csv"))
summ <- res[, .(run_mae_pp = mean(run_mae_pp), run_mae_sd = sd(run_mae_pp), brier = mean(brier), err01 = mean(err01),
                logloss = mean(logloss), auc = mean(auc, na.rm = TRUE), n = .N), by = .(frac, predictor)]
fwrite(summ, file.path(outdir, "holdout_summary.csv")); print(summ)
