# Methods summary: TMS (ICSE'24) and PT (ICSE-SEET'26) mixed-model pipelines

Sources (downloaded verbatim, this directory):
- `TMS_regression-analysis.Rmd`: hammad-a/ICSE24_TMS, `analysis_scripts_2/regression-analysis.Rmd` (1012 lines)
- `PT_glmer-regression-analysis-v3.Rmd`: pasantiesteban/ICSE_SEET2026_Chats, `annotations-data-analysis/glmer-regression-analysis-v3.Rmd` (2068 lines)

## 0. Mismatches with the expected checklist (read this first)

Several things you might expect are **not in either file**:
- **Neither file models a binary outcome.** TMS fits *linear* mixed models (`lmer`) to `log(response_time)`.
  The text says accuracy was modeled with GLMMs, but that code is not in this file or anywhere else in the
  repo. PT fits **Poisson / negative-binomial count** GLMMs (`glmer(family=poisson)`, `glmer.nb`) with a log offset.
- **No MuMIn, performance, car, pROC.** There is no R² (marginal/conditional), VIF, ROC/AUC, or DHARMa anywhere.
  The only packages loaded are `lme4, dplyr, readr, emmeans, purrr, lattice, TAF, moments` (TMS) and
  `lme4, dplyr, readr, emmeans, stringr, purrr, tidyr, ggplot2, ggbreak` (PT).
- **PT does no formula enumeration and no "invalid formula" filtering.** Each PT model is one
  hand-written, near-maximal formula. The **brute-force enumeration plus pruning by design rules** is in **TMS** (§3 below),
  and TMS prunes by hand-coded exclusion rules, not by programmatic validity checks.
  None of PT's helper scripts (`rscripts/*.R`, not downloaded) enumerate formulas either. They only refit
  single models with `nAGQ=1`, fit nested h0 models, or profile them.
- **No scaling/centering of predictors in either file.** There are no `scale()` calls and no `relevel()`/`contrasts` settings.
  Both rely on R's default treatment coding, where the reference level is the alphabetically first one.
- **No parallelization.** TMS uses a plain sequential `for` loop. PT fits each model once, caches it as `.rds`,
  and runs long fits as separate batch R scripts.
- **Convergence/singularity handling is never explicit.** There is no `isSingular()` check, no warning capture, and no `allFit()`.

## 1. Data shape and unit of observation

### TMS
- Long format with **one row per participant × question (stimulus) response**. This is question level, not exam level.
  Columns: `id` (participant, 14 people), `stimulus` (re-indexed question id; `original_stimulus` is kept),
  `domain` (`LETTERS[1:5]`), `condition` (TMS site, `LETTERS[24:26]` = X/Y/Z), `session_num` (1-3),
  `response_time`, `is_programming`, `isMR`.
- The data is split into two subsets that are modeled separately: `prog_da = da %>% filter(is_programming)` and
  `pos_ctrl_da = da %>% filter(isMR)` (the positive control, mental rotation).
- Cleaning:
  - Drop rows with `NA` response_time (11 rows).
  - Drop one "sleepy" participant's responses that are more than 2 SD from the other participants' per-question mean (29 rows):
    ```r
    stimuli = da %>% filter(id != "19391") %>% group_by(original_stimulus) %>%
      summarise(response_time.stimulus.mean = mean(response_time),
                response_time.stimulus.std_dev = sd(response_time))
    da = merge(da, stimuli, by="original_stimulus") %>%
      filter(id != "19391" | abs(response_time - response_time.stimulus.mean) <= 2*response_time.stimulus.std_dev)
    ```
- Outcome: `log(response_time)`, a continuous Gaussian response. Raw `response_time` was also fitted and then rejected because of skew (§6).

### PT
- Long count table with **one row per conversation × annotator × code × speaker** (file
  `codebook{k}_conv-annotator-code-speaker_outcome-counts.csv.gz`), plus `outcome` (S/F, conversation level),
  `request` (help-request type), `speakerIsLearner` (bool), `ln_conversation_length` (log exposure).
- Outcome: `count` of annotations, modeled with a log link and `offset=ln_conversation_length` (a rate per message).
- Three "codebooks" pool and filter the codes differently. Compound code strings are split into factor columns, e.g.
  ```r
  da7 = da %>% filter(str_starts(da$code, "Helping > "))
  da7["code"] = substring(da7$code, first=nchar("Helping > ")+2, last=nchar(da7$code)-1)
  da7[c("commMech","certainty","content","specificity")] = str_split_fixed(da7$code, ", ", 4)
  ```
