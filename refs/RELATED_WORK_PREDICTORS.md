# Predictors in related work, and recommended predictors for the HAL GLMER

Compiled 2026-10-12 from the arXiv papers and their GitHub repos (read directly), plus `responses.md`.
Local copies of the external metadata are in `data/external/`; its README lists source URLs and checksums.

## 1. Messier (Krsteski et al., 2026; arXiv 2607.25891; EMNLP 2026)
- Code: https://github.com/Andromede-AI/messier. Data: https://huggingface.co/datasets/Andromede-AI/messier
  (records.jsonl 594 MB, tasks.jsonl 134 MB, classifications.jsonl 14 MB, trajectories 8.5 GB).
- **Model**: plain 1PL/Rasch, `P(y_mt=1) = sigmoid(theta_m - beta_t)`, fit with Pyro SVI. It has **no covariates and no
  hierarchy**. A 2PL variant agrees with it (rho = 0.99). Here an "agent" is a model+scaffold(+reasoning effort) string.
  For capability scores they keep **the best scaffold per model x benchmark** and do not model scaffold effects.
- **Recorded metadata (schema in `src/messier/models.py` and `docs/data.md`)**:
  - Agent level: `agent_model` and `agent_scaffold` (normalized to Epoch naming with hand-written alias tables in
    `builders/agents.py`), `model_reasoning_effort` (enabled/low/medium/high/xhigh/max/null; appended to the agent id),
    and `model_date`. Dates come from Epoch `notable_ai_models.csv` plus manual `EXTRA_MODEL_DATES`/`DATE_OVERRIDES`.
  - Task level: benchmark, `benchmark_group`, action-space type, environment-state type/access, verifier type/mode,
    scoring rule, `task_date`, `human` effort (minutes or steps), source `difficulty_label`, and SOC occupation / NAICS
    industry codes. The codes are labeled by a 3-LLM voting ensemble (Haiku, Sonnet, GPT-5-mini) with Opus adjudication.
  - Not recorded: model family, provider-as-covariate, parameter count, and compute.
- **Difficulty prediction**: RidgeCV of beta on bge-base text embeddings, using either the instruction alone or all text
  fields (instruction, environment, action space, gold answer). Spearman on raw beta is 0.48 (instruction) and 0.51
  (all), against a benchmark-mean baseline of 0.47. On within-benchmark z-scored beta it is only 0.26-0.30.
  Lesson: most of the explained difficulty is between benchmarks. The authors note that embeddings encode semantics
  rather than complexity.
- Overlap with HAL: Online-Mind2Web (keeps `level` and reference length as human steps), ScienceAgentBench
  (`difficulty`), SWE-bench Verified (human-minute bands from BRIDGE), and tau2-bench. They validate against Epoch ECI
  (Spearman 0.84). HAL appears only as related work, not as a data source.

## 2. A Rosetta Stone for AI Benchmarks / Epoch Capabilities Index (Ho et al., 2025; arXiv 2512.00193)
- Code: https://github.com/epoch-research/benchmark-stitching (`data/all_ai_models.csv`, `benchmarks_runs.csv`, ...).
  Live index: https://epoch.ai/benchmarks/eci
- **Model**: `score_mb = sigmoid(alpha_b (C_m - D_b))` on aggregate benchmark scores, fit by L2-regularized least squares,
  with WinoGrande as the anchor. The fit uses **no covariates** (179 models, 38 benchmarks, 1,324 scores).
- **Downstream covariates**: training compute and release date, from the Epoch AI Models DB, are used to explain
  capability (`C_m = k log FLOP + b`, an algorithmic-progress analysis). Distilled models are excluded from that analysis.
- **Inclusion and exclusion**:
  - Models with 3 or fewer benchmarks are dropped (too little overlap to identify them).
  - Benchmarks are chosen to be economically relevant, unsaturated and widely used.
  - Where several settings exist, the **max score per model** is kept.
  - **Scaffold-specific variants are excluded** (for example, multiple SWE-bench Verified scaffolds).
  - Reasoning budget is folded into the model variant name (for example "o3-high" or "Opus 4 (16K thinking)").
  - The authors acknowledge that scores depend on prompts, scaffolds and inference compute.
