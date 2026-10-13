# HAL interpolation analysis: binomial GLMER over task-level agent results

**Question.** The HAL paper (Kapoor et al., arXiv 2510.11977) paid for fresh runs of every
(model × scaffold × benchmark × configuration) combination it reports. How well could those
results be recovered by an IRT-style mixed-effects logistic regression fit on only a subset of runs?

**Short answer.**
* Fit on all 174 paper runs (21,333 task outcomes), the selected model has task-level AUC 0.91 and conditional R² 0.70.
  * In-sample run-accuracy MAE is **1.3 pp**. That is a loose floor, because the model has a run-level random effect that absorbs most of each run's deviation.
* With 10–50 % of the combinations removed and the model refit, held-out run accuracy is predicted to
  **7.1–8.4 pp MAE**. The naive baselines reach 8.9–10.8 pp. Held-out task-level AUC is 0.84–0.86.
* Holding out individual task scores instead (§4c), the refit fills in a run's full accuracy to **0.9 / 1.6 / 2.7 pp** with 10 / 25 / 50 % of its tasks missing. Reporting the accuracy on the observed tasks alone gives 1.1 / 1.9 / 3.3 pp, so the refit is 0.2–0.7 pp (about 20 %) better.
* For runs added after the paper, MAE is **7.0 pp** for runs whose model is already known and **10.7 pp** for runs on brand-new models.

Design decisions, including the changes made after fitting (PF-1, and PF-2 / DC-1 from the statistical audit in [`AUDIT.md`](AUDIT.md)), are in [`DESIGN.md`](DESIGN.md).
Takeaways and the latent factors are in [`summary.md`](summary.md).

---

## 1. Data

| Item | Value |
|---|---|
| Source | HF `agent-evals/hal_traces`: 380 encrypted trace zips, 113 GB. They were streamed and decrypted with the public hal-harness password, keeping only config, per-task scores, latencies and usage (`scripts/extract_hal_traces.py`). The 175 modelled paper zips were streamed a second time to summarise the per-call Weave logs into per-task LLM-activity timing for E2 (`scripts/extract_call_timing.py`). |
| Paper runs | 186 runs, matched to zips from the paper's LaTeX appendix tables and the leaderboard links (`data/meta/hf_runs.csv`, `data/meta/README.md`). |
| Modelled | **174 runs**: the 186 minus 12 AssistantBench runs (see below). They cover 172 cells, 8 benchmarks, 15 models, 10 scaffolds, 4 effort levels and 1,084 tasks, for **21,333 task-level binary outcomes**. |
| Out-of-time test | 48 runs uploaded after the paper's HF snapshot (2025-10-08): new models (Claude Sonnet/Haiku/Opus 4.5, Gemini 3 Pro) and new scaffolds (Claude Code, TAU-bench Tool Calling). |
| Outcome | HAL's own per-task success flag, i.e. the quantity HAL's headline accuracy is computed from. |

**Data integrity.**
* Every modelled paper run reproduces the paper's reported accuracy exactly. Four pairs were averaged over two runs in the paper, and their means match.
* Getting there needed three fixes, all documented in the scripts:
  1. **15 SWE-bench zips were re-uploaded to HF in Nov 2025 with different task results.** For example, Claude 3.7 Sonnet with the HAL Generalist scaffold is 24 % in the paper but 38 % in the current file. The paper-time versions were taken from HF commit `1bf4166d`.
  2. ScienceAgentBench stores per-task success only inside `raw_eval_results`.
  3. HAL counts tasks missing from a run (agent crashes) as failures, e.g. 13/50 rather than 13/31.

**Partial credit (prompt item 7).** Only AssistantBench reports a partial-credit headline metric. hal-harness stores its per-task partial scores as an unlabeled list that cannot be aligned to task ids, and its only task-aligned binary outcome (exact match) is not HAL's metric. AssistantBench is therefore left out.
* All other benchmarks have a binary per-task outcome that equals their headline metric.
* So glmmTMB (beta / ordered beta) was not needed. A timing study on simulated data found it affordable (~45 s per fit), but there were no aligned partial scores to fit it to. Neither lme4 nor glmmTMB can mix a binary and a beta family in one model.

## 2. Methods (mirroring the TMS and PT analyses)

Full details are in `DESIGN.md`. The TMS/PT method summary is in `refs/METHODS_SUMMARY.md`, and the predictor rationale from related work is in `refs/RELATED_WORK_PREDICTORS.md`.

