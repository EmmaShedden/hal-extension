#!/usr/bin/env bash
# Rerun everything downstream of Part 1 selection after PF-2 (DESIGN.md). Run after R/02_fit_candidates.R. Logs in logs/.
set -x
cd "$(dirname "$0")"
./run_R.sh R/03_report_selected.R 16 main > logs/part1_report_main.log 2>&1 &
./run_R.sh R/05_post_paper.R > logs/post_paper.log 2>&1 &
./run_R.sh R/04_holdout.R 60 main > logs/part2_main.log 2>&1
wait
./run_R.sh R/10_task_holdout.R 60 main > logs/part2_task_main.log 2>&1 &
./run_R.sh R/08_judge_refit.R > logs/ext3_judge_refit.log 2>&1 &
./run_R.sh R/07_ap_features.R > logs/ext1_ap.log 2>&1
wait
for v in judge_both judge_any manual; do ./run_R.sh R/04_holdout.R 60 $v > logs/ext3_holdout_$v.log 2>&1; done
./run_R.sh R/06_runtime.R 64 > logs/ext2_runtime.log 2>&1
./run_R.sh R/09_latent_factors.R > logs/latent.log 2>&1
./run_R.sh R/11_ap_interactions.R full > logs/ext1b_full.log 2>&1
./run_R.sh R/11_ap_interactions.R cell 90 > logs/ext1b_cell.log 2>&1
./run_R.sh R/11_ap_interactions.R task 90 > logs/ext1b_task.log 2>&1
./run_R.sh R/11_ap_interactions.R summary > logs/ext1b_summary.log 2>&1
PY=/home/eshedden/miniconda3/envs/fa26-hal/bin/python
$PY scripts/make_report_tables.py > logs/tables.log 2>&1
$PY scripts/make_figures.py > logs/figures.log 2>&1
$PY scripts/make_task_holdout_figures.py >> logs/figures.log 2>&1
echo ALLDONE
