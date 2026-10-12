# Extension 3: apply LLM-judge task-validity flags (TAU-bench Airline; Kirgis et al. 2026) to the data.
# variant: judge_both (flagged by both GPT-5 and Sonnet 4.5 judges; pre-registered primary),
#          judge_any (either judge), manual (human review; reference)
apply_judge_correction <- function(d, variant) {
  j <- fread(path("data/external/judge/docent_taubench_airline/taubench_airline_task_validity_kirgis2026.csv"),
             colClasses = list(character = "task_id"))
  flag <- switch(variant,
    judge_both = j$gpt5_docent == 1 & j$sonnet45_docent == 1,
    judge_any = j$gpt5_docent == 1 | j$sonnet45_docent == 1,
    manual = j$manual == 1,
    stop("unknown variant ", variant))
  drop_tasks <- paste("TAU-bench Airline", j$task_id[flag], sep = "::")
  cat(sprintf("[%s] dropping %d TAU-bench tasks (%d rows)\n", variant, sum(flag), sum(d$task %in% drop_tasks)))
  droplevels(d[!task %in% drop_tasks])
}
