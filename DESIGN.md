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
### PF-1 (2026-10-12, after the 64-candidate fit, `results/candidate_metrics.csv`): singular-fit rule
*Observation.* 50/64 candidates were singular; in every inspected case the zero component is the **core**
`(1|model)` term (SD ~1e-5), because the model-level fixed effects (provider, reasoning, release date,
domain x release) plus `model:scaffold` / `model:benchmark` / `model:effort` absorb all between-model variance
(15 models). The pre-registered justification for excluding singular fits ("the same model without that
component is in the candidate set") is therefore false for these fits: the core terms were never optional.
*Decision.* The **pre-registered rule is kept as the primary analysis** (selected: `c027`, lowest-AIC non-singular,
dAIC = +48 vs the best singular fit). Because the rule's stated intent was "simplify only the components the data
cannot support", a **sensitivity analysis** implements that intent literally: every singular candidate is refit
with its zero-variance components (SD < 1e-3) removed, the reduced fits join the pool, and the lowest-AIC
non-singular fit of the pool is selected (`R/02b_reduce_singular.R`, `results/reduced/`). Both designs go through
Part 2 with the same holdout seeds; results for both are reported, the primary is not swapped after seeing holdout results.
*Compute note (not a design change).* The first launch was killed after 10 min with no completed fits: OpenBLAS
was spawning 96 threads in each of 64 workers (load ~1300). All R scripts are now run via `run_R.sh`, which
sets single-threaded BLAS. Part 1 candidate fitting then took 4.2 min.

## Added analysis (2026-10-12, requested after the cell-holdout results): task-level holdout (Part 2b)
This analysis was added on request after Part 2 results were seen. It is specified here before it is run, and the formula and everything else are unchanged.
* **Unit held out.** An individual task score: one row = one task × one run, i.e. a model × scaffold × benchmark × effort
  combination on a single task. Rows are sampled by simple random sampling of all rows in the paper data; the
  benchmark, run and task are not stratified.
* **Grid.** Fractions 10 / 25 / 50 % of rows, 20 repetitions each, seeds 1001..1060. The primary design `c027` is refit
  unchanged on the remaining rows. The sensitivity design `r032` gets the same grid with the same seeds.
* **Prediction.** `predict(type = "response", allow.new.levels = TRUE)`. Almost every run, task, model and scaffold
  level is still present in training, so held-out rows are predicted with their BLUPs. This setting is therefore
  *matrix completion* (filling in missing task scores of runs that were partly observed), not prediction for unseen agents.
* **Metrics, on held-out rows.**
  * Task-level Brier, log-loss, 0/1 error and AUC.
  * Run-level accuracy error on the held-out subset: |mean predicted p − observed accuracy| over each run's held-out tasks.
  * Run-level accuracy error of the *completed* run: observed training rows plus predicted held-out rows,
    compared with the run's full observed accuracy.
  * Sampling-noise floor of the subset metric: E|mean p − mean y| with y ~ Bernoulli(p_full), using 200 draws.
    It shows how much of the subset error is unavoidable when only a few tasks per run are held out.
* **Baselines on the same rows.**
  * (a) The full-data model (in-sample).
  * (b) Benchmark mean in training.
  * (c) The run's own training accuracy. This is the "run only a subsample of the tasks" estimator.
  * (d) The task's training solve rate.
  * (e) Additive logit: logit(run acc) + logit(task rate) − logit(benchmark mean), with rates clamped to [0.005, 0.995].

## Added analysis (2026-10-12, requested after E1 was reported): E1b task-feature × agent interactions (SWE-bench)
Requested after E1, Part 2 and Part 2b results were seen. Everything below is fixed before any E1b model is fit.
*Motivation.* E1 added task features only as main effects. For seen tasks, those are largely redundant with `(1|task)`.
`(1|task)` is additive, so every agent ranks tasks identically. Feature × agent interactions let the ranking depend on
the kind of task, and can inform held-out combinations. Agent Psychometrics (AP) uses an additive 1PL and never tests
such interactions, so the interaction specification is ours. The feature encoding follows AP.
* **Features (inherited, no annotation).**
  * AP's fixed default 15 LLM-judge features, z-scored over all 500 SWE-bench Verified tasks (AP standardizes per dataset).
  * **Task-type scores** `sw_pc1` and `sw_pc2`: the first two principal components of the 15 z-scored features. PCA is
    fit on all 500 Verified tasks (external to HAL outcomes, so identical in every holdout fold). Signs are set so
    each PC correlates positively with AP's 1PL `b`. Each is then centered and scaled to SD 1 over the 50 Mini tasks.
  * **AP difficulty score** `sw_dhat`: AP's two-stage recipe (their eq. 2). A ridge regression of their frozen 1PL `b`
    on the 15 z-features is fit on the **450 Verified tasks not in Mini**, with λ chosen by 5-fold CV MSE on a log grid.
    It is then predicted for the 50 Mini tasks and centered and scaled to SD 1 over them.
  * All three are 0 on non-SWE rows.
* **Models.** Each is `c027` plus the terms shown, where A = `provider + reasoning_model + release_years_z + effort + generalist`,
  i.e. all agent-side fixed effects of `c027`.
  | id | added terms |
  |---|---|
  | M0 | none (`c027`) |
  | M1 | `sw_pc1 + sw_pc2` (main effects, as in E1) |
  | M2 | M1 + `(sw_pc1 + sw_pc2):(A)` (fixed feature × agent interactions) |
  | M3 | M1 + `(0 + sw_pc1 + sw_pc2 \| model)` (model-specific slopes on task type) |
  | M4 | M2 + `(0 + sw_pc1 + sw_pc2 \| model)` (maximal; **primary**) |
  | D1 | `sw_dhat` |
  | D4 | D1 + `sw_dhat:(A)` + `(0 + sw_dhat \| model)` (1-D "discrimination" analog of M4) |
  If the full-data M4 fit is singular, the PF-1 reduction is applied: components with SD < 1e-3 are dropped, and the
  reduced formula becomes the primary for the holdouts. Rank-deficient fixed columns are dropped by lme4 as usual.
* **Evaluation.**
  * (a) Full-data fits: AIC, an LRT of the interaction block (M2/M3/M4 vs M1, D4 vs D1), and the coefficients.
  * (b) **Cell holdout** with Part 2's grid and seeds (1..60). All 7 models are refit on identical training sets.
    Primary metrics are on held-out **SWE** cells: task log-loss, Brier, AUC and run MAE (pp). The same metrics are also
    computed over all held-out cells.
  * (c) **Task-level holdout** with Part 2b's grid and seeds (1001..1060), on held-out SWE rows: task log-loss and
    Brier, held-out-subset run MAE and completed-run MAE.
  * **Prediction intervals** (b and c): the 90 % interval of each held-out SWE run's observed accuracy (on its held-out
    tasks), from 1,000 draws. Each draw takes β ~ N(β̂, V̂). Seen random-effect levels are drawn from their conditional
    modes and variances (`condVar`), and unseen levels from N(0, Σ̂). Bernoulli outcomes are then drawn per task.
    The interval ignores β–b covariance and the uncertainty in Σ̂, the same for every model. Reported: mean width and coverage.
  * Paired comparison per seed, model − M0, summarized as a mean with a bootstrap 95 % CI over seeds (AP's
    seed-bootstrap; 10,000 resamples).
