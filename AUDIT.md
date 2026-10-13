# Statistical audit of the HAL interpolation analysis

**Audited state.** Commit `1f9333a` (E1b pre-registration), plus the uncommitted edits to `REPORT.md` and `summary.md` and the untracked `R/11_ap_interactions.R` that were in the working tree on 2026-10-12. The analysis is still being extended, so anything added after that point has not been audited.

**Scope.** I checked `prompt.md` against `DESIGN.md`, all `R/` scripts, the data-preparation scripts, the result files, `REPORT.md` and `summary.md`, and the two reference analyses (`refs/TMS_regression-analysis.Rmd`, `refs/PT_glmer-regression-analysis-v3.Rmd`).
* Where a claim could be tested, I re-ran it against the saved fits and data. The check scripts are in `audit/` (see §6).
* Every number below that does not appear in the repo's own results comes from those scripts.
* All models I fitted here are **diagnostic**. They were fitted after the results were seen, so they must not replace the pre-registered selection without being logged as a post-fit change in DESIGN.md.

---

## 0. Bottom line

| Area | Verdict |
|---|---|
| Outcome data (per-task success, task sets, paper-accuracy reproduction) | **Sound.** Verified independently; see §4. |
| Predictive results (Part 1 fit, Part 2 cell holdout, Part 2b task holdout) | **Broadly trustworthy.** None of the issues below changes the main predictive numbers by more than about a point. One untested bias for unseen levels is noted (M7). |
| Inferential claims (p-values, "strongly supported" effects, latent-factor interpretation) | **Overstated.** The primary model leaves out two variance components that the data strongly support: a run-level random effect and `model:benchmark`. Once they are added, several headline effects shrink from p ≈ 1e-5 to p ≈ 0.04. |
| Model selection (PF-1) | **Internally inconsistent.** The "non-singular" primary model `c027` has a model SD of 5.5e-4. That is below the 1e-3 threshold PF-1 itself uses to call a component zero. |
| Extension 3 (LLM-judge corrections) | **The verdict rests on an invalid comparison**, and the text contains a factual error. A like-for-like comparison shows the correction has *no* effect, not a negative one. |
| Extension 2 (runtime) | **The outcome variable is mis-measured.** It is not per-task wall time. |
| Extension 1 / 1b (task features) | E1's headline compares unlike quantities. The new E1b script has a bug that stops the pre-registered PF-1 reduction from ever running. |

---

## 1. High-severity findings

### H1. No run-level (cell-level) random effect: the fixed-effect SEs and LRTs are anticonservative
* **What.** No candidate contains `(1|run)` or `(1|cell)`. Task outcomes within a run share run-specific conditions that none of the other terms capture: infrastructure, API behaviour, and the run's particular model × scaffold × benchmark × effort combination. `model:scaffold` and `model:effort` do not split the data into runs, so this correlation goes unmodelled.
  * The TMS rule "groups of size ≤ 1 are excluded" does not apply. Each run has 45–307 tasks.
* **Evidence** (`audit/a2_diagnostic_refits.R`, `audit/a3_r032_plus_run_lrt.R`):

  | Model | AIC | Run SD |
  |---|---|---|
  | `c027` (primary) | 18,854.0 | — |
  | `r032` (PF-1 sensitivity) | 18,801.8 | — |
  | `c027 + (1\|run)` | **18,738.2** (−116 vs c027) | 0.50 |
  | `r032 + (1\|run)` | **18,728.4** (−73 vs r032) | 0.43 |

  * The run term beats every one of the 64 candidates and every PF-1 reduction by a wide margin.
  * When it is added, `model:effort` collapses to ≈ 0. Effort varies at run level, so the model:effort term had been absorbing run noise.
  * This agrees with the DHARMa result already in the report: run-aggregated uniformity p = 0.024 (`c027`) and 0.013 (`r032`). The report lists this as a limitation, but nothing was done about it.
* **Impact.**
  * The Wald SEs and drop-one LRTs of every run-level and higher-level fixed effect assume task outcomes are conditionally independent within a run. That is false, so the p-values are too small (see H2 for magnitudes).
  * Predictions for held-out *cells* are almost unchanged, because a new run gets run effect 0.
  * The task-level holdout (Part 2b), where the run is seen, would probably *improve*.
