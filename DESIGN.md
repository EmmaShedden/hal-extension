# Analysis design (pre-registration)

Written **before any model was fitted on real HAL data** (2026-10-12). The only fits so far are the
timing study on simulated data (`R/00_timing_dummy.R`, `logs/timing_dummy.log`). Any change made after
real-data fitting is logged in the "Post-fit design changes" section at the bottom, with its reason.

## User decisions (clarification round, 2026-10-12)
| Question | Decision |
|---|---|
| Data scope | Fit on the **paper snapshot** (the 186 runs in arXiv 2510.11977); runs uploaded after the paper are an **out-of-time test set**. |
| Holdout | Drop whole (model × scaffold × benchmark × config) **cells**, at 10 / 25 / 50 %, 20 random repetitions each. |
| Error metric | Headline: run-level **accuracy MAE** (predicted vs observed accuracy of the held-out cell). Also task-level **Brier**, 0/1 error at 0.5, and log-loss. |
| Partial credit | glmmTMB allowed, subject to the runtime budget (Part 1 must run in < 2 h). |

## Data
* Source: HF `agent-evals/hal_traces` (380 encrypted zips, 113 GB). Each zip is streamed, decrypted with
  the public hal-harness password, and reduced to config / results / raw_eval_results / usage
  (`scripts/extract_hal_traces.py` → `data/raw/hal_slim/`, gitignored, ~0.3 GB).
* Run → paper mapping: `data/meta/hf_runs.csv` (`scripts/meta/*`). It matches paper appendix tables
  (arXiv LaTeX source) to the leaderboard rows that link each zip. 185 runs match exactly. For the 2 UNSURE CORE-Bench
  DeepSeek-R1 zips, keep the one whose decrypted accuracy equals the paper's reported 2.2 % (if both or neither do,
  keep the earlier one and note it).
* **Unit of observation**: one run × one task. **Outcome**: HAL's own per-task success flag
  (`results.successful_tasks` / `failed_tasks`), which is exactly what HAL's headline accuracy is
  computed from on 8 of the 9 paper benchmarks.
* **AssistantBench is excluded from the main analysis** (prompt item 7). Its HAL headline metric is the
  *average partial-credit score*. hal-harness (`hal/benchmarks/assistantbench.py`) stores the per-task
  partial scores as an unlabeled list in the agent-output iteration order. The successful/failed id
  lists are split out separately, so the scores cannot be aligned to task ids. The only id-aligned binary outcome is exact match,
  and that is not HAL's reported metric. Every other paper benchmark has a binary per-task outcome that equals its
  headline metric (SciCode: main-problem success; USACO: all tests pass; CORE-Bench Hard: all questions
  of a capsule correct; ScienceAgentBench: success_rate; Online Mind2Web: WebJudge success;
  SWE-bench Verified Mini: resolved; TAU-bench Airline: reward = 1; GAIA: exact match). So no partial-credit
  model class is needed and **glmmTMB is not used**. Mixing families (binary + beta) in one model is
  not possible in lme4 or glmmTMB anyway. The timing study showed glmmTMB ordbeta would have fit in the budget (~45 s/fit), but
  there is no task-aligned partial-credit data to use it on.
* TAU-bench few-shot scaffold runs are excluded, as in the paper (test-set leakage). They are not in the paper snapshot.
* Out-of-time test set: zips with `in_paper == FALSE` uploaded after the paper's HF cutoff commit
  (2025-10-08), on the 8 modelled benchmarks, with a non-`unknown` model, excluding few-shot and ColBench.
  The paper-time versions of re-uploaded SWE-bench zips are the ones used; we verify that decrypted accuracy equals
  the paper accuracy for every paper run (if not, the paper-revision zip is fetched).

## Predictors
Chosen from related work (refs/RELATED_WORK_PREDICTORS.md) and limited to what can be collected
programmatically for all runs.