- Takeaway for us: ECI treats scaffold and effort as nuisance and averages them away, whereas HAL can model them
  explicitly. ECI can serve as an **external model-ability covariate**. Caveat: ECI includes SWE-bench Verified, a mild
  leakage risk for HAL's SWE-bench Verified Mini.

## 3. Collaborative Performance Prediction (Zhang, Lyu, Liu, Ma; EMNLP 2024; arXiv 2407.01300)
- Code and data: https://github.com/Don-Joey/CPP_LLM (`data/model_feature.csv`, `data/benchmark_feature.csv`).
- **Model**: matrix factorization or neural collaborative filtering over model x task scores, with optional
  factor embeddings. Data: 72 models x 29 tasks (about 56% dense), plus HELM.
- **Model factors (12, plus Finetuning in the CSV)**: family, pretraining tokens, parameters, GPU-hours, FLOPs,
  context window, batch size, layers, heads, key/value size, bottleneck activation size, and CO2.
  **Task factors (4)**: ability (reasoning, commonsense, ...), task family, output format, and few-shot setting.
- **Labeling**: collected by hand from model cards, technical reports and papers. Conflicting scores are resolved in
  favour of the Open LLM Leaderboard. **Missing factors are filled with 0**, which is a weakness: proprietary models
  withhold most of them.
- **Importance** (Shapley-style masking, measured as change in validation loss): beyond data size and parameters,
  **model family, context window and batch size** matter. Among task factors, **ability (domain)** matters most.
- Takeaway: family plus task domain/ability are the robust factors. Architecture details are unavailable for closed
  models, which are most of HAL's models.

## 4. Agent Psychometrics (Ge, Kryvosheieva, Fried, Girit, Hariharan; arXiv 2604.00594)
- Code and data: https://github.com/dariakryvosheieva/agent-psychometrics (MIT).
  Benchmarks: SWE-bench Verified (500 tasks, 134 agents), SWE-bench Pro (730), GSO (102) and Terminal-Bench 2.0 (89).
- **Model**: 1PL IRT with additive agent ability, `P(y=1) = sigmoid(theta_LLM + theta_scaffold - beta_task)`.
  - The additive form gives the same AUC as one theta per agent (mean |dAUC| = 0.002). LLM thetas from heterogeneous
    scaffolds correlate r = 0.974 with fixed-scaffold (Terminus 2) abilities.
  - beta is predicted from task features by **ridge regression on frozen IRT difficulties**. A joint-likelihood
    version did worse.
  - The data cover 38 LLMs and 112 LLM-scaffold pairs.
- **Exclusions**:
  - Agents with multiple or undisclosed LLMs are dropped.
  - There are **no agent-side text features**, because agent descriptions are not standardized.
  - **Training compute is not used**, because it is "unavailable for many LLMs, especially proprietary ones".
  - Terminal-Bench responses count as pass if at least 50% of attempts pass, or are modelled as binomial
    (`responses_per_attempt.jsonl`).
- **Task features, LLM-judged**: Claude Opus 4.6 sees the problem statement, tests and gold patch, and scores each
  feature on a discrete rubric.
  - `solution_hint` (0-3), `domain_knowledge_required`, `logical_reasoning_required`, `atypicality`
  - `verification_difficulty`, `error_specificity`, `debugging_complexity`, `codebase_scope`
  - `similar_issue_likelihood` (0/1), `side_effect_risk`, `test_edge_case_coverage`, `solution_complexity`
  - All are 1-5 unless noted.
- **Task features, auditor agent**: an agent explores the repository in the task sandbox. Three of its 8 features are
  used by default: `codebase_scale`, `fix_localization` (higher means more localized) and
  `implementation_language_complexity`.
- **No purely programmatic features.** The paper also reports embedding features: DeepSeek-R1-Distill-Qwen-32B
  last-token embeddings of the task, the solution and an instruction (`.npz` files in `embeddings/`).
- **Feature selection**: the default 15 were chosen by greedy forward selection for cross-dataset AUC. The 28-feature
  pool also includes `problem_clarity`, `standard_pattern_available`, `reproduction_clarity`,
  `expected_behavior_clarity`, `information_completeness`, `test_comprehensiveness`, `test_assertion_complexity`,
  `integration_complexity`, `entry_point_clarity`, `change_blast_radius`, `environment_setup_complexity`, ...