* **Recommendation.**
  * Add `(1|run)` to the core random part. With 2 replicate pairs, `(1|cell)` is nearly the same thing.
  * Re-run selection, logged as a post-fit change: "the pre-registered candidate class omitted the observation-cluster term".
  * At minimum, report the fixed-effect inference from `r032 + (1|run)`.

**Fixed:** (DESIGN.md PF-2; commits `3a327e2`, `af28663`, `f2ae7a4`)
* **Change.** `(1|run)` is now part of the core random part: `R/candidates.R`, `RE_CORE = (1|task) + (1|run) + (1|model) + (1|scaffold)`.
  * The validity rule "every level is a single run" exempts `run`, because the observation cluster is exactly what this term is for.
  * All 64 candidates were refit, and selection was redone under the H3 rule.
* **Result.** The selected model `c028_r1` keeps `(1|run)` with SD 0.43. The drop-one LRT for the run term (`results/part1/lrt_random_terms.csv`, a new output) is χ²(1) = 84.1, boundary-corrected p = 2e-20, and dropping it would cost 82 AIC. As predicted here, `model:effort` collapsed to 0 and was removed.
* **Correction to the evidence above.** The DHARMa run-aggregated uniformity test cited above (p = 0.024) is **not valid evidence** for this design, in either direction. I checked this while making the fix:
  * DHARMa's default simulation redraws the crossed task effects that all runs share. The simulated run totals are then too spread, and the observed residuals pile up near 0.5. The new model gives p = 2e-6, with 94 of 174 runs in the 0.4–0.6 band.
  * Simulating conditional on the fitted random effects goes the other way and is strongly under-dispersed (p < 1e-7), because those effects were estimated from the same runs.
  * The support for `(1|run)` rests on the AIC and LRT evidence alone. `R/03_report_selected.R` now says this, and REPORT.md no longer reads the DHARMa run-level test as a misfit signal.
* **Effect on the results.**
  * In-sample run MAE falls to 1.3 pp, because a fitted run effect absorbs most of each run's deviation. That makes it a much looser floor than before.
  * Cell-holdout MAE is 7.1 / 7.1 / 8.3 pp at 10 / 25 / 50 %, against 7.5 / 7.2 / 8.2 before.
  * The task-level holdout, where the run is seen, improved as expected: held-out-subset MAE is 9.7 / 6.4 / 5.3 pp, against 10.2 / 7.0 / 5.9. The GLMM now beats the covariate-free additive logit at every fraction.

### H2. The primary model `c027` omits `model:benchmark`, which inflates the domain and benchmark claims
* **What.** `release_years_z:domain` is a model-level × benchmark-level effect. Its natural error term is model × benchmark (or model × domain) variation. `c027` has no such random term, so every bit of model-specific benchmark strength is credited to the 3 domain-slope parameters.
* **Evidence.** The same LRTs under three random structures:

  | Term (drop-one LRT) | `c027` (reported) | `r032` (has model:benchmark) | `r032 + (1\|run)` |
  |---|---|---|---|
  | release × domain, χ²(3) | 25.6, **p = 1e-5** | 8.3, p = 0.040 | 8.4, p = 0.038 |
  | release (+ slopes), χ²(4) | 26.9, p = 2e-5 | 9.7, p = 0.046 | 10.9, p = 0.028 |
  | benchmark, χ²(7) | 136.6 | 39.6 | 40.4 |
  | generalist, χ²(1) | 2.9, p = 0.09 | 9.6, p = 0.002 | 9.7, p = 0.002 |
  | provider, χ²(3) | 12.0, p = 0.007 | 11.7, p = 0.009 | 15.7, p = 0.001 |
  | reasoning + effort (joint), χ²(4) | 2.6, p = 0.63 | 3.2, p = 0.53 | 2.7, p = 0.61 |

  * Adding `(1|model:benchmark)` directly to `c027` (AIC 18,805.8, −48) gives the same answer: release × domain χ²(3) = 8.4, p = 0.038.
  * Under `c027`, the domain slopes for customer service and science have p = 3e-4 and 0.01. Under `r032` they are 0.085 and 0.079.