| Level | Predictor | Coding | Source / rationale |
|---|---|---|---|
| model | `model` | random intercept (IRT ability θ_LLM) | HAL leaderboard label; Agent Psychometrics additive θ_LLM |
| model | `provider` | fixed, 4 levels (OpenAI, Anthropic, Google, DeepSeek) | Epoch `organization`; CPP's top factor was model family |
| model | `reasoning_model` | fixed, logical (trained reasoner) | post-training method proxy; hf_runs `reasoning_capable` (LiteLLM/OpenRouter/vendor docs) |
| model | `release_date` | fixed, numeric years since 2024-01-01 (candidate transforms: linear or log of days since the earliest model in the data + 30) | Epoch `model_metadata.csv` (Messier and ECI use release date) |
| config | `effort` | fixed, levels none / default / low / high (unknown → default, prompt item 8; OpenAI "medium" → default) | HAL config |
| scaffold | `scaffold` | random intercept (θ_scaffold) | Agent Psychometrics: additive LLM + scaffold ability |
| scaffold | `generalist` | fixed, logical (HAL Generalist Agent vs benchmark-specific scaffold) | HAL paper's main scaffold contrast |
| benchmark | `benchmark` | fixed, 8 levels (too few levels for a random effect, per the TMS rule) | benchmark difficulty |
| task | `task` (benchmark:task_id) | random intercept (IRT difficulty β) | IRT |

