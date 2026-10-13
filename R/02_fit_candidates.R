# Part 1a: enumerate candidate formulas, apply validity filter, fit all valid candidates in parallel,
# select by AIC among converged, hereditary candidates; zero-variance components are kept (DESIGN.md PF-3). Usage: Rscript R/02_fit_candidates.R [n_cores]
source("R/common.R"); source("R/candidates.R")
suppressPackageStartupMessages(library(parallel))
args <- commandArgs(TRUE); ncores <- if (length(args)) as.integer(args[1]) else 48
unlink(path("fits/candidates"), recursive = TRUE)
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

# PF-3: heredity is a validity rule; no reduction; singular fits (zero components, SD < 1e-3) stay eligible (keep it maximal).
v <- cands[cands$valid, ]
t0 <- Sys.time()
FR <- fit_and_reduce(setNames(v$formula, v$id), function(f) glmer(f, data = d, family = binomial, control = CTRL),
                     mapper = function(x, f) mclapply(x, f, mc.cores = min(ncores, length(x)), mc.preschedule = FALSE),
                     save_dir = path("fits/candidates"), reduce = FALSE, allow_singular = TRUE)
cat("fitting wall time (min):", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "\n")
met <- merge(FR$metrics, cands[, c("id", "rd", "bench", "re_opt")], by = "id", all.x = TRUE)
met <- met[order(met$AIC), ]
fwrite(met, path("results/candidate_metrics.csv"))
cat("fits:", nrow(met), "(original", sum(met$round == 0), ", reductions", sum(met$round > 0), "); singular originals:",
    sum(met$singular[met$round == 0], na.rm = TRUE), "; eligible:", sum(met$eligible), "\n")
sel <- met[met$eligible, ][1, ]
cat("SELECTED:", sel$id, "\n", sel$formula, "\nAIC", sel$AIC, "BIC", sel$BIC, "\n")
writeLines(c(sel$id, sel$formula), path("results/selected_formula.txt"))
file.copy(path("fits/candidates", paste0(sel$id, ".Rds")), path("fits/selected_model.Rds"), overwrite = TRUE)
