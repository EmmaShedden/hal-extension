# Part 1a: enumerate candidate formulas, apply validity filter, fit all valid candidates in parallel,
# select by AIC (DESIGN.md). Usage: Rscript R/02_fit_candidates.R [n_cores]
source("R/common.R"); source("R/candidates.R")
suppressPackageStartupMessages(library(parallel))
args <- commandArgs(TRUE); ncores <- if (length(args)) as.integer(args[1]) else 48
dir.create(path("fits/candidates"), recursive = TRUE, showWarnings = FALSE)
dir.create(path("results"), showWarnings = FALSE)

L <- load_analysis_data("paper"); d <- L$d
saveRDS(L$scaling, path("results/scaling.Rds"))
cat("rows", nrow(d), "runs", nlevels(d$run), "cells", nlevels(d$cell), "tasks", nlevels(d$task),
    "models", nlevels(d$model), "scaffolds", nlevels(d$scaffold), "\n")

# Rule 3 (base): drop fixed-effect terms that are aliased in the base fixed part, for all candidates
base_fx <- sprintf(FIXED_BASE, RD_OPTS[["linear"]])
X <- model.matrix(as.formula(paste("success ~", base_fx)), d)
q <- qr(X); aliased <- if (q$rank < ncol(X)) colnames(X)[q$pivot[(q$rank + 1):ncol(X)]] else character(0)
cat("aliased base columns:", if (length(aliased)) paste(aliased, collapse = ", ") else "none", "\n")
writeLines(c("aliased_base_columns", aliased), path("results/aliased_base_columns.txt"))
if (length(aliased)) {
  tl <- attr(terms(as.formula(paste("success ~", base_fx))), "term.labels")
  bad <- unique(tl[attr(X, "assign")[match(aliased, colnames(X))]])
  cat("dropping terms for all candidates:", bad, "\n")
  for (b in bad) FIXED_BASE <- gsub(paste0(" \\+ ", b, "|", b, " \\+ "), "", FIXED_BASE)
}

cands <- enumerate_candidates("success")
cands <- validity_filter(cands, d)
cands <- cands[!duplicated(cands$formula), ]
cands$id <- sprintf("c%03d", seq_len(nrow(cands)))
fwrite(cands, path("results/candidates.csv"))
cat("candidates:", nrow(cands), "valid:", sum(cands$valid), "\n")
print(table(cands$reason[!cands$valid]))

fit_one <- function(i) {
  f <- cands$formula[i]; id <- cands$id[i]
  t0 <- Sys.time(); warns <- character(0)
  m <- withCallingHandlers(
    tryCatch(glmer(as.formula(f), data = d, family = binomial, control = CTRL), error = function(e) e),
    warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") })
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (inherits(m, "error")) return(data.frame(id = id, AIC = NA, BIC = NA, logLik = NA, df = NA, singular = NA,
                                              conv_warning = TRUE, messages = conditionMessage(m), secs = secs))
  saveRDS(m, path("fits/candidates", paste0(id, ".Rds")))
  conv <- c(warns, m@optinfo$conv$lme4$messages)
  data.frame(id = id, AIC = AIC(m), BIC = BIC(m), logLik = as.numeric(logLik(m)), df = attr(logLik(m), "df"),
             singular = isSingular(m), conv_warning = length(conv) > 0, messages = paste(unique(conv), collapse = " | "), secs = secs)
}
valid_idx <- which(cands$valid)
t0 <- Sys.time()
res <- mclapply(valid_idx, fit_one, mc.cores = min(ncores, length(valid_idx)), mc.preschedule = FALSE)
cat("fitting wall time (min):", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "\n")
met <- merge(cands, do.call(rbind, res), by = "id", all.x = TRUE)
met <- met[order(met$AIC), ]
met$eligible <- met$valid & !is.na(met$AIC) & !met$conv_warning & !met$singular
fwrite(met, path("results/candidate_metrics.csv"))
sel <- met[met$eligible, ][1, ]
cat("SELECTED:", sel$id, "\n", sel$formula, "\nAIC", sel$AIC, "BIC", sel$BIC, "\n")
writeLines(c(sel$id, sel$formula), path("results/selected_formula.txt"))
file.copy(path("fits/candidates", paste0(sel$id, ".Rds")), path("fits/selected_model.Rds"), overwrite = TRUE)