* **"Promising" gate** (decides whether the other benchmarks get annotated and the features enter Parts 1–2). The
  primary model (M4, or its PF-1 reduction) must reduce held-out-SWE task log-loss vs M0, with the paired 95 % CI
  excluding 0, pooled over the three fractions, in the cell holdout **or** the task holdout. In that same holdout,
  its run-MAE point estimate must not be worse than M0 and its 90 % PI coverage must be ≥ 0.80. Otherwise the
  extension stops at SWE-bench and is reported as such.
*E1b outcome (recorded after the holdouts).*
* The full M4 was singular: its model slopes collapsed once the fixed interactions were present. The PF-1 reduction
  (`M4r`, which drops the PC2 slope) was used as the primary, as pre-registered.
* The primary raised held-out SWE log-loss in both holdouts, so **the gate is not met**. The other benchmarks were not
  annotated, and Parts 1–2 are unchanged.
* M3 (model slopes only) improved every holdout metric slightly. It is reported as a secondary result, not swapped in.

## Post-fit design changes from the statistical audit (2026-10-12; AUDIT.md H1–H3, M2)
Written after the audit and before any PF-2 result was inspected. The PF-2 Part 1 run had started but none of its output had been read. These changes respond to problems the audit found in the design. They were not chosen by looking at which variant predicts better.