* **Impact.**
  * `summary.md` takeaway 6 ("strongly supported, χ²(3) = 25.6, p = 1e-5") and the REPORT LRT table overstate the evidence by about four orders of magnitude. The honest statement is "weak evidence (p ≈ 0.04) that release-date gains differ by domain, driven mainly by web". The web slope is the only one that stays clearly negative (p = 0.005).
  * The generalist conclusion goes the other way. It is *stronger* in every model that has scaffold:benchmark (p = 0.002). `c027` understates it.
  * The provider effect and the null effort/reasoning result are robust.
* **Recommendation.** Base all inferential statements in REPORT/summary on `r032` (preferably `r032 + (1|run)`), or report both side by side. Prediction-based statements can stay on `c027`, since the predictions are nearly identical.

**Fixed:** (DESIGN.md PF-2, item 4)
* **Change.** PF-2 selection (H1 + H3) picks `c028_r1`:
  `provider + reasoning + release + effort + generalist + benchmark + release:domain + (1|task) + (1|run) + (1|model:benchmark) + (1|scaffold:benchmark) + (1|model:scaffold)`.
  * It contains `model:benchmark`, which is the error term the domain × release test needed.
  * All p-values, CIs and LRTs in REPORT.md and summary.md now come from this model (`results/part1/lrt_fixed_terms.csv`).
  * Its LRTs reproduce the `r032 + (1|run)` column above:

  | Term | Before (`c027`) | After (`c028_r1`) |
  |---|---|---|
  | release × domain, χ²(3) | 25.6, p = 1e-5 | 8.4, **p = 0.038** |
  | release (+ slopes), χ²(4) | 26.9, p = 2e-5 | 10.9, p = 0.028 |
  | benchmark, χ²(7) | 136.6 | 40.4 |
  | generalist, χ²(1) | 2.9, p = 0.09 | 9.7, **p = 0.002** |
  | provider, χ²(3) | 12.0, p = 0.007 | 15.6, p = 0.001 |
  | effort, χ²(3) | 2.2, p = 0.54 | 2.2, p = 0.54 |
  | reasoning model, χ²(1) | 0.7, p = 0.42 | 0.1, p = 0.72 |

* **Documentation.** REPORT.md §3 and summary.md takeaways 4–6 and the fixed-effects table were rewritten:
  * The domain × release result is now called weak evidence (p ≈ 0.04), carried by the web slope (−1.23 per 2 SD, p = 0.005).
  * The customer-service and science slopes are no longer distinguishable from the coding slope (p = 0.09 and 0.06).
  * The generalist effect is now stated as clearly supported.

### H3. The PF-1 selection rule is internally inconsistent: `c027` is itself singular by PF-1's own definition
* **What.** The primary rule keeps fits that `isSingular()` does not flag. lme4's default tolerance is θ < 1e-4. `c027`'s `(1|model)` SD is **5.5e-4** (`results/part1/random_effects_variance.csv`; θ = 0.000548). That is under the 1e-3 threshold `R/02b_reduce_singular.R` uses to declare a component zero.
  * So the only difference between `c027` and the 50 "singular" fits is where an arbitrary tolerance happens to fall. `c027` has exactly the problem PF-1 describes, a core `(1|model)` at zero.
  * REPORT §3 and summary already show "model ≈ 0 %".
* **Impact.**
  * The stated reason for treating `c027` as primary ("pre-registered rule kept") does not hold up. It is ΔAIC +52 worse than `r032`, and it lacks the `model:benchmark` term behind H2.
  * The predictive results are unaffected, since `r032` predicts the same within 0.3 pp.
* **Recommendation.** Log this in DESIGN.md, and either:
  * make `r032` (or its H1 extension) primary for inference; or
  * state explicitly that `c027` is near-singular and that inference comes from the sensitivity model.

