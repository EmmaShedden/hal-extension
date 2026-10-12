# Summary: can a GLMM stand in for HAL's expensive runs?

Full results and methods are in [`REPORT.md`](REPORT.md) and the design log in [`DESIGN.md`](DESIGN.md).
All coefficients below are on the logit scale for the primary model `c027` unless stated otherwise.

## Takeaways

1. **Interpolation works reasonably well.**
   * The selected binomial GLMM was refit after dropping 10–50 % of the paper's (model × scaffold × benchmark × effort) combinations.
   * It predicts the accuracy of the dropped runs to **7–8 pp mean absolute error**. The naive baselines are at 9–11 pp, and in-sample error is 3 pp.
   * Error barely grows between 10 % and 50 % held out (7.5 → 8.2 pp). Roughly half of HAL's runs could have been predicted to within about 8 pp.
   * That is good enough to rank clearly separated agents, but not to settle close leaderboard positions. HAL's own run-to-run spread on repeated runs is several pp.
   * **For scale:** HAL run accuracies range from 0 % to 70 % (SD 17 pp), and a run typically sits 10.2 pp from its benchmark's average. The refit removes about a quarter of that.
   * The gain is concentrated on SWE-bench, CORE-Bench, ScienceAgentBench and SciCode (45–25 % less error than guessing the benchmark mean).
   * On GAIA, TAU-bench, USACO and Online Mind2Web it is no better than that guess. See REPORT.md §4b and `results/figures/`.
2. **Extrapolating to new models is much weaker.**
   * Runs on models released after the paper (the Claude 4.5 series, Gemini 3 Pro) are predicted to 11.8 pp MAE.
   * Known models on new scaffolds are predicted to 5.8 pp.
   * Model ability is identified only through covariates (provider, reasoning, release date), and those extrapolate poorly.
3. **Task difficulty dominates.**
   * The task random effect explains about 52 % of latent variance (SD 2.1 logits).
   * By comparison, model × scaffold explains 4.9 % and scaffold 3.7 %.
   * Benchmark-level means hide most of what decides an individual outcome.
4. **Scaffold choice matters about as much as model choice.** The specialized scaffolds' abilities span about 2.1 logits (from HF Open Deep Research to SWE-Agent), which is comparable to the spread of model abilities.
   * The **HAL Generalist Agent** is about 1.1–1.2 logits worse than benchmark-specific scaffolds: OR ≈ 0.31; p = 0.07 in the primary model, p = 0.002 in the sensitivity model.
   * Model × scaffold interactions are substantial (SD 0.64). Some pairings work far better than additivity predicts, e.g. GPT-5 with HF Open Deep Research +1.07, Opus 4.1 with HAL Generalist +0.91. Others work far worse, e.g. DeepSeek-R1 with SWE-Agent −1.35.
5. **Reasoning effort and "reasoning model" status add little once release date and provider are known.**
   * High vs no-thinking effort: +0.24 (OR 1.27, p = 0.18).
   * Reasoning model: −0.32 (p = 0.43).
   * Effort LRT: p = 0.54.
   * This matches HAL's own finding that higher reasoning effort often did not improve accuracy.
6. **Progress over time is domain-specific.**
   * Newer models are much better on **coding** benchmarks (+2.4 logits per year of release date).
   * On science reproduction the gain is weaker (+0.6 / yr).
   * It is flat or negative on web browsing (−1.0 / yr) and customer service (−0.35 / yr), once provider and the other terms are controlled.
   * The domain × release interaction is strongly supported (χ²(3) = 25.6, p = 1e-5).
   * There are only 15 models, so treat the non-coding slopes as descriptive.
7. **Task features help for new tasks, not new combinations.**
   * For SWE-bench Verified Mini, inherited Agent Psychometrics features raise held-out-*task* AUC from 0.72 to 0.85, and their external IRT difficulty raises it to 0.90.
   * For held-out *combinations* the task random effect already captures difficulty, so the features add nothing there.
8. **LLM-judge corrections did not improve prediction.** Removing TAU-bench tasks that the judges flag as broken makes TAU-bench look easier: accuracy goes from 30.7 % to 35.4 % with both judges, or 39.1 % with manual flags. But holdout error does not improve: TAU run MAE rises from 11.9–13.0 pp to 13.9–15.9 pp with both judges.
   * The correction changes *what is measured* more than *how predictable it is*.
   * The two LLM judges agree on only 20 of the 39 tasks either one flags.
9. **Runtime is a scaffold property.** In the log-runtime model of successful traces, scaffold explains 63 % of variance, task 14 % and model under 1 %.
   * Reasoning models take ×1.85 as long, high effort ×1.26 and low effort ×0.70.
   * DeepSeek models take ×2.25, which likely reflects provider serving speed rather than the model itself.

## Latent factors (primary model `c027`)

### Fixed effects
Reference levels: OpenAI, non-reasoning, effort = none, benchmark-specific scaffold, GAIA, release date at the sample mean (2025-05).

| Term | Estimate | 95 % CI | OR | Interpretation |
|---|---|---|---|---|
| (Intercept) | 1.02 | [0.19, 1.85] | 2.76 | A typical GAIA task for the reference agent |
| Provider: Anthropic | 0.31 | [−0.35, 0.97] | 1.36 | Not distinguishable from OpenAI |
| Provider: Google | −1.11 | [−1.92, −0.30] | 0.33 | Gemini 2.0 Flash / 2.5 Pro (preview) underperform |
| Provider: DeepSeek | −1.09 | [−1.74, −0.43] | 0.34 | DeepSeek V3 / R1 family underperform |
| Reasoning model | −0.32 | [−1.12, 0.48] | 0.72 | No extra benefit given release date and effort |
| Release date (coding; per 2 SD ≈ 5 months) | 1.00 | [0.36, 1.64] | 2.71 | Strong capability growth on coding |
| × domain: customer service | −1.14 | [−1.77, −0.52] | | Net slope −0.15 per 5 months |
| × domain: science | −0.74 | [−1.30, −0.17] | | Net slope +0.26 per 5 months |
| × domain: web | −1.42 | [−2.02, −0.83] | | Net slope −0.43 per 5 months |
| Effort: default / low / high (vs none) | 0.14 / −0.09 / 0.24 | all CIs include 0 | | Effort is not a reliable lever |
| Generalist scaffold | −1.18 | [−2.48, 0.11] | 0.31 | The generic HAL scaffold underperforms specialized ones |

