# Method 03: A Rosetta Stone for AI Benchmarks / Epoch Capabilities Index (Ho et al. 2025; epoch-research/benchmark-stitching).
# score_rc = sigmoid(alpha_c (C_r - D_c)) on aggregate scores, least squares + lambda * sum(params^2) / n_params (lambda = 0.1),
# bounds C, D in [-10, 10], alpha in [0.1, 10], anchor alpha fixed at 1 and D shifted to 0 after the fit
# (related_methods/DESIGN.md, method 03). Usage: ./run_R.sh related_methods/03_benchmark_irt_eci/fit.R
source("related_methods/common.R")
out <- RM("03_benchmark_irt_eci", "results"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
d <- load_rm_data(); ct <- cell_table(d)
LAMBDA <- 0.1

eci_fit <- function(y, r, cc, anchor, lambda = LAMBDA) {
  r <- droplevels(factor(r)); cc <- droplevels(factor(cc))
  nr <- nlevels(r); nc <- nlevels(cc); ri <- as.integer(r); ci <- as.integer(cc); a0 <- match(anchor, levels(cc))
  stopifnot(!is.na(a0)); af <- setdiff(seq_len(nc), a0); np <- nr + nc + length(af)
  y <- pmin(pmax(y, 0), 1)                                   # code clips only values outside [0, 1] (to [0.001, 0.999])
  unpack <- function(p) { al <- rep(1, nc); al[af] <- p[nr + nc + seq_along(af)]; list(C = p[seq_len(nr)], D = p[nr + seq_len(nc)], al = al) }
  fn <- function(p) { P <- unpack(p); s <- plogis(P$al[ci] * (P$C[ri] - P$D[ci])); sum((s - y)^2) + lambda * sum(p^2) / np }
  gr <- function(p) {
    P <- unpack(p); u <- P$C[ri] - P$D[ci]; a <- P$al[ci]; s <- plogis(a * u); g <- 2 * (s - y) * s * (1 - s)
    c(as.vector(tapply(g * a, ri, sum, default = 0)), as.vector(tapply(-g * a, ci, sum, default = 0)),
      as.vector(tapply(g * u, ci, sum, default = 0))[af]) + 2 * lambda * p / np
  }
  set.seed(42); p0 <- c(0.1 * rnorm(nr + nc), rep(1, length(af)))
  lo <- c(rep(-10, nr + nc), rep(0.1, length(af))); hi <- c(rep(10, nr + nc), rep(10, length(af)))
  o <- optim(p0, fn, gr, method = "L-BFGS-B", lower = lo, upper = hi, control = list(maxit = 20000, factr = 10, pgtol = 1e-10))
  P <- unpack(o$par); fitted <- plogis(P$al[ci] * (P$C[ri] - P$D[ci]))
  shift <- P$D[a0]; P$C <- P$C - shift; P$D <- P$D - shift          # anchor D = 0 after the fit (fit unchanged)
  list(P = P, fitted = fitted, convergence = o$convergence, message = o$message, n_params = np, rows = levels(r), cols = levels(cc),
       at_bound = sum(o$par <= lo + 1e-6 | o$par >= hi - 1e-6))
}
pick_anchor <- function(cols) { tb <- table(cols); tb <- tb[tb == max(tb)]; sort(names(tb))[1] }

# primary: all 172 cells, columns = scaffold x benchmark
anc <- pick_anchor(as.character(ct$column))
f <- eci_fit(ct$acc, ct$llm, ct$column, anc); stopifnot(f$convergence == 0)
ct[, pred := f$fitted]
p_task <- expand_cell_pred(d, ct)
met <- cbind(fit_metrics(d, p_task, "ECI sigmoid(alpha_c (C_r - D_c)), rows = model x effort, columns = scaffold x benchmark"),
             n_params = f$n_params, cells = nrow(ct), anchor = anc, params_at_bound = f$at_bound)
bb <- cbind(method = "ECI primary", run_mae_by_benchmark(d, p_task))

# faithful: ECI data rules -- max score per row x benchmark, benchmark columns, rows with <= 3 benchmarks dropped
mx <- ct[order(-acc, column)][, .SD[1], by = .(llm, benchmark)]
mx <- mx[llm %in% mx[, .N, by = llm][N > 3, llm]]
anc2 <- pick_anchor(as.character(mx$benchmark))
f2 <- eci_fit(mx$acc, mx$llm, mx$benchmark, anc2); stopifnot(f2$convergence == 0)
mx[, pred := f2$fitted]
met2 <- data.table(method = "ECI faithful (max scaffold per model x benchmark, rows with > 3 benchmarks; metrics on those maxima only)",
                   n = nrow(mx), run_mae_pp = 100 * mean(abs(mx$pred - mx$acc)), run_rmse_pp = 100 * sqrt(mean((mx$pred - mx$acc)^2)),
                   run_cor = cor(mx$pred, mx$acc), n_params = f2$n_params, cells = nrow(mx), anchor = anc2, params_at_bound = f2$at_bound)
saveRDS(list(primary = f, faithful = f2), RM("03_benchmark_irt_eci", "fits.Rds"))
cap <- merge(data.table(llm = f$rows, C = f$P$C), data.table(llm = f2$rows, C_faithful = f2$P$C), by = "llm", all.x = TRUE)[order(-C)]
colp <- data.table(column = f$cols, D = f$P$D, alpha = f$P$al)
write_outputs(out, rbindlist(list(met, met2), fill = TRUE), bb,
              list(capability = cap, column_params = colp, faithful_benchmark_params = data.table(benchmark = f2$cols, D = f2$P$D, alpha = f2$P$al),
                   faithful_cells = mx[, .(llm, benchmark, column, acc, pred)]))
print(rbindlist(list(met, met2), fill = TRUE), digits = 3); print(cap, digits = 3); print(colp, digits = 3)
