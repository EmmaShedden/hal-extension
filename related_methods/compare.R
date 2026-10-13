# Collect every method's Part 1 quality-of-fit metrics next to the GLMER (c028) reference.
# Usage: ./run_R.sh related_methods/compare.R   (after each related_methods/*/fit.R has run)
source("related_methods/common.R")
dirs <- sort(list.dirs(RM(), recursive = FALSE)); dirs <- dirs[grepl("/[0-9]{2}_", dirs)]
ref <- fread(path("results/part1/in_sample_metrics.csv"))
ref <- data.table(method = c("GLMER c028, conditional", "GLMER c028, fixed effects only"), ref[, -"pred"])
ref[, `:=`(dir = "R/ (main analysis)", n_params = NA_real_)]
m <- rbindlist(lapply(dirs, function(x) {
  f <- file.path(x, "results", "in_sample_metrics.csv")
  if (file.exists(f)) cbind(dir = basename(x), fread(f))
}), fill = TRUE)
all <- rbindlist(list(ref, m), fill = TRUE)
setcolorder(all, c("dir", "method"))
fwrite(all, RM("comparison_in_sample.csv"))
bb <- rbindlist(lapply(dirs, function(x) {
  f <- file.path(x, "results", "run_mae_by_benchmark.csv")
  if (file.exists(f)) cbind(dir = basename(x), fread(f))
}), fill = TRUE)
g <- fread(path("results/part1/run_level_fit.csv"))[, .(run_mae_pp = mean(abs_err_pp), max_err_pp = max(abs_err_pp), runs = .N), by = benchmark]
bb <- rbind(cbind(dir = "R/ (main analysis)", method = "GLMER c028, conditional", g), bb, fill = TRUE)
fwrite(dcast(bb, dir + method ~ benchmark, value.var = "run_mae_pp"), RM("comparison_run_mae_by_benchmark.csv"))
print(all, digits = 3)
