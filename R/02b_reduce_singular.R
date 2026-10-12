# Post-fit sensitivity (DESIGN.md PF-1): refit singular candidates without their zero-variance components,
# pool with the non-singular fits, select lowest AIC among non-singular, converged fits.
source("R/common.R")
suppressPackageStartupMessages(library(parallel))
args <- commandArgs(TRUE); ncores <- if (length(args)) as.integer(args[1]) else 48
dir.create(path("fits/reduced"), recursive = TRUE, showWarnings = FALSE)
dir.create(path("results/reduced"), recursive = TRUE, showWarnings = FALSE)
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
met <- fread(path("results/candidate_metrics.csv"))
sing <- met[singular == TRUE]
reduce_formula <- function(id) {
  m <- readRDS(path("fits/candidates", paste0(id, ".Rds")))
  v <- as.data.frame(VarCorr(m)); zero <- v$grp[v$sdcor < 1e-3]
  f <- formula(m)
  for (g in zero) f <- update(f, as.formula(sprintf(". ~ . - (1 | %s)", g)))
  data.frame(id = id, dropped = paste(zero, collapse = ";"), formula = paste(deparse(f, width.cutoff = 500), collapse = ""))
}
red <- do.call(rbind, lapply(sing$id, reduce_formula))
red$rid <- paste0("r", substring(red$id, 2))
red <- red[!duplicated(red$formula), ]
fit_one <- function(i) {
  warns <- character(0)
  m <- withCallingHandlers(glmer(as.formula(red$formula[i]), data = d, family = binomial, control = CTRL),
         warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") })
  saveRDS(m, path("fits/reduced", paste0(red$rid[i], ".Rds")))
  conv <- c(warns, m@optinfo$conv$lme4$messages)
  data.frame(rid = red$rid[i], AIC = AIC(m), BIC = BIC(m), singular = isSingular(m), conv_warning = length(conv) > 0,
             messages = paste(unique(conv), collapse = " | "))
}
res <- merge(red, do.call(rbind, mclapply(seq_len(nrow(red)), fit_one, mc.cores = min(ncores, nrow(red)), mc.preschedule = FALSE)), by = "rid")
pool <- rbind(met[eligible == TRUE, .(id, formula, AIC, BIC, singular, conv_warning, source = "original")],
              data.table(res)[, .(id = rid, formula, AIC, BIC, singular, conv_warning, source = paste0("reduced from ", id, " (dropped ", dropped, ")"))])
pool <- pool[order(AIC)]; pool[, eligible := !singular & !conv_warning]
fwrite(pool, path("results/reduced/pool_metrics.csv"))
sel <- pool[eligible == TRUE][1]
cat("SELECTED (sensitivity):", sel$id, "\n", sel$formula, "\nAIC", sel$AIC, "\n")
writeLines(c(sel$id, sel$formula), path("results/reduced/selected_formula.txt"))
src <- if (startsWith(sel$id, "r")) path("fits/reduced", paste0(sel$id, ".Rds")) else path("fits/candidates", paste0(sel$id, ".Rds"))
file.copy(src, path("fits/selected_model_reduced.Rds"), overwrite = TRUE)