### PF-2: observation-cluster term, one zero-variance threshold, and reduction as part of selection
*Problems.*
* **H1.** No candidate contains a run-level random effect. Task outcomes within a run share run-specific conditions, and the run-aggregated DHARMa test flags misfit (p = 0.024). The audit's diagnostic fit `c027 + (1|run)` lowers AIC by 116.
* **H3.** The primary rule calls a fit singular via `isSingular()`, whose tolerance is θ < 1e-4. PF-1 instead treats SD < 1e-3 as zero. The selected `c027` has a model SD of 5.5e-4: it counts as non-singular under one threshold and zero under the other.
* **H2.** Because the selected model contained no `model:benchmark` term, the domain × release LRTs were tested without the model × benchmark variance that is their natural error term.

*Changes.*
1. **`(1|run)` joins the core random part**, giving `(1|task) + (1|run) + (1|model) + (1|scaffold)`. The validity rule "every level is a single run" exempts `run`, since that is the term's purpose. The candidate class is otherwise unchanged at 64 candidates.
2. **One threshold.** A variance component is zero when its SD < 1e-3. A fit is singular when `isSingular()` is TRUE or any component is zero (`R/candidates.R: is_singular2`). The same rule is applied to holdout refits when singular fits are counted.
3. **Reduction is part of the primary selection.** Every singular fit is refit without its zero components. This repeats for up to 5 rounds, until no zero component remains. Originals and reductions form one pool. The selected model is the lowest-AIC fit in the pool that converged and has no zero component (`R/02_fit_candidates.R`).
   * This is PF-1's sensitivity procedure, now made primary and iterated.
   * The separate `reduced` variant (`R/02b_reduce_singular.R`, `r032`) is retired.
   * The pre-registered `c027` results stay in git history at commit `e4812fe`. REPORT.md compares them with the PF-2 results.
4. **Inference (H2).** All p-values, LRTs and CIs in REPORT.md and summary.md come from the PF-2 selected model.
   * If that model has no model × benchmark component, the domain × release test is also reported with `(1|model:benchmark)` added, and the more conservative result is the one interpreted.
   * Predictions use the selected model as before.
5. **Everything downstream reruns with the PF-2 model**, with the same seeds and grids: Part 1 report, Part 2 cell holdout, Part 2b task holdout, out-of-time test, E1, E1b, E3 refits and holdouts, and latent factors.
   * E2 uses the same PF-2 selection rule on its own candidate set, which now also includes `(1|run)`.

### DC-1: Extension 2 outcome (AUDIT.md M2)
* **The problem.** `latency_s` was HAL's `results.latencies[task].total_time`. That is the time from the first LLM call's *start* to the last call's *start*, so single-call tasks read about 0 s. SAB Self-Debug had 79 successful traces at exactly 0 s and 109 more under 1 s.
* **The new outcome, `span_s`.** It runs from the first LLM call's start to the last LLM call's end, by task, computed from HAL's per-call Weave logs (`raw_logging_results`). `scripts/extract_call_timing.py` re-streams the 175 modelled paper zips, using the paper-revision copies for the 15 SWE-bench files, and writes `data/processed/task_timing.csv.gz`. That file also holds the call count and summed call time.
* **What it measures.** It is the span of the agent's LLM activity. It still excludes environment setup and evaluation, and it includes API queueing under HAL's concurrent task execution. REPORT.md describes it that way rather than as wall time.
* **Unchanged.** The design otherwise stays the same: successful traces, a log outcome, the same predictors and the same candidate class.