**Fixed:** (DESIGN.md PF-2, items 2–3; `R/candidates.R: zero_components`, `is_singular2`, `fit_and_reduce`)
* **One threshold.** A variance component is zero when its SD < 1e-3. A fit is singular when `isSingular()` is TRUE **or** any component is zero. The same definition decides both eligibility and which components get removed, and the holdout scripts use it to count singular refits.
* **Reduction is part of the primary rule.** Every singular fit is refit without its zero components, repeatedly, until none remains. Originals and reductions form one pool, and the selected model is the lowest-AIC fit that converged with no zero component.
  * The separate `reduced` / `r032` sensitivity variant (`R/02b_reduce_singular.R`) is retired, and its outputs were removed.
  * The pre-registered `c027` results stay in git history at `e4812fe`. REPORT.md compares old and new side by side.
* **Result.**
  * All 64 originals are singular under the single threshold, and their reductions give 32 distinct formulas, 29 of them eligible.
  * Three of the reduced fits (`c064_r1`, `c015_r1`, `c057_r1`) had a further component reach zero. Each second-round reduction is a formula already in the pool (`c055_r1`, `c009_r1`, `c052_r1`, all eligible), so the loop correctly skips refitting it.
  * `(1|model)`, `(1|scaffold)` and `(1|model:effort)` are zero in every candidate that has them.
  * The selected `c028_r1` has no component below SD 0.39 and is not singular under either criterion.
  * The convergence-warning flag no longer counts lme4's "boundary (singular) fit" message, which singularity already tracks.

### H4. Extension 3: the "corrections did not improve prediction" verdict comes from an invalid comparison, and the text misstates the judge agreement
* **Invalid comparison.** Uncorrected and corrected models were scored on **different outcomes**: TAU run accuracy over 50 tasks vs over 20 / 11 / 25 tasks.
  * A run accuracy over fewer tasks has a larger binomial SD. At p ≈ 0.35 that is 6.7 pp with 50 tasks and 10.7 pp with 20.
  * The rise in TAU run MAE (11.9 → 13.9 pp and up) is therefore mechanical. REPORT mentions this, then gives the verdict anyway.
* **Like-for-like check** (`audit/a1_judge_like_for_like.R`). I took the same 60 holdout splits and scored both the uncorrected and the `judge_both` refits on the **same rows**: held-out TAU runs, only the 20 tasks both judges consider valid.

  | Held out | Run MAE, uncorrected | Run MAE, corrected | Brier, uncorrected | Brier, corrected |
  |---|---|---|---|---|
  | 10 % | 13.1 | 13.6 | 0.2167 | 0.2168 |
  | 25 % | 14.2 | 14.1 | 0.2095 | 0.2075 |
  | 50 % | 15.0 | 15.8 | 0.2230 | 0.2254 |

  The correction neither helps nor hurts prediction of the valid tasks.
  * The substantive effects stand: TAU looks easier and its accuracy rises.
  * The right verdict is "**no detectable effect on predictive accuracy**", not "did not improve, error rose".
* **Factual error.** REPORT says "20 tasks flagged by both, 39 by either". summary says "The two LLM judges agree on only 20 of the 39 tasks either one flags".
  * From `taubench_airline_task_validity_kirgis2026.csv`: **30** tasks are flagged by both, 39 by either and 25 by manual review. The 20 is the number of tasks *kept*.
  * So the judges agree on 30 of 39 (77 %), not "only 20".
* **Scope note (low).** The prompt describes HAL judge output as *correcting labels*, i.e. flipping individual run × task outcomes. HAL's own per-run judgments are not public, and the per-run Docent dump covers 12 Jan-2026 runs that are not in the HAL traces. Using task-level validity flags and dropping tasks is therefore a reasonable substitute. It is a different operation, though, and REPORT should say so explicitly.

---

## 2. Medium-severity findings

### M1. Predictor coding errors (data pipeline)
* **DeepSeek V3 release date is about 3 months early.** `scripts/build_analysis_table.py:20` maps `deepseek-v3` to Epoch `DeepSeek-V3` (2024-12-26).
  * All 14 paper runs are "DeepSeek V3 (March 2025)" in both the paper and the leaderboard. At least one config calls `deepseek-chat-v3-0324`, so the right Epoch key is `DeepSeek-V3-0324` (2025-03-24).
  * This is the earliest model in the data, so it also sets `min_days` for the log-release candidates (`R/common.R:29`).
  * Effects: the release-date coefficient, the domain slopes and the linear vs log AIC comparison all shift.
