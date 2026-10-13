# Shared helpers for the HAL GLMER analysis.
suppressPackageStartupMessages({
  library(lme4); library(data.table)
})
# All scripts are run from the repository root: Rscript R/<script>.R
ROOT <- getwd()
stopifnot(file.exists(file.path(ROOT, "DESIGN.md")))
path <- function(...) file.path(ROOT, ...)

CTRL <- glmerControl(optimizer = "nloptwrap", calc.derivs = TRUE)

# Load the task-level analysis table with all predictors; returns list(d, scaling)
load_analysis_data <- function(splits = c("paper"), scaling = NULL) {
  runs <- fread(path("data/processed/runs.csv"))
  tasks <- fread(path("data/processed/tasks.csv.gz"), colClasses = list(character = "task_id"))
  # resolve the 2 UNSURE CORE-Bench DeepSeek-R1 zips (DESIGN.md): keep the one matching paper accuracy
  uns <- runs[split == "unsure"]
  if (nrow(uns)) {
    uns[, match := abs(extracted_acc_pct - paper_acc_pct) < 0.05]
    pick <- if (sum(uns$match) == 1) uns[match == TRUE] else uns[order(hf_first_upload)][1]
    runs[source_file == pick$source_file, split := "paper"]
    runs[split == "unsure", split := "unused"]
  }
  runs <- runs[split %in% splits & benchmark != "AssistantBench"]
  d <- merge(tasks, runs, by = "source_file")
  d[, task := paste(benchmark, task_id, sep = "::")]
  d[, cell := paste(model, scaffold, benchmark, effort, sep = "|")]
  d[, run := source_file]
  d[effort %in% c("", "unknown", "medium"), effort := "default"]
  rd <- as.numeric(as.Date(d$release_date) - as.Date("2024-01-01")) / 365.25
  d[, release_years := rd]
  if (is.null(scaling)) {
    min_days <- min(as.numeric(as.Date(runs$release_date) - as.Date("2024-01-01")))
    scaling <- list(min_days = min_days)
  }
  d[, log_release_age := log(as.numeric(as.Date(release_date) - as.Date("2024-01-01")) - scaling$min_days + 30)]
  # Gelman 2-SD scaling, computed on the fitting data (paper split) and reused elsewhere
  for (v in c("release_years", "log_release_age")) {
    if (is.null(scaling[[v]])) {
      ur <- unique(d[, c("model", v), with = FALSE])[[v]]   # scale over models, not task rows
      scaling[[v]] <- c(center = mean(ur), scale = 2 * sd(ur))
    }
    d[[paste0(v, "_z")]] <- (d[[v]] - scaling[[v]][["center"]]) / scaling[[v]][["scale"]]
  }
  d[, provider := factor(provider, levels = c("OpenAI", "Anthropic", "Google", "DeepSeek"))]
  d[, effort := factor(effort, levels = c("none", "default", "low", "high"))]
  d[, reasoning_model := as.logical(reasoning_model)]
  d[, generalist := scaffold == "HAL Generalist Agent"]
  d[, benchmark := factor(benchmark, levels = c("GAIA", setdiff(sort(unique(benchmark)), "GAIA")))]
  d[, domain := factor(domain)]
  for (v in c("model", "scaffold", "task", "cell", "run")) d[[v]] <- factor(d[[v]])
  list(d = d, scaling = scaling)
}

# Nakagawa & Schielzeth (2013) / Nakagawa et al. (2017) R2 on the latent scale, computed from its definition:
# marginal = var(X b) / (var(X b) + sum of RE variances + residual), conditional = (var(X b) + sum RE) / (same).
# Residual = pi^2/3 for binomial-logit (theoretical), sigma^2 for lmer. Used instead of performance::r2_nakagawa,
# which returns NA (and an inflated marginal value) when a variance component is exactly zero, as under PF-3.
r2_nakagawa_def <- function(m) {
  vf <- var(as.vector(getME(m, "X") %*% fixef(m)))
  vc <- as.data.frame(VarCorr(m)); vr <- sum(vc$vcov[vc$grp != "Residual" & is.na(vc$var2)])
  ve <- if (isGLMM(m)) pi^2 / 3 else sigma(m)^2
  data.frame(R2_marginal = vf / (vf + vr + ve), R2_conditional = (vf + vr) / (vf + vr + ve))
}
