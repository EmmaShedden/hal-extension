# Part 1b: quality of fit of the selected model (DESIGN.md "Quality-of-fit report").
# Usage: ./run_R.sh R/03_report_selected.R [n_cores] [variant: main | reduced]
source("R/common.R"); source("R/metrics.R")
suppressPackageStartupMessages({library(parallel); library(performance); library(DHARMa)})
args <- commandArgs(TRUE); ncores <- if (length(args)) as.integer(args[1]) else 16
variant <- if (length(args) >= 2) args[2] else "main"
set.seed(42)
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
m <- readRDS(path(if (variant == "main") "fits/selected_model.Rds" else sprintf("fits/selected_model_%s.Rds", variant)))
out <- path(if (variant == "main") "results/part1" else sprintf("results/part1_%s", variant)); dir.create(out, showWarnings = FALSE, recursive = TRUE)
sink(file.path(out, "summary_selected.txt")); print(summary(m)); sink()

# fixed effects: estimates, Wald CIs, odds ratios
fe <- data.frame(term = names(fixef(m)), est = fixef(m), se = sqrt(diag(as.matrix(vcov(m)))))
fe$lo <- fe$est - 1.96 * fe$se; fe$hi <- fe$est + 1.96 * fe$se
fe$z <- fe$est / fe$se; fe$p <- 2 * pnorm(-abs(fe$z)); fe$OR <- exp(fe$est)
fwrite(fe, file.path(out, "fixed_effects.csv"))

# LRT for each fixed-effect term (TMS: anova(m0, m1) on the model without that term)
tl <- attr(terms(lme4::nobars(formula(m))), "term.labels")
# a main effect is tested jointly with the interactions that contain it (marginality); otherwise R just reparametrizes
lrt <- mclapply(tl, function(t) {
  drop <- tl[vapply(strsplit(tl, ":", fixed = TRUE), function(p) t %in% p || identical(paste(p, collapse = ":"), t), TRUE)]
  m1 <- update(m, as.formula(paste(". ~ . -", paste(drop, collapse = " - "))))
  a <- anova(m1, m)
  data.frame(term = t, dropped = paste(drop, collapse = " + "), Chisq = a$Chisq[2], Df = a$Df[2], p = a$`Pr(>Chisq)`[2], dAIC = AIC(m1) - AIC(m))
}, mc.cores = min(ncores, length(tl)))
fwrite(do.call(rbind, lrt), file.path(out, "lrt_fixed_terms.csv"))

# random effects: SDs and variance shares (latent-scale residual pi^2/3)
vc <- as.data.frame(VarCorr(m))
vc$share <- vc$vcov / (sum(vc$vcov) + pi^2 / 3)
fwrite(vc, file.path(out, "random_effects_variance.csv"))
re <- ranef(m, condVar = TRUE)
for (g in names(re)) {
  pv <- attr(re[[g]], "postVar")
  fwrite(data.frame(level = rownames(re[[g]]), blup = re[[g]][, 1], se = sqrt(pv[1, 1, ])), file.path(out, paste0("blup_", gsub(":", "_", g), ".csv")))
}

# R2 (Nakagawa)
r2 <- tryCatch(performance::r2_nakagawa(m), error = function(e) NULL)
if (!is.null(r2)) fwrite(data.frame(R2_marginal = r2$R2_marginal, R2_conditional = r2$R2_conditional), file.path(out, "r2.csv"))

# in-sample predictive metrics: conditional (all REs) and marginal (fixed only)
d$p <- predict(m, type = "response")
d$p_fixed <- predict(m, type = "response", re.form = NA)
tm <- rbind(cbind(pred = "conditional", task_metrics(d$p, d$success)),
            cbind(pred = "fixed_only", task_metrics(d$p_fixed, d$success)))
rl <- run_level(d)
tm$run_mae_pp <- c(mean(rl$abs_err_pp), mean(run_level(d, "p_fixed")$abs_err_pp))
tm$run_cor <- c(cor(rl$obs, rl$pred), with(run_level(d, "p_fixed"), cor(obs, pred)))
fwrite(tm, file.path(out, "in_sample_metrics.csv"))
runs <- fread(path("data/processed/runs.csv"))
rl <- merge(rl, runs[, .(run = source_file, model, scaffold, effort, paper_acc_pct, extracted_acc_pct)], by = "run")
fwrite(rl, file.path(out, "run_level_fit.csv"))

# DHARMa simulated residuals, overall and aggregated to runs (where overdispersion would show)
sim <- simulateResiduals(m, n = 250, seed = 42)
sim_run <- recalculateResiduals(sim, group = d$run)
dh <- data.frame(test = c("uniformity_task", "dispersion_task", "uniformity_run", "dispersion_run"),
  p = c(testUniformity(sim, plot = FALSE)$p.value, testDispersion(sim, plot = FALSE)$p.value,
        testUniformity(sim_run, plot = FALSE)$p.value, testDispersion(sim_run, plot = FALSE)$p.value),
  stat = c(testUniformity(sim, plot = FALSE)$statistic, testDispersion(sim, plot = FALSE)$statistic,
           testUniformity(sim_run, plot = FALSE)$statistic, testDispersion(sim_run, plot = FALSE)$statistic))
fwrite(dh, file.path(out, "dharma_tests.csv"))
png(file.path(out, "dharma_run_level.png"), 1000, 500); plot(sim_run); dev.off()
cat("done\n")
