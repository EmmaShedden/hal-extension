# External LLM-judge / validity data for HAL score corrections

Retrieved 2026-10-12. All of it is public and was fetched without authentication.

## docent_taubench_airline/
Source: Kirgis, Kapoor et al., "Log analysis is necessary for credible evaluation of AI agents",
arXiv:2605.08545, App. "tau-Bench Validation Comparisons". It links to this Docent collection:
https://docent.transluce.org/dashboard/57cf585c-45b2-4537-8ad7-629a5f9ea07b
("tau-bench-airline-one-run-answers"; owner pk7019@princeton.edu). It is readable through the
REST API at https://api.docent.transluce.org/rest/ (endpoints `rubric/{cid}/rubrics` and
`dql/{cid}/execute`).

- `collection_details.json`, `rubrics.json`: the collection metadata, plus the 2 rubrics (full rubric text and output schema).
- `judge_results_raw.json.gz`: the DQL dump, judge_results JOIN agent_runs (1200 rows = 600 runs x 2 judges).
- `docent_judge_per_run_task.csv`: the flattened version of that dump.
  Columns: run_id, task_id, agent_name, model, reward, success, judge, label, category, explanation.
  - judge is gpt-5-medium or claude-sonnet-4-5-medium.
  - label is "match" (the failure is due to a benchmark issue, so this is a false negative) or "no match".
  - category is filled only when label is "match", and only for the Sonnet judge. Values: grading_error, database_error, ambiguous_instructions.
  - Coverage: 12 taubench_toolcalling runs from Jan 2026 (run_id suffix 1768xxxxxx), rep1 only, x 50 tasks.
    These run_ids are NOT in agent-evals/hal_traces, so they cannot be joined to it by run_id.
- `taubench_airline_task_validity_kirgis2026.csv`: Table "tab:validation", parsed from the paper's TeX source.
  It gives a per-task (0-49) issue type (P = policy inconsistency, A = ambiguous instructions,
  D = database/grading error) and which approaches flagged the task: manual, Amazon AGI (SABER),
  GPT-5 Docent, Sonnet 4.5 Docent. Manual review flags 25 tasks, and the authors exclude those 25.

## corebench_v1.1/
Source: HF agent-evals/core-bench-v1.1-{mainline,ood} (core_test.json, croissant.json; updated 2026-05-05).
This is not judge output. Of the 45 CORE-Bench Hard capsules that HAL uses, v1.1 keeps 29 in its
mainline split and drops 16. The reason for dropping them is not documented in the files.
