# Shared helpers for the related-work method comparison (related_methods/DESIGN.md).
# Every method fits the same Part 1 data as the GLMER (174 paper runs, 21,333 task outcomes) and reports the same
# quality-of-fit metrics. Run from the repository root: ./run_R.sh related_methods/<method>/fit.R
source("R/common.R"); source("R/metrics.R")
RM <- function(...) path("related_methods", ...)

# Task-level table (identical rows to Part 1) plus the identifiers each method needs.
#   agent  = model | scaffold | effort   (Messier's agent string: model + scaffold + reasoning effort)
#   llm    = model | effort              (the model configuration; AP's theta_LLM, the matrix row)
#   column = scaffold | benchmark        (the measurement; the matrix column)
load_rm_data <- function() {
  L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- copy(L$d)
  d[, agent := factor(paste(model, scaffold, effort, sep = "|"))]
  d[, llm := factor(paste(model, effort, sep = "|"))]
  d[, column := factor(paste(scaffold, benchmark, sep = "|"))]
  d
}

# Cell table for the aggregate-score methods: one row per cell (llm x column), with the accuracy pooled over the
# cell's replicate runs (k successes of n task outcomes) and the covariates of the cell.
cell_table <- function(d) {
  d[, .(k = sum(success), n = .N, acc = mean(success)),
    by = .(cell, llm, column, model, effort, scaffold, benchmark, domain, provider, reasoning_model, generalist,
           release_years_z)]
}

# Logit with the clipping used for 0 % / 100 % scores (DESIGN.md: half a task, i.e. (k + 0.5) / (n + 1)).
emp_logit <- function(k, n) qlogis((k + 0.5) / (n + 1))

# Quality of fit, in the same form as results/part1/in_sample_metrics.csv.
# Task-level methods pass task rows with column p; aggregate methods pass cell predictions (pred_cell, by cell),
# which are expanded to every task row of the cell (the method has no task information).
fit_metrics <- function(d, p, label) {
  dd <- copy(d)[, p := p]
  rl <- run_level(dd)
  cbind(method = label, task_metrics(dd$p, dd$success),
        run_mae_pp = mean(rl$abs_err_pp), run_rmse_pp = sqrt(mean(rl$abs_err_pp^2)), run_cor = cor(rl$obs, rl$pred))
}
expand_cell_pred <- function(d, cells) cells$pred[match(d$cell, cells$cell)]

# Per-benchmark run MAE, the breakdown REPORT.md §3 gives for the GLMER.
run_mae_by_benchmark <- function(d, p) {
  rl <- run_level(copy(d)[, p := p])
  rl[, .(run_mae_pp = mean(abs_err_pp), max_err_pp = max(abs_err_pp), runs = .N), by = benchmark][order(benchmark)]
}


write_outputs <- function(dir, metrics, by_bench = NULL, extra = list()) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  fwrite(metrics, file.path(dir, "in_sample_metrics.csv"))
  if (!is.null(by_bench)) fwrite(by_bench, file.path(dir, "run_mae_by_benchmark.csv"))
  for (nm in names(extra)) fwrite(extra[[nm]], file.path(dir, paste0(nm, ".csv")))
}
