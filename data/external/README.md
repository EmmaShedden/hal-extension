# External metadata (downloaded 2026-10-12)

Small (<20 MB each) third-party metadata files for model/task covariates in the HAL GLMER analysis.
Files are snapshots of living sources; re-download changes values. SHA-256 sums are at the bottom.
See refs/RELATED_WORK_PREDICTORS.md for how they are meant to be used.

| Local path | Source URL | Notes / license |
|---|---|---|
| epoch/all_ai_models.csv | https://epoch.ai/data/all_ai_models.csv | Epoch AI "AI Models" database (57 cols: Organization, Publication date, Parameters, Training compute (FLOP), Model accessibility, Open model weights?, Base model, ...). CC-BY 4.0 |
| epoch/notable_ai_models.csv | https://epoch.ai/data/notable_ai_models.csv | Notable subset (used by Messier to resolve release dates). CC-BY 4.0 |
| epoch/frontier_ai_models.csv | https://epoch.ai/data/frontier_ai_models.csv | Frontier subset. CC-BY 4.0 |
| epoch/eci_benchmarks.csv | https://epoch.ai/data/eci_benchmarks.csv (301 redirect, then 200) | Benchmark-score long table used to fit ECI (as fetched by Messier analysis/epoch_eci/fetch_eci.py) |
| epoch/benchmark_data/{README.md, model_metadata.csv, benchmark_metadata.csv, eci_scores.csv, swe_bench_verified.csv, scicode_external.csv} | https://epoch.ai/data/benchmark_data.zip (2.4 MB zip; only these members extracted; eci_scores.csv was at epoch_capabilities_index/eci_scores.csv) | model_metadata.csv maps API model_version strings (e.g. claude-3-7-sonnet-20250219_16K) to model_group/date/org/accessibility/training_compute_flop; eci_scores.csv = Epoch Capabilities Index with CIs. CC-BY 4.0 |
| agent_psychometrics/swebench_verified_llm_judge_features_defaults15.csv | https://raw.githubusercontent.com/dariakryvosheieva/agent-psychometrics/main/llm_judge_features/defaults/swebench_verified/llm_judge_features.csv | 500 SWE-bench Verified tasks x 15 default features (12 Claude Opus 4.6 judge + 3 auditor-agent). Covers all 50 SWE-bench Verified Mini tasks. MIT |
| agent_psychometrics/swebench_verified_llm_judge_features_source28.csv | .../llm_judge_features/information_ablation/source/swebench_verified.csv | 28-feature pool (20 Opus 4.6 judge + 8 GPT-5.4 auditor) used for source ablation. MIT |
| agent_psychometrics/swebench_verified_irt_1pl_items.csv | .../data/swebench_verified/irt/1d_1pl/items.csv | Their 1PL difficulty b (+ b_std) per Verified task, fit on 134 SWE-bench leaderboard agents. MIT |
| llm_registries/litellm_model_prices_and_context_window.json | https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json | supports_reasoning, token prices, context window per API model id. MIT |
| llm_registries/openrouter_models.json | https://openrouter.ai/api/v1/models | created (unix ts), supported_parameters (contains "reasoning"), pricing, hugging_face_id |

Not downloaded (too large or gated), but verified reachable:
- Messier corpus: https://huggingface.co/datasets/Andromede-AI/messier (tasks.jsonl 134 MB, records.jsonl 594 MB, classifications.jsonl 14 MB).
- Parameter counts for open-weight models: https://huggingface.co/api/models/<repo>?expand[]=safetensors (e.g. deepseek-ai/DeepSeek-V3 -> total 684,531,386,000).
- Native task difficulty: princeton-nlp/SWE-bench_Verified `difficulty` (time buckets), AssistantBench/AssistantBench `difficulty`, osunlp/ScienceAgentBench `domain`/`subtask_categories` (via datasets-server.huggingface.co). osunlp/Online-Mind2Web (`level`) and gaia-benchmark/GAIA (`Level`) are gated and need an HF token.

## SHA-256
```
b8f01c1b2fdbbcc9dfe8d40d3f668d2f42659a50d706c7d73fbe5a7a54bcc874  ./agent_psychometrics/swebench_verified_irt_1pl_items.csv
2dddefd3e0cf7d70b849198099fd438f7d2c10ccdbc6fc387964f830f2460c31  ./agent_psychometrics/swebench_verified_llm_judge_features_defaults15.csv
586cbefe94168433dda0a390ace9bdc182f29de6dc55e58a719015ad7a1f2046  ./agent_psychometrics/swebench_verified_llm_judge_features_source28.csv
d845f68989881cb922ee6fd131d2bce6fb9c88dce5978eb0719a4c053476eff9  ./epoch/all_ai_models.csv
f88ac08bce68b629dd10908dc9cb797dec8254fd3f572bedf85b34b2fc184d5d  ./epoch/benchmark_data/benchmark_metadata.csv
30844141e711b775a0970cbe0504d1d96f4abd8b8e86b7f9e24ecf70281de159  ./epoch/benchmark_data/eci_scores.csv
86b61f39ecfb89998ff0d6d0f2f3f777d8a816a97504579d078a48b2919f0e69  ./epoch/benchmark_data/model_metadata.csv
6a594819e9a038c71711db45854bc80d30441c8f488d84b7aca9ccd18dfc0e0c  ./epoch/benchmark_data/scicode_external.csv
6480176a5d9b1573676fcacc5df5e8c58f9e5fce34025600a19b3bf60617561c  ./epoch/benchmark_data/swe_bench_verified.csv
84423df0ed6e137365e2d8039f54e16ddb1b4747f8b11793498416b4340c32fe  ./epoch/eci_benchmarks.csv
46c62a18eeed9b37fe384c5fa7d34f9dc5ad26f2ed1efd2a2b950ac0a02d7fe5  ./epoch/frontier_ai_models.csv
bacde4f9af388703ceebd01cf71a14854f93b8995e425141b016e48f21d4e7df  ./epoch/notable_ai_models.csv
10764517ded77844701b88837070f749d1b26c2573eb0ffd330b189a33d7d138  ./llm_registries/litellm_model_prices_and_context_window.json
b11d45d389581207e9ba12b1cd668d9e36c955000abae1d44b162c19d2434ca8  ./llm_registries/openrouter_models.json
```
