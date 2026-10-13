# Candidate formula enumeration + PT-style validity filter (see DESIGN.md).
FIXED_BASE <- "provider + reasoning_model + %s + effort + generalist + benchmark"
RD_OPTS <- c(linear = "release_years_z", log = "log_release_age_z")
BENCH_OPTS <- c(none = "", domain_slope = " + domain:%s")
# (1|run) is the observation-cluster term: task outcomes of one run share run-level conditions (PF-2, AUDIT.md H1)
RE_CORE <- c("(1|task)", "(1|run)", "(1|model)", "(1|scaffold)")
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
      if (!g %in% c("task", "run") && all(runs_per_level <= 1)) reasons <- c(reasons, sprintf("%s: every level is a single run", g))
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

# ---- PF-2 selection rule (DESIGN.md; AUDIT.md H3) ----
# A variance component is "zero" when its SD < ZERO_SD. A fit is singular when isSingular() or any SD < ZERO_SD,
# so the same threshold decides both selection eligibility and which components are removed.
ZERO_SD <- 1e-3
zero_components <- function(m) { v <- as.data.frame(VarCorr(m)); v <- v[is.na(v$var2) & v$grp != "Residual", ]; unique(v$grp[v$sdcor < ZERO_SD]) }
is_singular2 <- function(m) isSingular(m) || length(zero_components(m)) > 0
drop_components <- function(f, groups) {
  f <- as.formula(f)
  for (g in groups) f <- update(f, as.formula(sprintf(". ~ . - (1 | %s)", g)))
  paste(deparse(f, width.cutoff = 500L), collapse = "")
}
norm_formula <- function(f) paste(deparse(as.formula(f), width.cutoff = 500L), collapse = "")

# Fit every formula in `forms` (named character vector) with fit_fun(formula) -> model (may throw);
# refit each singular fit without its zero components, repeatedly, until no zero component remains.
# Returns list(metrics = data.frame, models = list) with one row per distinct formula fitted
# (models are saved to save_dir/<id>.Rds instead of returned when save_dir is given).
# ids: original names; reductions get "<parent>_r<k>". `mapper` is lapply or a parallel equivalent.
fit_and_reduce <- function(forms, fit_fun, mapper = lapply, max_rounds = 5, save_dir = NULL) {
  one <- function(id, f) {
    warns <- character(0); t0 <- Sys.time()
    m <- withCallingHandlers(tryCatch(fit_fun(as.formula(f)), error = function(e) e),
                             warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") })
    secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    if (inherits(m, "error")) return(list(row = data.frame(id = id, formula = f, AIC = NA, BIC = NA, logLik = NA, df = NA,
      singular = NA, zero = "", conv_warning = TRUE, messages = conditionMessage(m), secs = secs, stringsAsFactors = FALSE), m = NULL))
    conv <- c(warns, m@optinfo$conv$lme4$messages); conv <- conv[!grepl("singular", conv)]   # singularity is tracked separately
    z <- zero_components(m)
    if (!is.null(save_dir)) saveRDS(m, file.path(save_dir, paste0(id, ".Rds")))
    list(row = data.frame(id = id, formula = f, AIC = AIC(m), BIC = BIC(m), logLik = as.numeric(logLik(m)), df = attr(logLik(m), "df"),
                          singular = is_singular2(m), zero = paste(z, collapse = ";"), conv_warning = length(conv) > 0,
                          messages = paste(unique(conv), collapse = " | "), secs = secs, stringsAsFactors = FALSE),
         m = if (is.null(save_dir)) m else NULL)
  }
  rows <- list(); models <- list(); seen <- character(0)
  todo <- data.frame(id = names(forms), formula = vapply(forms, norm_formula, ""), parent = NA_character_, stringsAsFactors = FALSE)
  for (round in 0:max_rounds) {
    todo <- todo[!todo$formula %in% seen & !duplicated(todo$formula), ]
    if (!nrow(todo)) break
    res <- mapper(seq_len(nrow(todo)), function(i) one(todo$id[i], todo$formula[i]))
    nxt <- list()
    for (i in seq_along(res)) {
      r <- res[[i]]$row; r$parent <- todo$parent[i]; r$round <- round
      rows[[length(rows) + 1]] <- r; models[[r$id]] <- res[[i]]$m; seen <- c(seen, r$formula)
      if (isTRUE(r$singular) && nzchar(r$zero))
        nxt[[length(nxt) + 1]] <- data.frame(id = paste0(r$id, "_r", round + 1), formula = drop_components(r$formula, strsplit(r$zero, ";")[[1]]),
                                             parent = r$id, stringsAsFactors = FALSE)
    }
    todo <- if (length(nxt)) do.call(rbind, nxt) else todo[0, ]
  }
  met <- do.call(rbind, rows)
  met$eligible <- !is.na(met$AIC) & !met$conv_warning & !met$singular
  met <- met[order(met$AIC), ]
  list(metrics = met, models = models)
}
