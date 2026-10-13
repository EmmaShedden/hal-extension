# Related-work statistical methods applied to Part 1: design

Written 2026-10-13, **before any of these methods was fit on the real HAL data**.
The only real-data steps run before writing this were data management (row and cell counts in `common.R`, and the
external-score matrix in `07_observational_scaling/build_external_scores.R`). The IRT fitter was checked on simulated data only.
Changes made after fitting are logged at the bottom under "Post-fit changes", as in the main `DESIGN.md`.

## Scope
* **Task.** Part 1 of the core task: fit the whole paper dataset and report quality of fit, using the statistical
  method of each related work in `responses.md` instead of the binomial GLMER. Part 2 (holdout) is not run here.
* **Data.** Exactly the Part 1 data: 174 paper runs, 172 cells, 21,333 task outcomes, 8 benchmarks (AssistantBench excluded,
  as in the main analysis), loaded by `R/common.R: load_analysis_data`. Effort coding is the main analysis' (unknown and
  OpenAI "medium" → default).
* **Reference.** The selected GLMER `c028` (`results/part1/in_sample_metrics.csv`), conditional and fixed-effects-only.

## Units used by the methods
| Name | Definition | Count | Used as |
|---|---|---|---|
| agent | model × scaffold × effort | 128 | Messier's agent string (model + scaffold + reasoning effort) |
| llm | model × effort | 21 | AP's θ_LLM; the row of the aggregate-score matrix (ECI folds the reasoning budget into the model variant) |
| scaffold | HAL scaffold | 10 | AP's θ_scaffold |
| column | scaffold × benchmark | 15 | the column of the aggregate-score matrix (each scaffold-benchmark pair is a distinct measurement) |
| cell | llm × column | 172 (of 315 possible, 55 % observed) | one aggregate score; replicate runs are pooled |
| task | benchmark × task id | 1,084 | IRT item |

Task-level methods (01, 02) use the 21,333 binary outcomes. Aggregate methods (03 to 07) use cell accuracies: they have no
task information, so every task row of a cell gets the cell's predicted accuracy.

## Metrics (same as `results/part1/in_sample_metrics.csv`)
* Task-level Brier, log-loss, 0/1 error at 0.5, AUC. For aggregate methods these only reflect the run-level prediction,
  because the predicted p is constant within a run. They are reported for completeness and are not comparable to the task-level methods'.
* Run-accuracy MAE (pp), RMSE (pp) and correlation over the 174 runs. This is the metric every method shares.
* Number of fitted parameters. In-sample fit rewards flexibility: a method with a free parameter per run or agent fits
  run accuracy almost exactly, as the GLMER's conditional fit does through `(1|run)`.
* Per-benchmark run MAE, as in REPORT.md §3.

## Hyperparameters
* The structure of each method (its equation, units and priors) is fixed by the paper and its code. It is not tuned.
* Where the paper selected a hyperparameter from data (a rank, a penalty, a number of components), its **published choice** is
  used as is. Re-selecting on HAL would add a data-driven choice per method; the papers' values make every method fully
  specified before fitting. The only new rules are those forced by HAL's structure (method 06 covariates, method 07 small columns),
  and they are stated below.
* No method is tuned after seeing its HAL results. Any change is logged under "Post-fit changes".

## Methods
Source details (equations, priors, optimisers, defaults) were read from each paper's released code; file and line
references are in `README.md`. Where a paper's text and its code disagree, the **code** is followed and the
difference is noted. Every fit is deterministic given the seeds stated.