* **Model.** `lme4::glmer(success ~ …, family = binomial)`, Laplace approximation, `nloptwrap` optimizer (the optimizer PT used). The unit of observation is task × run, not benchmark × run (TMS and PT likewise work at the question level).
* **Predictors**, all collected programmatically:

  | Level | Predictor | Source |
  |---|---|---|
  | Model | provider | Epoch |
  | Model | reasoning model (post-training proxy) | LiteLLM / OpenRouter / leaderboard |
  | Model | release date | Epoch `model_metadata.csv` |
  | Configuration | reasoning effort (none / default / low / high; unknown and OpenAI "medium" → default) | HAL config |
  | Scaffold | generalist vs benchmark-specific scaffold | HAL agent name |
  | Benchmark | benchmark (fixed effect; only 8 levels) | HAL config |
  | Benchmark | domain (coding / science / web / customer service), entered only as a release-date slope | — |

  Core random intercepts are task (IRT difficulty), run (the observation cluster, added by PF-2), model (ability) and scaffold (Agent Psychometrics' additive scaffold ability).
* **Model size and training compute were excluded.** They are unknown for 12 of the 15 models, all closed-weight. Agent Psychometrics excluded compute for the same reason, and CPP's zero-fill of missing values would inject false information.
* **Candidate class.** Much smaller than TMS's 819 formulas: **64 candidates**.
  * Two release-date transforms: linear or log.
  * With or without domain-specific release slopes.
  * Every subset of four optional random terms (`model:benchmark`, `scaffold:benchmark`, `model:scaffold`, `model:effort`) on top of the maximal fixed part and the core random effects.
* **Validity filter (PT-style), applied before fitting:**
  * grouping factors with fewer than 3 levels;
  * groups observed in only one run (except `run` itself);
  * random terms whose partition duplicates another random term or a fixed factor;
  * random interactions whose factors have no main term, fixed or random (heredity, PF-3);
  * a rank-deficient fixed-effect matrix;
  * duplicate formulas.

  All 64 passed.
* **Selection (PF-3):** lowest AIC (as in TMS) among converged fits.
  * Zero-variance components (SD < 1e-3) are kept rather than removed, following "keep it maximal" (Barr et al. 2013).
  * Singular fits are therefore eligible.
* **Runtime.** Part 1 totals about 20 minutes, well within the 2 h budget:
  * 64 candidate fits: 6.8 min on 70 cores;
  * report with drop-one LRTs for fixed and random terms, plus DHARMa: ~10 min.

### Post-fit design changes (logged in DESIGN.md)
**PF-1 (superseded).**
* 50 of the original 64 fits were singular, and in every one the zero component was the *core* `(1|model)` term.
* The pre-registered rule kept the lowest-AIC non-singular fit, `c027`. A sensitivity analysis refit the singular fits without their zero components and selected `r032`.

**PF-2, after the statistical audit ([`AUDIT.md`](AUDIT.md) H1–H3).**
1. **Run-level random effect.** No candidate had one, so task outcomes within a run were treated as conditionally independent. This made the fixed-effect SEs and LRTs anticonservative. `(1|run)` is now a core term.
2. **One zero-variance threshold.** The primary `c027` was "non-singular" only under lme4's θ < 1e-4 tolerance, while PF-1 treated SD < 1e-3 as zero. A single 1e-3 threshold now applies everywhere.
3. **Model × benchmark term.** The selected `c027` lacked `model:benchmark`, the natural error term for the release × domain slopes.

PF-2 removed zero components by iterative reduction and selected `c028_r1`.

**PF-3, a user decision after PF-2.**
* **Heredity.** Random effects must respect heredity, the inheritance principle followed by PT's formulas: an interaction such as `(1|model:benchmark)` requires `model` as a fixed factor or as `(1|model)`. `c028_r1` had dropped `(1|model)` and `(1|scaffold)` while keeping their interactions, so it violates this.
* **Keep it maximal.** Following Barr et al. (2013), zero-variance components are **kept, not reduced**, and singularity no longer disqualifies a fit. Their simulations found that "overfitting the data with a maximal model has only minimal consequences for Type I error and power"; DESIGN.md PF-3 quotes the passage and states its scope.
* **Selection.** The lowest-AIC converged candidate is `c028`, the hereditary parent of `c028_r1`. It is numerically the same fit:
  * the zero `(1|model)` and `(1|scaffold)` sit at SD ≈ 3e-5;
  * fixed effects differ by at most 0.007 and fitted probabilities by at most 5e-4.
* **What PF-3 changes is the drop-one LRTs.** Their null models now keep the hereditary `(1|model)` and `(1|scaffold)`, and these can absorb variance once a covariate is removed.

**Effect on the conclusions.** Predictions barely change (§4). The inferential claims do. The pre-registered `c027` results are at commit `e4812fe`.

| Quantity | `c027` (pre-registered) | `c028_r1` (PF-2) | `c028` (PF-3, current) |
|---|---|---|---|
| AIC | 18,854.0 | 18,726.4 | 18,730.4 |
| release × domain LRT | χ²(3) = 25.6, p = 1e-5 | χ²(3) = 8.4, p = 0.038 | χ²(3) = 11.5, **p = 0.009** |
| generalist scaffold LRT | χ²(1) = 2.9, p = 0.09 | χ²(1) = 9.7, p = 0.002 | χ²(1) = 5.5, **p = 0.019** |
| benchmark LRT | χ²(7) = 136.6 | χ²(7) = 40.4 | χ²(7) = 40.4 |
| Cell-holdout run MAE, 10 / 25 / 50 % | 7.52 / 7.20 / 8.22 pp | 7.14 / 7.06 / 8.31 pp | 7.10 / 7.07 / 8.36 pp |
| Out-of-time MAE: known model / new model | 5.8 / 11.8 pp | 7.0 / 10.7 pp | 7.0 / 10.7 pp |

## 3. Part 1: full-data fit and quality of fit

**Selected formula (`c028`).**

```
success ~ provider + reasoning_model + release_years_z + effort + generalist + benchmark
          + release_years_z:domain
          + (1|task) + (1|run) + (1|model) + (1|scaffold)
          + (1|model:benchmark) + (1|scaffold:benchmark) + (1|model:scaffold)
```

* All 64 candidates pass the validity filter, including the heredity rule.
* All 64 are singular:
  * `(1|model)` is zero in 60 of 64 candidates;
  * `(1|scaffold)` is zero in 18 of the 32 that also contain `scaffold:benchmark`;
  * `(1|model:effort)` is zero in all 32 that contain it.
  * Model ability beyond the covariates is carried by `model:benchmark` and `model:scaffold`.
  * Model × effort variation is absorbed by `(1|run)`.
  * Under PF-3 these zero components are kept, and all 64 are eligible.
* Runners-up:
  * `c023` (ΔAIC +1.0) drops `scaffold:benchmark`. Its `(1|scaffold)` then takes that variance.
  * `c032` (ΔAIC +2.0) is `c028` plus a zero `(1|model:effort)`: the same fit, and the 2.0 is the parameter penalty.
  * The best candidate without domain slopes (`c007`) is 3.5 AIC behind.
* All 64 fits are in `results/candidate_metrics.csv`, and the top 20 in `results/tables/candidates_top20.md`.

**Quality of fit**

| Metric | Conditional (all random effects) | Fixed effects only |
|---|---|---|
| Task Brier | 0.113 | 0.215 |
| Task log-loss | 0.353 | 0.633 |
| Task 0/1 error at 0.5 | 16.3 % | 32.4 % |
| Task AUC | 0.910 | 0.646 |
| Run-accuracy MAE (pp) | **1.28** | 12.40 |
| Run accuracy, corr(pred, obs) | 0.995 | 0.710 |
| Nakagawa R², marginal / conditional | 0.219 / 0.702 | |

* **The conditional run-level fit is close to perfect by construction.** Each run has its own fitted effect, so the in-sample run MAE (1.3 pp) measures little; use the holdouts (§4) to judge interpolation.
  * By benchmark (MAE / max, pp): CORE 1.8 / 6.5, GAIA 0.8 / 3.4, Mind2Web 0.2 / 0.5, SWE 2.5 / 6.7, SciCode 0.9 / 3.0, SAB 0.9 / 2.1, TAU 2.1 / 4.5, USACO 0.5 / 1.5 (`results/part1/run_level_fit.csv`).
* **R² is computed from Nakagawa's definition** (`R/common.R: r2_nakagawa_def`, π²/3 residual). `performance::r2_nakagawa` returns NA when a variance component is exactly zero.
* **DHARMa simulated residuals.** Task-level uniformity p = 0.06, dispersion 1.00 (p = 0.64). For 0/1 outcomes the task-level dispersion test is not informative.
  * The run-aggregated tests are reported in `results/part1/dharma_tests.csv` (uniformity p = 2e-6, dispersion 1.03, p = 0.51), but **they are not interpretable for this crossed design**:
    * DHARMa's default simulation redraws the task effects that all runs share, so the simulated run totals are too spread. The observed residuals pile up near 0.5 (94 of 174 runs fall in 0.4–0.6).
    * Simulating conditional on the fitted effects is circular, since those effects were fit to the same runs, and the residuals come out strongly under-dispersed.
  * The pre-PF-2 report read the run-level p = 0.024 as mild misfit, which was not justified (AUDIT.md H1). Evidence on run-level dependence comes from the random-term LRTs below.
* **Variance components** (latent scale; π²/3 residual):
  * A term is tested by dropping it **together with every interaction that contains its factors** (heredity), e.g. `model` with `model:benchmark` and `model:scaffold`.
  * Single-variance tests use the boundary-corrected p (halved). Block tests use the plain χ² p, which is conservative.

  | Term | SD | Share | Dropped in the LRT | χ² (df) | p |
  |---|---|---|---|---|---|
  | task | 2.16 | 53.9 % | task | 5,821 (1) | < 1e-300 |
  | model × scaffold | 0.44 | 2.2 % | itself | 13.7 (1) | 1e-4 |
  | run | 0.43 | 2.1 % | itself | 86.3 (1) | 8e-21 |
  | model × benchmark | 0.40 | 1.9 % | itself | 9.7 (1) | 9e-4 |
  | scaffold × benchmark | 0.39 | 1.8 % | itself | 3.0 (1) | 0.04 |
  | model | ≈ 0 (4e-5) | 0 % | model + model × benchmark + model × scaffold | 23.1 (3) | 4e-5 |
  | scaffold | ≈ 0 (3e-5) | 0 % | scaffold + scaffold × benchmark + model × scaffold | 33.2 (3) | 3e-7 |

  * Task difficulty dominates.
  * Model-specific and scaffold-specific variation exists as blocks (p = 4e-5 and 3e-7), but none of it is a constant model or scaffold offset beyond the covariates. It is all benchmark- or pairing-specific.
  * `results/part1/lrt_random_terms.csv`.
* **Drop-one likelihood-ratio tests** for the fixed effects (TMS-style). A main effect is tested together with the interactions that contain it. The null models keep the full hereditary random structure:

  | Term | χ² | df | p | ΔAIC when dropped |
  |---|---|---|---|---|
  | benchmark | 40.4 | 7 | 1e-6 | +26.4 |
  | provider | 17.4 | 3 | 6e-4 | +11.4 |
  | release date (+ domain slopes) | 14.0 | 4 | 0.007 | +6.0 |
  | release × domain | 11.5 | 3 | 0.009 | +5.5 |
  | generalist scaffold | 5.5 | 1 | 0.019 | +3.5 |
  | effort | 5.2 | 3 | 0.16 | −0.8 |
  | reasoning model | 0.1 | 1 | 0.72 | −1.9 |

  * Wald tests from the same fit (`results/part1/fixed_effects.csv`): generalist p = 6e-4, web slope p = 0.005, customer-service slope p = 0.09, science slope p = 0.05.
  * The generalist LRT is weaker than its Wald test because the flag marks a single scaffold. When the flag is dropped, that scaffold's own `(1|scaffold)` intercept can take up the difference. The LRT is the more appropriate test.
  * With only 15 models, the χ² reference distributions for model-level terms (provider, release) are optimistic, so treat p-values near 0.01–0.05 as modest evidence.
  * The interpretation is in `summary.md`.

## 4. Part 2: holdout

**Procedure.** A cell is a model × scaffold × benchmark × effort combination; replicate runs of a cell are dropped together.
* For each holdout fraction (10 / 25 / 50 % of the 172 cells) there are 20 random repetitions with seeds 1–60.
* The fixed formula is refit on the remaining cells, and the held-out tasks are predicted from the training random effects. Levels never seen in training get 0; this always includes the held-out run's own `(1|run)` effect.
* **Baselines on the same held-out cells:**
  - the full-data model, which is in-sample and so a floor;
  - the training mean accuracy of the same benchmark;
  - an additive logit model (benchmark + model) fit to training cell accuracies.

**Averages over the 20 repetitions (primary design `c028`; ± is the SD across repetitions)**

| Held out | Refit run MAE (pp) | Full-model run MAE | Benchmark-mean MAE | Additive MAE | Refit task Brier | Refit 0/1 error | Refit AUC |
|---|---|---|---|---|---|---|---|
| 10 % (17 cells) | **7.10** ± 1.97 | 1.48 | 10.81 | 9.62 | 0.141 | 20.8 % | 0.857 |
| 25 % (43 cells) | **7.07** ± 1.05 | 1.26 | 10.35 | 8.93 | 0.140 | 20.5 % | 0.857 |
| 50 % (86 cells) | **8.36** ± 1.08 | 1.30 | 10.74 | 9.66 | 0.150 | 22.0 % | 0.838 |

* The **per-holdout-set** error rates the prompt asked for (each refit next to the full-data baseline) are in
  `results/tables/holdout_per_set_main.md` (60 rows) and `results/part2/main/holdout_metrics.csv`.
  Per-run predictions are in `results/part2/main/holdout_per_run.csv`.
* Earlier designs gave nearly identical results, with nearly identical Brier and AUC: the pre-registered `c027` 7.52 / 7.20 / 8.22 pp and the retired PF-1 design `r032` 7.28 / 7.11 / 8.03 pp (commit `e4812fe`), and PF-2's `c028_r1` 7.14 / 7.06 / 8.31 pp. Changing the random structure barely changes interpolation accuracy.
* All refits are singular, as expected: the hereditary `(1|model)` stays at zero (PF-3).
* **Reading the results:**
  - Dropping half the combinations costs only about 1 pp of run-level accuracy error compared with dropping 10 %.
  - The refit is consistently better than both naive baselines, by 1.3–3.7 pp on run accuracy and on every task-level metric.
  - The gap to the in-sample fit (~6–7 pp) is the cost of not running a combination at all. Part of it is the run's own effect (SD 0.43 logits), which cannot be known without running it.
* **Out-of-time test** (fit on paper data, predict the 48 later runs; `results/post_paper/`):

  | Case | Runs | Run MAE (pp) | Task AUC |
  |---|---|---|---|
  | Known model, new scaffold | 14 | 7.0 | 0.68 |
  | New model, known scaffold | 30 | 10.7 | 0.81 |
  | Known model, known scaffold, new cell | 2 | 12.1 | 0.88 |
  | New model and new scaffold | 2 | 35.1 | 0.88 |

  New models get ability only from their covariates (provider, reasoning, release date). Extrapolating release date past the training range (Claude 4.5 series, Gemini 3) is the main error source.

## 4b. Putting the pp errors in context
Figures are generated by `scripts/make_figures.py` and saved under `results/figures/`. Numbers are in `results/context_stats.md`.

**How scores are distributed.** The 174 modelled paper runs have accuracies from 0 % to 70 %: mean 26.9 %, median 26.9 %, IQR 11–38 %, SD 17.1 pp.
* Benchmarks differ greatly in level and in spread: SciCode median 5 % (SD 3 pp) through USACO median 39 % (SD 14 pp).
* Within a benchmark, runs typically sit **10.2 pp** from their benchmark's mean. That is the error of the trivial guess "this run will score the benchmark average".

![Run accuracy by benchmark](results/figures/run_accuracy_by_benchmark.png)

**Comparing error levels.** Each benchmark gets three numbers:
* in-sample fit (1.3 pp overall; a loose floor, because each run has its own fitted effect);
* held-out refit (7.8 pp overall, pooled over all holdouts);
* the naive benchmark-mean guess (10.2 pp).

The refit removes about a quarter of the naive error overall, but the gain is uneven:

| Benchmark | Naive | Held-out refit | Ratio |
|---|---|---|---|
| SWE-bench Verified Mini | 18.0 | 9.8 | 0.54 |
| CORE-Bench Hard | 10.4 | 6.6 | 0.64 |
| ScienceAgentBench | 7.3 | 5.3 | 0.73 |
| SciCode | 2.5 | 1.9 | 0.78 |
| TAU-bench Airline | 12.8 | 10.3 | 0.80 |
| GAIA | 13.2 | 12.4 | 0.94 |
| USACO | 11.0 | 12.1 | 1.10 |
| Online Mind2Web | 5.1 | 6.7 | 1.31 |

* **Where it helps:** benchmarks where runs differ a lot by model or scaffold (SWE-bench, CORE-Bench, ScienceAgentBench, SciCode, and now TAU-bench, which was at 0.97 under `c027`).
* **Where it does not beat a benchmark-average guess:**
  - GAIA and USACO, whose runs differ in ways the covariates don't capture;
  - Online Mind2Web, where every run is close to the mean anyway (SD 6 pp).
* The naive number is computed in-sample, so it is slightly optimistic for the naive guess.

![Error in context](results/figures/error_in_context.png)

**Size of individual errors.** Across all 2,958 held-out run predictions, 45 % fall within ±5 pp, 60 % within ±7.5 pp and 71 % within ±10 pp. Errors grow modestly with the fraction held out.
For reference, HAL's own paired repeat runs differ by up to about 4.5 pp (e.g. CORE-Agent with DeepSeek-R1: 8.9 % vs 4.4 %), so part of the error is irreducible run-to-run noise.

![Predicted vs observed](results/figures/holdout_pred_vs_obs.png)

**Why task-level modelling helps here.** Task solve rates are highly skewed.
* Share of tasks no paper run solved: 83 % on SciCode, 36 % on ScienceAgentBench, 22 % on CORE-Bench, SWE-bench and USACO.
* Tasks solved by every run: none on most benchmarks (at most 5 %, on USACO).
* So the task random effect (SD 2.2 logits) captures structure that benchmark-level averages cannot.

![Task solve rates](results/figures/task_solve_rates.png)

## 4c. Part 2b: task-level holdout (added on request; design in DESIGN.md)
**Setup.**
* The holdout unit is now a single task score: one task × one run, i.e. one model × scaffold × benchmark × effort combination on one task. Section 4 held out whole combinations instead.
* 10 / 25 / 50 % of the 21,333 rows are held out at random (20 repetitions each, seeds 1001–1060), and the selected formula `c028` is refit on the rest.
* Every run and task keeps most of its observations, so this tests *filling in* missing task scores of partly observed runs, not predicting unseen agents.
* Every refit keeps the zero hereditary `(1|model)`, so all are singular by design (PF-3). Results match PF-2's `c028_r1` to within 0.01 pp.
* The held-out row's own run effect is estimated from that run's training rows, which is where the run term helps most.

**Results** (`c028`; `results/part2_task/main/`):

| Held out | Held-out tasks per run | Subset MAE: GLMM refit | Subset MAE: run's own accuracy | Subset MAE: additive run+task logit | Noise floor | Full-run MAE: observed + GLMM-filled | Full-run MAE: subsample only | Cell holdout (§4) | Task Brier / AUC |
|---|---|---|---|---|---|---|---|---|---|
| 10 % | 12 | **9.7** | 12.1 | 10.2 | 9.2 | **0.91** | 1.13 | 7.1 | 0.130 / 0.876 |
| 25 % | 31 | **6.4** | 7.8 | 7.0 | 5.7 | **1.57** | 1.91 | 7.1 | 0.130 / 0.876 |
| 50 % | 61 | **5.3** | 6.7 | 6.1 | 4.0 | **2.65** | 3.32 | 8.3 | 0.135 / 0.866 |

All values are in pp unless labelled otherwise.
* **Subset MAE** is |mean predicted p − observed accuracy| over a run's held-out tasks.
* **Noise floor** is the error a perfect p would still incur on so few tasks: E|mean p − mean y| with y ~ Bernoulli(p_full), using 200 draws.
* **Full-run MAE** is error in the run's accuracy over all its tasks. "Subsample only" means the run's accuracy on its observed tasks.
* Other baselines: the benchmark mean gives 15.5 / 11.9 / 10.8 pp; the task's solve rate gives 14.2 / 11.8 / 11.1 pp; the in-sample full model gives 8.5 / 4.9 / 3.0 pp.
* The pre-registered `c027` gave 10.2 / 7.0 / 5.9 pp subset MAE and 0.96 / 1.72 / 2.94 pp full-run MAE. The run effect (PF-2) is what improved this setting.

![Task-level holdout](results/figures/task_holdout_error.png)

**Interpretation.**
1. **Most of the held-out-subset error is sampling noise.** With 12 held-out tasks per run, even the true probabilities would miss the observed subset accuracy by about 9.2 pp. Removing the floor in quadrature (a rough approximation) leaves a systematic error of about **3–3.5 pp at every fraction** (3.1 / 3.0 / 3.5). So losing up to half the rows barely degrades the model.
2. **Filling in a run is far easier than predicting it outright.**
   * A run whose remaining tasks are observed and the rest filled in by the GLMM has full-benchmark accuracy within 0.9 / 1.6 / 2.7 pp.
   * Predicting a whole run, as in the cell holdout, gives 7.1–8.4 pp.
   * So the run's own observed tasks carry most of the information about that run.
3. **The GLMM's advantage over subsampling is real but moderate.**
   * Simply running a random subset of tasks and reporting that accuracy gives 1.1 / 1.9 / 3.3 pp. The GLMM saves 0.2–0.7 pp, about 20 %.
   * A covariate-free additive logit (run accuracy + task solve rate) gives 0.96 / 1.72 / 3.06 pp, and 10.2 / 7.0 / 6.1 pp on the held-out subset.
     * The GLMM now beats it at every fraction, on subset MAE, full-run MAE, Brier (0.130–0.135 vs 0.132–0.140) and log-loss.
     * Under the pre-registered `c027`, which had no run effect, the two were tied. The gain comes from partially pooled run effects combined with the rest of the structure.
4. **Task-level discrimination is the same as in the cell holdout** (AUC 0.87–0.88 vs 0.84–0.86; Brier 0.13 vs 0.14–0.15). Task difficulty dominates individual outcomes, and in both settings the task is seen in training.
5. **The gain varies by benchmark** (25 % holdout, subset MAE; `per_benchmark.md`).
   * The GLMM now beats subsampling on every benchmark. The gain is largest on CORE-Bench (8.3 vs 10.9 pp), SWE-bench (8.4 vs 10.4), Online Mind2Web (4.1 vs 5.2), USACO (4.0 vs 5.0) and SciCode (3.0 vs 3.9).
   * It is only level on **TAU-bench** (11.0 vs 11.1). Under `c027` it was worse on TAU-bench (13.5 vs 11.1) and USACO (5.3 vs 5.0).
   * TAU-bench remains the hardest benchmark to fill in, and its broken tasks (E3) add noise.

## 5. Extensions

### E1. Agent Psychometrics task features (SWE-bench Verified Mini)
* **Why it applies.** SWE-bench has the largest in-sample run error (2.5 pp) and the largest gain from modelling (§4b). An unseen task can only be predicted from its features.
* **Features.** All inherited from the Agent Psychometrics release (`data/external/agent_psychometrics/`); nothing was annotated by hand:
  - PC1 of their 15 LLM-judged features (48 % of variance). Loadings are highest on debugging complexity, atypicality, logical reasoning and solution complexity.
  - Their published 1PL difficulty `b`, fit on 134 SWE-bench leaderboard agents.
* **Evaluation.** 5-fold cross-validation over held-out tasks (`results/ext1_ap_features/`):

  | Model | Held-out-task Brier | Log-loss | 0/1 error | AUC | Run MAE (pp) |
  |---|---|---|---|---|---|
  | Selected model | 0.189 | 0.561 | 31.4 % | 0.733 | 8.00 |
  | + AP feature PC1 | 0.136 | 0.429 | 19.3 % | 0.866 | 4.45 |
  | + AP difficulty `b` | **0.110** | **0.355** | **15.3 %** | **0.909** | **4.45** |

* **In-sample.** PC1 coefficient −2.19 (SE 0.36), ΔAIC −34; `b` coefficient −2.89 (SE 0.46), ΔAIC −49. The overall task random-effect SD falls from 2.16 to 2.11 (PC1) and 2.09 (`b`).
* **Conclusion.** Inherited task features substantially improve prediction for *new tasks*, matching the Agent Psychometrics finding (their AUC 0.84 vs 0.72).
* **What this does not show.** The features entered only as task-level *main effects*. For tasks already seen in training, a main effect mostly duplicates the task random intercept. `(1|task)` is also additive: every run ranks tasks the same way. Task features crossed with agent terms could capture run × task structure that `(1|task)` cannot. E1b tests this.

### E1b. Task-feature × agent interactions (SWE-bench Verified Mini)
Added on request after E1 was reported, and pre-registered in DESIGN.md ("E1b") before any fit. Script: `R/11_ap_interactions.R`; outputs: `results/ext1b_interactions/`.
* **Features (inherited, following Agent Psychometrics).**
  * AP's fixed default 15 LLM-judge features, z-scored over all 500 SWE-bench Verified tasks.
  * Two **task-type scores**: PC1 and PC2 of the 15 features (PCA on the 500 tasks).
    * PC1 (42 % of variance) is a general difficulty axis: atypicality, debugging complexity, logical reasoning, domain knowledge and verification difficulty.
    * PC2 (9 %) contrasts codebase scope, test edge-case coverage, solution complexity and fix localization against implementation-language complexity and codebase scale.
  * **AP's own difficulty score** `dhat`, from their two-stage recipe: ridge regression of their frozen 1PL `b` on the 15 features.
    * It is fit on the 450 Verified tasks *not* in Mini (λ = 100 by 5-fold CV; CV R² 0.38) and predicted for the 50 Mini tasks (r = 0.69 with their `b`).
* **Models.** Each is the selected model (now `c028`, PF-3) plus extra terms. A = all agent-side fixed effects (provider, reasoning, release, effort, generalist).

  | id | added terms | what it lets vary |
  |---|---|---|
  | M0 | none | nothing (baseline) |
  | M1 | PC1 + PC2 main effects | task difficulty only (E1-style) |
  | M2 | M1 + (PC1 + PC2) × A | how provider, reasoning, release, effort and scaffold type shift performance on each task type (18 fixed terms) |
  | M3 | M1 + `(0 + PC1 + PC2 \| model)` | a shrunken model-specific slope on each task type |
  | M4 | M2 + M3 (primary, "keep it maximal") | both |
  | D1 / D4 | `dhat`, and `dhat` × A + `(0 + dhat \| model)` | 1-D analogs: model-specific sensitivity to difficulty |

  * **Reductions.** The full M4 is singular because its model slopes collapse to 0 once the fixed interactions are present. E1b's pre-registered PF-1 reduction drops the zero slopes, giving M4r, which is identical to M2. As in the original E1b run, M4r is the primary in the holdouts.
  * D4 is singular too, but its zero `(1|scaffold)` intercept blocks the script's reduction, so D4 is used unreduced (DESIGN.md PF-3 outcome).
* **In-sample (full data, base `c028`).**
  * Task features as main effects are strongly supported: M1 vs M0 χ²(2) = 35.2, p = 2e-8; D1 vs M0 χ²(1) = 30.9.
  * **The interaction blocks are no longer supported:**
    * M2 vs M1: χ²(18) = 21.9, p = 0.24;
    * M3 vs M1: χ²(3) = 6.3, p = 0.10;
    * D4 vs D1: χ²(10) = 15.4, p = 0.12.
  * On the pre-registered `c027` base these were p = 0.009, 0.009 and 0.03. That base had no run or model × benchmark effects, so model-specific SWE strength had nowhere to go except the feature interactions.
  * AIC: M3 −31.5 vs M0, M1 −31.2, D1 −28.9, M2/M4r −17.1. SWE in-sample run MAE: 2.50 pp (M0), 2.46 (M3), 2.38 (M2/M4r).
  * The largest fixed interaction is still provider × PC1: Anthropic models lose more from task difficulty than OpenAI models, −0.93 logits per SD of PC1 (SE 0.47, p = 0.051), on top of the −2.34 main effect. Before PF-2 this was −1.39 (SE 0.42).
  * The M3 slopes have SD 0.20 on PC1 and 0.22 on PC2, with correlation −1.00. That is effectively a single model-specific difficulty-sensitivity axis.
    * o4-mini is flattest across difficulty (+0.29 on PC1).
    * Claude Opus 4.1, DeepSeek V3 and Claude 3.7 Sonnet are steepest (−0.10 to −0.15).
  * No PC2 interaction is distinguishable from 0.
* **Holdouts.** Every model was refit on the same training sets as Part 2 (cell holdout, seeds 1–60) and Part 2b (task holdout, seeds 1001–1060), 840 refits in all.
  * Metrics are on held-out SWE rows.
  * 90 % intervals for each held-out run's accuracy come from simulation (fixed effects from their sampling distribution, random effects from their conditional distribution or from N(0, Σ) for unseen levels, then Bernoulli outcomes).
  * The M0 rows reproduce Part 2 (all-benchmark run MAE 7.10 / 7.07 / 8.36).
  * Values below are for 10 / 25 / 50 % held out.

  | Holdout, metric (SWE) | M0 | M3 (model slopes) | M4r primary (fixed interactions) |
  |---|---|---|---|
  | Cell: task log-loss | 0.332 / 0.372 / 0.373 | 0.331 / 0.369 / 0.369 | 0.351 / 0.402 / 0.497 |
  | Cell: run MAE (pp) | 9.49 / 9.21 / 9.89 | **9.30 / 9.00 / 9.47** | 9.80 / 9.17 / 9.87 |
  | Cell: 90 % PI width (pp); coverage | 36.1 / 36.6 / 36.6; 0.66 / 0.84 / 0.80 | 34.2 / 35.0 / 34.8; 0.71 / 0.84 / 0.78 | 34.5 / 34.4 / 33.8; 0.66 / 0.84 / 0.77 |
  | Task: log-loss | 0.332 / 0.326 / 0.340 | 0.330 / 0.326 / 0.336 | 0.336 / 0.338 / 0.355 |
  | Task: held-out-subset run MAE (pp) | 12.93 / 8.40 / 7.04 | 12.89 / 8.46 / 7.02 | 12.95 / 8.50 / 7.24 |
  | Task: completed-run MAE (pp) | 1.17 / 2.06 / 3.51 | 1.17 / 2.08 / 3.50 | 1.18 / 2.09 / 3.60 |
  | Task: 90 % PI width (pp); coverage | 55.1 / 41.9 / 39.0; 0.99 / 0.99 / 0.98 | 53.1 / 40.6 / 36.6; 0.99 / 0.99 / 0.97 | 53.1 / 40.2 / 36.2; 0.99 / 0.99 / 0.96 |

  Paired differences vs M0, pooled over fractions, with seed-bootstrap 95 % CIs (`*_paired_vs_M0.csv`). These CIs reflect variation across random splits of this dataset, not sampling uncertainty about new tasks or models (AUDIT.md M6).
  * **M4r (primary).**
    * SWE log-loss is *worse*: +0.058 [+0.022, +0.121] in the cell holdout and +0.010 [+0.007, +0.014] in the task holdout. AUC is also lower.
    * Run MAE is not better: cell +0.08 pp [−0.20, +0.36], task +0.11 [−0.02, +0.24]. Completed-run MAE is slightly worse, +0.04 [+0.00, +0.09].
    * Intervals are about 2.2 pp narrower, with slightly lower coverage (−0.01).
    * The 18 fixed interaction terms are estimated from 10 models on SWE-bench and overfit.
  * **M3 (model slopes only).**
    * In the cell holdout it helps modestly: log-loss −0.0027 [−0.0045, −0.0008], run MAE −0.27 pp [−0.40, −0.17], about 3 %. PI width is −1.8 pp with unchanged coverage.
    * In the task holdout it no longer improves run accuracy: subset MAE +0.00 [−0.08, +0.08], completed-run +0.00 [−0.02, +0.03]. Log-loss improves very slightly (−0.002), and PI width narrows by 1.9 pp with coverage 0.006 lower.
    * Under the pre-registered `c027` base, M3 had improved every task-holdout metric. With a run effect in the base model, a partly observed run's own data already captures what the slopes added.
  * **M1 (main effects only)** does about as well as M3 in the cell holdout: log-loss −0.0016 [−0.0033, +0.0003], run MAE −0.16 pp [−0.28, −0.07].
  * **D4** behaves like M4r: intervals narrow, log-loss gets worse (cell +0.040).
  * The intervals under-cover in the cell holdout for *every* model, M0 included (0.66–0.85 against a nominal 0.90). The simulation ignores uncertainty in the variance components, and new model × scaffold combinations differ more than Σ̂ implies.
* **Verdict on the pre-registered gate: not met.**
  * The primary (M4r) raises held-out SWE log-loss in both holdouts.
  * Therefore the extension stops at SWE-bench, as pre-registered: the other benchmarks were **not** annotated, and Parts 1–2 are unchanged.
  * **What remains of the earlier positive finding is small.** Task features carry information about held-out combinations mainly as **main effects** plus, at most, a single shrunken model-specific sensitivity to difficulty (M3).
    * M3 gives about a 3 % gain in held-out-cell run MAE and none in the task holdout.
    * In-sample, the interaction blocks are not statistically supported once the run and model × benchmark effects are modelled (p = 0.10–0.24).

### E2. Runtime of successful traces (TMS-style `lmer`)
* **Outcome (DC-1, AUDIT.md M2).** `span_s` is the time from the first LLM call's start to the last LLM call's end, per task. It comes from HAL's per-call Weave logs (`scripts/extract_call_timing.py` → `data/processed/task_timing.csv.gz`).
  * HAL's own `latencies.total_time`, used before DC-1, stops at the *start* of the last call. Single-call tasks therefore read about 0 s (79 SAB Self-Debug successes were exactly 0, and 109 more were under 1 s).
  * The span measures the agent's LLM activity, including API queueing under HAL's concurrent execution. It excludes environment setup and evaluation, so it is **not** full wall time.
  * Single-call tasks remain in the data, now with their true call duration: 26 % of SAB Self-Debug successes and 18 % of SciCode Zero Shot successes. No successful trace is now under 1 s.
* **Data.** 6,805 successful traces across 168 runs. Same 64-candidate class (now with `(1|run)` as a core term) and the PF-3 selection rule (heredity, zero components kept). 61 of 64 fits are singular, and 63 are eligible; one has a convergence warning.
* **Selected model:**

  ```
  log(span) ~ provider + reasoning + release + effort + generalist + benchmark + release:domain
              + (1|task) + (1|run) + (1|model) + (1|scaffold) + (1|model:benchmark)
  ```
* **TMS transform check.** Residual skewness is 0.42 on the log scale vs 28.3 raw, so the log is clearly right.
* **Fit.** R² marginal / conditional = 0.28 / 0.82.
  * Variance shares: scaffold 45 %, residual 26 %, task 16 %, model × benchmark 7 %, run 6 %, model 0 (kept for heredity).
  * Before DC-1 the scaffold share was 63 %. Part of that came from the measurement artefact, which made single-call scaffolds look near-instant.
  * Multiplicative effects on LLM-activity time:
    * reasoning models ×1.83 (SE 0.19 on the log scale);
    * DeepSeek ×2.01 (provider serving speed);
    * high effort ×1.24, low effort ×0.61;
    * newer models are slower on coding, ×1.73 per 2 SD of release date (SE 0.19).
  * Scaffold type matters most. Median span ranges from 28 s (SciCode Zero Shot, median 3 calls) to 470 s (SeeAct, 34 calls); see `results/ext2_runtime/outcome_by_scaffold.csv`.
* **Holdout** (same cell design), log-span RMSE: refit 0.74 / 0.78 / 0.81 at 10 / 25 / 50 %, against 0.55–0.56 for the full model and 1.03–1.09 for the benchmark mean. That is roughly a 2.2× typical multiplicative error (it was 0.99–1.13 with the old outcome).
  Outputs: `results/ext2_runtime/`.

### E3. LLM-judge score corrections (TAU-bench Airline)
* **Data available.** HAL's own per-task Docent judgments were never released (`data/external/judge/README.md`).
  The only public per-task LLM-judge labels for a HAL benchmark are the TAU-bench Airline task-validity flags of Kirgis et al. (2026), from GPT-5 and Claude Sonnet 4.5 judges plus a manual review.
* **Correction.** Flagged tasks are treated as broken and removed from all TAU runs, then the selected formula is refit and Part 2 is rerun with the same seeds.
  The pre-registered primary flags tasks where *both* judges agree; sensitivity variants use either judge, or the manual review.

| Variant | TAU tasks kept | TAU accuracy | TAU benchmark coefficient | Overall holdout run MAE, 10 / 25 / 50 % | TAU-only holdout run MAE |
|---|---|---|---|---|---|
| Uncorrected | 50 | 30.7 % | −0.49 | 7.10 / 7.07 / 8.36 | 9.5 / 9.8 / 10.8 |
| Both judges (primary) | 20 | 35.4 % | −0.05 | 7.38 / 7.40 / 8.47 | 11.6 / 12.9 / 13.3 |
| Either judge | 11 | 33.8 % | −0.65 | 8.11 / 8.11 / 8.96 | 18.8 / 20.1 / 19.4 |
| Manual review | 25 | 39.1 % | −0.47 | 7.44 / 7.26 / 8.40 | 12.9 / 11.8 / 13.2 |

* **Verdict: the corrections did not improve predictive accuracy.**
  - TAU-only holdout error rose for every variant, and overall task-level Brier was unchanged (0.141 → 0.141 at 10 %).
  - Part of this is mechanical: a TAU run's accuracy then rests on 11–25 tasks instead of 50, so it is noisier. The removed tasks were also near-certain failures, which are easy to predict.
  - The correction does change the *substantive* estimate: TAU-bench looks easier (coefficient −0.49 → −0.05), and accuracy rises by 4.7 pp (judges) or 8.4 pp (manual).
  - The two judges agree with the manual review only partly: 20 tasks flagged by both, 39 by either, 25 by the manual review.
  - Outputs: `results/ext3_judge/`, `results/part2/judge_*`.

## 6. Limitations
* **Selection on all the data.** The formula was chosen on the full paper data, so the Part 2 holdout reuses a design selected with the held-out cells present. The user specified this. The effect is small because only 64 candidates were compared.
* **Post-fit design changes.** PF-2 (after the statistical audit) and PF-3 (a user decision on heredity and keep-it-maximal) changed the random structure and selection rule after results were seen.
  * Each was logged in DESIGN.md before its own results were inspected.
  * The pre-registered `c027` results are kept in git history (§2).
* **Model ability rests on few models.** With 15 models, `(1|model)` is estimated at zero once the covariates and model × benchmark / model × scaffold terms are present. Ability for a new model therefore extrapolates provider + reasoning + release date, which gives 10.7 pp MAE out of time.
* **Missing benchmarks and labels.**
  * AssistantBench is excluded: its per-task partial-credit scores cannot be aligned to task ids.
  * For Extension 3, LLM-judge labels exist for TAU-bench only.
* **Unmatched configurations.** Reasoning effort is assumed to mean the same thing across providers (prompt item 8). Claude runs with thinking off are coded `none`.
* **Run-level dependence** is now modelled by `(1|run)`. No valid run-level goodness-of-fit test is available for this crossed design (§3, DHARMa), so it rests on the AIC and LRT evidence.
* **Small-sample inference.** χ² p-values for model-level fixed effects (provider, release date) rest on 15 models and are optimistic.

## 7. Reproduction
```
conda env create -f environment.yml                        # fa26-hal (R 4.4.3, lme4 2.0.6, python 3.11)
python -I scripts/extract_hal_traces.py data/meta/hf_tree.json data/raw/hal_slim data/tmp_zips 12
HAL_REVISION=1bf4166d052cdd3445127e17c15139cbb5505ca5 HAL_ONLY=data/meta/paper_revision_files.txt \
  python -I scripts/extract_hal_traces.py data/meta/hf_tree.json data/raw/hal_slim_paperrev data/tmp_zips_rev 15
python -I scripts/build_task_table.py data/processed/extracted_runs.csv data/processed/extracted_tasks.csv.gz data/raw/hal_slim data/raw/hal_slim_paperrev
python -I scripts/build_analysis_table.py
./run_R.sh R/01_data_check.R
python -I scripts/extract_call_timing.py data/meta/timing_zips_main.txt data/raw/call_timing data/tmp_zips_timing 12
HAL_REVISION=1bf4166d052cdd3445127e17c15139cbb5505ca5 \
  python -I scripts/extract_call_timing.py data/meta/timing_zips_paperrev.txt data/raw/call_timing_paperrev data/tmp_zips_timing 8
mkdir -p data/raw/call_timing_all && cp data/raw/call_timing/*.csv.gz data/raw/call_timing_paperrev/*.csv.gz data/raw/call_timing_all/
python -I scripts/extract_call_timing.py --merge data/raw/call_timing_all data/processed/task_timing.csv.gz   # E2 outcome (DC-1)
./run_R.sh R/02_fit_candidates.R 70        # Part 1 selection (PF-3) -> fits/candidates/*.Rds, fits/selected_model.Rds
./run_R.sh R/03_report_selected.R 16 main  # Part 1 quality of fit
./run_R.sh R/04_holdout.R 60 main          # Part 2 (also: judge_both, judge_any, manual) -> fits/holdout/*
./run_R.sh R/10_task_holdout.R 60 main     # Part 2b task-level holdout -> fits/holdout_task/*
./run_R.sh R/05_post_paper.R               # out-of-time test
./run_R.sh R/06_runtime.R 64               # E2
./run_R.sh R/07_ap_features.R              # E1
./run_R.sh R/11_ap_interactions.R full; for k in cell task summary; do ./run_R.sh R/11_ap_interactions.R $k 46; done   # E1b
./run_R.sh R/08_judge_refit.R              # E3 (then 04_holdout.R with judge_* variants)
./run_R.sh R/09_latent_factors.R; python scripts/make_report_tables.py
python scripts/make_figures.py; python scripts/make_task_holdout_figures.py
```
* **Fitted models.** All are saved as `.Rds` under `fits/`: 64 candidates, 240 cell-holdout refits (main + 3 judge variants), 60 task-holdout refits, the runtime and extension fits. `run_pf2.sh` reruns everything after Part 1 selection. The folder is gitignored because of its size, and the scripts regenerate it.
* **Determinism.** Seeds are fixed (cell-holdout seeds 1–60, task-holdout seeds 1001–1060, DHARMa 42, CV 1).
* **Threads.** `run_R.sh` forces single-threaded BLAS. Without it, OpenBLAS oversubscribed the server (see DESIGN.md).
