
## Literature search (GPT 6 Astra)

The paper "Holistic Agent Leaderboard: The Missing Infrastructure for AI Agent Evaluation" argues that existing agent evals are insufficient because:
1. models don't publish scores for a consistent set of benchmarks, meaning many of them can't be compared head to head,
2. many benchmarks don't check transcripts to see whether agents cheated on tasks,
3. many models/benchmarks only report accuracy, but more information is relevant, like $/compute/token costs,
4. settings like reasoning mode are not standardized between model families,
5. benchmarks' test suites are often incomplete and miss side effects or missteps (e.g., on a flight booking task, an agent initially charged the wrong credit card but still "passed" the task), and
6. many benchmarks or benchmark-model interfaces are buggy (e.g., benchmarks' not equipped to handle abstentions, or benchmark system prompts conflicting with model system prompts).

I want to understand the claims of this project in the context of the claims put forward by frontier models and benchmarks individually. Formally, this would approximately entail:
1. collate leaderboard data (accuracy) for the benchmarks and models that HAL covers, plus any related benchmarks/models that have come out since then,
2. compare these to the HAL-reported numbers where applicable,
3. perform a psychometrics-style (likely binomial GLMER) analysis of this dataset with factors controlling for/modeling model family, model size, model post-training method, benchmark domain, benchmark difficulty, etc.,
4. compare the fitted model's predictions to the HAL paper's reported numbers, and
5. use the fitted model to fill in the gaps in the HAL paper's reported accuracies (which did not cover all combinations within the models and benchmarks they considered).

Your task is to identify all existing literature that performs such an inquiry (or even just overlaps it). I suspect that the paper itself may answer some of this, and the follow-up work "Log analysis is necessary for credible evaluation of AI agents" may be also relevant (although it seems to focus more on LLM-as-a-judge evaluation).

---

### Bottom line

**Several papers overlap substantially with your proposed study, including some much closer than HAL itself.** The strongest matches are:

1. **Messier** — consolidates heterogeneous agent-evaluation results and fits cross-benchmark psychometric capability scales.
2. **Agent Psychometrics** — predicts task-level agent performance using IRT, explicitly separating model and scaffold contributions.
3. **A Rosetta Stone for AI Benchmarks / Epoch Capabilities Index** — statistically links incomplete benchmark score matrices.
4. **You Don’t Need to Run Every Eval / BenchPress** — predicts missing aggregate model–benchmark scores.
5. **Collaborative Performance Prediction** and **Sloth** — incorporate model/task characteristics and model-family structure into cross-benchmark prediction. ([arxiv.org](https://arxiv.org/abs/2607.25891?utm_source=openai))

**I did not identify a paper completing your exact five-step inquiry:** pooling external claims, reconciling them with HAL under matched conditions, fitting the proposed covariate-rich statistical model, evaluating its predictions against held-out HAL results, and imputing HAL’s remaining cells. That is a search finding, not proof that no such work exists.

Below is a prioritized literature map, searched through **October 12, 2026**. I distinguish substantive methodological overlap from papers that merely introduce another benchmark; an exhaustive list of the latter would obscure the relevant literature.

---

### 1. Closest existing studies

###### 1. Messier: A High-Resolution Corpus for Cross-Benchmark Agent Evaluation  
**Krsteski et al., July 2026**

**Probably the closest overall match to your proposed project.**

- Consolidates **957,253 records across 30 benchmarks, 714 agents, and 11,891 tasks**, combining public results with additional evaluations.
- Preserves model, scaffold, environment, task, verifier, and aggregation-rule information.
- Fits a **Rasch/1PL IRT model** to the consolidated response matrix, producing cross-benchmark capability scales.
- Examines domain-specific progress, counterfactual rescoring, and prediction of task difficulty from task metadata.
- Explicitly identifies HAL as its closest infrastructure precedent, while distinguishing consolidation of existing evidence from HAL’s standardized new evaluations. ([arxiv.org](https://arxiv.org/abs/2607.25891?utm_source=openai))

**Overlap:** especially your steps **1 and 3**, and infrastructure useful for **5**.

**Important differences:** its headline external validation compares capability rankings with **Epoch ECI**, not predicted scores with HAL. Its displayed capability analysis selects the best observed scaffold within each benchmark, rather than estimating every model–scaffold interaction. It is therefore not the matched-protocol HAL reconciliation you describe. ([andromede-ai.github.io](https://andromede-ai.github.io/messier/))

###### 2. Agent Psychometrics: Task-Level Performance Prediction in Agentic Coding Benchmarks  
**Ge, Kryvosheieva, Fried, Girit, and Hariharan, April 2026**

**The closest statistical-methods paper for agents.**

It augments IRT with:

- Task features extracted from issue descriptions, repositories, solutions, and tests.
- An **additive decomposition of agent ability into LLM and scaffold components**.
- Predictive evaluations involving held-out responses, tasks, and entire benchmarks.

Its experiments cover four agentic coding benchmarks and include a comparison between abilities inferred from heterogeneous scaffolds and a fixed-scaffold evaluation on Terminal-Bench 2.0. ([arxiv.org](https://arxiv.org/html/2604.00594v1))

**Overlap:** strongly **3 and 5**; particularly relevant to choosing the observational unit and separating model from scaffold.

**Difference:** coding-focused, not a broad reconciliation of vendor claims against HAL, and not the full family/size/post-training/domain model you propose. ([arxiv.org](https://arxiv.org/html/2604.00594v1))

###### 3. A Rosetta Stone for AI Benchmarks  
**Ho, Denain, Atanasov, Albanie, and Shah, 2025**  
**Living implementation: Epoch Capabilities Index, ECI**

**The closest benchmark-level psychometric precedent.**

The paper stitches together incomplete benchmark results using model capability, benchmark difficulty, and benchmark slope parameters. Its basic relationship is approximately

\[
\text{normalized score}_{mb}
\approx \sigma\!\left[a_b(\theta_m-d_b)\right].
\]

This permits comparisons when models were not evaluated on identical benchmarks. Applications include capability trends, algorithmic efficiency, and detecting accelerations in progress. ECI is the ongoing implementation, with general and domain-specific indices. ([arxiv.org](https://arxiv.org/abs/2512.00193?utm_source=openai))

**Overlap:** **1, 3, and the predictive foundation for 5**.

**Difference:** an IRT-inspired model of **aggregate benchmark scores**, not your proposed fully crossed binomial GLMM. It does not establish that disparate scaffolds, reasoning settings, or scoring implementations are interchangeable; the authors explicitly acknowledge evaluation comparability and benchmark-optimization limitations. ([arxiv.org](https://arxiv.org/html/2512.00193v1))

###### 4. You Don’t Need to Run Every Eval  
**Zeng and Papailiopoulos, June 2026**  
**System: BenchPress**

**The closest direct missing-score imputation study.**

The paper studies an **84-model × 133-benchmark** public score matrix, including reasoning, coding, and agentic evaluations. BenchPress uses logit-space, low-rank matrix completion; the paper reports roughly **4.6 score points median absolute error** on held-out cells. It also studies uncertainty, preservation of rankings, sparse scorecard recovery, and failure cases. The released repository supplies provenance-backed scores and prediction code. ([arxiv.org](https://arxiv.org/html/2606.24020v1))

**Overlap:** directly **1 and 5**, with predictive statistical modeling corresponding to **3**.

**Difference:** not a covariate-rich explanatory GLMM or a HAL replication audit. The authors explicitly distinguish predicting a benchmark’s score from validating the benchmark itself: prediction can reproduce a defective measurement faithfully. Also distinguish the paper’s frozen matrix from the expanding live dataset. ([arxiv.org](https://arxiv.org/html/2606.24020v1))

###### 5. Collaborative Performance Prediction for Large Language Models  
**Zhang, Lyu, Liu, and Ma, EMNLP 2024**

**An unusually close predecessor to your proposed data-collection and covariate strategy.**

It:

- Collects scores from papers, technical reports, model cards, and leaderboards.
- Constructs a dataset covering **72 models and 29 tasks**, alongside a HELM-based analysis.
- Predicts missing model–task scores using collaborative filtering.
- Incorporates model-design and task-design factors and analyzes their importance. ([arxiv.org](https://arxiv.org/abs/2407.01300?utm_source=openai))

**Overlap:** **1, 3, and 5**.

**Difference:** primarily conventional LLM evaluations, predating HAL; its statistical machinery is collaborative prediction rather than binomial mixed-effects inference. Nevertheless, it belongs near the top of your related-work section. ([arxiv.org](https://arxiv.org/abs/2407.01300?utm_source=openai))

###### 6. Sloth: Scaling Laws for LLM Skills to Predict Multi-Benchmark Performance Across Families  
**Maia Polo et al., 2024 preprint; NeurIPS 2025**

Sloth models low-dimensional latent skills that depend on **model size and training tokens, with family-specific conversion efficiencies**. It exploits correlations across 12 Open LLM Leaderboard benchmarks to predict performance and interpret differences in skill scaling. The authors also examine instruction tuning and increased inference-time computation. ([arxiv.org](https://arxiv.org/abs/2412.06540?utm_source=openai))

**Overlap:** particularly your proposed **family/size/training-related structure in step 3**, plus prediction in **5**.

**Difference:** not agent-focused and not a correction for measurement differences between laboratories. ([arxiv.org](https://arxiv.org/abs/2412.06540?utm_source=openai))

###### 7. Observational Scaling Laws and the Predictability of Language Model Performance  
**Ruan, Maddison, and Hashimoto, NeurIPS 2024**

Fits a low-dimensional capability representation across approximately 100 public models. Crucially for your question, it predicts **AgentBench and AgentBoard performance from simpler, non-agentic benchmark results**, including predictions for proprietary models. It also studies chain-of-thought and self-consistency interventions. ([arxiv.org](https://arxiv.org/abs/2405.10938?utm_source=openai))

**Overlap:** **3 and 5**, including cross-domain prediction of agent performance.

**Distinction:** chain-of-thought and self-consistency here are inference interventions, not a substitute for identifying effects of SFT, preference optimization, or RL post-training.

###### 8. Efficient Benchmarking of AI Agents  
**2026; arXiv:2603.23749**

Studies efficient agent evaluation under **scaffold-driven and temporal distribution shifts**. An IRT-motivated, mid-difficulty task filter reduces evaluation tasks by **44–70%** while maintaining high ranking fidelity. ([arxiv.org](https://arxiv.org/abs/2603.23749))

**Overlap:** efficient acquisition of the missing observations needed for **1 and 5**, and validation under a confound central to HAL.

**Difference:** recovering rankings from subsets is not the same target as accurately imputing absolute success probabilities. This paper explicitly treats that distinction. ([arxiv.org](https://arxiv.org/html/2603.23749v1))

---

### 2. What HAL and its follow-ups actually answer

###### Holistic Agent Leaderboard: The Missing Infrastructure for AI Agent Evaluation  
**Kapoor et al., October 2025; ICLR 2026**

HAL itself provides:

- **Table 1 and Appendix A9:** an inventory of previously evaluated model–benchmark combinations and their sources.
- **Section 4 and Appendix A10:** standardized measured results and scaffold/reasoning comparisons.
- **Appendices A3, A5, and A7:** implementation problems, leakage, and transcript analysis.

However, Table 1 is primarily a **coverage comparison**, not a statistical reconciliation of external and HAL scores. I found no fitted cross-benchmark psychometric model or missing-cell imputation. ([arxiv.org](https://arxiv.org/html/2510.11977v1))

One important refinement to your framing: the missingness is substantially in the **model × scaffold × benchmark × configuration** array, rather than simply model × benchmark. HAL reports 142 combinations in its main analysis, with 186 total runs and additional partial results in the appendix. Start from those comprehensive results, not only the headline plots. ([arxiv.org](https://arxiv.org/html/2510.11977v1))

###### Log Analysis Is Necessary for Credible Evaluation of AI Agents  
**Kirgis et al., May 2026**

This is **more directly relevant than “mostly LLM-as-a-judge” suggests**. Its central contribution is evaluation validity; automated judging is one instrument.

Its τ-Bench Airline case study:

- Evaluates 13 frontier models.
- Identifies errors or ambiguities in **25 of 50 tasks**.
- Shows mean **pass^5** increasing from **20.8% to 40.0% after excluding those tasks**.
- Separately measures persuasion-induced policy violations, differentiating models with similar benchmark performance. ([arxiv.org](https://arxiv.org/pdf/2605.08545))

Two qualifications matter: these are **pass^5**, not ordinary accuracy/pass@1; and the increase is measured on a **different, filtered task set**, not after repairing and rerunning all original tasks. This is highly relevant to score interpretation and auditing, but not cross-benchmark imputation. ([arxiv.org](https://arxiv.org/pdf/2605.08545))

###### Towards a Science of AI Agent Reliability  
**Rabanser et al., February 2026**

A direct HAL-related extension beyond accuracy: twelve metrics covering **consistency, robustness, predictability, and safety**. The current paper evaluates 15 models across two benchmarks and finds that capability improvements have produced comparatively limited reliability improvements. Relevant to deciding which dependent variables your synthesis should retain, rather than a replacement for the proposed score model. ([arxiv.org](https://arxiv.org/pdf/2602.16666))

###### Life After Benchmark Saturation: A Case Study of CORE-Bench  
**Nadgir et al., June 2026**

A particularly relevant later study of a benchmark in HAL. It examines six dimensions that remain informative after accuracy saturation: **construct validity, out-of-distribution generalization, efficiency, reliability, model-versus-scaffold contributions, and uplift from additional information**. Useful for interpreting whether newer scores represent the same construct as the original HAL measurements. ([arxiv.org](https://arxiv.org/pdf/2606.26158))

---

### 3. Additional prediction and psychometrics literature

These should be included in a broad related-work search, although they are less directly HAL-specific.

| Work | Relevant overlap |
|---|---|
| **How Predictable Are Large Language Model Capabilities? A Case Study on BIG-bench — Ye et al., 2023** | Predicts experimental outcomes from model family, parameter count, task, and in-context-example count; constructs informative benchmark subsets. A close precursor to your covariate-based prediction idea. ([arxiv.org](https://arxiv.org/abs/2305.14947?utm_source=openai)) |
| **Can a Crow Hatch a Falcon? Lineage Matters in Predicting Large Language Model Performance — Tamura et al., COLM 2025** | Lineage-regularized matrix factorization incorporates parent–child and model-merging relationships. Especially relevant if “post-training method” should be represented through actual model ancestry rather than coarse labels. ([openreview.net](https://openreview.net/pdf?id=ULYqB2JORB&utm_source=openai)) |
| **STAR: Bridging Statistical and Agentic Reasoning for Large Model Performance Prediction — Wang et al., 2026** | Combines probabilistic matrix factorization, semantic metadata, retrieved information, and intra-family comparisons under severe missingness. Here “agentic” describes the prediction system, not necessarily the evaluated benchmarks. ([arxiv.org](https://arxiv.org/abs/2602.12143?utm_source=openai)) |
| **Look Before You Leap: Estimating LLM Benchmark Scores from Descriptions — Park et al., 2025** | PRECOG predicts scores from task descriptions and intended configurations without executing the benchmark; includes uncertainty and leakage-conscious validation. Useful as a metadata-based baseline. ([arxiv.org](https://arxiv.org/abs/2509.20645?utm_source=openai)) |
| **Evaluation Examples Are Not Equally Informative: How Should That Change NLP Leaderboards? — Rodriguez et al., ACL 2021** | Bayesian IRT leaderboard modeling; ranking reliability, annotation errors, overfitting, and informative item selection. A foundational bridge between psychometrics and benchmark auditing. ([par.nsf.gov](https://par.nsf.gov/servlets/purl/10309824?utm_source=openai)) |
| **tinyBenchmarks: Evaluating LLMs with Fewer Examples — Maia Polo et al., 2024** | IRT-based estimation of full-benchmark performance from small item subsets, evaluated on Open LLM Leaderboard, MMLU, HELM, and AlpacaEval. Primarily within-benchmark completion rather than entirely unobserved benchmark cells. ([arxiv.org](https://arxiv.org/abs/2402.14992?utm_source=openai)) |
| **metabench — A Sparse Benchmark to Measure General Ability in Large Language Models — Kipnis et al., 2024/ICLR 2025** | Psychometric construction of a compact general-ability evaluation from multiple benchmarks. Relevant to latent-dimensionality assumptions and selecting efficient anchor evaluations. ([arxiv.org](https://arxiv.org/abs/2407.12844?utm_source=openai)) |
| **Lost in Benchmarks? Rethinking Large Language Model Benchmarking with Item Response Theory — Zhou et al., 2025/AAAI 2026** | PSN-IRT estimates model abilities and item characteristics; analyzes measurement weaknesses across 11 benchmarks and 41,871 items. Particularly relevant to testing whether benchmark difficulty/discrimination are well behaved. ([arxiv.org](https://arxiv.org/abs/2505.15055)) |
| **BRIDGE: Predicting Human Task Completion Time From Model Performance — Liu et al., ICML 2026** | Uses agent-task performance and psychometric difficulty to connect benchmark difficulty with human completion time. Relevant if your “difficulty” covariate should have an external interpretation. ([arxiv.org](https://arxiv.org/abs/2602.07267)) |
| **Efficient SWE Agent Benchmarking via Trajectory-Aware Evaluation — September 2026** | PTA-IRT combines trajectory/process information with outcome-based IRT for efficient coding-agent evaluation. A direct connection between HAL-style traces and predictive psychometrics. ([arxiv.org](https://arxiv.org/abs/2609.01603?utm_source=openai)) |
| **Laplace-PSN-IRT: Uncertainty Quantification for Neural Item Response Theory Models of LLM Benchmarks — July 2026** | Adds uncertainty to neural IRT estimates; demonstrates that many apparent leaderboard differences are not statistically distinguishable. Relevant to intervals around imputations and comparisons. ([arxiv.org](https://arxiv.org/abs/2607.25257?utm_source=openai)) |
| **LLM Benchmarking via Representation Multi-task Learning — October 2026** | Defines overall and domain-specific traits through IRT and borrows information across domains. Especially close to the domain structure contemplated in your statistical model. ([arxiv.org](https://arxiv.org/abs/2610.05613?utm_source=openai)) |

A further useful methodological caution is **Contamination Inflates Scores but Rarely Reorders Large Language Model Leaderboards** (September 2026). It frames contamination through differential item functioning using original/paraphrased items. Its reported distinction between absolute-score inflation and ranking changes is directly relevant: **good rank prediction does not establish valid absolute accuracy**. Its empirical conclusion should not be generalized beyond the studied models and contamination setting. ([arxiv.org](https://arxiv.org/abs/2609.02899?utm_source=openai))

---

### 4. Literature testing the validity of the measurements being pooled

These works overlap mainly with your motivation and score-reconciliation steps, rather than with imputation.

###### AI Agents That Matter — Kapoor et al., 2024

The main intellectual precursor to HAL: cost–accuracy trade-offs, mistaken attribution of accuracy gains, inadequate holdouts, benchmark overfitting, and inconsistent evaluation procedures. Important background for explaining why a model–benchmark score alone is an insufficient observational unit. ([arxiv.org](https://arxiv.org/abs/2407.01502?utm_source=openai))

###### The BrowserGym Ecosystem for Web Agent Research — Chezelles et al., 2024/2025

A standardized multi-benchmark web-agent evaluation framework, with a six-model comparative experiment and complementary experiment-management tooling in AgentLab. This provides **new matched evaluations**, rather than statistical harmonization of existing scores, and is relevant to extending HAL’s web-agent coverage. ([arxiv.org](https://arxiv.org/abs/2412.05467?utm_source=openai))

###### AgentRewardBench: Evaluating Automatic Evaluations of Web Agent Trajectories — Lù et al., 2025

Contains **1,302 expert-reviewed trajectories across five benchmarks and four LLMs**, with annotations concerning success, side effects, and repetition. Evaluates twelve LLM judges and finds that common rule-based evaluators can **underreport** success. This directly overlaps your concerns about incomplete evaluators and transcript inspection—and shows that evaluator problems need not inflate scores. ([arxiv.org](https://arxiv.org/abs/2504.08942?utm_source=openai))

###### SABER: Small Actions, Big Errors—Safeguarding Mutating Steps in LLM Agents — Cuadron et al., 2025

Analyzes trajectories on τ-Bench and SWE-bench Verified, distinguishing environment-changing actions from other steps and locating decisive deviations. The log-analysis follow-up explicitly credits this work with independently discovering many τ-Bench Airline problems and compares the audits in its appendix. ([arxiv.org](https://arxiv.org/abs/2512.07850))

###### Beyond Metrics: A Critical Analysis of the Variability in Large Language Model Evaluation Frameworks — Pimentel et al., 2024

Examines variation across LLM evaluation frameworks and the implications for standardized measurement. This is a conventional-LLM counterpart to HAL’s concern that implementations, rather than underlying capabilities alone, produce score differences. ([arxiv.org](https://arxiv.org/abs/2407.21072?utm_source=openai))

---

### 5. What remains distinctive about your proposed inquiry

My synthesis is that existing work separates into three partially connected programs:

| Program | Strongest precedents |
|---|---|
| **Collect and statistically connect incomplete scores** | Messier, ECI/Rosetta Stone, CPP, BenchPress |
| **Predict using model/task/scaffold structure** | Agent Psychometrics, Sloth, observational scaling laws, lineage-regularized factorization |
| **Determine whether the recorded successes mean what they claim** | HAL, Log Analysis, AgentRewardBench, SABER, reliability and CORE-Bench follow-ups |

The opportunity is to **connect these programs**, not to introduce cross-benchmark prediction or agent IRT from scratch. Those methods already have substantial precedents. ([arxiv.org](https://arxiv.org/abs/2607.25891?utm_source=openai))

For your specific design, I would preserve five distinctions:

1. **Reported score versus protocol-matched score.** Treat scaffold, model snapshot, reasoning budget, benchmark version/subset, and scoring rule as part of the measurement’s identity—not merely nuisance metadata. Messier’s data model and Agent Psychometrics are the most useful starting points. ([arxiv.org](https://arxiv.org/abs/2607.25891?utm_source=openai))
2. **Aggregate-score prediction versus item-level psychometrics.** BenchPress/ECI and Agent Psychometrics/tinyBenchmarks solve related but different problems. If item-level outcomes are available, retain them rather than reducing everything to percentages. ([arxiv.org](https://arxiv.org/html/2606.24020v1))
3. **Accuracy versus other scoring functions.** Do not put pass@1, pass@k, pass^k, partial-credit scores, and filtered-task accuracies into one binomial likelihood without modeling their different meanings. The log-analysis case study is an especially consequential example. ([arxiv.org](https://arxiv.org/pdf/2605.08545))
4. **Prediction versus validation.** A statistical model can predict flawed outcomes accurately. Residuals might flag suspicious evaluations, but cannot alone establish cheating, side effects, or evaluator correctness. ([arxiv.org](https://arxiv.org/html/2606.24020v1))
5. **Independent validation versus circular agreement.** For the proposed HAL comparison, I would hold HAL results out of fitting and model selection, then test on matched measured cells. Imputed cells should remain explicitly labeled predictions, with uncertainty and sensitivity to missingness assumptions.

**Recommended reading order:** **Messier → Agent Psychometrics → Rosetta Stone/ECI → BenchPress → CPP and Sloth → HAL’s appendices → Log Analysis.** Together, these provide the closest existing foundation for your study; what I did not find is their integration into a provenance-controlled, externally validated analysis specifically reconciling frontier-model claims with HAL.
