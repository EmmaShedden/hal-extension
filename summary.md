# Summary: can a GLMM stand in for HAL's expensive runs?

Full results and methods are in [`REPORT.md`](REPORT.md), and the design log is in [`DESIGN.md`](DESIGN.md).
* All coefficients below are on the logit scale for the primary model `c028_r1`, selected under PF-2 (DESIGN.md; [`AUDIT.md`](AUDIT.md) H1–H3).
* PF-2 added a run-level random effect and fixed the singular-fit rule.
* Predictions changed little. Several p-values became much weaker, and the takeaways below reflect that.

## Takeaways

1. **Interpolation works reasonably well.**
   * The selected binomial GLMM was refit after dropping 10–50 % of the paper's (model × scaffold × benchmark × effort) combinations.
   * It predicts the accuracy of the dropped runs to **7–8 pp mean absolute error**, against 9–11 pp for the naive baselines.
   * Error barely grows between 10 % and 50 % held out (7.1 → 8.3 pp). Even with half of HAL's combinations never run, the rest would have been predicted with about 8 pp MAE.
   * That is good enough to rank clearly separated agents, but not to settle close leaderboard positions. HAL's own run-to-run spread on repeated runs is several pp, and the model estimates a run-specific effect (SD 0.43 logits) that cannot be known without running the configuration.
   * **For scale:** HAL run accuracies range from 0 % to 70 % (SD 17 pp), and a run typically sits 10.2 pp from its benchmark's average. The refit removes about a quarter of that.
   * The gain is concentrated on SWE-bench, CORE-Bench, ScienceAgentBench, SciCode and TAU-bench, with 20–46 % less error than guessing the benchmark mean.
   * On GAIA, USACO and Online Mind2Web it is no better than that guess. See REPORT.md §4b and `results/figures/`.
   * **Task-level holdout.** Filling in missing task scores is much easier than predicting whole runs, and here the GLMM clearly helps.
     * The model was also refit with 10–50 % of *individual task scores* held out. Each run's observed tasks are combined with GLMM predictions for its missing ones.
     * This recovers full-benchmark run accuracy to **0.9 / 1.6 / 2.7 pp**, against 7–8 pp for predicting whole runs.
     * Just reporting the accuracy on the tasks that were run gives 1.1 / 1.9 / 3.3 pp, and a covariate-free run + task additive logit gives 1.0 / 1.7 / 3.1 pp. The GLMM beats both at every fraction, by about 20 %. Without the run effect (pre-PF-2) it only tied the additive logit.
     * On a run's held-out tasks alone, the error is 5–10 pp, mostly binomial sampling noise; about 3–3.5 pp is systematic. See REPORT.md §4c.
2. **Extrapolating to new models is much weaker.**
   * Runs on models released after the paper (the Claude 4.5 series, Gemini 3 Pro) are predicted to 10.7 pp MAE.
   * Known models on new scaffolds are predicted to 7.0 pp.
   * Model ability is identified only through covariates (provider, reasoning, release date) plus model × benchmark and model × scaffold deviations, and those extrapolate poorly.
3. **Task difficulty dominates.**
   * The task random effect explains about 54 % of latent variance (SD 2.2 logits).
   * Each of the other components explains about 2 %: model × scaffold (SD 0.44), run (0.43), model × benchmark (0.40) and scaffold × benchmark (0.39). All are clearly supported by likelihood-ratio tests.
   * Benchmark-level means hide most of what decides an individual outcome.
4. **The HAL Generalist scaffold is clearly worse than benchmark-specific scaffolds.**
   * It is about 1.1 logits worse (OR 0.33, 95 % CI 0.18–0.63; LRT p = 0.002). Before PF-2 this looked borderline (p = 0.09), because the old model had no scaffold × benchmark term.
   * Among specialized scaffolds, abilities span about 1.2 logits, from HF Open Deep Research (−0.57) to SWE-Agent (+0.58). Model abilities span about 2 logits.
   * These scaffold abilities are only comparable through the Generalist, which is the one scaffold run on several benchmarks. Each specialized scaffold is identified relative to it on its own benchmark.
   * Model × scaffold fit matters (SD 0.44). Some pairings work better than additivity predicts, e.g. o4-mini with SWE-Agent +0.64 and Claude 3.7 Sonnet with the HAL Generalist +0.62. Others work worse, e.g. DeepSeek-R1 with SWE-Agent −0.61.
