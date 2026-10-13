source("R/common.R"); suppressPackageStartupMessages(library(parallel))
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
mr <- readRDS("fits/selected_model_reduced.Rds")
fr <- update(formula(mr), . ~ . + (1|run))
drops <- list(full=NULL, rxd="release_years_z:domain", rel="release_years_z + release_years_z:domain", gen="generalist", prov="provider", bench="benchmark", re="reasoning_model + effort")
fits <- mclapply(drops, function(x) { f <- if (is.null(x)) fr else update(fr, as.formula(paste(". ~ . -", gsub("\\+", "-", x)))); glmer(f, data=d, family=binomial, control=CTRL) }, mc.cores=7)
m <- fits$full; cat("AIC r032+run", AIC(m), "singular", isSingular(m), "\n"); print(as.data.frame(VarCorr(m))[,c("grp","sdcor")])
print(round(summary(m)$coefficients, 3))
for (n in names(drops)[-1]) { a <- anova(fits[[n]], m); cat(n, "chisq", round(a$Chisq[2],2), "df", a$Df[2], "p", signif(a$`Pr(>Chisq)`[2],3), "\n") }
