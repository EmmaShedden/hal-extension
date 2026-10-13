# Method 07: Observational Scaling Laws (Ruan, Maddison, Hashimoto 2024; ryoungj/ObsScaling).
# Capabilities = PCs of external non-agentic benchmark scores (pca_impute, then PCA on unstandardised scores; PC1-3);
# each HAL column (scaffold x benchmark) regressed as y = (1 - f) sigmoid(w0 + w'PC) + f, f in [0, 0.2], least squares.
# Small columns: >= 10 cells PC1-3, 5-9 cells PC1, fewer -> column mean. Variant: ECI as the 1-D capability.
# (related_methods/DESIGN.md, method 07). Usage: run build_external_scores.R first, then ./run_R.sh related_methods/07_observational_scaling/fit.R
source("related_methods/common.R")
out <- RM("07_observational_scaling", "results")
d <- load_rm_data(); ct <- cell_table(d)
X <- fread(file.path(out, "external_scores.csv"))
bench <- setdiff(names(X), c("Model", "model", "eci"))
S <- as.matrix(X[, ..bench]); rownames(S) <- X$model

# utils/data.py: pca_impute -- standardise, mean-fill, iterate 1-component PCA reconstruction of missing cells, unscale, clip
pca_impute <- function(S, maxit = 1000, tol = 1e-4) {
  miss <- is.na(S); mu <- colMeans(S, na.rm = TRUE); sdv <- apply(S, 2, sd, na.rm = TRUE) * sqrt((colSums(!miss) - 1) / colSums(!miss))
  Z <- sweep(sweep(S, 2, mu), 2, sdv, "/"); Z[miss] <- 0
  for (it in seq_len(maxit)) {
    m <- colMeans(Z); Zc <- sweep(Z, 2, m); sv <- svd(Zc, nu = 1, nv = 1)
    R <- sweep(sv$d[1] * sv$u %*% t(sv$v), 2, m, "+")
    delta <- max(abs(R[miss] - Z[miss])); Z[miss] <- R[miss]
    if (delta < tol) break
  }
  out <- sweep(sweep(Z, 2, sdv, "*"), 2, mu, "+"); pmin(pmax(out, 0), 1)
}
Si <- pca_impute(S)
pc <- prcomp(Si, center = TRUE, scale. = FALSE)
PC <- pc$x[, 1:3]
cap_sets <- list(`PC1-3 of external benchmarks` = PC,
                 `ECI (z-scored)` = matrix(as.vector(scale(X$eci)), ncol = 1, dimnames = list(X$model, "eci")))

# sigmoid-parametric regression; p0 = [w0 = 0, w = 0.03, f = 0]; f bounded to [0, 0.2]
sig_fit <- function(y, Z) {
  k <- ncol(Z)
  fn <- function(p) { f <- p[k + 2]; s <- plogis(p[1] + Z %*% p[2:(k + 1)]); sum(((1 - f) * s + f - y)^2) }
  gr <- function(p) { f <- p[k + 2]; s <- as.vector(plogis(p[1] + Z %*% p[2:(k + 1)])); r <- 2 * ((1 - f) * s + f - y)
                      ge <- r * (1 - f) * s * (1 - s); c(sum(ge), crossprod(Z, ge), sum(r * (1 - s))) }
  o <- optim(c(0, rep(0.03, k), 0), fn, gr, method = "L-BFGS-B", lower = c(rep(-Inf, k + 1), 0), upper = c(rep(Inf, k + 1), 0.2),
             control = list(maxit = 10000, factr = 10))
  list(par = o$par, fitted = as.vector((1 - o$par[k + 2]) * plogis(o$par[1] + Z %*% o$par[2:(k + 1)]) + o$par[k + 2]), conv = o$convergence)
}
res <- list(); coefs <- list()
for (nm in names(cap_sets)) {
  Cm <- cap_sets[[nm]]; ct[, pred := NA_real_]; ct[, k_used := NA_integer_]; npar <- 0
  for (col in levels(ct$column)) {
    i <- which(ct$column == col); n <- length(i)
    k <- if (n >= 10) min(3, ncol(Cm)) else if (n >= 5) 1 else 0
    if (k == 0) { ct$pred[i] <- mean(ct$acc[i]); npar <- npar + 1; ct$k_used[i] <- 0L; next }
    Z <- Cm[as.character(ct$model[i]), 1:k, drop = FALSE]
    f <- sig_fit(ct$acc[i], Z); stopifnot(f$conv == 0)
    ct$pred[i] <- f$fitted; ct$k_used[i] <- k; npar <- npar + k + 2
    coefs[[length(coefs) + 1]] <- data.table(capability = nm, column = col, cells = n, k = k, w0 = f$par[1],
                                             w = paste(round(f$par[2:(k + 1)], 3), collapse = ";"), floor = f$par[k + 2])
  }
  res[[nm]] <- list(cells = copy(ct), n_params = npar)
}
saveRDS(list(res = res, pca = pc, imputed = Si, coefs = rbindlist(coefs)), RM("07_observational_scaling", "fits.Rds"))
met <- rbindlist(lapply(names(res), function(nm) cbind(fit_metrics(d, expand_cell_pred(d, res[[nm]]$cells), paste("OSL sigmoid regression on", nm)),
                                                        n_params = res[[nm]]$n_params)))
bb <- rbindlist(lapply(names(res), function(nm) cbind(method = paste("OSL", nm), run_mae_by_benchmark(d, expand_cell_pred(d, res[[nm]]$cells)))))
ve <- data.table(pc = paste0("PC", 1:ncol(pc$x)), var_share = pc$sdev^2 / sum(pc$sdev^2))
load <- data.table(benchmark = rownames(pc$rotation), pc$rotation[, 1:3])
capab <- data.table(model = rownames(PC), PC, eci = X$eci)
write_outputs(out, met, bb, list(pca_variance = ve, pca_loadings = load, capabilities = capab, column_fits = rbindlist(coefs),
                                 imputed_scores = data.table(model = rownames(Si), Si)))
print(met, digits = 3); print(ve, digits = 3); print(rbindlist(coefs), digits = 3)
