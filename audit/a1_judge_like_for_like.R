source("R/common.R"); source("R/metrics.R"); source("R/judge.R")
suppressPackageStartupMessages(library(parallel))
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
dj <- apply_judge_correction(d, "judge_both"); keep <- unique(as.character(dj$task[dj$benchmark=="TAU-bench Airline"]))
cells <- levels(droplevels(d$cell))
grid <- expand.grid(rep = 1:20, frac = c(0.10, 0.25, 0.50)); grid$seed <- seq_len(nrow(grid))
res <- rbindlist(mclapply(seq_len(nrow(grid)), function(i){
  g <- grid[i,]; set.seed(g$seed); held <- sample(cells, round(g$frac*length(cells)))
  te <- d[cell %in% held & benchmark=="TAU-bench Airline" & task %in% keep]
  if (!nrow(te)) return(NULL)
  fn <- sprintf("holdout_f%02d_r%02d.Rds", round(100*g$frac), g$rep)
  m0 <- readRDS(file.path("fits/holdout/main", fn)); m1 <- readRDS(file.path("fits/holdout/judge_both", fn))
  te$p0 <- predict(m0, newdata=te, type="response", allow.new.levels=TRUE)
  te$p1 <- predict(m1, newdata=te, type="response", allow.new.levels=TRUE)
  r <- te[, .(o=mean(success), a=mean(p0), b=mean(p1)), by=run]
  data.table(frac=g$frac, rep=g$rep, mae_uncorr=100*mean(abs(r$a-r$o)), mae_corr=100*mean(abs(r$b-r$o)),
             brier_uncorr=brier(te$p0,te$success), brier_corr=brier(te$p1,te$success))
}, mc.cores=30))
print(res[, lapply(.SD, mean), by=frac, .SDcols=3:6])
