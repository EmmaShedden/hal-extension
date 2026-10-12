"""Render result CSVs into markdown tables included in REPORT.md (results/tables/*.md)."""
import os, pandas as pd
os.makedirs('results/tables', exist_ok=True)
def md(df, f, floatfmt=3):
    open(f'results/tables/{f}.md', 'w').write(df.round(floatfmt).to_markdown(index=False) + '\n')
for v in ['main', 'reduced']:
    m = pd.read_csv(f'results/part2/{v}/holdout_metrics.csv')
    w = m.pivot_table(index=['frac', 'rep', 'n_held_cells'], columns='predictor', values='run_mae_pp').reset_index()
    b = m[m.predictor == 'refit'][['frac', 'rep', 'brier', 'err01', 'logloss', 'auc', 'singular']]
    w = w.merge(b, on=['frac', 'rep'])
    w = w.rename(columns={'refit': 'MAE_refit_pp', 'full_model': 'MAE_full_pp', 'naive_bench_mean': 'MAE_bench_mean_pp', 'naive_additive': 'MAE_additive_pp',
                          'brier': 'Brier_refit', 'err01': 'err01_refit', 'logloss': 'logloss_refit', 'auc': 'AUC_refit'})
    md(w[['frac', 'rep', 'n_held_cells', 'MAE_refit_pp', 'MAE_full_pp', 'MAE_bench_mean_pp', 'MAE_additive_pp', 'Brier_refit', 'err01_refit', 'logloss_refit', 'AUC_refit', 'singular']],
       f'holdout_per_set_{v}', 3)
    s = pd.read_csv(f'results/part2/{v}/holdout_summary.csv')
    md(s, f'holdout_summary_{v}', 3)
pp = pd.read_csv('results/post_paper/post_paper_runs.csv')
pp['obs_pct'] = 100 * pp.obs; pp['pred_pct'] = 100 * pp.pred
md(pp[['benchmark', 'scaffold', 'model', 'effort', 'new_model', 'new_scaffold', 'obs_pct', 'pred_pct', 'abs_err_pp']].sort_values(['benchmark', 'model']), 'post_paper_runs', 1)
rl = pd.read_csv('results/part1/run_level_fit.csv')
rl['obs_pct'] = 100 * rl.obs; rl['pred_pct'] = 100 * rl.pred
md(rl.groupby('benchmark').agg(runs=('run', 'size'), mae_pp=('abs_err_pp', 'mean'), max_pp=('abs_err_pp', 'max')).reset_index(), 'part1_run_fit_by_benchmark', 2)
for f in ['part1/fixed_effects', 'part1/lrt_fixed_terms', 'part1/random_effects_variance', 'part1_reduced/fixed_effects', 'part1_reduced/random_effects_variance',
          'latent/model_ability', 'latent/scaffold_ability', 'latent/task_difficulty_by_benchmark', 'ext2_runtime/fixed_effects', 'ext2_runtime/random_effects_variance',
          'ext1_ap_features/cv_metrics', 'ext1_ap_features/in_sample', 'ext1_ap_features/pc1_loadings', 'ext3_judge/in_sample_comparison']:
    df = pd.read_csv(f'results/{f}.csv')
    md(df, f.replace('/', '__'), 3)
pm = pd.read_csv('results/candidate_metrics.csv'); pm['dAIC'] = pm.AIC - pm.AIC.min()
md(pm[['id', 'rd', 'bench', 're_opt', 'AIC', 'BIC', 'dAIC', 'singular', 'eligible']].head(20), 'candidates_top20', 1)
print('ok')
