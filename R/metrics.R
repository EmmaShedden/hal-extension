# Prediction-error metrics shared by Part 1, Part 2 and the extensions.
brier <- function(p, y) mean((p - y)^2)
logloss <- function(p, y, eps = 1e-12) { p <- pmin(pmax(p, eps), 1 - eps); -mean(y * log(p) + (1 - y) * log(1 - p)) }
err01 <- function(p, y) mean((p >= 0.5) != y)
auc <- function(p, y) {  # Mann-Whitney AUC
  if (length(unique(y)) < 2) return(NA_real_)
  r <- rank(p); n1 <- sum(y == 1); n0 <- sum(y == 0)
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}
# run-level accuracy error: per run, mean predicted p vs observed accuracy (percentage points)
run_level <- function(dt, pcol = "p") {
  r <- dt[, .(obs = mean(success), pred = mean(get(pcol)), n = .N), by = .(run, cell, benchmark)]
  r[, abs_err_pp := 100 * abs(pred - obs)]
  r
}
task_metrics <- function(p, y) data.frame(brier = brier(p, y), logloss = logloss(p, y), err01 = err01(p, y), auc = auc(p, y), n = length(y))
