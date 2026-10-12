# data/meta — HAL run inventory and paper membership

`hf_runs.csv` has one row per encrypted trace zip in the HuggingFace dataset
`agent-evals/hal_traces` (380 zips). Each row says whether the zip is one of the runs reported in the paper.

Paper: Kapoor, Stroebl et al., *Holistic Agent Leaderboard: The Missing Infrastructure for AI Agent
Evaluation*, arXiv **2510.11977** (v1 is the only version; submitted 2025-10-13 22:22 UTC; ICLR 2026).
The paper reports 21,730 rollouts, "142 model-scaffold-benchmark combinations ... from a total of 186 runs"
(Sec. "Limitations", main.tex l.577), and token prices "as of September 24, 2025".

## Sources (accessed 2026-10-12)

| file in `sources/` | origin |
|---|---|
| `paper_tables/*.tex` | LaTeX source `https://arxiv.org/e-print/2510.11977`, files `tables/*_full_results.tex` (appendix "Leaderboard" tables, one per benchmark: Scaffold, Model, Accuracy, Cost, Pareto) |
| `paper_appendix_runs.csv` | those tables parsed by `scripts/meta/parse_paper_tables.py` (184 rows) |
| `hf_tree_current.json` | `https://huggingface.co/api/datasets/agent-evals/hal_traces/tree/main` |
| `hf_commits.json` | `https://huggingface.co/api/datasets/agent-evals/hal_traces/commits/main?p=N` (625 commits; titles name the uploaded file) |
| `hf_tree_paper_snapshot.json` | `.../tree/1bf4166d052cdd3445127e17c15139cbb5505ca5`, the last HF commit before the arXiv submission (2025-10-08). It has 331 zips. |
| `hal_leaderboard_html_20261012/*.html.gz` | `https://hal.cs.princeton.edu/<benchmark>` for the 9 paper benchmarks. ColBench pages return 404. |
| `hal_leaderboard_scrape_20261012.csv` | those pages parsed by `scripts/meta/scrape_hal_leaderboard.py` (246 rows) |

There is no released CSV/JSON/DB of leaderboard results. Checked:
`github.com/princeton-pli/hal-harness` has no result data, only test fixtures.
`github.com/benediktstroebl/hal-frontend` was last pushed 2025-08 and only has old `preprocessed_traces/*.db` for other benchmarks.
The HF org `agent-evals` has only `hal_traces` and two `core-bench-v1.1-*` datasets.
The live leaderboard is server-rendered HTML. Each row has scaffold, model label, accuracy, total cost, a "Runs" count, and a link to one HF zip.
When Runs > 1, accuracy and cost are the mean across runs, with a min/max range, but the row still links only one zip.

## How `in_paper` was determined

1. **Exact match (176 zips).** Each paper table row was joined to the leaderboard row with the same benchmark page, scaffold and model label (e.g. `o4-mini High (April 2025)`).
   176 of 184 rows have identical accuracy (±0.05 pp) and cost (±$0.005) and a single run. The zip that row links is marked `TRUE`.
2. **Manual resolution of the other 8 paper rows.** The leaderboard row has changed since the paper for these (see `MANUAL` in `scripts/meta/build_hf_runs.py`):
   * The paper value equals the leaderboard's 2-run mean, so both runs are in the paper.
     These are CORE-Agent/DeepSeek R1 (adds `coreagentdeepseekr1_1757604883`) and SciCode Tool Calling/Opus 4.1 High (adds `..._claudeopus41_high_1755107101`).
     This explains 186 runs = 184 table rows + 2.
   * The paper value is one end of a 2-run range, and the other run is newer: GAIA HAL Generalist/DeepSeek V3 (the other run was uploaded 2025-10-14) and SWE-Agent/Opus 4.1.
     For SWE-Agent/Opus 4.1 the leaderboard now links a 2025-10-06 rerun, so the paper run is the remaining Aug-2025 zip `sweagentclaudeopus4120250805_1754598086`.
   * USACO GPT-5 / o4-mini High / o4-mini Low: the leaderboard now links 2026-03 reruns that are **not on HF**. The only pre-paper HF zip for each config is marked `TRUE`. These are inferred.
   * CORE-Bench HAL Generalist/DeepSeek R1 (Jan): the paper reports one run (2.2%, $13.87), but the leaderboard now averages two runs (`hal_generalist_agent_1747247500`, `hal_generalist_agentdeepseekr1_1757615687`).
     Exactly one of these two is in the paper. Both are marked **`UNSURE`**.