### 01 Messier: Rasch / 1PL and 2PL (`01_rasch_messier/`)
* **Model.** `logit P(y_at = 1) = θ_agent − b_task`. Messier's code (`src/messier/irt.py`) uses hierarchical priors
  θ ~ N(0, σ_θ), b ~ N(0, σ_b), σ ~ HalfNormal(1), with point-estimated σ's and a mean-field variational posterior (SVI).
  That is empirical Bayes on the variance components. Here it is fit as the equivalent Laplace GLMM,
  `glmer(success ~ 1 + (1|agent) + (1|task))` (the standard Rasch-as-GLMM; De Boeck et al. 2011), and the conditional modes are
  the abilities and difficulties. Differences from the code: lme4 estimates a free intercept where Messier centres θ and
  gives b a zero-mean prior (only a location shift), and the σ's get no HalfNormal(1) hyperprior (weak at these sample sizes).
* **2PL** (their robustness variant): `logit P = a_t (θ − b_t)`, log a_t ~ N(0, σ_loga). lme4 cannot fit it. It is
  fit by MAP (`irt_map.R`) with σ_θ and σ_b fixed at the 1PL estimates and σ_loga = 1 (the HalfNormal(1) scale).
  The θ and b priors are centred on the 1PL intercept split.
* **Primary: all runs**, agent = model × scaffold × effort (Messier's `format_agent_id`); all 21,333 rows.
* **Faithful variant: the paper fit** (`analysis/epoch_eci/run.py: keep_best_scaffold`). For each model × benchmark, keep
  the scaffold with the highest mean score (ties: more tasks, then alphabetical). Agent = model, so all efforts are pooled.
  Tasks solved by every or by no retained run are then dropped. Metrics are reported on the retained rows only.

### 02 Agent Psychometrics: additive LLM + scaffold 1PL (`02_additive_irt_agent_psychometrics/`)
* **Model.** `logit P = θ_LLM + θ_scaffold − b_task`, with hierarchical normal priors and point-estimated SDs, and both θ's centred
  (`swebench_irt/train_model_scaffold_shared.py`). Fit as `glmer(success ~ 1 + (1|llm) + (1|scaffold) + (1|task))`.
* **LLM = model.** AP collapses effort suffixes into the base model (`split_agents_model_scaffold.py`), so efforts are pooled.
* **Primary: per benchmark, as AP fits.** One fit per benchmark (8 fits). TAU-bench has a single scaffold, so its fit
  has no scaffold term (the scaffold is absorbed by the intercept).
* **Pooled variant:** one fit across all benchmarks (the same additive model, as in Messier's cross-benchmark scale).
* **AP's comparison (per-agent 1PL):** `(1|agent) + (1|task)` with agent = model × scaffold × effort, per benchmark.
  This corresponds to their py-irt hierarchical 1PL. Reported: ΔAUC (additive − per-agent), which AP found to be about 0.002.

### 03 Rosetta Stone / ECI: aggregate-score IRT (`03_benchmark_irt_eci/`)
* **Model.** `score_rc = σ(α_c (C_r − D_c))`, fit to cell accuracies by least squares. The code's penalty
  (`fit.py: residuals`) is λ·(ΣC² + ΣD² + Σα_free²) / (number of parameters), with **λ = 0.1** (their default).
  The anchor column's α is fixed at 1 during the fit, and afterwards C and D are shifted so the anchor's D = 0. Bounds are
  C, D ∈ [−10, 10] and α ∈ [0.1, 10]. Initial values are C, D ~ 0.1·N(0, 1) (seed 42) and α = 1. No guessing-floor rescaling, as in the code.
* **Rows** = model × effort (ECI keeps reasoning variants as separate model rows).
* **Anchor:** the column observed for the most rows; ties are broken alphabetically. (ECI's anchor is Winogrande, which HAL does not have.)
* **Primary:** columns = scaffold × benchmark (15), all 172 cells, evaluated on all 174 runs.
* **Faithful variant:** ECI's data rules (`data_loader.py`): the max score per row × benchmark (scaffold variants excluded),
  8 benchmark columns, and rows with 3 or fewer benchmarks dropped. Fit and metrics are on those retained maxima only.

### 04 BenchPress: logit low-rank matrix completion (`04_lowrank_benchpress/`)
* **Model.** The code's default predictor (`methods/predictors.py`), "Logit Bias-ALS":
  1. Clip cell accuracy to [0.5 %, 99.5 %] and take the logit.
  2. z-score each column (population SD; an SD below 1e-8, or a single-cell column, is set to 1).
  3. Fit `Z = μ + a_r + c_c + U_r V_cᵀ` by alternating closed-form ridge solves. The loss is squared error plus λ(‖a‖² + ‖c‖² + ‖U‖² + ‖V‖²), and μ is the unpenalised residual mean.
  4. Run 40 iterations from U, V ~ N(0, 0.01²) and a = c = 0, for each of 10 seeds (42–51), and average the 10 reconstructions on the z scale.
  5. Invert the z-score and the logit.
* **Hyperparameters:** rank 2 and λ = 0.1, the paper's selected values. They are used as published, not re-selected.
* **Rows/columns** as in 03 primary.
* **In-sample fit** is measured on the **reconstruction**. BenchPress returns observed cells unchanged, which would make the in-sample error trivially 0.
* The code learns the biases a and c with a ridge penalty, whereas the paper's Eq. 2 fixes them at observed means; the code is followed.

### 05 Collaborative Performance Prediction (`05_collab_filtering_cpp/`)
* **Target:** CPP min-max normalises each model row after setting missing cells to 0 (`normalize_scores`). With accuracies
  ≥ 0 this divides each row by its maximum. Predictions are multiplied back by the row maximum.
* **CPP-MF** (`src/mf.py`): r̂ = ⟨p_r, q_c⟩, d = 10, no biases, init N(0, 0.01²). SGD with lr 0.01, batch 16, MSE,
  no weight decay, **250,000 epochs**, all as in the paper and code. Seed 1.
* **CPP with factors.** The released factor model is a neural CF (GMF plus 64-32-16 MLP towers) in PyTorch, which this
  R environment does not have. With 172 training cells those towers would be heavily over-parameterised. The
  implementation here keeps CPP's *factor-embedding* idea inside the MF model: each side's vector is its id embedding plus
  embeddings of its categorical factors, plus a linear projection of its numeric factors (in place of the numeric-factor MLP).
  * Model factors: provider (family), reasoning model (post-training), effort, and release date (numeric; z-scored).
  * Column factors: benchmark, domain (CPP's "ability", its most important task factor), and scaffold type (generalist or not).
  * Same optimiser and epochs as CPP-MF.
* The released `main.py` keeps only a random 10 % of observed cells, and its training loop shadows the network variable.
  These are treated as bugs and not reproduced.
* SGD runs in C++ through Rcpp for speed. The arithmetic is the same.

### 06 Sloth: skills from model covariates (`06_skill_scaling_sloth/`), adapted
* **Model** (`sloth/sloth.py`): `μ_rc = γ_c + (1 − γ_c)·σ(Λ_c·θ_r + b_c)`, with skills
  `θ_r = W_D·onehot(family_r) + W_X·x_r`. Family enters only as a per-skill intercept (the "efficiency"), and the slopes are shared.
  There are **no free per-row parameters**: a model's skills come entirely from its covariates.
* **Adaptation (necessary).** Sloth's x is (log params, log tokens, their product), but these are unknown for 13 of 15 HAL models.
  * Release date (z-scored) stands in as the scale proxy.
  * Effort enters x as dummies (high, low, none vs default), since Sloth treats inference compute as a covariate.
  * Family = provider × reasoning model, the analogue of Sloth's base/instruct split into separate families.
* γ_c = 0 (no multiple-choice guessing floor for these benchmarks), with the basic sigmoid link and **d = 3 skills** (the paper's choice).
  d = 1 is reported as a variant.
* **Fitting as in the code.** Loss is SmoothL1 (β = 0.01) on the accuracy scale, full-batch Adam with no weight decay.
  Three learning rates (0.1, 0.01, 0.001) are each tried, keeping the best training MAE. ReduceLROnPlateau uses factor 0.95 and
  patience 20, with up to 100,000 epochs and an early stop after 500 epochs without MAE improvement. W_X and Λ are initialised
  from |N(0, 1)|, the other weights from N(0, 1) and b from 0, seed 1. Columns are scaffold × benchmark and rows are model × effort, as in 03.

### 07 Observational scaling laws (`07_observational_scaling/`)
* **Capabilities.** The external, non-agentic benchmarks from Epoch (`build_external_scores.R`) are the 7 that cover ≥ 12 of the 15
  models: GPQA diamond, SimpleBench, OTIS Mock AIME, Fiction.LiveBench, MATH level 5, WeirdML and Aider polyglot.
  * Agentic and HAL-overlapping benchmarks (SWE-bench Verified, METR, ...) are excluded.
  * The score is the max over model versions.
  * OSL's own 7 metrics (MMLU, GSM8K, ...) are not reported for these models (each covers ≤ 1 of 15).
  * 15 of 105 cells are missing. They are imputed as in `utils/data.py: pca_impute`: standardise, mean-fill, then iterate a
    1-component PCA reconstruction of the missing cells (≤ 1000 iterations, tol 1e-4), unscale, and clip to [0, 1].
  * PCA is then fit on the unstandardised imputed scores, and **PC1–3** are used (the headline setting).
* **Regression** (`fit_multivariate_regression_model`, "sigmoid-parametric"): `y = (1 − f)·σ(w₀ + wᵀPC) + f` with floor
  f ∈ [0, 0.2] and height 1, by unweighted least squares, **one fit per target column** (scaffold × benchmark). Rows are model × effort cells;
  all efforts of a model share its PCs, so effort is not modelled (OSL fits a separate regression per inference intervention instead).
* **Small columns (rule set here, not in OSL).** OSL's targets have many models; some HAL columns have few cells.
  * 3 PCs need ≥ 10 cells (5 parameters).
  * With 5–9 cells, PC1 only is used (3 parameters).
  * With fewer, the column mean is used (only the single-cell `HAL Generalist Agent|USACO`).
* **Variant: ECI as the capability** (1-D; z-scored Epoch Capabilities Index), with the same regression and PC1 rules.
  ECI includes SWE-bench Verified, a mild leakage risk for HAL's SWE-bench column.
* Optimiser: L-BFGS-B with bounds on f, starting from w₀ = 0, w = 0.03 and f = 0 (OSL's p0).

## Not applied
| Work (responses.md) | Why it is not fit here |
|---|---|
| Efficient Benchmarking of AI Agents (2603.23749) | Selects a mid-difficulty task subset to preserve rankings; this is evaluation design, not a model to fit. Its IRT is the 1PL of method 01. |
| tinyBenchmarks, metabench, Rodriguez et al. 2021, Lost in Benchmarks (PSN-IRT), Laplace-PSN-IRT | Within-benchmark IRT (1PL/2PL/3PL or neural IRT) for item selection or uncertainty. The 1PL/2PL cores are method 01; the neural variants need a deep-learning stack and items in common across many models. |
| How Predictable Are LLM Capabilities? (Ye et al. 2023) | Regression (MLP/trees) on family, parameter count and shots; parameter counts are unknown for 13 of 15 models. |
| Can a Crow Hatch a Falcon? (lineage-regularised MF) | Needs a lineage graph (parent/merge relations); the HAL models are closed and have no published lineage beyond family, which method 05 already uses. |
| STAR, PRECOG | Use LLM agents or LLM reading of task descriptions to predict scores, not a statistical model of the existing results. |
| BRIDGE, PTA-IRT | Need human completion times or agent trajectories as inputs. |
| Log Analysis, AgentRewardBench, SABER, Reliability, CORE-Bench saturation, Beyond Metrics, Contamination (DIF), AI Agents That Matter, BrowserGym | About measurement validity or new evaluations, not fitting a predictive model. Log Analysis' judge labels are already used in E3. |

## Post-fit changes
None yet.