- **±1 effect coding for random slopes** (Codebook 1):
  ```r
  da["numeric_outcome"]          = ifelse(da$outcome == "S", 1, -1)
  da["numeric_speakerIsLearner"] = ifelse(da$speakerIsLearner == TRUE, 1, -1)
  da["LS_HF"] = ifelse((da$speakerIsLearner & da$outcome=="S") | (!da$speakerIsLearner & da$outcome=="F"), 1, -1)  # interaction contrast
  ```
  Model m6 also uses 0/1 indicator slopes: `I.Q`/`I.H` select the question-type or help-type subset, as in `(0+I.Q|quesType)`.

## 2. Packages and exact fitting calls

### TMS (Gaussian LMM)
```r
m = lmer(f, data=prog_da, REML=FALSE)   # ML, not REML, so AIC/BIC are comparable across fixed effects
```
Default `lmerControl()` is used throughout. No optimizer, nAGQ, or weights are set.

### PT (count GLMM)
```r
m1a = glmer(f1, data=da, family=poisson(link=log),
            offset=ln_conversation_length,
            nAGQ=0,                                   # "faster"; nAGQ=1 "slower but necessary for profiling"
            control=glmerControl(optimizer="nloptwrap"))
m1b = glmer.nb(f1, data=da, offset=ln_conversation_length, nAGQ=0,
               control=glmerControl(optimizer="nloptwrap"))
saveRDS(m1a, file=rds1a)   # all fits are cached; `if (FALSE) {refit} else {readRDS}`
```
- `nAGQ=0` is used for every model in the notebook. Separate scripts (`rscripts/*-nAGQ1-fitting.R`) refit some models with `nAGQ=1`
  and profile them with `profile(m, devtol=1e-07)`. The Outcomes-model profile **failed** with
  "profiling detected new, lower deviance", which suggests the fit had not reached the optimum.
- Fit times range from minutes (m1, ~7-13 min) to about a week (m7, Poisson). NB was "not tractable" for m7, m8 and m6.
- The notebook's comments say: "make sure to compare against a model with matching nAGQ setting" when running LRTs.

## 3. Candidate formula generation (TMS only)

**Fixed-effect structures:** 13 candidates, brute-force enumerated, then pruned by hand.
- All `condition × session_num` interactions are removed because there is no prior hypothesis and only about 2 people per ordering.
- No 3-way interactions are included.
- Heredity is enforced because `a*b` implies `a + b`. Interaction-only terms are excluded.
```r
fixed_effects = c("", "condition", "domain", "session_num",
  "condition + domain", "domain + session_num", "condition + session_num",
  "condition + domain + session_num",
  "condition * domain", "domain * session_num",
  "condition * domain + session_num", "domain * session_num + condition",
  "condition * domain + domain * session_num")
```
**Random-effect terms:** 6 random intercepts, kept from the brute-force list of 15 after documented exclusions:
```r
random_effects = c("id", "stimulus", "id:domain", "id:condition", "stimulus:condition", "id:domain:condition")
```
Exclusion rules, as numbered in the source:
1. The no-random-effect model is dropped. If there is no true random effect, the variance estimates will simply be about 0.
2. Grouping factors with few levels (`domain` has 5, `condition` has 3) and factors that are already fixed effects are not used as random effects. Neither is `domain:condition`.
3. Groups of size ≤1 are excluded. For example, `id:stimulus` is out because each person sees each question once.
4. **Nested** (not crossed) combinations are excluded. `stimulus:domain` is out because stimuli are nested within domains.
   Only crossed factors from the design are interacted.

All random slopes are intercept-only, of the form `(1|g)`. There are no correlated slopes.

**Random structures:** every non-empty subset of the 6 terms gives 2^6 - 1 = 63 structures:
```r
random_effects = map(random_effects, function(s) sprintf("(1|%s)", s))
for (k in 1:N_random) for (ii in combn(1:N_random, k, simplify=FALSE))
  random_exprs = append(random_exprs, paste(random_effects[ii], collapse=" + "))
```
**Full formulas:** 13 × 63 = **819** candidates, written as `sprintf("log(response_time) ~ %s + %s", fe, re)`
(or `~ re` when there is no fixed effect). The same 819 formulas are refit on 4 dataset/response combinations
(programming vs MR × log vs raw time).

**PT, by contrast,** writes one maximal-ish random-intercept formula per research question. It includes all 2- and 3-way
interactions of the grouping factors with conversation, annotator, request, speaker and code dimensions, and drops
4-way and higher terms ("skip higher-order interactions"). Fixed effects are minimal (`outcome`, `request`,
`speakerIsLearner`, `QH`), and the research questions are answered from the **random effects (BLUPs)**. Example (m5):
```r
f5 = paste("count ~ request", "(1|conversation_sharedID) + (1|annotator)",
  "(1|contentDomain)", "(1|questionType)", "(1|contentDomain:questionType)",
  "(1|annotator:contentDomain)", "(1|annotator:questionType)", "(1|annotator:contentDomain:questionType)",
  "(1|conversation_sharedID:contentDomain)", "(1|conversation_sharedID:questionType)",
  "(1|conversation_sharedID:contentDomain:questionType)",
  "(1|request:contentDomain)", "(1|request:questionType)", "(1|request:contentDomain:questionType)", sep=" + ")
```
Model m1 also has uncorrelated random **slopes** by code: `(0+numeric_outcome|code) + (0+numeric_speakerIsLearner|code) + (0+LS_HF|code)`.
The m7 formula repeats `(1|request:speakerIsLearner)` twice, and so does m8. Nothing deduplicates them.

