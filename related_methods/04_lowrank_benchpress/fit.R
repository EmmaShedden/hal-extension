# Method 04: BenchPress / "You Don't Need to Run Every Eval" (Zeng & Papailiopoulos 2026; microsoft/benchpress).
# Default predictor "Logit Bias-ALS": logit of clipped scores, per-column z-score, Z = mu + a_r + c_c + U_r V_c^T by ridge ALS
# (rank 2, lambda 0.1, 40 iterations), averaged over seeds 42-51 (related_methods/DESIGN.md, method 04).
# Usage: ./run_R.sh related_methods/04_lowrank_benchpress/fit.R
source("related_methods/common.R")
out <- RM("04_lowrank_benchpress", "results"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
d <- load_rm_data(); ct <- cell_table(d)
RANK <- 2; LAMBDA <- 0.1; ITERS <- 40; SEEDS <- 42:51

# completers.py: complete_bias_als. obs: data.table(i, j, z); returns the full reconstruction matrix
bias_als <- function(obs, nr, nc, k, lambda, iters, seed) {
  set.seed(seed)
  U <- matrix(rnorm(nr * k, 0, 0.01), nr, k); V <- matrix(rnorm(nc * k, 0, 0.01), nc, k)
  a <- numeric(nr); cc <- numeric(nc); mu <- mean(obs$z)
  byr <- split(seq_len(nrow(obs)), obs$i); byc <- split(seq_len(nrow(obs)), obs$j)
  ridge <- function(X, t) solve(crossprod(X) + lambda * diag(ncol(X)), crossprod(X, t))
  for (it in seq_len(iters)) {
    for (r in names(byr)) { s <- byr[[r]]; i <- as.integer(r); jj <- obs$j[s]
      w <- ridge(cbind(1, V[jj, , drop = FALSE]), obs$z[s] - mu - cc[jj]); a[i] <- w[1]; U[i, ] <- w[-1] }
    for (cl in names(byc)) { s <- byc[[cl]]; j <- as.integer(cl); ii <- obs$i[s]
      w <- ridge(cbind(1, U[ii, , drop = FALSE]), obs$z[s] - mu - a[ii]); cc[j] <- w[1]; V[j, ] <- w[-1] }
    mu <- mean(obs$z - a[obs$i] - cc[obs$j] - rowSums(U[obs$i, , drop = FALSE] * V[obs$j, , drop = FALSE]))
  }
  list(Z = mu + outer(a, cc, `+`) + U %*% t(V), a = a, c = cc, U = U, V = V, mu = mu)
}

ct[, `:=`(i = as.integer(llm), j = as.integer(column))]
ct[, x := qlogis(pmin(pmax(acc, 0.005), 0.995))]                          # transforms.py: _to_logit, clip [0.5, 99.5] %
cs <- ct[, .(m = mean(x), s = sqrt(mean((x - mean(x))^2))), by = j]      # col_stats: nanmean, nanstd (ddof 0)
cs[s < 1e-8, s := 1]
ct <- merge(ct, cs, by = "j"); ct[, z := (x - m) / s]
nr <- nlevels(ct$llm); nc <- nlevels(ct$column)
fits <- lapply(SEEDS, function(sd) bias_als(ct[, .(i, j, z)], nr, nc, RANK, LAMBDA, ITERS, sd))
Zbar <- Reduce(`+`, lapply(fits, `[[`, "Z")) / length(fits)
ct[, pred := plogis(Zbar[cbind(i, j)] * s + m)]
saveRDS(list(fits = fits, Zbar = Zbar, rows = levels(ct$llm), cols = levels(ct$column), col_stats = cs), RM("04_lowrank_benchpress", "fits.Rds"))

p_task <- expand_cell_pred(d, ct)
npar <- 1 + nr + nc + RANK * (nr + nc)
met <- cbind(fit_metrics(d, p_task, "BenchPress Logit Bias-ALS (rank 2, lambda 0.1), reconstruction"), n_params = npar, cells = nrow(ct),
             cell_mae_pp = 100 * mean(abs(ct$pred - ct$acc)))
bb <- cbind(method = "BenchPress", run_mae_by_benchmark(d, p_task))
full <- CJ(llm = levels(ct$llm), column = levels(ct$column))
full[, pred := plogis(Zbar[cbind(match(llm, levels(ct$llm)), match(column, levels(ct$column)))] *
                        cs$s[match(match(column, levels(ct$column)), cs$j)] + cs$m[match(match(column, levels(ct$column)), cs$j)])]
full[, observed := paste(llm, column) %in% paste(ct$llm, ct$column)]
write_outputs(out, met, bb, list(cells = ct[, .(llm, column, acc, pred)], completed_matrix = full))
print(met, digits = 3)
