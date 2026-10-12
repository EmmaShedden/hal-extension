# Part 2b: task-level (row) holdout refits with the fixed design. DESIGN.md "Added analysis ... task-level holdout".
# Usage: ./run_R.sh R/10_task_holdout.R [n_cores] [variant]   variant: main (default) | reduced
source("R/common.R"); source("R/metrics.R")
suppressPackageStartupMessages(library(parallel))
args <- commandArgs(TRUE)
ncores <- if (length(args) >= 1) as.integer(args[1]) else 60
variant <- if (length(args) >= 2) args[2] else "main"
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
f <- as.formula(readLines(path(if (variant == "reduced") "results/reduced/selected_formula.txt" else "results/selected_formula.txt"))[2])
full <- if (variant == "main") readRDS(path("fits/selected_model.Rds")) else readRDS(path(sprintf("fits/selected_model_%s.Rds", variant)))
d$p_full <- predict(full, newdata = d, type = "response", allow.new.levels = TRUE)
d[, row_id := .I]
outdir <- path("results/part2_task", variant); dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
fitdir <- path("fits/holdout_task", variant); dir.create(fitdir, recursive = TRUE, showWarnings = FALSE)

grid <- expand.grid(rep = 1:20, frac = c(0.10, 0.25, 0.50)); grid$seed <- 1000 + seq_len(nrow(grid))
clamp <- function(p) pmin(pmax(p, 0.005), 0.995)

naive_preds <- function(train, test) {
  bm <- train[, .(b = mean(success)), by = benchmark]
  rm <- train[, .(r = mean(success)), by = run]
  tm <- train[, .(t = mean(success)), by = task]
  p_b <- bm$b[match(test$benchmark, bm$benchmark)]
  p_r <- rm$r[match(test$run, rm$run)]; p_r[is.na(p_r)] <- p_b[is.na(p_r)]
  p_t <- tm$t[match(test$task, tm$task)]; p_t[is.na(p_t)] <- p_b[is.na(p_t)]
  p_a <- plogis(qlogis(clamp(p_r)) + qlogis(clamp(p_t)) - qlogis(clamp(p_b)))
  list(p_bench = p_b, p_run = p_r, p_task = p_t, p_add = p_a)
}

# sampling-noise floor of the held-out-subset run accuracy: E|mean p - mean y|, y ~ Bernoulli(p_full)
noise_floor <- function(test, ndraw = 200) {
  test[, {
    y <- matrix(rbinom(.N * ndraw, 1, p_full), nrow = .N)
    .(noise_pp = 100 * mean(abs(mean(p_full) - colMeans(y))))
  }, by = run]
}

PRED <- c(refit = "p", full_model = "p_full", naive_bench_mean = "p_bench", naive_run_mean = "p_run",
          naive_task_mean = "p_task", naive_additive = "p_add")

one <- function(i) {
  g <- grid[i, ]; set.seed(g$seed)
  held <- sample(d$row_id, round(g$frac * nrow(d)))
  train <- droplevels(d[!row_id %in% held]); test <- copy(d[row_id %in% held])
  warns <- character(0)
  m <- withCallingHandlers(glmer(f, data = train, family = binomial, control = CTRL),
                           warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") })
  saveRDS(m, file.path(fitdir, sprintf("holdout_f%02d_r%02d.Rds", round(100 * g$frac), g$rep)))
  test$p <- predict(m, newdata = test, type = "response", allow.new.levels = TRUE)
  nv <- naive_preds(train, test); for (nm in names(nv)) test[[nm]] <- nv[[nm]]
  # full-run totals for the completed-run metric
  tot <- d[, .(n_all = .N, acc_all = mean(success)), by = run]
  trn <- train[, .(n_tr = .N, s_tr = sum(success)), by = run]
  nf <- noise_floor(test)
  rows <- lapply(PRED, function(pc) {
    tmet <- task_metrics(test[[pc]], test$success)
    rl <- run_level(test, pc)
    sp <- test[, .(sum_p = sum(get(pc))), by = run]
    cr <- merge(merge(tot, trn, by = "run", all.x = TRUE), sp, by = "run")
    cr[is.na(s_tr), `:=`(s_tr = 0, n_tr = 0)]
    cr[, err_pp := 100 * abs((s_tr + sum_p) / n_all - acc_all)]
    cbind(tmet, run_mae_pp = mean(rl$abs_err_pp), run_rmse_pp = sqrt(mean(rl$abs_err_pp^2)),
          completed_run_mae_pp = mean(cr$err_pp), n_runs = nrow(rl), mean_heldout_tasks_per_run = mean(rl$n))
  })
  res <- do.call(rbind, Map(function(nm, r) cbind(predictor = nm, r), names(rows), rows))
  res$noise_floor_pp <- mean(nf$noise_pp)
  res$frac <- g$frac; res$rep <- g$rep; res$seed <- g$seed; res$n_held_rows <- length(held)
  res$singular <- isSingular(m); res$warnings <- paste(unique(c(warns, m@optinfo$conv$lme4$messages)), collapse = " | ")
  per_run <- test[, .(obs = mean(success), pred = mean(p), pred_full = mean(p_full), pred_run = mean(p_run),
                      pred_add = mean(p_add), n = .N), by = .(run, cell, benchmark)]
  per_run <- merge(per_run, nf, by = "run")
  per_run[, abs_err_pp := 100 * abs(pred - obs)]; per_run$frac <- g$frac; per_run$rep <- g$rep
  list(res = res, per_run = per_run)
}
t0 <- Sys.time()
R <- mclapply(seq_len(nrow(grid)), one, mc.cores = min(ncores, nrow(grid)), mc.preschedule = FALSE)
bad <- vapply(R, inherits, TRUE, "try-error"); if (any(bad)) print(R[bad])
R <- R[!bad]
cat("task holdout wall time (min):", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "\n")
res <- rbindlist(lapply(R, `[[`, "res")); fwrite(res, file.path(outdir, "holdout_metrics.csv"))
fwrite(rbindlist(lapply(R, `[[`, "per_run")), file.path(outdir, "holdout_per_run.csv"))
summ <- res[, .(run_mae_pp = mean(run_mae_pp), run_mae_sd = sd(run_mae_pp), completed_run_mae_pp = mean(completed_run_mae_pp),
                noise_floor_pp = mean(noise_floor_pp), brier = mean(brier), err01 = mean(err01),
                logloss = mean(logloss), auc = mean(auc, na.rm = TRUE), tasks_per_run = mean(mean_heldout_tasks_per_run),
                n_singular = sum(singular), n = .N), by = .(frac, predictor)]
fwrite(summ, file.path(outdir, "holdout_summary.csv")); print(summ, digits = 3)