## 4. Predictor preprocessing
- TMS:
  - The outcome is log-transformed. The choice is justified by the skewness of the raw data and of the residuals, measured with `moments::skewness` (§6).
  - `session_num` is entered as **numeric**, because lme4 has no ordinal predictor type.
  - `condition` and `domain` are character factors with default treatment contrasts, so the reference levels are `X` and `A`.
  - There is no centering or scaling.
- PT:
  - The only transform is the log-exposure offset `ln_conversation_length`, which is precomputed upstream.
  - Binary predictors are coded ±1 when used as random slopes (above).
  - Fixed-effect factors use default treatment coding, for example `outcomeS` is the coefficient for S vs F.
  - There is no scaling.

## 5. Model selection, convergence and singularity
- **TMS: AIC with ML fits.** Every candidate's `AIC(m)` and `BIC(m)` are written to `metrics.csv`. The rows are sorted, the top 10 are inspected,
  and the best-AIC formula is refit:
  ```r
  f0 = log_time_models_da[order(log_time_models_da$AIC),]$formula[[1]]
  m0 = lmer(f0, data=prog_da, REML=FALSE)
  ```
  BIC is reported as an alternative. The authors note that BIC picks smaller models and cite Barr et al. 2013 ("keep it maximal")
  to defend AIC. They also treat **robustness across the top 10** as evidence: `id:condition` appears in all of the top-10 models under both criteria.
- **PT: family selection only.** Poisson is preferred unless NB is better by more than 4 AIC units:
  ```r
  m1 = if (AIC(m1a) < AIC(m1b) + 4) m1a else m1b   # "Source for the 4: Sec 3.3 of PMC6962709"
  ```
  The NB dispersion is checked with `getME(m1b,"glmer.nb.theta")`, together with a plot of `fv + fv^2/theta` against `fv`. The notebook header says m1
  was selected as NB, but the code's rule plus the heading "Select the model family (Poisson)" are ambiguous. m5 is Poisson by AIC.
  m6, m7 and m8 are Poisson by tractability.
- Neither file checks for convergence or singular fits, and neither drops failing fits or catches warnings. TMS writes each
  `summary(m)` to `<outputdir>/<formula>/summary.txt`, so any warnings only appear in those files.

## 6. Diagnostics and fit reporting
- **TMS**
  - **Profile-likelihood CIs** on the random-effect SDs: `pp0 = profile(m0); xyplot(pp0); confint(pp0)`. A term counts as significant
    if the CI for its σ excludes 0. For example, `.sig03` = `id:condition` has 95% CI (0.0663, 0.143).
  - **PVE (proportion of variance explained)** for a random term, computed as that term's variance divided by the sum of all variance components, including the residual:
    ```r
    get_pve = function(m, effect) { re = as.data.frame(VarCorr(m)) %>% rename(Groups=grp, Variance=vcov)
      (re %>% filter(Groups==effect))$Variance / sum(re$Variance) }
    b0 = bootMer(m0, FUN=function(m) get_pve(m,"id:condition"), nsim=1000); quantile(b0$t, c(.025,.975))
    ```
    The result is 2.2% with 95% CI [0.7%, 4.0%], from a parametric bootstrap with `set.seed(42)`.
  - **LRTs for fixed effects:** `anova(m0, m1)` compares the best-AIC model with the same structure minus one term (taken from the BIC ranking).
    This gives p=0.001 for `session_num` and p=0.018 for `condition` in the MR model.
  - **Post-hoc contrasts:** `emmeans(m0, pairwise ~ domain); pairs(e0, adjust="BH")`, which is Benjamini-Hochberg corrected.
  - **Residuals:** `r0 = log(y) - predict(m0); hist(r0); skewness(r0)`. The log model's skew is 0.105, versus a much larger skew for raw time.
    The skewness of the raw and log-transformed response is also reported. `table()` is used to check the balance of condition and domain.
