# Build the external (non-HAL, non-agentic) benchmark score matrix for the observational-scaling method
# (related_methods/DESIGN.md, method 07). Data management only; no model is fit here.
# Usage: ./run_R.sh related_methods/07_observational_scaling/build_external_scores.R
source("related_methods/common.R")
out <- RM("07_observational_scaling", "results"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
e <- fread(path("data/external/epoch/eci_benchmarks.csv"))
eci <- fread(path("data/external/epoch/benchmark_data/eci_scores.csv"))

# HAL model id -> Epoch display name (one row per HAL paper model; checked against model_meta.csv epoch keys)
MAP <- c("claude-3.7-sonnet" = "Claude 3.7 Sonnet", "claude-opus-4" = "Claude Opus 4", "claude-opus-4.1" = "Claude Opus 4.1",
         "claude-sonnet-4" = "Claude Sonnet 4", "deepseek-r1" = "DeepSeek-R1", "deepseek-r1-0528" = "DeepSeek-R1 (May 2025)",
         "deepseek-v3" = "DeepSeek-V3", "deepseek-v3.1" = "DeepSeek-V3.1", "gemini-2.0-flash" = "Gemini 2.0 Flash (Feb 2025)",
         "gemini-2.5-pro-preview" = "Gemini 2.5 Pro (Mar 2025)", "gpt-4.1" = "GPT-4.1", "gpt-5" = "GPT-5",
         "gpt-oss-120b" = "gpt-oss-120b", "o3" = "o3", "o4-mini" = "o4-mini")
d <- load_rm_data(); stopifnot(setequal(names(MAP), levels(d$model)))

# Benchmarks that are agent evaluations, or overlap HAL's benchmarks, are excluded: observational scaling predicts
# agentic performance from non-agentic capability measurements, and HAL-overlapping scores would leak the outcome.
AGENTIC <- c("METR Time Horizons", "SWE-Bench verified", "GSO-Bench", "Cybench", "OSWorld", "Terminal Bench",
             "The Agent Company", "DeepResearch Bench", "GDPval", "Balrog", "APEX-Agents", "Remote Labor Index", "EBR-bench")
s <- e[Model %in% MAP & !benchmark %in% AGENTIC]
s <- s[, .(score = max(performance)), by = .(Model, benchmark)]           # max over versions/settings (ECI convention)
cover <- s[, .(n_models = uniqueN(Model)), by = benchmark][order(-n_models)]
keep <- cover[n_models >= 12, benchmark]
X <- dcast(s[benchmark %in% keep], Model ~ benchmark, value.var = "score")
X[, model := names(MAP)[match(Model, MAP)]]
X <- X[match(names(MAP), model)]
X[, eci := eci$eci[match(Model, eci$Model)]]
fwrite(cover, file.path(out, "external_benchmark_coverage.csv"))
fwrite(X, file.path(out, "external_scores.csv"))
cat("kept benchmarks:", paste(keep, collapse = "; "), "\n"); print(X)
cat("missing cells:", sum(is.na(as.matrix(X[, ..keep]))), "of", length(keep) * nrow(X), "\n")
