# Candidate formula enumeration + PT-style validity filter (see DESIGN.md).
FIXED_BASE <- "provider + reasoning_model + %s + effort + generalist + benchmark"
RD_OPTS <- c(linear = "release_years_z", log = "log_release_age_z")
BENCH_OPTS <- c(none = "", domain_slope = " + domain:%s")
RE_CORE <- c("(1|task)", "(1|model)", "(1|scaffold)")
RE_OPT <- c("(1|model:benchmark)", "(1|scaffold:benchmark)", "(1|model:scaffold)", "(1|model:effort)")

enumerate_candidates <- function(response = "success") {
  out <- list()
  for (rd in names(RD_OPTS)) for (bo in names(BENCH_OPTS)) {
    fx <- sprintf(FIXED_BASE, RD_OPTS[[rd]])
    if (bo != "none") fx <- paste0(fx, sprintf(BENCH_OPTS[[bo]], RD_OPTS[[rd]]))
    for (k in 0:length(RE_OPT)) for (cmb in combn(RE_OPT, k, simplify = FALSE)) {
      re <- paste(c(RE_CORE, cmb), collapse = " + ")
      out[[length(out) + 1]] <- data.frame(rd = rd, bench = bo, re_opt = paste(cmb, collapse = " + "),
                                           formula = paste(response, "~", fx, "+", re), stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, out)
}

re_groups <- function(f) {
  bars <- lme4::findbars(as.formula(f))
  vapply(bars, function(b) deparse(b[[3]]), "")
}

grouping_partition <- function(d, g) {
  vars <- strsplit(g, ":", fixed = TRUE)[[1]]
  as.integer(factor(do.call(paste, c(lapply(vars, function(v) d[[v]]), sep = "|"))))
}
same_partition <- function(a, b) {
  # identical partitions up to relabelling
  length(unique(a)) == length(unique(b)) && length(unique(paste(a, b))) == length(unique(a))
}

# Returns data.frame(formula, valid, reason)
validity_filter <- function(cands, d, fixed_factors = c("benchmark", "provider", "effort")) {
  res <- lapply(seq_len(nrow(cands)), function(i) {
    f <- cands$formula[i]
    reasons <- character(0)
    groups <- re_groups(f)
    parts <- lapply(groups, function(g) grouping_partition(d, g))
    names(parts) <- groups
    for (g in groups) {
      p <- parts[[g]]
      nlev <- length(unique(p))
      runs_per_level <- tapply(d$run, p, function(x) length(unique(x)))
      if (nlev < 3) reasons <- c(reasons, sprintf("%s has %d levels", g, nlev))
      if (g != "task" && all(runs_per_level <= 1)) reasons <- c(reasons, sprintf("%s: every level is a single run", g))
    }
    for (a in seq_along(groups)) for (b in seq_along(groups)) if (a < b && same_partition(parts[[a]], parts[[b]]))
      reasons <- c(reasons, sprintf("%s == %s (same partition)", groups[a], groups[b]))
    for (g in groups) for (ff in fixed_factors) if (same_partition(parts[[g]], as.integer(d[[ff]])))
      reasons <- c(reasons, sprintf("%s == fixed %s", g, ff))
    X <- model.matrix(lme4::nobars(as.formula(f)), d)
    rk <- qr(X)$rank
    if (rk < ncol(X)) reasons <- c(reasons, sprintf("fixed X rank %d < %d cols", rk, ncol(X)))
    data.frame(formula = f, valid = length(reasons) == 0, reason = paste(reasons, collapse = "; "), stringsAsFactors = FALSE)
  })
  cbind(cands, do.call(rbind, res)[, c("valid", "reason")])
}
