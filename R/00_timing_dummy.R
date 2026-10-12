# Timing study on SIMULATED data (no real HAL data) to choose model class/settings
# under the <2h budget for Part 1. Sizes approximate the HAL paper subset.
suppressPackageStartupMessages({library(lme4); library(glmmTMB)})
set.seed(1)
nbench <- 9; ntask_per <- c(33,45,165,300,65,102,50,50,307)
tasks <- data.frame(bench = rep(paste0("b",1:nbench), ntask_per))
tasks$task <- paste0(tasks$bench, "_", seq_len(nrow(tasks)))
models <- paste0("m",1:13); scaffolds <- paste0("s",1:14)
runs <- do.call(rbind, lapply(1:186, function(i) {
  b <- sample(paste0("b",1:nbench),1)
  data.frame(run=paste0("r",i), bench=b, model=sample(models,1), scaffold=sample(scaffolds,1),
             effort=sample(c("default","high","low"),1), logsize=rnorm(1))
}))
d <- merge(runs, tasks, by="bench")
re <- function(lv, s) setNames(rnorm(length(lv),0,s), lv)
tk <- re(unique(d$task),1.5); md <- re(models,0.8); sc <- re(scaffolds,0.5)
mb <- re(unique(paste(d$model,d$bench)),0.4); sb <- re(unique(paste(d$scaffold,d$bench)),0.4)
eta <- -0.5 + tk[d$task] + md[d$model] + sc[d$scaffold] + mb[paste(d$model,d$bench)] +
  sb[paste(d$scaffold,d$bench)] + 0.3*(d$effort=="high") + 0.3*d$logsize
d$y <- rbinom(nrow(d),1,plogis(eta))
cat("n obs:", nrow(d), "\n")
f <- y ~ effort + logsize + bench + (1|task) + (1|model) + (1|scaffold) + (1|model:bench) + (1|scaffold:bench)
tm <- function(expr) { t <- system.time(x <- expr)[["elapsed"]]; cat(sprintf("  %.1fs\n", t)); x }
cat("glmer nAGQ=0 nloptwrap:"); m0 <- tm(glmer(f, d, binomial, nAGQ=0, control=glmerControl(optimizer="nloptwrap")))
cat("glmer nAGQ=1 bobyqa:");   m1 <- tm(glmer(f, d, binomial, control=glmerControl(optimizer="bobyqa")))
cat("glmer nAGQ=1 nloptwrap:");  m2 <- tm(glmer(f, d, binomial, control=glmerControl(optimizer="nloptwrap")))
cat("glmmTMB binomial:");       m3 <- tm(glmmTMB(f, d, family=binomial))
d$p <- ifelse(d$y==1, 1, runif(nrow(d), 0, 1)) # fake partial scores incl. 0/1 mass
cat("glmmTMB ordbeta:");        m4 <- tm(glmmTMB(update(f, p ~ .), d, family=ordbeta()))
print(c(AIC0=AIC(m0), AIC1=AIC(m1), AIC2=AIC(m2), AIC3=AIC(m3)))