* **Two GPT-5 runs actually ran at `high` effort but are coded `default`.** In both, the config sets `reasoning_effort: "high"`, while the leaderboard label says "GPT-5 Medium":
  * `swebench_verified_mini_sweagentgpt520250807_1754592641`
  * `taubench_airline_hal_generalist_high_reasoning___gpt5_1754597451`
  * `data/meta/README.md` notes the TAU one but keeps the label. The config should take precedence.
* **Fix.** Correct both. Because the fix comes after fitting, re-run Part 1 and log it in DESIGN.md as a data correction, not a design change.

### M2. Extension 2: `latency_s` is not per-task wall time
* `scripts/build_task_table.py:83` takes the time from the first LLM call to the last LLM call.
  * Environment setup and evaluation are excluded.
  * API queueing and rate-limit waits are included, and tasks run concurrently.
  * A task with a single LLM call gets about 0 s.
* Examples of the artefacts:
  * SAB Self-Debug has 79 successful traces at exactly 0 s, which `R/06_runtime.R:9` drops.
  * Another 109 of its 229 remaining successful traces are under 1 s and stay in, as log-scale outliers near −3.
  * SciCode Zero Shot has 4 zeros.
* **Impact.**
  * "Runtime is a scaffold property (63 % of variance)" partly reflects how many LLM calls each scaffold makes, plus measurement artefacts.
  * REPORT §E2's "per-task wall time" is wrong.
* **Fix.** Rename the variable "LLM-call span". Then either exclude single-call scaffolds or model them separately, or use a direct per-task duration if the traces have one. Re-run E2.

### M3. The overdispersion check uses a test that cannot detect anything on Bernoulli data
* DHARMa's dispersion test on ungrouped 0/1 outcomes is uninformative: binary data cannot be overdispersed observation by observation.
* So "dispersion 1.00 (p = 0.65), so there is no overdispersion" (REPORT §3) is unsupported. The only meaningful tests are the run-aggregated ones, and those show misfit (H1).
* **Fix.** Drop the task-level dispersion claim and report the run-level tests as evidence of unmodelled run-level dependence.

### M4. Reasoning effort and reasoning-model status are nearly confounded with model identity
* The design (`audit` tabulation, paper data) has these features:
  * Every non-reasoning model is `none`.
  * `low` is **only o4-mini**.
  * `default` comes only from models never run at any other level, apart from gpt-oss-120b. These are R1, R1-0528, GPT-5, o3 and Gemini 2.5.
* So `effortdefault` and `effortlow` are between-model contrasts estimated from a handful of models. With `(1|model)` ≈ 0 they are effectively tested against task-level noise.
* Only a few within-model contrasts exist: Claude none vs high, o4-mini low vs high and gpt-oss default vs high.
* `reasoning_model` is identified by 3 non-reasoning models: GPT-4.1, Gemini 2.0 Flash and DeepSeek V3.
* **Impact.** The null result is robust; the joint test of reasoning + effort is χ²(4) ≈ 2.6–3.2, p ≈ 0.5–0.6 in every model. But it is a low-power null.
  * Takeaway 5 should say the data contain little within-model effort variation, rather than present the result as confirming HAL's finding.
  * The separate drop-one LRTs for `reasoning_model` and `effort` each condition on the other, which is the wrong test for "do these matter". Report the joint test.

### M5. Extension 1: the headline result compares unlike things
* **`ap_b` is not a task feature.** It is AP's 1PL difficulty, fit to 134 SWE-bench leaderboard agents' **outcomes on these same tasks**. A genuinely new task has no `b`.
  * The AUC of 0.90 therefore shows transfer of externally measured difficulty, not prediction for new tasks from their features.
  * Comparing it with AP's feature-based AUC (0.84 vs 0.72), as REPORT and summary do, is apples to oranges. PC1 (AUC 0.855) is the comparable number.
  * The new E1b script handles this correctly: `sw_dhat` is a ridge prediction trained on the 450 non-Mini tasks.
