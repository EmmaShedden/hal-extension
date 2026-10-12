# Extension 1: Agent Psychometrics task features for SWE-bench Verified Mini (inherited, no annotation).
# 5-fold CV over the 50 SWE tasks: selected model vs + AP PC1 vs + AP 1PL difficulty (DESIGN.md).
source("R/common.R"); source("R/metrics.R")
suppressPackageStartupMessages(library(parallel))
out <- path("results/ext1_ap_features"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
f0 <- as.formula(readLines(path("results/selected_formula.txt"))[2])
feat <- fread(path("data/external/agent_psychometrics/swebench_verified_llm_judge_features_defaults15.csv"))
items <- fread(path("data/external/agent_psychometrics/swebench_verified_irt_1pl_items.csv"))
swe_ids <- unique(d[benchmark == "SWE-bench Verified Mini", task_id])
feat <- feat[instance_id %in% swe_ids]; stopifnot(nrow(feat) == length(swe_ids))
X <- scale(as.matrix(feat[, -"instance_id"]))
pc <- prcomp(X); feat$pc1 <- pc$x[, 1] / sd(pc$x[, 1])
fwrite(data.frame(feature = rownames(pc$rotation), loading_pc1 = pc$rotation[, 1]), file.path(out, "pc1_loadings.csv"))
fwrite(data.frame(var_explained = pc$sdev^2 / sum(pc$sdev^2)), file.path(out, "pc_var_explained.csv"))
idcol <- intersect(c("item_id", "instance_id", "task_id", "id", "V1"), names(items))[1]
bcol <- intersect(c("b", "difficulty", "beta"), names(items))[1]
items <- items[get(idcol) %in% swe_ids]; items$bz <- as.numeric(scale(items[[bcol]]))
d[, ap_pc1 := 0]; d[, ap_b := 0]
is_swe <- d$benchmark == "SWE-bench Verified Mini"
d$ap_pc1[is_swe] <- feat$pc1[match(d$task_id[is_swe], feat$instance_id)]
d$ap_b[is_swe] <- items$bz[match(d$task_id[is_swe], items[[idcol]])]
stopifnot(!anyNA(d$ap_pc1), !anyNA(d$ap_b))
forms <- list(base = f0, ap_pc1 = update(f0, . ~ . + ap_pc1), ap_b = update(f0, . ~ . + ap_b))
# in-sample: fit with features on full data, LRT vs base
full <- mclapply(forms, function(f) glmer(f, data = d, family = binomial, control = CTRL), mc.cores = 3)
saveRDS(full, path("fits/ext1_ap_full_models.Rds"))
fwrite(data.frame(model = names(full), AIC = sapply(full, AIC), logLik = sapply(full, function(m) as.numeric(logLik(m))),
  coef = c(NA, fixef(full$ap_pc1)["ap_pc1"], fixef(full$ap_b)["ap_b"]),
  se = c(NA, sqrt(diag(as.matrix(vcov(full$ap_pc1))))["ap_pc1"], sqrt(diag(as.matrix(vcov(full$ap_b))))["ap_b"]),
  task_sd = sapply(full, function(m) attr(VarCorr(m)$task, "stddev"))), file.path(out, "in_sample.csv"))
# 5-fold held-out-task CV over SWE tasks
set.seed(1); fold <- sample(rep(1:5, length.out = length(swe_ids))); names(fold) <- swe_ids
jobs <- expand.grid(k = 1:5, model = names(forms), stringsAsFactors = FALSE)
cv <- rbindlist(mclapply(seq_len(nrow(jobs)), function(i) {
  k <- jobs$k[i]; held <- names(fold)[fold == k]
  tr <- droplevels(d[!(is_swe & task_id %in% held)]); te <- d[is_swe & task_id %in% held]
  m <- glmer(forms[[jobs$model[i]]], data = tr, family = binomial, control = CTRL)
  te$p <- predict(m, newdata = te, type = "response", allow.new.levels = TRUE)
  te[, .(model = jobs$model[i], fold = k, task_id, run, success, p)]
}, mc.cores = 15))
fwrite(cv, file.path(out, "cv_predictions.csv"))
res <- cv[, c(task_metrics(p, success), list(run_mae_pp = mean(100 * abs(.SD[, mean(p), by = run]$V1 - .SD[, mean(success), by = run]$V1)))), by = model]
fwrite(res, file.path(out, "cv_metrics.csv")); print(res)