* **Excluded on purpose**: model **size / training compute** (unknown for 12 of 15 paper models, which are closed weights; Agent Psychometrics
  excluded compute for the same reason, and CPP's zero-fill of missing values would inject false information);
  **benchmark domain** (with only 8 benchmarks each benchmark is its own domain, apart from coding: SWE, USACO, SciCode, SAB. Domain is a coarsening of the
  `benchmark` fixed effect and so is collinear with it. It enters only as an alternative to `benchmark` in the candidate set below);
  run cost (only known after a run, so not usable for interpolation).

## Candidate formulas (TMS-style enumeration, much smaller class, "keep it maximal")
Response `success ~ ...`, `family = binomial(link = "logit")`.

* **Fixed part** (always included; maximal with respect to the predictors above):
  `provider + reasoning_model + RD + effort + generalist + BENCH`, where
  * `RD` ∈ {`release_date` (linear), `log_release_age` (log days since earliest release + 30)}: the log-transform choice;
  * `BENCH` ∈ {`benchmark`, `benchmark + domain:release`}: does capability growth differ by domain?
    (domain: coding = SWE-bench Verified Mini, USACO, SciCode; science = CORE-Bench Hard, ScienceAgentBench;
    web = GAIA, Online Mind2Web; customer-service = TAU-bench Airline; interaction of domain with RD)
* **Random part** (always included: `(1|task) + (1|model) + (1|scaffold)`, the IRT core), plus every subset of
  {`(1|model:benchmark)`, `(1|scaffold:benchmark)`, `(1|model:scaffold)`, `(1|model:effort)`} → 16 random structures.
* Total: 2 × 2 × 16 = **64 candidates**.

### Validity filter (applied before fitting; PT-style)
A candidate is dropped before fitting if any of these hold (computed on the actual data):
1. A random-effect grouping factor has < 3 levels, or every level is observed in only one run
   (variance not identifiable apart from residual run noise).
2. A random-effect grouping factor yields the **same partition** of the data as another random term
   already in the formula, or as a fixed-effect factor (e.g. `scaffold:benchmark` ≡ `scaffold` when every
   scaffold is used on one benchmark only).
3. The fixed-effect model matrix is rank-deficient (`qr(X)$rank < ncol(X)`). That means some fixed effect is
   aliased (e.g. `effort == none` for every non-reasoning model).
   If this happens for the base fixed part, the aliased column's predictor is dropped **for all candidates**,
   and the drop is logged.
4. Duplicate formula after the drops above.

### Fitting and selection
* `lme4::glmer`, Laplace (`nAGQ = 1`), `glmerControl(optimizer = "nloptwrap", calc.derivs = TRUE)`,
  run in parallel (PT used nloptwrap; Laplace instead of PT's nAGQ = 0 so that AIC is comparable; the timing study gives ~40 s per fit).
* Continuous predictors are centred and scaled (2 SD, Gelman) for convergence. Factor coding is treatment coding with
  reference levels OpenAI / none / non-generalist / GAIA, as in TMS (default treatment coding).
* **Selection: lowest AIC** (TMS), among fits with no convergence warning and **not singular**. A singular fit
  means a variance component is estimated at the boundary. The same model without that component is
  in the candidate set, so excluding singular fits is the "keep it maximal, simplify only when the data cannot
  support it" rule (Barr et al. 2013; Matuschek et al. 2017). BIC is reported alongside, plus the terms present in all top-10
  models (as TMS does).
* All fits are saved as `.Rds` under `fits/` (gitignored, reproducible from scripts).

### Quality-of-fit report (Part 1)
For the selected model: Nakagawa marginal/conditional R²; in-sample AUC, Brier and log-loss; run-level
calibration (predicted vs observed run accuracy: MAE, correlation); DHARMa simulated residuals; LRT
(`anova`) for each fixed-effect term (TMS drop-one approach); random-effect SDs with profile CIs where tractable
(otherwise Wald, noted); variance shares (σ²_term / (Σσ² + π²/3)); the predicted accuracy of each paper cell vs the paper value.

## Part 2: holdout
* Cell = model × scaffold × benchmark × effort (replicate runs of a cell are dropped together).
* Fractions 10 / 25 / 50 % of cells, 20 repetitions each, seeds 1..60 (stratified only by the RNG).
* The selected formula is refit unchanged on the remaining cells. Held-out tasks are predicted with
  `predict(type = "response", re.form = NULL, allow.new.levels = TRUE)`: random effects of levels seen in training
  are used, unseen levels (e.g. a model:benchmark pair whose cells were all dropped) contribute 0.
* Metrics per holdout set, all on held-out cells: run-accuracy MAE (pp), task Brier, task 0/1 error, task log-loss.
  **Baselines on the same held-out cells**: (a) the full-data selected model (in-sample, a lower bound);
  (b) naive: training mean accuracy of the same benchmark; (c) naive additive: logit(acc) = benchmark mean +
  model mean (fit by least squares on training cells).
* Also reported: the fitted model's predictions for every out-of-time run (new models get the fixed-effect-only ability).

## Extensions (pre-registered plans)
1. **Agent Psychometrics task features** (SWE-bench Verified Mini only; inherited from their release, no new
   annotation). Evaluated on a **held-out-task** split, because features can only help where the task random effect is unknown:
   5-fold CV over the 50 SWE tasks, comparing the selected model against the selected model plus the first principal
   component of the 15 standardized features (interacted with an is-SWE indicator, 0 elsewhere). Metric: held-out-task Brier / AUC.
   Second variant (also inherited, no annotation): their published 1PL difficulty `b` for each SWE-bench Verified task
   (fit on 134 SWE-bench leaderboard agents, so external to HAL), standardized, in place of PC1.
   Run regardless of Part 1/2 outcome, as a check of whether the original predictors fall short.
2. **Runtime of successful traces** (TMS analysis outcome): `lmer(log(latency_s) ~ ..., REML = FALSE)` on
   successful tasks with a latency recorded. Same predictor set and the same 64-candidate enumeration and validity filter;
   AIC selection; log vs raw outcome checked by residual skewness (TMS used `moments::skewness`).
3. **LLM-judge corrections**: HAL's own per-task Docent judgments were not released (see
   `data/external/judge/README.md`). The only public per-task LLM-judge labels for HAL benchmarks are for TAU-bench
   Airline (Kirgis et al. 2026: GPT-5 and Claude Sonnet 4.5 judges flag tasks as broken). Correction: TAU-bench tasks
   flagged by **both** LLM judges are removed (they cannot be passed fairly); the union of flags and the manual-review labels are sensitivity analyses.
   The selected formula is refit and compared with the uncorrected model on (i) in-sample fit for TAU-bench runs and (ii)
   holdout MAE / Brier with the same holdout seeds.
4. `summary.md`: takeaways and the latent factor coefficients (fixed effects + random-effect BLUPs: model ability,
   scaffold ability, task difficulty distribution), with interpretation.

## Post-fit design changes
(none yet)