- **Held-out-task AUC on Verified**: baseline 0.718, embeddings 0.824, judge 0.841, combined 0.842, oracle 0.945.
  - Source ablation (judge features): problem statement only 0.787, all sources 0.848. The solution and test artifacts
    add the most.
  - Auditor features add less than 2 AUC points once the judge has full context.
  - The paper gives **no per-feature ranking**.
- **Our quick check** on their files: 500 Verified tasks, Spearman correlation of each feature with their beta.

  | Feature | Spearman rho |
  |---|---|
  | atypicality | 0.58 |
  | logical_reasoning_required | 0.58 |
  | debugging_complexity | 0.57 |
  | solution_complexity | 0.56 |
  | verification_difficulty | 0.50 |
  | side_effect_risk | 0.49 |
  | domain_knowledge_required | 0.49 |
  | codebase_scope | 0.45 |
  | fix_localization | -0.38 |
  | codebase_scale | 0.01 |

  A joint ridge on standardized features (lambda = 50) gives in-sample R^2 = 0.44. Its largest coefficients are
  codebase_scope, test_edge_case_coverage, atypicality and solution_complexity. The features are highly collinear.
- **Inheritable feature file**:
  https://raw.githubusercontent.com/dariakryvosheieva/agent-psychometrics/main/llm_judge_features/defaults/swebench_verified/llm_judge_features.csv
  - It has 500 rows keyed by `instance_id`, and **all 50 SWE-bench Verified Mini tasks are present**. We checked
    against HF `MariusHobbhahn/swe-bench-verified-mini`.
  - Copied to `data/external/agent_psychometrics/`, together with the 28-feature pool and their 1PL `items.csv` (b).
  - **No files exist for HAL's other 8 benchmarks.** Extending to them would need re-running their
    `llm_judge_feature_extraction` pipeline, which is LLM-judged rather than manual. That is allowed under the rule of no
    manual annotation, but it costs API calls and must be documented.

## 5. Other notes from responses.md
- Sloth (arXiv 2412.06540): latent skills driven by log params and log tokens, with **family-specific efficiencies**.
  This supports a `(1 | family)` term and log size.
- Observational scaling laws (arXiv 2405.10938): a low-dimensional capability factor predicts agent benchmarks. This
  supports an external ability proxy (ECI) as a model-level fixed effect.
- Ye et al. 2023 (BIG-bench predictability): family, parameter count, task and shots.
- Common caution across these papers: keep scaffold, reasoning effort and scoring rule as part of the measurement
  identity. Do not pool partial-credit scores into a binomial likelihood.

## 6. Programmatic metadata sources (verified 2026-10-12)
| Need | Source (URL) | Status / coverage for HAL models |
|---|---|---|
| Release date, org, accessibility, open weights, params, compute | https://epoch.ai/data/all_ai_models.csv (also `notable_`, `frontier_`; `ai_models.zip`) | HTTP 200, 6.8 MB, 3,626 models. All HAL models present. Compute is known only for GPT-5 (6.6e25), Claude 3.7 Sonnet (3.35e25) and DeepSeek V3/R1 (3.3-4.0e24); **NaN for most closed models**. Params NaN for closed models; 671B for DeepSeek V3/R1. Caveat: o3 is dated 2024-12-20 (announcement); ECI uses 2025-04-16 (release). |
| API-id to model mapping + date + compute | https://epoch.ai/data/benchmark_data.zip -> `model_metadata.csv` | 200, 2.4 MB zip. Keys like `claude-3-7-sonnet-20250219_16K`, so it can join on HAL model ids. |
| External ability (ECI) | same zip -> `epoch_capabilities_index/eci_scores.csv`; `https://epoch.ai/data/eci_benchmarks.csv` | 274 models with CIs. GPT-4.1 136.8, o4-mini 145.6, o3 146.9, GPT-5 150.0, Claude 3.7 Sonnet 141.2, Opus 4 142.7, Opus 4.1 144.1, Sonnet 4.5 146.8, Gemini 2.0 Flash 134.7, Gemini 2.5 Pro 142.5-145.3 (by version), DeepSeek V3 132.3, R1 139.0. |
| Reasoning-capable flag, prices, context | https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json (`supports_reasoning`); https://openrouter.ai/api/v1/models (`supported_parameters` contains "reasoning", `created`) | Both 200. LiteLLM gives True for gpt-5, o3, o4-mini, gemini-2.5-pro, sonnet-4.5 and deepseek-reasoner; None for gpt-4.1 and deepseek-chat. Some Claude ids are missing, so a small cross-checked table is needed. |
| Open-model parameter counts | `https://huggingface.co/api/models/<repo>?expand[]=safetensors` | deepseek-ai/DeepSeek-V3 has total 684.5B (671B plus MTP module). Only DeepSeek V3/R1 are open among HAL models. |
| Native task difficulty | HF datasets-server: `princeton-nlp/SWE-bench_Verified.difficulty` (time buckets); `AssistantBench/AssistantBench.difficulty` (Easy/Medium/Hard, validation split); `osunlp/ScienceAgentBench.domain`, `subtask_categories` | Public. `osunlp/Online-Mind2Web.level` and `gaia-benchmark/GAIA.Level` are **gated** (need an HF token). USACO has bronze/silver/gold/platinum in HAL's USACO json. SciCode has the number of sub_steps. |