5. **Reasoning effort and "reasoning model" status add little once release date and provider are known.**
   * High vs no-thinking effort: +0.07 (OR 1.07, p = 0.60).
   * Reasoning model: −0.12 (p = 0.72).
   * Effort LRT: p = 0.54.
   * This matches HAL's own finding that higher reasoning effort often did not improve accuracy. Effort varies little within models, though, so this null result has limited power.
6. **Progress over time may be domain-specific, but the evidence is weak.**
   * Newer models are better on **coding** benchmarks: +1.03 logits per 2 SD of release date (about 5 months; 95 % CI 0.37–1.68).
   * The slopes for science (+0.25) and customer service (+0.11) are not distinguishable from the coding slope (interaction p = 0.06 and 0.09).
   * Only the **web** slope clearly differs: net −0.20, interaction p = 0.005.
   * The domain × release interaction as a whole is weak: χ²(3) = 8.4, p = 0.038. The best model without it is only 2.4 AIC worse.
   * Before PF-2 this test read p = 1e-5, because the model had no model × benchmark term to absorb model-specific benchmark strengths.
   * There are only 15 models, so treat all the slopes as descriptive.
7. **Task features help a lot for new tasks, and a little for new combinations, once they interact with the agent.**
   * For SWE-bench Verified Mini, inherited Agent Psychometrics features raise held-out-*task* AUC from 0.72 to 0.85, and their external IRT difficulty raises it to 0.90.
   * As main effects they add little for tasks already seen, which `(1|task)` covers. Crossed with the agent they do help (E1b; REPORT.md):
     * The best form is shrunken model-specific slopes on AP task-type scores, `(0 + PC1 + PC2 | model)`.
     * It lowers held-out SWE run MAE by about 0.3–0.4 pp (about 4–5 %) in both the cell and task holdouts, improves log-loss, and narrows 90 % intervals by 1–2 pp at unchanged coverage.
   * The pre-registered primary was the maximal model with 18 fixed feature × agent terms. It overfits the 10 SWE-bench models: run MAE and intervals improve, but task log-loss gets worse.
   * So the gate for annotating the other benchmarks was not met, and Parts 1–2 are unchanged.
   * The interaction is essentially one-dimensional: models differ in how steeply they fall off with general task difficulty. Anthropic models are steeper than OpenAI models, and o4-mini, gpt-4.1 and o3 are flattest. A second task-type axis added nothing detectable.
8. **LLM-judge corrections did not improve prediction.** Removing TAU-bench tasks that the judges flag as broken makes TAU-bench look easier: accuracy goes from 30.7 % to 35.4 % with both judges, or 39.1 % with manual flags. But holdout error does not improve: TAU run MAE rises from 9.5–10.7 pp to 11.6–13.3 pp with both judges.
   * The correction changes *what is measured* more than *how predictable it is*.
   * The two LLM judges agree on only 20 of the 39 tasks either one flags.
9. **LLM-activity time is mostly a scaffold property.**
   * The outcome is the time from the first LLM call's start to the last call's end on successful tasks (DESIGN.md DC-1). It is not full wall time.
   * Scaffold explains 45 % of variance, task 16 %, model × benchmark 7 % and run 6 %, with 26 % residual.
   * Reasoning models take ×1.83 as long, high effort ×1.24, low effort ×0.61, and newer models ×1.73 per 2 SD of release date on coding.
   * DeepSeek models take ×2.01, which likely reflects provider serving speed rather than the model itself.
   * Before DC-1 the scaffold share read 63 %, partly because HAL's own timing field records single-call tasks as 0 s.

## Latent factors (primary model `c028_r1`)

### Fixed effects
Reference levels: OpenAI, non-reasoning, effort = none, benchmark-specific scaffold, GAIA, release date at the sample mean (2025-05).

