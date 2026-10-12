# Extension 1b: Agent Psychometrics task features x agent interactions (SWE-bench Verified Mini). DESIGN.md "E1b".
# Usage: ./run_R.sh R/11_ap_interactions.R full            # full-data fits, LRTs, PF-1 reduction of the primary
#        ./run_R.sh R/11_ap_interactions.R cell [n_cores]  # cell holdout (Part 2 grid/seeds), all models
#        ./run_R.sh R/11_ap_interactions.R task [n_cores]  # task-level holdout (Part 2b grid/seeds), all models
#        ./run_R.sh R/11_ap_interactions.R summary         # paired seed-bootstrap comparisons vs M0
source("R/common.R"); source("R/metrics.R")
suppressPackageStartupMessages(library(parallel))
args <- commandArgs(TRUE)
mode <- if (length(args) >= 1) args[1] else "full"
ncores <- if (length(args) >= 2) as.integer(args[2]) else 90
SWE <- "SWE-bench Verified Mini"
out <- path("results/ext1b_interactions"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
fitdir <- path("fits/ext1b"); dir.create(fitdir, recursive = TRUE, showWarnings = FALSE)
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
f0 <- as.formula(readLines(path("results/selected_formula.txt"))[2])

# ---- features (AP default 15; PCA and ridge fit on the 500 / 450 external Verified tasks) ----
build_features <- function() {
  feat <- fread(path("data/external/agent_psychometrics/swebench_verified_llm_judge_features_defaults15.csv"))
  items <- fread(path("data/external/agent_psychometrics/swebench_verified_irt_1pl_items.csv")); setnames(items, 1, "instance_id")
  feat <- merge(feat, items[, .(instance_id, b)], by = "instance_id"); stopifnot(nrow(feat) == 500)
  fcols <- setdiff(names(feat), c("instance_id", "b"))
  Z <- scale(as.matrix(feat[, ..fcols]))
  pc <- prcomp(Z)
  S <- pc$x[, 1:2]; sgn <- sign(cor(S, feat$b)); S <- sweep(S, 2, sgn, `*`)
  rot <- sweep(pc$rotation[, 1:2], 2, sgn, `*`)
  mini <- unique(d[benchmark == SWE, as.character(task_id)]); is_mini <- feat$instance_id %in% mini
  stopifnot(sum(is_mini) == 50)
  # AP two-stage: ridge of frozen 1PL b on z-features, trained on the 450 non-Mini tasks, lambda by 5-fold CV MSE
  Xtr <- Z[!is_mini, ]; ytr <- feat$b[!is_mini]
  ridge <- function(X, y, lam) { mx <- colMeans(X); my <- mean(y); Xc <- sweep(X, 2, mx)
    w <- solve(crossprod(Xc) + lam * diag(ncol(X)), crossprod(Xc, y - my)); list(w = w, b0 = my - sum(mx * w)) }
  pr <- function(fit, X) drop(X %*% fit$w) + fit$b0
  lams <- 10^seq(-3, 4, length.out = 50); set.seed(0); fold <- sample(rep(1:5, length.out = nrow(Xtr)))
  cvmse <- sapply(lams, function(l) mean(unlist(lapply(1:5, function(k) {
    fit <- ridge(Xtr[fold != k, ], ytr[fold != k], l); (pr(fit, Xtr[fold == k, , drop = FALSE]) - ytr[fold == k])^2 }))))
  lam <- lams[which.min(cvmse)]; rf <- ridge(Xtr, ytr, lam)
  dhat <- pr(rf, Z)
  z50 <- function(x) (x - mean(x[is_mini])) / sd(x[is_mini])
  F <- data.table(task_id = feat$instance_id, sw_pc1 = z50(S[, 1]), sw_pc2 = z50(S[, 2]), sw_dhat = z50(dhat), ap_b = feat$b)[is_mini]
  info <- list(rotation = rot, var_explained = pc$sdev^2 / sum(pc$sdev^2), lambda = lam,
               ridge_w = setNames(drop(rf$w), fcols), cor_dhat_b_mini = cor(dhat[is_mini], feat$b[is_mini]),
               cv_r2_450 = 1 - min(cvmse) / var(ytr))
  list(F = F, info = info)
}
FE <- build_features(); F <- FE$F
for (v in c("sw_pc1", "sw_pc2", "sw_dhat")) {
  d[[v]] <- 0
  i <- d$benchmark == SWE
  d[[v]][i] <- F[[v]][match(as.character(d$task_id[i]), F$task_id)]
}
stopifnot(!anyNA(d$sw_pc1), !anyNA(d$sw_dhat))

A <- "provider + reasoning_model + release_years_z + effort + generalist"
base_forms <- list(
  M0 = f0,
  M1 = update(f0, . ~ . + sw_pc1 + sw_pc2),
  M2 = update(f0, as.formula(sprintf(". ~ . + sw_pc1 + sw_pc2 + (sw_pc1 + sw_pc2):(%s)", A))),
  M3 = update(f0, . ~ . + sw_pc1 + sw_pc2 + (0 + sw_pc1 + sw_pc2 | model)),
  M4 = update(f0, as.formula(sprintf(". ~ . + sw_pc1 + sw_pc2 + (sw_pc1 + sw_pc2):(%s) + (0 + sw_pc1 + sw_pc2 | model)", A))),
  D1 = update(f0, . ~ . + sw_dhat),
  D4 = update(f0, as.formula(sprintf(". ~ . + sw_dhat + sw_dhat:(%s) + (0 + sw_dhat | model)", A))))
form_file <- file.path(out, "formulas.Rds")

fit1 <- function(f, data) {
  warns <- character(0)
  m <- withCallingHandlers(glmer(f, data = data, family = binomial, control = CTRL),
    warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") })
  attr(m, "warns") <- paste(unique(c(warns, m@optinfo$conv$lme4$messages)), collapse = " | ")
  m
}

# ---- simulation intervals for run accuracy on held-out rows (DESIGN.md E1b) ----
mvn <- function(n, mu, S) { k <- length(mu); R <- tryCatch(chol(S), error = function(e) { e <- eigen(S, TRUE); t(e$vectors %*% diag(sqrt(pmax(e$values, 0)), k)) })
  matrix(rnorm(n * k), n) %*% R + matrix(mu, n, k, byrow = TRUE) }
sim_intervals <- function(m, nd, ndraw = 1000) {
  tt <- delete.response(terms(m, fixed.only = TRUE))
  fr <- m@frame; xlev <- lapply(fr[vapply(fr, is.factor, TRUE)], levels)
  X <- model.matrix(tt, model.frame(tt, nd, xlev = xlev[intersect(names(xlev), all.vars(tt))]),
                    contrasts.arg = attr(getME(m, "X"), "contrasts"))
  beta <- fixef(m); X <- X[, names(beta), drop = FALSE]
  eta <- X %*% t(mvn(ndraw, beta, as.matrix(vcov(m))))                       # rows x draws
  stopifnot(max(abs(drop(X %*% beta) - predict(m, nd, re.form = NA))) < 1e-6)
  cnms <- getME(m, "cnms"); vc <- VarCorr(m); rr <- as.data.table(as.data.frame(ranef(m, condVar = TRUE)))
  for (i in seq_along(cnms)) {
    g <- names(cnms)[i]; cols <- cnms[[i]]; parts <- strsplit(g, ":", fixed = TRUE)[[1]]
    key <- do.call(paste, c(lapply(parts, function(p) as.character(nd[[p]])), sep = ":"))
    covm <- sapply(cols, function(cl) if (cl == "(Intercept)") rep(1, nrow(nd)) else nd[[cl]]); covm <- matrix(covm, nrow(nd))
    S <- as.matrix(vc[[i]])
    for (lv in unique(key)) {
      idx <- which(key == lv)
      if (all(covm[idx, ] == 0)) next
      sub <- rr[grpvar == g & grp == lv & term %in% cols]
      B <- if (nrow(sub) == length(cols)) { sub <- sub[match(cols, term)]
             sapply(seq_along(cols), function(k) rnorm(ndraw, sub$condval[k], sub$condsd[k])) } else mvn(ndraw, rep(0, length(cols)), S)
      B <- matrix(B, ndraw)
      eta[idx, ] <- eta[idx, ] + covm[idx, , drop = FALSE] %*% t(B)
    }
  }
  P <- plogis(eta); Y <- matrix(rbinom(length(P), 1, P), nrow(P))
  runs <- as.character(nd$run)
  rs <- function(M) rowsum(M, runs) / as.vector(table(runs)[rownames(rowsum(M, runs))])
  Pm <- rs(P); Ym <- rs(Y)
  q <- function(M, p) apply(M, 1, quantile, p)
  data.table(run = rownames(Pm), ci_lo = q(Pm, .05), ci_hi = q(Pm, .95), pi_lo = q(Ym, .05), pi_hi = q(Ym, .95))
}

eval_model <- function(f, train, test, tag) {
  m <- fit1(f, train)
  test$p <- predict(m, newdata = test, type = "response", allow.new.levels = TRUE)
  sw <- test[benchmark == SWE]
  allrl <- run_level(test, "p")
  res <- data.table(tag = tag, singular = isSingular(m), warnings = attr(m, "warns"),
                    all_logloss = logloss(test$p, test$success), all_brier = brier(test$p, test$success),
                    all_run_mae_pp = mean(allrl$abs_err_pp), n_swe_rows = nrow(sw))
  if (nrow(sw) == 0) return(list(res = res, rl = NULL))
  rl <- merge(run_level(sw, "p"), sim_intervals(m, sw), by = "run")
  res[, `:=`(swe_logloss = logloss(sw$p, sw$success), swe_brier = brier(sw$p, sw$success), swe_auc = auc(sw$p, sw$success),
             swe_run_mae_pp = mean(rl$abs_err_pp), swe_ci_width_pp = 100 * mean(rl$ci_hi - rl$ci_lo),
             swe_pi_width_pp = 100 * mean(rl$pi_hi - rl$pi_lo), swe_pi_cover = mean(rl$obs >= rl$pi_lo & rl$obs <= rl$pi_hi),
             swe_ci_cover = mean(rl$obs >= rl$ci_lo & rl$obs <= rl$ci_hi), n_swe_runs = nrow(rl), swe_tasks_per_run = mean(rl$n))]
  list(res = res, rl = rl)
}

if (mode == "full") {
  t0 <- Sys.time()
  full <- mclapply(base_forms, fit1, data = d, mc.cores = length(base_forms))
  saveRDS(full, file.path(fitdir, "full_models.Rds"))
  forms <- base_forms
  # PF-1 reduction for models with random slopes, if singular: drop slope columns with SD < 1e-3
  for (nm in c("M3", "M4", "D4")) {
    m <- full[[nm]]; if (!isSingular(m)) next
    vc <- as.data.frame(VarCorr(m)); vc <- vc[is.na(vc$var2), ]
    zero <- vc[vc$sdcor < 1e-3, ]
    cat(nm, "singular; zero components:\n"); print(zero)
    slope_zero <- zero$var1[zero$grp == "model" & grepl("^sw_", zero$var1)]
    if (length(slope_zero) && !any(zero$var1 == "(Intercept)" & zero$grp %in% c("task", "model", "scaffold", "model:scaffold", "model:effort"))) {
      keep <- setdiff(if (nm == "D4") "sw_dhat" else c("sw_pc1", "sw_pc2"), slope_zero)
      f <- as.formula(paste(deparse(forms[[nm]], width.cutoff = 500L), collapse = ""))
      f <- update(f, as.formula(sprintf(". ~ . - (0 + %s | model)", if (nm == "D4") "sw_dhat" else "sw_pc1 + sw_pc2")))
      if (length(keep)) f <- update(f, as.formula(sprintf(". ~ . + (0 + %s | model)", paste(keep, collapse = " + "))))
      forms[[paste0(nm, "r")]] <- f; full[[paste0(nm, "r")]] <- fit1(f, d)
    }
  }
  saveRDS(forms, form_file); saveRDS(full, file.path(fitdir, "full_models.Rds"))
  ic <- rbindlist(lapply(names(full), function(nm) { m <- full[[nm]]
    data.table(model_id = nm, AIC = AIC(m), BIC = BIC(m), logLik = as.numeric(logLik(m)), df = attr(logLik(m), "df"),
               singular = isSingular(m), warnings = attr(m, "warns")) }))
  ic[, dAIC_vs_M0 := AIC - AIC[model_id == "M0"]]
  lrt <- rbindlist(lapply(list(c("M1", "M0"), c("M2", "M1"), c("M3", "M1"), c("M4", "M1"), c("M4", "M2"), c("M4", "M3"),
                               c("D1", "M0"), c("D4", "D1")), function(p) {
    a <- anova(full[[p[2]]], full[[p[1]]]); data.table(test = paste(p[1], "vs", p[2]), chisq = a$Chisq[2], df = a$Df[2], p = a$`Pr(>Chisq)`[2]) }))
  fwrite(ic, file.path(out, "full_ic.csv")); fwrite(lrt, file.path(out, "full_lrt.csv"))
  co <- rbindlist(lapply(names(full), function(nm) { s <- coef(summary(full[[nm]]))
    data.table(model_id = nm, term = rownames(s), est = s[, 1], se = s[, 2], z = s[, 3], p = s[, 4]) }))
  fwrite(co[grepl("sw_", term)], file.path(out, "full_feature_coefs.csv"))
  re <- rbindlist(lapply(names(full), function(nm) cbind(model_id = nm, as.data.table(as.data.frame(VarCorr(full[[nm]]))))))
  fwrite(re, file.path(out, "full_varcorr.csv"))
  slopes <- rbindlist(lapply(intersect(names(full), c("M3", "M4", "M4r", "D4", "D4r")), function(nm) {
    r <- ranef(full[[nm]])$model; r <- r[, grep("^sw_", names(r)), drop = FALSE]
    cbind(model_id = nm, model = rownames(r), as.data.table(r)) }), fill = TRUE)
  fwrite(slopes, file.path(out, "full_model_slopes.csv"))
  fwrite(F, file.path(out, "swe_task_features.csv"))
  fwrite(data.table(feature = rownames(FE$info$rotation), FE$info$rotation, ridge_w = FE$info$ridge_w[rownames(FE$info$rotation)]),
         file.path(out, "pc_loadings_ridge_weights.csv"))
  writeLines(c(sprintf("var explained PC1..PC5: %s", paste(round(FE$info$var_explained[1:5], 3), collapse = ", ")),
               sprintf("ridge lambda: %.3g; CV R2 on 450 tasks: %.3f; cor(dhat, b) on Mini: %.3f",
                       FE$info$lambda, FE$info$cv_r2_450, FE$info$cor_dhat_b_mini),
               sprintf("cor(pc1, pc2, dhat) on Mini: %s", paste(round(cor(F[, .(sw_pc1, sw_pc2, sw_dhat)])[upper.tri(diag(3))], 3), collapse = ", "))),
             file.path(out, "feature_info.txt"))
  sw <- d[benchmark == SWE]; set.seed(7)
  chk <- rbindlist(lapply(names(full), function(nm) { iv <- merge(run_level(cbind(sw, p = predict(full[[nm]], sw, type = "response")), "p"), sim_intervals(full[[nm]], sw), by = "run")
    data.table(model_id = nm, in_sample_pi_cover = mean(iv$obs >= iv$pi_lo & iv$obs <= iv$pi_hi), pi_width_pp = 100 * mean(iv$pi_hi - iv$pi_lo),
               ci_width_pp = 100 * mean(iv$ci_hi - iv$ci_lo), run_mae_pp = mean(iv$abs_err_pp)) }))
  fwrite(chk, file.path(out, "full_in_sample_swe_intervals.csv")); print(chk)
  print(ic); print(lrt); print(co[grepl("sw_", term)], digits = 3)
  cat("full wall time (min):", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "\n")
}

primary_forms <- function() {
  forms <- readRDS(form_file)
  # the PF-1-reduced formula, if one exists, replaces its parent in the holdouts (DESIGN.md E1b)
  for (nm in c("M3", "M4", "D4")) if (!is.null(forms[[paste0(nm, "r")]])) { forms[[nm]] <- forms[[paste0(nm, "r")]]; forms[[paste0(nm, "r")]] <- NULL }
  forms
}

run_holdout <- function(kind) {
  forms <- primary_forms()
  if (kind == "cell") {
    cells <- levels(droplevels(d$cell)); grid <- expand.grid(rep = 1:20, frac = c(0.10, 0.25, 0.50)); grid$seed <- seq_len(nrow(grid))
  } else {
    d[, row_id := .I]; grid <- expand.grid(rep = 1:20, frac = c(0.10, 0.25, 0.50)); grid$seed <- 1000 + seq_len(nrow(grid))
  }
  jobs <- CJ(g = seq_len(nrow(grid)), model_id = names(forms))
  t0 <- Sys.time()
  R <- mclapply(seq_len(nrow(jobs)), function(j) {
    g <- grid[jobs$g[j], ]; set.seed(g$seed)                    # same draw as R/04_holdout.R and R/10_task_holdout.R
    if (kind == "cell") { held <- sample(cells, round(g$frac * length(cells))); te_i <- d$cell %in% held
    } else { held <- sample(d$row_id, round(g$frac * nrow(d))); te_i <- d$row_id %in% held }
    train <- droplevels(d[!te_i]); test <- copy(d[te_i])
    set.seed(100000 + g$seed)
    E <- eval_model(forms[[jobs$model_id[j]]], train, test, tag = sprintf("f%02d_r%02d", round(100 * g$frac), g$rep))
    r <- E$res; rl <- E$rl; r$model_id <- jobs$model_id[j]
    if (kind == "task" && !is.null(rl)) {                      # completed-run MAE for SWE runs
      tot <- d[benchmark == SWE, .(n_all = .N, acc_all = mean(success)), by = run]
      trn <- train[benchmark == SWE, .(n_tr = .N, s_tr = sum(success)), by = run]
      cr <- merge(merge(tot, trn, by = "run", all.x = TRUE), rl[, .(run, sum_p = pred * n)], by = "run")
      cr[is.na(s_tr), `:=`(s_tr = 0, n_tr = 0)]
      r$swe_completed_run_mae_pp <- mean(100 * abs((cr$s_tr + cr$sum_p) / cr$n_all - cr$acc_all))
    }
    per_run <- if (!is.null(rl)) cbind(model_id = jobs$model_id[j], frac = g$frac, rep = g$rep, rl) else NULL
    r$frac <- g$frac; r$rep <- g$rep; r$seed <- g$seed
    list(res = r, per_run = per_run)
  }, mc.cores = min(ncores, nrow(jobs)), mc.preschedule = FALSE)
  bad <- vapply(R, inherits, TRUE, "try-error"); if (any(bad)) { print(R[bad]); }
  R <- R[!bad]
  cat(kind, "holdout wall time (min):", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " failed jobs:", sum(bad), "\n")
  res <- rbindlist(lapply(R, `[[`, "res"), fill = TRUE)
  fwrite(res, file.path(out, sprintf("%s_holdout_metrics.csv", kind)))
  fwrite(rbindlist(lapply(R, `[[`, "per_run"), fill = TRUE), file.path(out, sprintf("%s_holdout_per_run_swe.csv", kind)))
}
if (mode %in% c("cell", "task")) run_holdout(mode)

if (mode == "summary") {
  set.seed(2026)
  boot_ci <- function(x, B = 10000) { x <- x[is.finite(x)]; bm <- replicate(B, mean(sample(x, replace = TRUE))); c(mean(x), quantile(bm, c(.025, .975))) }
  for (kind in c("cell", "task")) {
    fn <- file.path(out, sprintf("%s_holdout_metrics.csv", kind)); if (!file.exists(fn)) next
    res <- fread(fn)
    mets <- intersect(c("swe_logloss", "swe_brier", "swe_auc", "swe_run_mae_pp", "swe_completed_run_mae_pp", "swe_ci_width_pp",
                        "swe_pi_width_pp", "swe_pi_cover", "swe_ci_cover", "all_logloss", "all_run_mae_pp"), names(res))
    summ <- res[, c(lapply(.SD, mean, na.rm = TRUE), list(n_fits = .N, n_singular = sum(singular), n_with_swe = sum(n_swe_rows > 0))),
                by = .(frac, model_id), .SDcols = mets]
    fwrite(summ, file.path(out, sprintf("%s_holdout_summary.csv", kind)))
    w <- dcast(melt(res[n_swe_rows > 0, c("seed", "frac", "model_id", mets), with = FALSE], id.vars = c("seed", "frac", "model_id")),
               seed + frac + variable ~ model_id)
    others <- setdiff(unique(res$model_id), "M0")
    pair <- rbindlist(lapply(others, function(o) w[, { r <- boot_ci(get(o) - M0); .(model_id = o, diff = r[1], lo = r[2], hi = r[3], n = .N) },
                                                     by = .(variable)][, frac := "pooled"]))
    pair_f <- rbindlist(lapply(others, function(o) w[, { r <- boot_ci(get(o) - M0, 2000); .(model_id = o, diff = r[1], lo = r[2], hi = r[3], n = .N) },
                                                       by = .(variable, frac)][, frac := as.character(frac)]))
    pair <- rbind(pair, pair_f)
    fwrite(pair, file.path(out, sprintf("%s_paired_vs_M0.csv", kind)))
    cat("\n====", kind, "\n"); print(summ, digits = 3); print(pair[frac == "pooled"], digits = 3)
  }
}