## 7. Recommended predictors for the HAL binomial GLMER
Principle: the related work agrees on random intercepts for model, scaffold/agent and task (IRT). Fixed covariates
must be (i) available for all of HAL's mostly closed models, which rules out params, compute and architecture, and
(ii) obtained programmatically.

**(a) Model level**
- `(1 | model)`: IRT ability theta_LLM, as in Agent Psychometrics and Messier.
- `family` / `provider` as a random intercept `(1 | provider/model)` or a fixed effect. Source: the HAL model string plus
  Epoch `Organization`. This follows CPP (family matters) and Sloth (family-specific efficiencies).
- `reasoning_model` (trained reasoner vs hybrid vs non-reasoning) and HAL `reasoning_effort` (unknown is folded into
  default, as the task says). Sources: LiteLLM/OpenRouter flags, a ~15-row table cross-checked against vendors, and the
  HAL config. Messier and ECI fold effort into the agent id.
- `release_date` (years, centered). Source: Epoch `eci_scores.csv` or `model_metadata.csv` dates, used by Rosetta and
  Messier.
- Optional `ECI` (z-scored) as an external ability proxy. Note the SWE-bench Verified leakage.
- **Exclude** compute, parameters and architecture: they are NaN for about 85% of HAL models (AP's and CPP's stated
  reason). At most, log-params could be a sensitivity check on the open-model subset.

**(b) Scaffold level**
- `(1 | scaffold)`: additive theta_scaffold. AP validated additivity (r = 0.974), and Messier and ECI simply collapse the
  scaffold.
- `scaffold_type` = generalist (HAL generalist) vs benchmark-specialized (SWE-agent, browser-use, SeeAct, CORE-Agent,
  tau-bench few-shot, USACO episodic+semantic, HF ODR). Source: the HAL agent name, with a one-time mapping.
- Optional `(1 | model:scaffold)` if the data identify it; under "keep it maximal", prune it if the fit is singular.

**(c) Benchmark and task level**
- `(1 | benchmark)` + `(1 | benchmark:task)`: task difficulty beta, which is the core of every IRT paper.
- `domain` / `action space` (coding, web, science/repro, customer service). Source: a benchmark-level mapping, which is
  CPP's "ability" (its most important task factor) and Messier's `benchmark_group`/action space.
- Optional `(model | benchmark)` or `(reasoning | benchmark)` slopes, mirroring ECI's per-benchmark slope alpha_b.
- Native per-task difficulty where it exists: SWE-bench Verified `difficulty`, AssistantBench `difficulty`, GAIA `Level`,
  Online-Mind2Web `level`, USACO level, SciCode number of sub-steps, ScienceAgentBench domain. Because coverage is
  benchmark-specific, enter it as benchmark-standardized ordinal scores or as nested factors.
- Extension 1: the AP 15 features (or the 4-5 strongest: atypicality, logical_reasoning_required, debugging_complexity,
  solution_complexity, codebase_scope) for SWE-bench Verified Mini only, inherited from the file above. Covering the
  other benchmarks requires re-running AP's judge pipeline.