### PF-2 / DC-1 outcome (recorded after the runs)
* **Selection.**
  * All 64 originals are singular under the single 1e-3 threshold. `(1|model)`, `(1|scaffold)` and `(1|model:effort)` are zero wherever they appear.
  * There are 32 distinct reductions, 29 of them eligible. Three reductions had a further zero component, and each of their second-round reductions was already in the pool.
  * Selected: `c028_r1` = full fixed part + `release_years_z:domain` + `(1|task) + (1|run) + (1|model:benchmark) + (1|scaffold:benchmark) + (1|model:scaffold)`, AIC 18,726.4. It contains `model:benchmark`, so the conditional rule in PF-2 item 4 was not needed.
* **Unplanned diagnostic finding.** The run-aggregated DHARMa tests cannot be interpreted for this crossed design. Unconditional simulation redraws the shared task effects, and conditional simulation is circular. They are reported with that caveat, and run-level dependence is assessed by random-term LRTs, a new output of `R/03_report_selected.R`. This is a change in interpretation only; no model was changed because of it.
* **Pipeline fix.** E2's first run under PF-2 crashed on a data.table type error in a descriptive table. It was fixed with `as.numeric()` and rerun; nothing about the design changed.
* **E1b base model.** E1b (pre-registered on `c027`) uses the selected formula as M0. Its rerun therefore uses `c028_r1`, and its gate is re-evaluated on the rerun. Its PF-1 reduction rule in `R/11_ap_interactions.R` is unchanged.

## PF-3 (2026-10-12, user decision after the PF-2 results): heredity, and zero-variance components kept
*Decision (by the user).* Random-effect formulas must respect **heredity**, the inheritance principle: a random interaction term may appear only if each of its factors is in the model as a fixed-effect factor or as its own random intercept.
* PF-2 chose `c028_r1`, which keeps `(1|model:benchmark)`, `(1|scaffold:benchmark)` and `(1|model:scaffold)` but drops `(1|model)` and `(1|scaffold)`. That is not hereditary.
* The user also directed that the "keep it maximal" result be followed: including a random effect that turns out to be unnecessary is not, by that result, a reason to remove it.

*Where heredity comes from.*
* TMS states heredity for fixed effects ("the principle of heredity in mixed modeling states that in general, main effects should be included when the fixed effects are").
* PT's hand-written formulas include each interaction's parent random intercepts, e.g. `(1|annotator) + (1|annotator:code)`.
* TMS's random-term enumeration does *not* enforce heredity: its subsets include `(1|id:domain)` without `(1|id)`. PF-3 therefore adopts PT's practice for random terms.

*The "keep it maximal" result, in its own words.* Barr, Levy, Scheepers & Tily (2013), "Random effects structure for confirmatory hypothesis testing: Keep it maximal", *J. Memory and Language* 68:255–278; author manuscript PMC3881361.
* Abstract: "LMEMs generalize best when they include the maximal random effects structure justified by the design."
* General Discussion: "overfitting the data with a maximal model has only minimal consequences for Type I error and power".
* Results, for the worst case of a zero random-slope variance: maximal LMEMs "incurred a negligible cost relative to random-intercepts-only LMEMs" in between-items designs. In within-items designs the cost was small and shrank as the number of items grew. The authors conclude "good performance of the estimation algorithm when random slope variances are zero."
* *Scope.* The evidence is from simulations of Gaussian LMMs with two crossed factors, and is mostly about random slopes. It says "minimal" or "negligible" cost, not "no" cost. Singular fits are not discussed.
* Matuschek et al. (2017, JML 94:305–315) argue that overparameterized models can cost power. Here that is moot, because a component estimated at zero changes neither the estimates nor the predictions; see the check below.

