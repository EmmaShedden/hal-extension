# Method 02: Agent Psychometrics (Ge et al. 2026). 1PL IRT with additive agent ability theta_LLM + theta_scaffold - b,
# hierarchical normal priors with estimated SDs (fit as the Laplace GLMM), LLM = model (efforts pooled, as AP does).
# Primary: one fit per benchmark (AP's protocol); variant: pooled across benchmarks. AP's comparison: per-agent 1PL.
# (related_methods/DESIGN.md, method 02). Usage: ./run_R.sh related_methods/02_additive_irt_agent_psychometrics/fit.R
source("related_methods/common.R"); suppressPackageStartupMessages(library(parallel))
out <- RM("02_additive_irt_agent_psychometrics", "results"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
d <- load_rm_data()
fit_one <- function(dd, form) glmer(form, data = droplevels(dd), family = binomial, control = CTRL)
F_ADD <- success ~ 1 + (1 | model) + (1 | scaffold) + (1 | task)
F_ADD1 <- success ~ 1 + (1 | model) + (1 | task)                  # single-scaffold benchmark (TAU-bench)
F_AGENT <- success ~ 1 + (1 | agent) + (1 | task)

benches <- levels(d$benchmark)
per_b <- mclapply(benches, function(b) {
  dd <- d[benchmark == b]
  add <- fit_one(dd, if (uniqueN(dd$scaffold) > 1) F_ADD else F_ADD1)
  ag <- fit_one(dd, F_AGENT)
  list(add = add, agent = ag, idx = which(d$benchmark == b))
}, mc.cores = length(benches))
names(per_b) <- benches
pooled <- fit_one(d, F_ADD)
saveRDS(list(per_benchmark = per_b, pooled = pooled), RM("02_additive_irt_agent_psychometrics", "fits.Rds"))

p_add <- p_ag <- numeric(nrow(d))
for (b in benches) { i <- per_b[[b]]$idx; p_add[i] <- predict(per_b[[b]]$add, type = "response"); p_ag[i] <- predict(per_b[[b]]$agent, type = "response") }
p_pool <- predict(pooled, type = "response")
npar <- function(ms) sum(vapply(ms, function(m) length(fixef(m)) + nrow(as.data.frame(VarCorr(m))), 0))
met <- rbind(
  cbind(fit_metrics(d, p_add, "AP additive 1PL (theta_model + theta_scaffold - b), per benchmark"), n_params = npar(lapply(per_b, `[[`, "add")),
        singular_fits = sum(vapply(per_b, function(x) isSingular(x$add), TRUE))),
  cbind(fit_metrics(d, p_ag, "AP comparison: per-agent 1PL, per benchmark"), n_params = npar(lapply(per_b, `[[`, "agent")),
        singular_fits = sum(vapply(per_b, function(x) isSingular(x$agent), TRUE))),
  cbind(fit_metrics(d, p_pool, "AP additive 1PL, pooled across benchmarks"), n_params = npar(list(pooled)), singular_fits = as.integer(isSingular(pooled))))
bb <- rbind(cbind(method = "AP additive, per benchmark", run_mae_by_benchmark(d, p_add)),
            cbind(method = "AP per-agent, per benchmark", run_mae_by_benchmark(d, p_ag)),
            cbind(method = "AP additive, pooled", run_mae_by_benchmark(d, p_pool)))
# AP's headline check: AUC of the additive vs the per-agent fit (they report mean |dAUC| = 0.002)
dauc <- d[, .(auc_additive = auc(p_add[.I], success), auc_per_agent = auc(p_ag[.I], success)), by = benchmark]
dauc <- rbind(dauc, data.table(benchmark = "all (pooled rows)", auc_additive = auc(p_add, d$success), auc_per_agent = auc(p_ag, d$success)))
dauc[, d_auc := auc_additive - auc_per_agent]
vc <- rbindlist(lapply(benches, function(b) cbind(benchmark = b, model = "additive", as.data.table(VarCorr(per_b[[b]]$add))[, .(grp, sdcor)])))
vc <- rbind(vc, cbind(benchmark = "pooled", model = "additive", as.data.table(VarCorr(pooled))[, .(grp, sdcor)]))
re <- ranef(pooled)
th <- rbind(data.table(component = "model", level = rownames(re$model), theta = re$model[, 1]),
            data.table(component = "scaffold", level = rownames(re$scaffold), theta = re$scaffold[, 1]))[order(component, -theta)]
write_outputs(out, met, bb, list(additive_vs_per_agent_auc = dauc, variance_components = vc, theta_pooled = th))
print(met, digits = 3); print(dauc, digits = 3); print(vc, digits = 3)
