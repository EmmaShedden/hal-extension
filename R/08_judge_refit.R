# Extension 3: refit the selected (primary) formula on judge-corrected data; compare TAU-bench fit with uncorrected.
# Usage: ./run_R.sh R/08_judge_refit.R   (then ./run_R.sh R/04_holdout.R 60 <variant> for each variant)
source("R/common.R"); source("R/metrics.R"); source("R/judge.R")
suppressPackageStartupMessages(library(parallel))
out <- path("results/ext3_judge"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d0 <- L$d
f <- as.formula(readLines(path("results/selected_formula.txt"))[2])
m0 <- readRDS(path("fits/selected_model.Rds"))
variants <- c("judge_both", "judge_any", "manual")
fits <- mclapply(variants, function(v) {
  d <- apply_judge_correction(d0, v)
  m <- glmer(f, data = d, family = binomial, control = CTRL)
  saveRDS(m, path(sprintf("fits/selected_model_%s.Rds", v))); m
}, mc.cores = 3)
names(fits) <- variants
summ <- function(m, d, v) {
  d$p <- predict(m, type = "response")
  tau <- d$benchmark == "TAU-bench Airline"
  rl <- run_level(d); rl_t <- run_level(d[tau])
  data.frame(variant = v, n_tau_tasks = uniqueN(d$task[tau]), tau_acc = mean(d$success[tau]),
             tau_brier = brier(d$p[tau], d$success[tau]), tau_auc = auc(d$p[tau], d$success[tau]),
             tau_run_mae_pp = mean(rl_t$abs_err_pp), all_brier = brier(d$p, d$success), all_run_mae_pp = mean(rl$abs_err_pp),
             tau_task_sd = NA, singular = isSingular(m))
}
res <- rbind(summ(m0, d0, "uncorrected"), do.call(rbind, lapply(variants, function(v) summ(fits[[v]], apply_judge_correction(d0, v), v))))
# fixed-effect change for TAU-bench (benchmark difficulty after removing broken tasks)
res$tau_benchmark_coef <- c(fixef(m0)["benchmarkTAU-bench Airline"], sapply(fits, function(m) fixef(m)["benchmarkTAU-bench Airline"]))
fwrite(res, file.path(out, "in_sample_comparison.csv")); print(res)