**Benchmark difficulty**, from benchmark effect plus task random effect (mean ± SD of task difficulty in logits; higher is harder):
* GAIA 0.10 ± 1.46 (easiest)
* TAU-bench 1.13 ± 1.32
* USACO 1.45 ± 2.06
* Online Mind2Web 1.99 ± 1.69
* CORE-Bench Hard 2.08 ± 1.80
* SWE-bench Verified Mini 2.59 ± 1.98
* ScienceAgentBench 2.96 ± 1.76
* SciCode 6.21 ± 1.54 (by far the hardest: only 59 successes out of 1,430 attempts)

Every benchmark has a within-benchmark task spread of 1.3–2.1 logits, which is as large as the differences between most benchmarks.

### Random effects (latent scale; variance share uses π²/3 as the residual)

| Grouping | SD | Share | Meaning |
|---|---|---|---|
| task | 2.11 | 52 % | IRT item difficulty |
| model × scaffold | 0.64 | 4.9 % | Model–scaffold fit (synergy) |
| scaffold | 0.56 | 3.7 % | Scaffold ability θ_scaffold |
| model × effort | 0.23 | 0.6 % | Model-specific response to reasoning effort |
| model | ≈ 0 | 0 % | No model ability left over beyond the covariates (see DESIGN.md PF-1) |

### Model ability (logit, averaged over domains)
Ability is provider + reasoning + release-date terms + model BLUP + mean model × scaffold BLUP + mean effort effect over the efforts each model was run with. Source: `results/latent/model_ability.csv`.

| Rank | Model | Ability | Coding | Science | Web | Customer service |
|---|---|---|---|---|---|---|
| 1 | Claude Opus 4 | 0.71 | 0.82 | 0.72 | 0.63 | 0.67 |
| 2 | GPT-5 | 0.29 | 0.81 | 0.35 | −0.09 | 0.09 |
| 3 | Claude Sonnet 4 | 0.22 | 0.33 | 0.23 | 0.14 | 0.18 |
| 4 | Claude Opus 4.1 | 0.20 | 0.71 | 0.25 | −0.17 | 0.00 |
| 5 | o4-mini | −0.08 | −0.16 | −0.09 | −0.02 | −0.04 |
| 6 | GPT-4.1 | −0.10 | −0.20 | −0.11 | −0.03 | −0.06 |
| 7 | o3 | −0.10 | −0.19 | −0.11 | −0.04 | −0.07 |
| 8 | Claude 3.7 Sonnet | −0.18 | −0.54 | −0.22 | 0.08 | −0.04 |
| 9 | Gemini 2.5 Pro (preview) | −0.76 | −0.94 | −0.78 | −0.64 | −0.70 |
| 10 | DeepSeek V3 | −0.93 | −1.62 | −1.00 | −0.43 | −0.66 |
| 11 | DeepSeek V3.1 | −0.95 | −0.35 | −0.88 | −1.38 | −1.18 |
| 12 | GPT-OSS-120B | −1.18 | −0.67 | −1.13 | −1.55 | −1.38 |
| 13 | Gemini 2.0 Flash | −1.24 | −1.71 | −1.29 | −0.91 | −1.07 |
| 14 | DeepSeek R1 | −1.42 | −1.97 | −1.48 | −1.02 | −1.21 |
| 15 | DeepSeek R1-0528 | −1.58 | −1.43 | −1.56 | −1.68 | −1.63 |

**What the ranking shows.**
* Anthropic's Claude 4 generation and GPT-5 lead, broadly in line with the HAL paper, where Opus 4.1 and GPT-5 sit on most Pareto frontiers.
* Recent models gain mostly in coding. GPT-5 and Opus 4.1 lead coding by about 0.7–0.8 logits but are near average on web tasks.
* Open-weight models trail by about 1–2 logits. That is an odds ratio of about 0.15–0.35 for solving the same task with the same scaffold.

### Scaffold ability
Ability is the generalist effect plus the scaffold BLUP, in logits:

| Scaffold | Ability |
|---|---|
| SWE-Agent | +1.00 |
| SciCode Zero Shot | +0.55 |
| SAB Self-Debug | +0.48 |
| USACO Episodic + Semantic | +0.42 |
| SciCode Tool Calling | +0.40 |
| SeeAct | +0.09 |
| Browser-Use | +0.06 |
| CORE-Agent | −0.40 |
| HAL Generalist | −1.07 |
| HF Open Deep Research | −1.11 |

On a benchmark where both exist, choosing a task-specific scaffold over the HAL Generalist is worth roughly as much as moving from a mid-table to a top model.

## Caveats
* **Small samples.** There are only 15 models and 10 scaffolds, so model-level coefficients have wide CIs and the domain slopes are descriptive.
* **Selection and holdout share data.** The formula was selected on the full paper data before the holdout, as the prompt required.
* **Benchmark coverage.** AssistantBench is excluded because its per-task partial-credit scores can't be matched to task ids. LLM-judge corrections exist for TAU-bench only.