- **PT**
  - **LRTs between nested models:** `anova(h1, h0)` drops one random term, e.g. `(0+LS_HF|code)`, or a block of terms,
    e.g. all `request:content` terms, to give an omnibus test. Several of these are marked FIXME or are incomplete.
  - Speaker-type validity is tested by `anova(m1, m1ns)`, where `m1ns` has no speaker terms.
  - **Fisher's exact test** of request type × outcome, run at the conversation level: `fisher.test(table(request, outcome))`.
  - `profile(m6)` is attempted and marked FIXME. There are no residual or dispersion diagnostics beyond the NB theta plot.

## 7. Coefficient / effect reporting
- **TMS:** raw `summary(m0)` estimates on the log scale, e.g. "-0.065" for session. There is no `exp()`, so no explicit
  ratio is reported. Random terms are reported as profile CIs on σ plus the bootstrapped PVE.
- **PT:** inference is done mainly on **BLUPs (conditional modes)** with their conditional SDs:
  ```r
  r1 = ranef(m1, condVar=TRUE); rdf1 = as.data.frame(r1)          # cols grpvar, term, grp, condval, condsd
  b["PI.low"] = b$condval - 2*b$condsd; b["PI.high"] = b$condval + 2*b$condsd
  b %>% filter(abs(condval) > 2*condsd)   # "significant"; condsd < |condval| <= 2*condsd is a "trend"
  b["rate.ratio"] = exp(b$condval)        # multiplicative rate ratio (sometimes reported)
  ```
  - When `as.data.frame(ranef)` fails ("factor level duplicated"), the fallback reads `attr(r[[g]], "postVar")[,,]`.
  - Results are shown as forest plots (ggplot `geom_point` plus `geom_linerange`, sorted by condval).
  - For m1, cell-wise "sigval" sums add up only the significant BLUP components (±1 coding) to build
    Learner/Helper × Success/Failure contrasts and difference-in-differences.
  - Fixed-effect significance in that sum is checked with `sqrt(diag(vcov(m1))["outcomeS"]) < 0.05`. This tests whether the SE is below 0.05, not whether p < 0.05, which looks like a bug.
  - There are no odds ratios and no Wald CIs on fixed effects.

## 8. Key differences: PT vs TMS
| Aspect | TMS | PT |
|---|---|---|
| Model | `lmer`, Gaussian, `log(rt)`, REML=FALSE | `glmer` Poisson(log) / `glmer.nb`, offset log length |
| Unit | participant × question response | conversation × annotator × code × speaker count |
| Formula search | 13 FE × 63 RE = 819 candidates, AIC ranking | 1 hand-built maximal-ish formula per RQ, no search |
| Pruning | design rules: few levels, already fixed, group size ≤1, nested | manual: drop interactions of more than 3 factors |
| Family choice | n/a (log vs raw by residual skew) | Poisson unless NB AIC is better by more than 4 |
| Optimizer / nAGQ | defaults | `nloptwrap`, `nAGQ=0` (nAGQ=1 in side scripts) |
| Inference target | fixed effects (LRT, emmeans BH) and random σ (profile CI, PVE bootstrap) | BLUPs with ±2·condSD intervals, LRT on random blocks |
| Caching | AIC/BIC CSV plus per-formula summary.txt | `saveRDS` per model and per ranef |
| Seed | `set.seed(42)` (bootMer) | optional, off by default |

## 9. Notes for replicating on a model × scaffold × benchmark × task binary outcome
These are adaptation notes. Neither source does this.
- Unit: one row per (model, scaffold, benchmark, task[, seed/run]). The outcome is solved ∈ {0,1}. This is the analogue of TMS's question-level rows.
- Analogue of TMS:
  - Fixed effects: low-cardinality factors of interest, e.g. scaffold and benchmark.
  - Random intercepts: crossed sampled units, e.g. `(1|model)`, `(1|task)` (task is nested in benchmark, so use `(1|benchmark:task)` or unique task IDs),
    and `(1|model:scaffold)`, `(1|model:benchmark)`.
  - Apply the same 4 pruning rules: drop factors with few levels as random effects, groups of size ≤1, nested combos, and FE/RE redundancy.
  - Enumerate FE subsets × non-empty RE subsets and rank by AIC.
- Fit: `glmer(y ~ ..., family=binomial(link="logit"), nAGQ=0 or 1, control=glmerControl(optimizer="nloptwrap" or "bobyqa"))`.
  Add checks that neither source does: `isSingular()` and convergence warnings (`m@optinfo$conv$lme4$messages`).
- PT-style BLUP readout: `ranef(m, condVar=TRUE)`, then flag |condval| > 2·condsd. `exp(condval)` is an odds ratio relative to the baseline.
- TMS-style: LRT (`anova`) for each fixed effect of interest, `emmeans(..., type="response")` with BH adjustment, profile CIs or `bootMer` for random SDs,
  and PVE. For a logistic model the residual variance is π²/3, which must be added to the PVE denominator.
