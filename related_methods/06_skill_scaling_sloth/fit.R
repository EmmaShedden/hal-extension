# Method 06: Sloth (Maia Polo et al. 2024/25; felipemaiapolo/sloth), adapted. Skills come only from model covariates:
#   theta_r = W_D' onehot(family_r) + W_X' x_r,   mu_rc = sigmoid(Lambda_c . theta_r + b_c)   (guessing floor gamma = 0)
# family = provider x reasoning model; x = (release date z, effort high, low, none vs default), in place of log params/tokens
# (unknown for 13 of 15 models). SmoothL1(beta = 0.01) loss, full-batch Adam, lr in {0.1, 0.01, 0.001} keeping the best
# training MAE, ReduceLROnPlateau(0.95, patience 20), <= 100k epochs, early stop after 500 without MAE improvement
# (related_methods/DESIGN.md, method 06). Usage: ./run_R.sh related_methods/06_skill_scaling_sloth/fit.R
source("related_methods/common.R"); suppressPackageStartupMessages(library(parallel))
out <- RM("06_skill_scaling_sloth", "results"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
d <- load_rm_data(); ct <- cell_table(d)
MAX_EPOCHS <- 100000; PATIENCE_STOP <- 500; BETA <- 0.01; SEED <- 1

rows <- unique(ct[, .(llm, provider, reasoning_model, effort, release_years_z)])[order(llm)]
rows[, family := factor(paste(provider, ifelse(reasoning_model, "reasoning", "non-reasoning")))]
X <- cbind(release = rows$release_years_z, high = rows$effort == "high", low = rows$effort == "low", none = rows$effort == "none") * 1
Dm <- model.matrix(~ 0 + family, rows)
ri <- match(ct$llm, rows$llm); ci <- as.integer(ct$column); nc <- nlevels(ct$column); y <- ct$acc

sloth_fit <- function(k, lr0) {
  set.seed(SEED)
  P <- list(WX = matrix(abs(rnorm(ncol(X) * k)), ncol(X), k), WD = matrix(rnorm(ncol(Dm) * k), ncol(Dm), k),
            L = matrix(abs(rnorm(nc * k)), nc, k), b = numeric(nc))
  M <- lapply(P, `*`, 0); V <- M
  fwd <- function(P) { th <- Dm %*% P$WD + X %*% P$WX; eta <- rowSums(th[ri, , drop = FALSE] * P$L[ci, , drop = FALSE]) + P$b[ci]
                       list(th = th, s = plogis(eta)) }
  lr <- lr0; best_mae <- Inf; best <- P; since_best <- 0; best_loss <- Inf; since_loss <- 0
  for (ep in seq_len(MAX_EPOCHS)) {
    F <- fwd(P); e <- F$s - y
    loss <- mean(ifelse(abs(e) < BETA, 0.5 * e^2 / BETA, abs(e) - 0.5 * BETA)); mae <- mean(abs(e))
    if (mae < best_mae - 1e-12) { best_mae <- mae; best <- P; since_best <- 0 } else since_best <- since_best + 1
    if (since_best >= PATIENCE_STOP) break
    if (loss < best_loss) { best_loss <- loss; since_loss <- 0 } else if ((since_loss <- since_loss + 1) > 20) { lr <- lr * 0.95; since_loss <- 0 }
    g <- ifelse(abs(e) < BETA, e / BETA, sign(e)) / length(y) * F$s * (1 - F$s)
    gth <- matrix(0, nrow(rows), k); GL <- matrix(0, nc, k)
    for (j in seq_len(k)) { gth[, j] <- tapply(g * P$L[ci, j], factor(ri, seq_len(nrow(rows))), sum, default = 0)
                            GL[, j] <- tapply(g * F$th[ri, j], factor(ci, seq_len(nc)), sum, default = 0) }
    G <- list(WX = crossprod(X, gth), WD = crossprod(Dm, gth), L = GL, b = as.vector(tapply(g, factor(ci, seq_len(nc)), sum, default = 0)))
    for (nm in names(P)) {                                               # Adam (torch defaults: 0.9, 0.999, 1e-8)
      M[[nm]] <- 0.9 * M[[nm]] + 0.1 * G[[nm]]; V[[nm]] <- 0.999 * V[[nm]] + 0.001 * G[[nm]]^2
      P[[nm]] <- P[[nm]] - lr * (M[[nm]] / (1 - 0.9^ep)) / (sqrt(V[[nm]] / (1 - 0.999^ep)) + 1e-8)
    }
  }
  F <- fwd(best)
  list(P = best, fitted = F$s, theta = F$th, train_mae = best_mae, epochs = ep, lr = lr0, k = k)
}
grid <- CJ(k = c(3, 1), lr = c(0.1, 0.01, 0.001))
runs <- mclapply(seq_len(nrow(grid)), function(i) sloth_fit(grid$k[i], grid$lr[i]), mc.cores = nrow(grid))
grid[, `:=`(train_mae_pp = 100 * vapply(runs, `[[`, 0, "train_mae"), epochs = vapply(runs, `[[`, 0, "epochs"))]
fits <- lapply(c(3, 1), function(k) { i <- which(grid$k == k); runs[[i[which.min(grid$train_mae_pp[i])]]] })
names(fits) <- c("d3", "d1")
saveRDS(list(fits = fits, grid = grid, rows = rows, X = X, D = Dm, cols = levels(ct$column)), RM("06_skill_scaling_sloth", "fits.Rds"))

npar <- function(k) (ncol(X) + ncol(Dm) + nc) * k + nc
met <- rbindlist(lapply(names(fits), function(n) { ct[, pred := fits[[n]]$fitted]
  cbind(fit_metrics(d, expand_cell_pred(d, ct), sprintf("Sloth-adapted, %d skill(s), covariates only (no per-model parameters)", fits[[n]]$k)),
        n_params = npar(fits[[n]]$k), lr = fits[[n]]$lr, epochs = fits[[n]]$epochs) }))
bb <- rbindlist(lapply(names(fits), function(n) { ct[, pred := fits[[n]]$fitted]
  cbind(method = paste("Sloth", n), run_mae_by_benchmark(d, expand_cell_pred(d, ct))) }))
eff <- data.table(term = c(colnames(X), colnames(Dm)), rbind(fits$d1$P$WX, fits$d1$P$WD))   # 1-skill coefficients (sign set by Lambda)
setnames(eff, "V1", "skill_coef_d1")
eff[, loading_sign := sign(mean(fits$d1$P$L))]
write_outputs(out, met, bb, list(lr_grid = grid, skill_coefficients_d1 = eff))
print(grid); print(met, digits = 3); print(eff, digits = 3)
