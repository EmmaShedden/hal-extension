source("R/common.R"); source("R/metrics.R")
suppressPackageStartupMessages(library(parallel))
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
m <- readRDS("fits/selected_model.Rds"); mr <- readRDS("fits/selected_model_reduced.Rds")
cat("theta c027:\n"); print(getME(m,"theta")); cat("AIC c027", AIC(m), " r032", AIC(mr), "\n")
d$p <- predict(m, type="response")
print(d[, .(auc=auc(p,success)), by=benchmark])
forms <- list(
  c027_plus_mb = update(formula(m), . ~ . + (1|model:benchmark)),
  c027_plus_taskmodel = update(formula(m), . ~ . + (1|task:model)),
  r032_plus_taskmodel = update(formula(mr), . ~ . + (1|task:model)),
  c027_plus_run = update(formula(m), . ~ . + (1|run)),
  c027_no_reason_effort = update(formula(m), . ~ . - reasoning_model - effort),
  r032_no_reason_effort = update(formula(mr), . ~ . - reasoning_model - effort))
fits <- mclapply(forms, function(f) glmer(f, data=d, family=binomial, control=CTRL), mc.cores=6)
saveRDS(fits, "fits/audit_diag_fits.Rds")
for (n in names(fits)) { f <- fits[[n]]; cat(n, "AIC", round(AIC(f),1), "singular", isSingular(f), "\n"); print(as.data.frame(VarCorr(f))[,c("grp","sdcor")]) }
print(anova(fits$c027_no_reason_effort, m)); print(anova(fits$r032_no_reason_effort, mr))
# release x domain under c027 + model:benchmark
f2 <- fits$c027_plus_mb
f2b <- update(f2, . ~ . - release_years_z:domain); print(anova(f2b, f2))
print(summary(f2)$coefficients[c("generalistTRUE","release_years_z"),])
