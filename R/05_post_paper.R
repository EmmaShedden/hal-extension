# Out-of-time test: predict runs uploaded after the paper with the selected full-data model.
source("R/common.R"); source("R/metrics.R")
sc <- readRDS(path("results/scaling.Rds"))
m <- readRDS(path("fits/selected_model.Rds"))
paper <- load_analysis_data("paper", scaling = sc)$d
L <- load_analysis_data("post_paper", scaling = sc); d <- L$d
d[, new_model := !model %in% levels(paper$model)]
d[, new_scaffold := !scaffold %in% levels(paper$scaffold)]
d[, new_cell := !cell %in% levels(paper$cell)]
d$p <- predict(m, newdata = d, type = "response", allow.new.levels = TRUE)
d$p_fixed <- predict(m, newdata = d, type = "response", re.form = NA)
rl <- d[, .(obs = mean(success), pred = mean(p), pred_fixed = mean(p_fixed), n = .N,
            new_model = new_model[1], new_scaffold = new_scaffold[1], new_cell = new_cell[1]),
        by = .(run, cell, benchmark, model, scaffold, effort)]
rl[, abs_err_pp := 100 * abs(pred - obs)]
dir.create(path("results/post_paper"), showWarnings = FALSE)
fwrite(rl, path("results/post_paper/post_paper_runs.csv"))
s <- rl[, .(run_mae_pp = mean(abs_err_pp), n_runs = .N), by = .(new_model, new_scaffold)]
tm <- d[, task_metrics(p, success), by = .(new_model, new_scaffold)]
print(s); print(tm)
fwrite(merge(s, tm, by = c("new_model", "new_scaffold")), path("results/post_paper/post_paper_summary.csv"))