*Rules (replacing PF-2 items 2–3 for Part 1 and E2).*
1. **Validity rule 5 (heredity).** Each factor of a random interaction term must be a fixed-effect factor (`benchmark`, `effort`, `provider`) or have its own random intercept in the formula. `run` and `task` are not interactions. All 64 pre-registered candidates satisfy it, because the core part contains `(1|model)` and `(1|scaffold)`.
2. **No reduction, and singularity does not disqualify.** Zero-variance components (SD < 1e-3) are kept at the boundary, following keep-it-maximal. A fit is eligible when it converged without warnings. Selection is the lowest AIC among eligible, valid candidates. The PF-2 reduction step is removed, and the `singular` and `zero` columns are still reported.
3. **`(1|run)` stays in the core (PF-2 item 1).** Unchanged: it is the observation cluster and is not an interaction.

*Expected consequence (stated before the rerun).*
* Among the PF-2 originals, the lowest-AIC candidate is `c028`, the hereditary parent of `c028_r1`: AIC 18,730.4 vs 18,726.4, with zero `(1|model)` and `(1|scaffold)`.
* The two are the same fit. Their log-likelihoods agree to 0.001, fixed effects differ by at most 0.007, SEs by at most 0.013, and fitted probabilities by at most 5e-4.
* `c032` (all four optional terms) is the same fit again, plus a zero `(1|model:effort)`, at ΔAIC +2.0. That difference is purely the parameter penalty.
* Everything downstream reruns with the PF-3 selection (`run_pf2.sh`).
* E1b uses the selected formula as M0, so its zero `(1|model)` is kept. Its own PF-1 slope-reduction step therefore does not fire, which matches PF-3's rule that zero components are kept.

### PF-3 outcome (recorded after the runs)
* **Selection.** `c028`, AIC 18,730.4, as predicted. All 64 candidates are valid under the heredity rule and all are singular.
  * `(1|model)` is zero in 60 of 64.
  * `(1|scaffold)` is zero in 18 of the 32 that contain `scaffold:benchmark`.
  * `(1|model:effort)` is zero in all 32 that contain it.
  * *Correction:* the PF-2 outcome note above said these three are zero "wherever they appear", which overstated it for `model` and `scaffold`.
* **Same fit as PF-2.** Estimates, SEs and predictions match `c028_r1`.
  * Cell-holdout MAE is 7.10 / 7.07 / 8.36 pp, against 7.14 / 7.06 / 8.31.
  * The task holdout and the out-of-time test match to within 0.05 pp.
* **What PF-3 changed.** The drop-one fixed-effect LRTs changed, because their null models keep the hereditary `(1|model)` and `(1|scaffold)`:
  * release × domain p = 0.009, against 0.038 under PF-2;
  * generalist p = 0.019, against 0.002;
  * effort p = 0.16, against 0.54.
* **Unplanned fix.** `performance::r2_nakagawa` returns NA (and an inflated marginal R²) when a component is exactly zero. R² is now computed from Nakagawa's definition (`R/common.R: r2_nakagawa_def`). On the non-singular `c028_r1` it reproduces the package value, 0.219 / 0.702.
* **E2.** Selects `t018` (hereditary; `(1|model)` zero), the same fit as PF-2's `t018_r1`.
* **E1b, correction to the PF-3 note above.** E1b's own pre-registered PF-1 slope reduction **did** fire for M4 and D4.
  * lme4 names the second `model` grouping `model.1`, so the script's check for a zero core intercept never matches it.
  * M4 therefore reduced to M4r (identical to M2), as in the developer's original E1b run. D4 reduced to D4r.
  * PF-3 does not override E1b's own pre-registered rule. M4 and M4r are the same fit numerically, because the dropped slopes are at SD ≈ 5e-5.
