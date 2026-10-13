# Method 01: Messier (Krsteski et al. 2026). Rasch / 1PL IRT, one ability per agent and one difficulty per task, no
# covariates. Messier's hierarchical normal priors with point-estimated SDs are fit as the Laplace GLMM
# (1|agent) + (1|task); the 2PL variant by MAP with the 1PL's variance estimates (related_methods/DESIGN.md, method 01).
# Usage: ./run_R.sh related_methods/01_rasch_messier/fit.R
source("related_methods/common.R"); source("related_methods/irt_map.R")
out <- RM("01_rasch_messier", "results"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
d <- load_rm_data()
rasch <- function(dd, agent_col) {
  dd <- copy(dd); dd[, ag := droplevels(factor(get(agent_col)))]; dd[, task := droplevels(task)]
  glmer(success ~ 1 + (1 | ag) + (1 | task), data = dd, family = binomial, control = CTRL)
}
sds <- function(m) { v <- as.data.frame(VarCorr(m)); setNames(v$sdcor, v$grp) }

# primary: all runs, agent = model x scaffold x effort
m1 <- rasch(d, "agent"); p1 <- predict(m1, type = "response")
s1 <- sds(m1)
# 2PL by MAP: theta ~ N(0, sd_agent), b ~ N(-intercept, sd_task), log a ~ N(0, 1)
m2 <- irt_map(d$success, list(agent = d$agent), d$task, twopl = TRUE,
              prior_sd = list(theta = s1[["ag"]], b = s1[["task"]], log_a = 1), b_mu = -fixef(m1)[[1]])
stopifnot(m2$convergence == 0)

# faithful: Messier's paper fit (keep_best_scaffold; agent = model; constant tasks dropped)
sc <- d[, .(score = mean(success), n = .N), by = .(model, benchmark, scaffold)]
best <- sc[order(model, benchmark, -score, -n, scaffold)][, .SD[1], by = .(model, benchmark)]
df <- d[best[, .(model, benchmark, scaffold)], on = .(model, benchmark, scaffold)]
const <- df[, .(m = mean(success)), by = task][m %in% c(0, 1), task]
df <- df[!task %in% const]
mf <- rasch(df, "model"); pf <- predict(mf, type = "response")
saveRDS(list(pl1 = m1, pl2 = m2, faithful = mf), RM("01_rasch_messier", "fits.Rds"))

k_glmm <- function(m) length(fixef(m)) + nrow(as.data.frame(VarCorr(m)))      # estimated parameters (the modes are not counted)
met <- rbind(
  cbind(fit_metrics(d, p1, "Messier 1PL, agent = model x scaffold x effort (all runs)"), n_params = k_glmm(m1),
        n_levels = nlevels(d$agent) + nlevels(d$task), rows = nrow(d), loglik = as.numeric(logLik(m1)), singular = isSingular(m1)),
  cbind(fit_metrics(d, m2$p, "Messier 2PL (MAP), same agents (all runs)"), n_params = NA, n_levels = m2$n_params, rows = nrow(d),
        loglik = m2$loglik, singular = NA),
  cbind(fit_metrics(df, pf, "Messier paper fit: best scaffold per model x benchmark, agent = model, constant tasks dropped"),
        n_params = k_glmm(mf), n_levels = uniqueN(df$model) + uniqueN(df$task), rows = nrow(df),
        loglik = as.numeric(logLik(mf)), singular = isSingular(mf)))
bb <- rbind(cbind(method = "Messier 1PL", run_mae_by_benchmark(d, p1)), cbind(method = "Messier 2PL", run_mae_by_benchmark(d, m2$p)),
            cbind(method = "Messier paper fit", run_mae_by_benchmark(df, pf)))
re <- ranef(m1)
theta <- data.table(agent = rownames(re$ag), theta = re$ag[, 1])[order(-theta)]
reF <- ranef(mf); theta_f <- data.table(model = rownames(reF$ag), theta = reF$ag[, 1])[order(-theta)]
b1 <- data.table(task = rownames(re$task), b = -(fixef(m1)[[1]] + re$task[, 1]))
b2 <- data.table(task = m2$levels$task, b_2pl = m2$par$b, a_2pl = exp(m2$par$la))
tp <- merge(b1, b2, by = "task")
th2 <- m2$par$th[[1]][match(theta$agent, m2$levels$agent)]
agree <- data.table(stat = c("spearman_theta_1pl_2pl", "spearman_b_1pl_2pl", "sd_agent_1pl", "sd_task_1pl", "sd_model_faithful", "sd_task_faithful",
                             "faithful_runs_kept", "faithful_tasks_dropped_constant"),
                    value = c(cor(theta$theta, th2, method = "spearman"), cor(tp$b, tp$b_2pl, method = "spearman"),
                              s1[["ag"]], s1[["task"]], sds(mf)[["ag"]], sds(mf)[["task"]], uniqueN(df$run), length(const)))
write_outputs(out, met, bb, list(agent_theta_1pl = theta, model_theta_paper_fit = theta_f, task_params = tp, variance_and_agreement = agree))
print(met, digits = 3); print(agree, digits = 3)