* **Minor.** In `R/07_ap_features.R:12-13`, standardization and PCA are fit on all 50 tasks, including the held-out fold. This leak uses no outcomes and is small, but the PCA should be fit on external tasks, as E1b does.

### M6. E1b (`R/11_ap_interactions.R`, not yet run): the pre-registered PF-1 reduction can never run
* DESIGN E1b says that if M4 is singular, components with SD < 1e-3 are dropped.
* The code (`R/11_ap_interactions.R:137`) reduces only when **no** core intercept, including `model`, is below 1e-3.
  * `c027`'s `(1|model)` SD is 5.5e-4 (H3), so M3, M4 and D4 will almost certainly carry that zero component.
  * The condition is then FALSE and the singular M4 silently stays primary.
  * The code also drops only slope columns, while the pre-registration says to drop all zero components.
* **Fix this before running.** Otherwise the run will deviate from its own pre-registration.
* Further E1b concerns:
  * **Over-parameterization.** M2 and M4 add 18 fixed interaction parameters, (pc1 + pc2) × (3 provider + reasoning + release + 3 effort + generalist), all estimated from 27 SWE runs.
    * `effortlow` × feature comes from o4-mini alone, and `effortdefault` × feature from a few models.
    * Expect huge SEs, and probably rank or convergence warnings. A smaller A (for example release + provider) would be more defensible. Choose it *before* fitting.
  * **The seed-bootstrap CI measures the wrong uncertainty.** Resampling the 60 holdout splits captures variation across random splits of *this* dataset (50 tasks, 15 models). It does not capture sampling uncertainty about new tasks or models, and the splits overlap. The CI will be too narrow for a "promising" claim, so say what it covers.
  * **The coverage gate is lenient.** "PI coverage ≥ 0.80" for a nominal 90 % interval is generous. State the rationale, or use the nominal level with a tolerance tied to the number of runs.

### M7. Predictions for unseen random-effect levels set the effect to 0, which can bias run accuracy
* For a held-out cell, `model:scaffold` and `model:effort` levels are often unseen. `predict(..., allow.new.levels = TRUE)` then plugs in 0 rather than averaging over the random-effect distribution.
* On the probability scale, E[plogis(η + u)] ≠ plogis(η). A rough delta-method estimate at p ≈ 0.27 with σ² ≈ 0.47 gives about 2 pp toward 0.5 per affected run. That is not small next to a 7–8 pp MAE.
* **Not verified empirically.** Test it by averaging predictions over draws u ~ N(0, Σ̂) for the unseen components. E1b's `sim_intervals` already does this.

### M8. The candidate class leaves out the item × person interaction that TMS includes
* TMS's random terms include `stimulus:condition`, i.e. question × treatment. The analog here is `(1|task:model)` or `(1|task:scaffold)`, which would let models rank tasks differently.
* It is identifiable, because each model runs each task under several scaffolds or efforts.

  | Model | AIC change | task:model SD |
  |---|---|---|
  | `c027 + (1\|task:model)` | −7.6 | 0.38 |
  | `r032 + (1\|task:model)` | −5.2 | 0.36 |

* The effect is modest but real. It bears directly on the §4c and E1b question of whether run × task structure exists beyond `(1|task)`.
* E1b asks the same question through features. This term is the feature-free baseline it should be compared against.

---

## 3. Low-severity findings: interpretation, wording and reporting

1. **Scaffold abilities are not on a common scale.** Every specialized scaffold appears on exactly one benchmark. Its "ability" is identified only relative to the HAL Generalist on that benchmark, plus the benchmark fixed effect.
   * Ranking SWE-Agent (+1.00) against HF Open Deep Research (−1.11) assumes the generalist does equally well relative to the specialists on every benchmark. That holds only without `scaffold:benchmark`, and `r032` estimates that SD at 0.41.
   * "Scaffold choice matters about as much as model choice" (summary takeaway 4) depends on this assumption.
