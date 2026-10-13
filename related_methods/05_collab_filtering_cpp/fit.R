# Method 05: Collaborative Performance Prediction (Zhang et al. 2024; Don-Joey/CPP_LLM).
# Scores min-max normalised per model row (missing set to 0, so divided by the row max); r = <p_row, q_col>, d = 10,
# SGD lr 0.01, batch 16, MSE, 250,000 epochs, init N(0, 0.01^2). CPP-MF (ids only) and CPP with factor embeddings
# (related_methods/DESIGN.md, method 05). Usage: ./run_R.sh related_methods/05_collab_filtering_cpp/fit.R
source("related_methods/common.R"); suppressPackageStartupMessages({library(Rcpp); library(parallel)})
sourceCpp(RM("05_collab_filtering_cpp", "sgd_mf.cpp"))
out <- RM("05_collab_filtering_cpp", "results"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
d <- load_rm_data(); ct <- cell_table(d)
D <- 10; LR <- 0.01; EPOCHS <- as.integer(Sys.getenv("CPP_EPOCHS", "250000")); BATCH <- 16; INIT_SD <- 0.01; SEED <- 1

ct[, rowmax := max(acc), by = llm]
ct[, y := acc / rowmax]
# categorical factors -> global indices (0-based) into one embedding table per side
index_table <- function(dt, cols) {
  off <- 0L; I <- matrix(0L, nrow(dt), length(cols))
  for (k in seq_along(cols)) { f <- factor(dt[[cols[k]]]); I[, k] <- off + as.integer(f) - 1L; off <- off + nlevels(f) }
  list(I = I, n = off)
}
none <- matrix(0, nrow(ct), 0)
specs <- list(
  `CPP-MF` = list(m = "llm", c = "column", xm = none),
  `CPP-MF + factor embeddings` = list(m = c("llm", "provider", "reasoning_model", "effort"), c = c("column", "benchmark", "domain", "generalist"),
                                      xm = matrix(ct$release_years_z, ncol = 1)))
fits <- mclapply(specs, function(s) {
  tm <- index_table(ct, s$m); tc <- index_table(ct, s$c)
  set.seed(SEED)
  t0 <- Sys.time()
  f <- sgd_mf(tm$I, s$xm, tm$n, tc$I, none, tc$n, ct$y, D, LR, EPOCHS, BATCH, INIT_SD)
  f$seconds <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  f$n_params <- (tm$n + tc$n + ncol(s$xm)) * D
  f
}, mc.cores = length(specs))
saveRDS(list(fits = fits, specs = specs, epochs = EPOCHS), RM("05_collab_filtering_cpp", "fits.Rds"))

met <- rbindlist(lapply(names(fits), function(k) {
  ct[, pred := pmin(pmax(fits[[k]]$fitted * rowmax, 0), 1)]               # back to accuracy; clipped to [0, 1]
  cbind(fit_metrics(d, expand_cell_pred(d, ct), k), n_params = fits[[k]]$n_params, epochs = EPOCHS,
        train_mse_normalised = mean((fits[[k]]$fitted - ct$y)^2), seconds = fits[[k]]$seconds)
}))
bb <- rbindlist(lapply(names(fits), function(k) {
  ct[, pred := pmin(pmax(fits[[k]]$fitted * rowmax, 0), 1)]
  cbind(method = k, run_mae_by_benchmark(d, expand_cell_pred(d, ct)))
}))
cells <- ct[, .(llm, column, acc, rowmax)]
for (k in names(fits)) cells[[paste0("pred_", k)]] <- pmin(pmax(fits[[k]]$fitted * ct$rowmax, 0), 1)
write_outputs(out, met, bb, list(cells = cells))
print(met, digits = 3)
