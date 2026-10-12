source("R/common.R"); source("R/candidates.R")
L <- load_analysis_data("paper"); d <- L$d
cat("rows", nrow(d), "runs", nlevels(d$run), "cells", nlevels(d$cell), "tasks", nlevels(d$task), "models", nlevels(d$model), "scaffolds", nlevels(d$scaffold), "\n")
print(table(d$benchmark)); print(table(d$effort, d$reasoning_model)); print(table(d$provider))
print(unique(d[, .(model, release_date, release_years_z, log_release_age_z)])[order(release_date)])
print(table(is.na(d$release_years_z)))
X <- model.matrix(as.formula(paste("success ~", sprintf(FIXED_BASE, "release_years_z"))), d); q <- qr(X); cat("base rank", q$rank, "of", ncol(X), "\n")
cands <- validity_filter(enumerate_candidates(), d)
cat("candidates", nrow(cands), "valid", sum(cands$valid), "\n"); print(table(cands$reason))