2. **"Generalist" is a single scaffold.** `generalist := scaffold == "HAL Generalist Agent"`. The fixed effect is therefore one scaffold's deviation, separated from that scaffold's random intercept only by shrinkage.
   * Read it as "the HAL Generalist Agent vs the specialized scaffolds", not as a property of generalist scaffolds.
3. **Model ability depends on what each model happened to be run on.** The model-ability table averages model × scaffold BLUPs and effort effects over the scaffolds and efforts each model was actually run with, and those differ by model. Claude Opus 4, ranked #1, has 8 runs.
   * Better: report ability at a fixed reference configuration, or say clearly that it is a composition-weighted average.
4. **Extrapolated units.** "+2.4 logits per year" (summary 6) extrapolates from release dates spanning about 8 months (Dec 2024–Aug 2025; 2 SD ≈ 5 months). Report per 2 SD, as the fixed-effects table does.
5. **"Roughly half of HAL's runs could have been predicted to within about 8 pp"** (summary 1) confuses MAE with a quantile. The report's own numbers are 46 % within 5 pp and 61 % within 7.5 pp. Reword it as "with half of the cells held out, MAE ≈ 8 pp".
6. **"Four pairs were averaged over two runs"** (REPORT §1). Only **2** replicate pairs are in the modelled data: CORE-Agent/R1 and SciCode Tool Calling/Opus 4.1 High. That is consistent with 174 runs forming 172 cells. Those 4 runs match the paper only as cell means.
7. **"The effect is small because only 64 candidates were compared"** (REPORT §6) is asserted, not shown. A nested holdout that re-selects within each training split would show it, or else the claim should be softened.
8. **"±" in the holdout table** is the SD across 20 overlapping random splits, not a CI or SE. Label it.
9. **The §4b naive baseline is in-sample** (acknowledged). The held-out benchmark-mean baseline (10.4–10.8 pp) is already computed in Part 2, so use it for the ratio table.
10. **Subtracting the noise floor "in quadrature" from an MAE** (REPORT §4c, point 1) is not valid. MAEs do not add in quadrature. Use the RMSE (`run_rmse_pp` is already computed) and subtract variances.
11. **Small-sample LRTs and Wald CIs for model-level terms.** There are only 15 models, so χ² reference distributions for provider, release and domain are optimistic even after H1/H2.
    * A parametric bootstrap (`pbkrtest::PBmodcomp`) or profile CIs would be more defensible. Profile CIs were pre-registered "where tractable", but only Wald CIs were reported.
12. **Out-of-time set details:**
    * 36 Online Mind2Web task ids in 4 post-paper runs carry a `_110325` suffix. Each matches a paper task once the suffix is stripped, but as written they enter as unseen tasks (144 rows).
    * Unlinked post-paper zips are kept, while unlinked pre-paper zips are dropped as superseded. In one CORE cell, the unlinked zip scores 75.6 % against 42.2 % for the linked one.
    * 2 "post-paper" cells repeat paper cells.
    * The Gemini 2.0 Flash "High" TAU run is coded `effort = high` on a non-reasoning model.
13. **The GAIA "missing = failure" rule has one exception.** HF Open Deep Research + GPT-5 has 164 GAIA rows because one task has no eval result. HAL scores that run as 103/164, matching the paper, so leaving the task out is correct. The rule as written in REPORT §1 should mention the exception.
14. **Reproducibility.** `run_R.sh` hard-codes `/home/eshedden/miniconda3/envs/fa26-hal`. Use `conda run -n fa26-hal` or `$CONDA_PREFIX`.

---

## 4. Checked and found sound

* **Outcome data.** Every modelled paper run's per-task outcomes reproduce the paper or leaderboard accuracy. The two replicate pairs match as cell means.
  * Task sets are complete: USACO 307, SciCode 65, CORE 45, SAB 102, Mind2Web 300, SWE 50, TAU 50, GAIA 165, apart from the one task in item 13.
  * Task ids are identical across runs, so `(1|task)` is correctly crossed. There are no duplicate rows.
  * The paper-time SWE-bench zips are correctly recovered from HF revision `1bf4166d`.
  * The UNSURE CORE R1 pair is resolved correctly (2.22 % matches the paper).
