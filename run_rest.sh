#!/usr/bin/env bash
# Queue of remaining analyses (run sequentially to avoid CPU oversubscription). Logs in logs/.
set -x
cd "$(dirname "$0")"
./run_R.sh R/03_report_selected.R 16 main > logs/part1_report_main.log 2>&1 &
./run_R.sh R/03_report_selected.R 16 reduced > logs/part1_report_reduced.log 2>&1 &
./run_R.sh R/05_post_paper.R > logs/post_paper.log 2>&1 &
./run_R.sh R/04_holdout.R 60 reduced > logs/part2_reduced.log 2>&1
wait
./run_R.sh R/06_runtime.R 64 > logs/ext2_runtime.log 2>&1 &
./run_R.sh R/07_ap_features.R > logs/ext1_ap.log 2>&1 &
./run_R.sh R/08_judge_refit.R > logs/ext3_judge_refit.log 2>&1
for v in judge_both judge_any manual; do ./run_R.sh R/04_holdout.R 60 $v > logs/ext3_holdout_$v.log 2>&1; done
wait
echo ALLDONE
