# Latent factors of the primary selected model, on the logit scale (for summary.md):
#  model ability by domain = provider + reasoning + (release slope + domain slope) * release_z + model BLUP
#                            + mean model:scaffold BLUP over the scaffolds the model was run with
#                            + mean (effort effect + model:effort BLUP) over the efforts the model was run with
#  scaffold ability = generalist effect + scaffold BLUP;  task difficulty = -(benchmark effect + task BLUP)
source("R/common.R")
m <- readRDS(path("fits/selected_model.Rds")); fe <- fixef(m); re <- ranef(m)
L <- load_analysis_data("paper", scaling = readRDS(path("results/scaling.Rds"))); d <- L$d
out <- path("results/latent"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
g <- function(n) if (n %in% names(fe)) fe[[n]] else 0
mods <- unique(d[, .(model, provider, reasoning_model, release_date, release_years_z)])
ms <- re[["model:scaffold"]]; ms <- data.table(level = rownames(ms), b = ms[, 1])
ms[, model := sub(":.*", "", level)]
ms_mean <- ms[, .(ms_mean = mean(b)), by = model]
mb <- re$model; mb <- data.table(model = rownames(mb), model_blup = mb[, 1])
mods <- merge(merge(mods, mb, by = "model", all.x = TRUE), ms_mean, by = "model", all.x = TRUE)
mev <- re[["model:effort"]]; mev <- data.table(level = rownames(mev), b = mev[, 1])
eff <- unique(d[, .(model, effort)]); eff[, level := paste(model, effort, sep = ":")]
eff <- merge(eff, mev, by = "level", all.x = TRUE); eff[is.na(b), b := 0]
eff[, fe_eff := sapply(as.character(effort), function(e) g(paste0("effort", e)))]
mods <- merge(mods, eff[, .(effort_mean = mean(fe_eff + b), efforts = paste(sort(as.character(effort)), collapse = "/")), by = model], by = "model")
for (dom in levels(d$domain)) {
  slope <- g("release_years_z") + g(paste0("release_years_z:domain", dom))
  mods[[paste0("ability_", dom)]] <- sapply(seq_len(nrow(mods)), function(i)
    g(paste0("provider", mods$provider[i])) + g("reasoning_modelTRUE") * mods$reasoning_model[i] +
      slope * mods$release_years_z[i] + mods$model_blup[i] + mods$ms_mean[i] + mods$effort_mean[i])
}
mods[, ability_mean := rowMeans(.SD), .SDcols = patterns("^ability_")]
fwrite(mods[order(-ability_mean)], file.path(out, "model_ability.csv"))
sc <- unique(d[, .(scaffold, generalist)]); sb <- re$scaffold
sc[, scaffold_blup := sb[as.character(scaffold), 1]]; sc[, ability := g("generalistTRUE") * generalist + scaffold_blup]
fwrite(sc[order(-ability)], file.path(out, "scaffold_ability.csv"))
tk <- unique(d[, .(task, benchmark)]); tb <- re$task
tk[, difficulty := -(sapply(as.character(benchmark), function(b) g(paste0("benchmark", b))) + tb[as.character(task), 1])]
fwrite(tk[, .(n_tasks = .N, mean = mean(difficulty), sd = sd(difficulty), q10 = quantile(difficulty, .1), q90 = quantile(difficulty, .9)), by = benchmark][order(mean)],
       file.path(out, "task_difficulty_by_benchmark.csv"))
me <- re[["model:effort"]]; fwrite(data.table(level = rownames(me), blup = me[, 1])[order(-blup)], file.path(out, "model_effort_blup.csv"))
print(mods[order(-ability_mean), .(model, release_date, ability_coding, ability_science, ability_web, ability_customer_service, ability_mean)])
print(sc[order(-ability)]); print(fread(file.path(out, "task_difficulty_by_benchmark.csv")))
