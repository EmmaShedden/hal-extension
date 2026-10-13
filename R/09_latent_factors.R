# Latent factors of the primary selected model, on the logit scale (for summary.md). Works for any selected random
# structure built from the candidate terms (DESIGN.md PF-2).
#  model ability in domain D = provider + reasoning + (release slope + domain-D slope) * release_z + (1|model) BLUP
#      + mean over the model's runs in D of [effort effect + BLUPs of every other random term whose grouping contains
#        `model` (model:scaffold, model:benchmark, model:effort)]. Domains where the model has no run get the first part only.
#      This is a composition-weighted average over the configurations the model was actually run with (AUDIT.md L3).
#  scaffold ability = generalist effect + (1|scaffold) BLUP + mean scaffold:benchmark BLUP over the benchmarks it was run on
#  task difficulty = -(benchmark effect + task BLUP)
source("R/common.R")
m <- readRDS(path("fits/selected_model.Rds")); fe <- fixef(m); re <- ranef(m)
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
out <- path("results/latent"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
g <- function(n) if (n %in% names(fe)) fe[[n]] else 0
blup <- function(grp, key) { if (!grp %in% names(re)) return(rep(0, length(key))); b <- re[[grp]][key, 1]; b[is.na(b)] <- 0; b }
key_of <- function(dt, grp) do.call(paste, c(lapply(strsplit(grp, ":", fixed = TRUE)[[1]], function(v) as.character(dt[[v]])), sep = ":"))
runs <- unique(d[, .(run, model, scaffold, benchmark, effort, domain, provider, reasoning_model, release_years_z, generalist)])
inter <- setdiff(grep("(^|:)model(:|$)", names(re), value = TRUE), "model")
runs[, model_cfg := sapply(as.character(effort), function(e) g(paste0("effort", e)))]
for (grp in inter) runs[, model_cfg := model_cfg + blup(grp, key_of(.SD, grp))]
mods <- unique(d[, .(model, provider, reasoning_model, release_date, release_years_z)])
mods[, base := sapply(seq_len(.N), function(i) g(paste0("provider", provider[i])) + g("reasoning_modelTRUE") * reasoning_model[i]) +
         blup("model", as.character(model))]
for (dom in levels(d$domain)) {
  slope <- g("release_years_z") + g(paste0("release_years_z:domain", dom))
  cfg <- runs[domain == dom, .(cfg = mean(model_cfg)), by = model]
  mods[[paste0("ability_", dom)]] <- mods$base + slope * mods$release_years_z + {x <- cfg$cfg[match(mods$model, cfg$model)]; x[is.na(x)] <- 0; x}
}
mods[, ability_mean := rowMeans(.SD), .SDcols = patterns("^ability_")]
mods[, n_runs := runs[, .N, by = model]$N[match(model, runs[, .N, by = model]$model)]]
fwrite(mods[order(-ability_mean)], file.path(out, "model_ability.csv"))
sc <- unique(runs[, .(scaffold, benchmark, generalist)])
sc[, sb := blup("scaffold:benchmark", paste(scaffold, benchmark, sep = ":"))]
sc <- sc[, .(generalist = generalist[1], sb_mean = mean(sb), benchmarks = paste(sort(as.character(benchmark)), collapse = "/")), by = scaffold]
sc[, scaffold_blup := blup("scaffold", as.character(scaffold))]
sc[, ability := g("generalistTRUE") * generalist + scaffold_blup + sb_mean]
fwrite(sc[order(-ability)], file.path(out, "scaffold_ability.csv"))
tk <- unique(d[, .(task, benchmark)])
tk[, difficulty := -(sapply(as.character(benchmark), function(b) g(paste0("benchmark", b))) + blup("task", as.character(task)))]
fwrite(tk[, .(n_tasks = .N, mean = mean(difficulty), sd = sd(difficulty), q10 = quantile(difficulty, .1), q90 = quantile(difficulty, .9)), by = benchmark][order(mean)],
       file.path(out, "task_difficulty_by_benchmark.csv"))
for (grp in inter) fwrite(data.table(level = rownames(re[[grp]]), blup = re[[grp]][, 1])[order(-blup)],
                          file.path(out, sprintf("blup_%s.csv", gsub(":", "_", grp))))
print(mods[order(-ability_mean)], digits = 2); print(sc[order(-ability)], digits = 2); print(fread(file.path(out, "task_difficulty_by_benchmark.csv")), digits = 3)