* **Other predictors.**
  * Provider coding is right (gpt-oss → OpenAI).
  * Reasoning flags match the configs (Claude hybrid and V3.1 → TRUE, with thinking-off runs carrying no reasoning argument).
  * Effort mapping (medium/unknown → default) follows prompt item 8.
  * The other release dates agree with Epoch.
* **AssistantBench exclusion.** Excluding it under prompt item 7 is justified as documented.
* **Candidate machinery.**
  * The validity filter (`R/candidates.R`), base rank check, enumeration and selection code do what DESIGN.md says.
  * The fits use ML/Laplace throughout, so AIC and LRT comparisons are valid within lme4.
  * The LRTs respect marginality, dropping main effects together with their interactions.
* **Holdout code (`R/04`, `R/10`).** Seeds, cell sampling, baselines and metric definitions match DESIGN.md. Replicate runs are dropped together.
* **Holdout leakage check.** The cell-holdout result is not driven by a sibling cell left in training (`audit/a4_holdout_by_sibling.py`). Error is 7.0 pp when another effort level of the same model/scaffold/benchmark stays in training and 7.4 pp when no same model + scaffold cell does (10 % holdout; similar at 25 / 50 %). Cells whose only link is the same model on the Generalist scaffold for *another* benchmark are worst (9.0–9.6 pp).
* **Per-benchmark discrimination.** In-sample AUC of `c027` within each benchmark is 0.83 (TAU) to 0.98 (SciCode). The pooled 0.906 is not just an artefact of pooling benchmarks.
* **Pre-registration discipline (prompt item 6).** PF-1, Part 2b and E1b were each logged before being run, with the reason given. No evidence of HARKing; the issues above are oversights, not result-driven choices.
* **Differences from TMS/PT that are justified:**
  * Laplace instead of PT's nAGQ = 0, which makes AIC comparable.
  * Centring and scaling, which help convergence and do not change the fit.
  * Programmatic validity filtering in place of hand-coded rules.
  * TMS-style skewness check for the runtime transform.

---

## 5. Recommended actions, in priority order

1. Add `(1|run)` to the core random part (H1). Re-run Part 1 inference, at least for `r032`, and log it as PF-2 in DESIGN.md.
2. Restate the inferential claims (release × domain, benchmark, generalist) from a model with `model:benchmark` and `run` terms (H2/H3), and update REPORT §3 and summary takeaways 4–6.
3. Rewrite the E3 verdict and fix the 20 → 30 error (H4). Use the like-for-like comparison.
4. Fix the DeepSeek V3 release date and the two GPT-5 effort codes (M1), then re-run.
5. Fix the E1b PF-1 reduction condition **before** running E1b, and consider shrinking the interaction block (M6).
6. Relabel E2's outcome and handle the artefacts before interpreting the variance shares (M2).
7. Correct the wording items in §3 and M3 / M4 / M5.

## 6. Audit scripts (in `audit/`)

| Script | What it checks | Run with |
|---|---|---|
| `a1_judge_like_for_like.R` | H4 like-for-like E3 comparison. Reads `fits/holdout/{main,judge_both}`. | `./run_R.sh audit/a1_judge_like_for_like.R` |
| `a2_diagnostic_refits.R` | θ of `c027`; per-benchmark AUC; `c027` + model:benchmark / task:model / run; `r032` + task:model; joint reasoning + effort LRTs; release × domain LRT under `c027 + model:benchmark`. Saves `fits/audit_diag_fits.Rds`. | `./run_R.sh audit/a2_diagnostic_refits.R` |
| `a3_r032_plus_run_lrt.R` | `r032 + (1\|run)` and its drop-one LRTs (H1/H2 table). | `./run_R.sh audit/a3_r032_plus_run_lrt.R` |
| `a4_holdout_by_sibling.py` | Cell-holdout error stratified by what training knows about the held-out cell. | `python3 -I audit/a4_holdout_by_sibling.py` |

The data-pipeline findings (M1, M2, §3 items 6, 12 and 13) were checked against the raw extracted configs in `data/raw/` (gitignored), with one-off queries that are not saved here.