| Term | Estimate | 95 % CI | OR | Interpretation |
|---|---|---|---|---|
| (Intercept) | 0.34 | [−0.56, 1.24] | 1.40 | A typical GAIA task for the reference agent |
| Provider: Anthropic | 0.22 | [−0.34, 0.77] | 1.24 | Not distinguishable from OpenAI |
| Provider: Google | −1.11 | [−1.79, −0.42] | 0.33 | Gemini 2.0 Flash / 2.5 Pro (preview) underperform |
| Provider: DeepSeek | −1.02 | [−1.59, −0.44] | 0.36 | DeepSeek V3 / R1 family underperform |
| Reasoning model | −0.12 | [−0.79, 0.54] | 0.88 | No extra benefit given release date and effort |
| Release date (coding; per 2 SD ≈ 5 months) | 1.03 | [0.37, 1.68] | 2.79 | Capability growth on coding |
| × domain: customer service | −0.92 | [−1.99, 0.15] | | Net slope +0.11 per 5 months; difference from coding not significant |
| × domain: science | −0.78 | [−1.57, 0.02] | | Net slope +0.25 per 5 months; difference from coding not significant |
| × domain: web | −1.23 | [−2.09, −0.37] | | Net slope −0.20 per 5 months |
| Effort: default / low / high (vs none) | −0.04 / −0.22 / 0.07 | all CIs include 0 | | Effort is not a reliable lever |
| Generalist scaffold | −1.10 | [−1.74, −0.47] | 0.33 | The generic HAL scaffold underperforms specialized ones |

**Benchmark difficulty**, from benchmark effect plus task random effect (mean ± SD of task difficulty in logits; higher is harder):
* GAIA 0.00 ± 1.48 (easiest)
* TAU-bench 0.44 ± 1.35
* USACO 0.51 ± 2.12
* Online Mind2Web 1.28 ± 1.69
* SWE-bench Verified Mini 1.52 ± 2.03
* CORE-Bench Hard 1.78 ± 1.83
* ScienceAgentBench 2.21 ± 1.77
* SciCode 5.57 ± 1.59 (by far the hardest: only 59 successes out of 1,430 attempts)

Every benchmark has a within-benchmark task spread of 1.4–2.1 logits, which is as large as the differences between most benchmarks.
The benchmark effects are relative to the reference agent and shrink when model × benchmark and scaffold × benchmark deviations are modelled. The benchmark LRT is χ²(7) = 40, against 137 before PF-2.

### Random effects (latent scale; variance share uses π²/3 as the residual)

| Grouping | SD | Share | Drop-one LRT p | Meaning |
|---|---|---|---|---|
| task | 2.16 | 53.9 % | < 1e-300 | IRT item difficulty |
| model × scaffold | 0.44 | 2.2 % | 8e-4 | Model–scaffold fit (synergy) |
| run | 0.43 | 2.1 % | 2e-20 | Run-specific conditions (infrastructure, API behaviour, the specific configuration) |
| model × benchmark | 0.40 | 1.9 % | 0.004 | Model-specific strength on a benchmark |
| scaffold × benchmark | 0.39 | 1.8 % | 9e-7 | Scaffold-specific strength on a benchmark |

`(1|model)`, `(1|scaffold)` and `(1|model:effort)` are estimated at zero in every candidate that contains them, so PF-2 removed them.
* Model ability beyond the covariates is carried entirely by model × benchmark and model × scaffold.
* Scaffold ability is carried by scaffold × benchmark, which for a specialized scaffold is its single benchmark.
* Model × effort variation is absorbed by the run effect.

### Model ability (logit, averaged over domains)
Ability is provider + reasoning + release-date terms + the effort effect, model × benchmark BLUP and model × scaffold BLUP, averaged over the model's runs in each domain. A domain where a model has no runs gets only the covariate part.
* Each model's ability is therefore an average over the configurations it was actually run with.
* DeepSeek V3.1 and Gemini 2.5 Pro have one run each, so most of their row is covariates.
* Source: `results/latent/model_ability.csv`.

