
## HAL Interpolation analysis

The paper "Holistic Agent Leaderboard: The Missing Infrastructure for AI Agent Evaluation" and its artifacts published scores for a collection of (model × scaffold × benchmark task × configuration) combinations. This required fresh runs of each combination under consideration, at great expense. I am curious how well these results could be approximated by using classical statistical analysis to interpolate over the data from only a subset of evaluations.

Your task is to perform a psychometrics (IRT) style analysis of this dataset, using binomial GLMER to express information such as model family, model size, model post-training method, scaffolding choices, benchmark domain, benchmark difficulty, etc.

1. Your analysis should mirror https://github.com/hammad-a/ICSE24_TMS/blob/main/analysis_scripts_2/regression-analysis.Rmd (the "TMS analysis") and https://github.com/pasantiesteban/ICSE_SEET2026_Chats/blob/main/annotations-data-analysis/glmer-regression-analysis-v3.Rmd (the "PT analysis"). For context, the PT analysis was based on the TMS analysis. If you think you see a mistake in these, you may choose to fix it, and document the change.
2. Like the TMS and PT analyses, even though the apparent number of observations is not high (186 runs over 142 combinations in this paper), the true number of observations at the task ("question") level (as opposed to the benchmark "exam" level) is significantly higher. It also helps that all information is combined under one model, rather than splitting the dataset into many small datasets and models (which is generally a less powerful strategy).
3. You should use the same tools as the TMS analysis, where applicable (e.g., `lme4`). All installs (including R itself) should be made in a new `fa26-hal` conda environment. The server is headless, don't try to install any kind of utilities for GUI interaction with R notebooks, and you may choose to skip the notebooks and produce plain R scripts instead. If you do use notebooks, save `.html` versions of final runs so that intermediate results can be easily viewed.
4. In comparison with the TMS analysis, you should consider a significantly smaller class of model formula candidates. Apply the "keep it maximal" philosophy.
5. Like the PT analysis, you should filter out invalid formulas before model fitting.
6. You may not cherry-pick or HARK -- you can run any data management scripts during development, or run anything with dummy data, but you must clearly document the reasoning for any design changes you make after any model fitting has been run on real data.
7. Binomial GLMER may not handle benchmark scaffolding choices that allow for partially correct scores. If lme4 supports a better-suited model class, use it, otherwise leave these out.
8. You may assume that reasoning levels like "high" or "default" have shared meaning across model families. If there are "unknown", group them with "default".
9. You may access huggingface and github to download the relevant datasets and artifacts. Take care to manage your storage footprint, and not download anything unnecessary. Everything should be in the `ml-ecosystems` directory.
10. To track your work, use the local git repository I've initialized, and break things into commits. You don't need to be too granular -- for instance, it's ok if the whole initial implementation is committed all at once. Don't try to create or push to a remote repository.
11. Write all your findings to a REPORT.md in the project root.
12. Related works (and their github projects) provide evidence for what predictors may be relevant to include in your candidate model formulas. For instance, "Messier: A High-Resolution Corpus for Cross-Benchmark Agent Evaluation", "A Rosetta Stone for AI Benchmarks", and "Collaborative Performance Prediction for Large Language Models" should include information about which predictors they used, how they were labeled, and why predictors were included or excluded. You should learn from their choices where applicable.
13. You should not manually annotate task scores, as they should be available in the data. Similarly, any predictors' information that is available in the data should be collected programmatically. It is possible that some of the predictors you choose to include based on the other works mentioned in the previous item may not be included in HAL's reported data. These should be collected programmatically from other sources if possible, and manually labeled otherwise.
14. You may (and should) deploy subagents and worktrees where useful. This can parallelize tasks and reduce each agent's context size.
15. Store `.Rds` copies of fitted models and ensure that everything can be replicated.
16. You can use as many cores on the server as you want.
17. A relevant literature search is at `./responses.md`.

You should address the above task in two parts. First, fit the whole dataset and report the quality of fit. This is the part where a model formula, including any log-transformation of inputs, is fixed upon (as well as any other hyperparameters), like in the TMS and PT analyses. The chosen analysis design will be shared with the second part rather than re-optimizing there. Second, perform a heldout analysis where random subsets of (model × scaffold × benchmark task × configuration) combinations are dropped from the HAL dataset and the model is refit on the remainder. For each holdout set, report the newly fitted model's prediction error rate (as a baseline, also report the full-dataset model's predicion error rate).

### Extensions
Perform these follow-on tasks:
1. The paper "Agent Psychometrics: Task-Level Performance Prediction in Agentic Coding Benchmarks" performs a similar analysis using task features extracted from issue descriptions, repositories, solutions, and tests. If the original predictors result in poor model fit or test performance, try to incorporate new predictors based on the recommendations/results in this paper. Avoid manually annotating data where it can be inherited.
2. Perform the analogous analysis that predicts runtimes of successful traces (like in the TMS and PT analyses).
3. HAL uses an LLM as a judge to analyze agent traces. Some of its results can be interpreted as correcting the originally labeled scores. Apply these corrections and rerun the analysis, then determine whether it improved the results.
4. Write a `summary.md` that summarizes the takeaways from your analysis results. As part of this, report latent factor coefficients and interpret them.