3. **Everything else is `FALSE`.** The `paper_evidence` column gives the reason:
   * not on HF at the 2025-10-08 snapshot (uploaded later);
   * ColBench (not a paper benchmark);
   * TAU-bench Few Shot (excluded in the paper for leakage);
   * a model not in any paper table (Sonnet 4.5, Haiku 4.5, o3-mini, GPT-4o);
   * linked from the leaderboard but absent from the paper tables (e.g. GAIA HAL Generalist with Opus 4.1 / GPT-5 / o3, SciCode HAL Generalist);
   * on HF before the paper but not linked from the leaderboard (superseded, failed or exploratory runs; all 186 paper runs are already assigned).

Result: TRUE 185, UNSURE 2 (one of them in the paper), FALSE 193, giving 186 paper runs.
Every paper table row maps to at least one zip.

## Column notes

* `benchmark`: Online Mind2Web = `browser-use_*` / `seeact_*`; TAU-bench Airline = `taubench_airline_*`; SWE-bench Verified Mini; CORE-Bench Hard.
* `scaffold`, `model_canonical`, `effort` use the leaderboard label when the zip is linked (`model_source = leaderboard label`), else the paper label for the manually resolved zips, else the filename.
  Filenames are unreliable. Some lack a model (`corebench_hard_coreagent_<ts>`, `swebench_verified_mini_<ts>`, `taubench_airline_<ts>`, giving `unknown`).
  Some contradict the label: `claudeopus4120250514` is Opus 4.1, `scicode-tool_calling_agent_claudeopus4120250514` is the *High* run, and `taubench ..._high_reasoning___gpt5` is labeled GPT-5 *Medium*.
  `filename_model` / `filename_effort` keep the raw parse.
* `model_canonical`: `deepseek-r1` = R1 (Jan 2025); `deepseek-r1-0528` = HAL label "DeepSeek R1 (May 2025)"; `deepseek-v3` = HAL label "DeepSeek V3 (March 2025)", i.e. V3-0324.
* `effort` (collapsed): `high`, `low`, `minimal` as labeled. `medium` (OpenAI default) becomes `default`.
  Reasoning-only models with no label (R1, gpt-oss, Gemini 2.5/3 Pro) and `unknown` become `default`.
  Claude/hybrid models without thinking ("no reasoning" in the paper) become `none`.
  Non-reasoning models (GPT-4.1, GPT-4o, DeepSeek V3, Gemini 2.0 Flash) become `none`.
  `effort_raw` is the explicit tag only. Anthropic "High" means a 4,096-token thinking budget (LiteLLM).
  To follow the "unknown → default" convention with Claude no-thinking treated as default, recode `none` to `default` where `reasoning_capable` is TRUE.
* `run_timestamp`: from the 10-digit unix time in the filename (run start, UTC). `browser-use_*`/`seeact_*` names have none; use `hf_first_upload`.
* `paper_acc_pct`/`paper_cost_usd`: the paper table value. For the two 2-run rows this is the 2-run mean, repeated on both zips.
  `hal_lb_*`: the current leaderboard row linking this zip, possibly a multi-run mean (`hal_lb_n_runs`, `hal_lb_acc_range`).
  `run_acc_pct`/`run_cost_usd`: the best single-run value (the paper value if single-run, else the leaderboard value if `hal_lb_n_runs == 1`). Blank otherwise.
* `hf_reuploaded_after_paper`: 15 paper SWE-bench zips were re-uploaded on 2025-11-01/09/10 with slightly different sizes.
  The paper-time bytes can be fetched from revision `1bf4166d052cdd3445127e17c15139cbb5505ca5`, e.g.
  `https://huggingface.co/datasets/agent-evals/hal_traces/resolve/1bf4166d052cdd3445127e17c15139cbb5505ca5/<filename>`.
  Their leaderboard scores still equal the paper's.

## Rebuild

```
python -I scripts/meta/parse_paper_tables.py <arxiv_src>/tables data/meta/sources/paper_appendix_runs.csv
python -I scripts/meta/scrape_hal_leaderboard.py <dir_of_leaderboard_html> data/meta/sources/hal_leaderboard_scrape_<date>.csv
python -I scripts/meta/build_hf_runs.py data/meta/sources data/meta/hf_runs.csv
```