| Rank | Model | Runs | Ability | Coding | Science | Web | Customer service |
|---|---|---|---|---|---|---|---|
| 1 | Claude Opus 4 | 8 | 0.45 | 0.79 | 0.13 | 0.28 | 0.60 |
| 2 | Claude Opus 4.1 | 19 | 0.39 | 0.95 | 0.74 | −0.87 | 0.73 |
| 3 | Claude 3.7 Sonnet | 28 | 0.26 | −0.25 | 0.35 | 0.05 | 0.90 |
| 4 | Claude Sonnet 4 | 6 | 0.18 | 0.23 | 0.21 | 0.16 | 0.11 |
| 5 | GPT-5 | 11 | 0.07 | 0.51 | −0.15 | 0.15 | −0.24 |
| 6 | o4-mini | 28 | −0.12 | −0.01 | 0.08 | −0.17 | −0.37 |
| 7 | GPT-OSS-120B | 4 | −0.18 | 0.52 | −0.93 | −0.25 | −0.06 |
| 8 | GPT-4.1 | 15 | −0.28 | −0.34 | −0.16 | −0.03 | −0.59 |
| 9 | o3 | 13 | −0.28 | −0.16 | −0.15 | −0.26 | −0.56 |
| 10 | DeepSeek V3.1 | 1 | −0.89 | −0.39 | −0.81 | −1.29 | −1.06 |
| 11 | DeepSeek V3 | 13 | −1.10 | −1.53 | −1.20 | −0.71 | −0.97 |
| 12 | Gemini 2.5 Pro (preview) | 1 | −1.20 | −1.45 | −0.91 | −1.19 | −1.25 |
| 13 | DeepSeek R1-0528 | 3 | −1.22 | −1.42 | −1.15 | −1.17 | −1.12 |
| 14 | Gemini 2.0 Flash | 13 | −1.23 | −1.65 | −1.39 | −0.94 | −0.93 |
| 15 | DeepSeek R1 | 11 | −1.52 | −2.07 | −1.59 | −1.03 | −1.37 |

**What the ranking shows.**
* The Claude 4 generation leads, followed by GPT-5. This is broadly in line with the HAL paper, where Opus 4.1 and GPT-5 sit on most Pareto frontiers.
* Recent models are strongest in coding: Opus 4.1 +0.95, Opus 4 +0.79, GPT-OSS-120B +0.52 and GPT-5 +0.51.
  * Opus 4.1 is weak on web tasks (−0.87), driven by its GAIA model × benchmark effect (−0.40).
* Open-weight DeepSeek and the Gemini models trail the leaders by about 1–2 logits. That is an odds ratio of about 0.15–0.35 for solving the same task with the same scaffold.
* Rankings among the middle group (ranks 3–9) are within about 0.5 logits and are not well separated.

### Scaffold ability
Ability is the generalist effect plus the mean scaffold × benchmark BLUP over the benchmarks the scaffold was run on (`(1|scaffold)` is zero), in logits:

| Scaffold | Ability |
|---|---|
| SWE-Agent | +0.58 |
| SciCode Zero Shot | +0.33 |
| SAB Self-Debug | +0.33 |
| SciCode Tool Calling | +0.24 |
| USACO Episodic + Semantic | +0.12 |
| SeeAct | +0.08 |
| Browser-Use | +0.05 |
| CORE-Agent | −0.13 |
| HF Open Deep Research | −0.57 |
| HAL Generalist | −1.04 |

* On a benchmark where both exist, choosing a task-specific scaffold over the HAL Generalist is worth about 1.1 logits. That is roughly the gap between a mid-table model and a top one.
* Specialized scaffolds sit on different benchmarks, so ranking them against each other assumes the Generalist does equally well relative to the specialists everywhere. The scaffold × benchmark term (SD 0.39) says that holds only roughly.

## Caveats
* **Small samples.** There are only 15 models and 10 scaffolds, so model-level coefficients have wide CIs, and χ² p-values for model-level terms are optimistic. The domain slopes are descriptive.
* **Design changes after fitting.** PF-2 changed the random structure after the results were seen, in response to the statistical audit (AUDIT.md). The pre-registered `c027` results remain in git history (commit `e4812fe`), and REPORT.md §2 compares the two.
* **Selection and holdout share data.** The formula was selected on the full paper data before the holdout, as the prompt required.
* **Benchmark coverage.** AssistantBench is excluded because its per-task partial-credit scores can't be matched to task ids. LLM-judge corrections exist for TAU-bench only.
