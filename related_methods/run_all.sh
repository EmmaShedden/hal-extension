#!/usr/bin/env bash
# Fit every related-work method on the Part 1 data and collect the comparison (related_methods/DESIGN.md).
# The conda env's bin must be on PATH for Rcpp to find its compiler (method 05). Logs in logs/related_methods/.
cd "$(dirname "$0")/.."
export PATH=/home/eshedden/miniconda3/envs/fa26-hal/bin:$PATH
mkdir -p logs/related_methods
./run_R.sh related_methods/07_observational_scaling/build_external_scores.R > logs/related_methods/07_build.log 2>&1
for m in 01_rasch_messier 02_additive_irt_agent_psychometrics 03_benchmark_irt_eci 04_lowrank_benchpress \
         05_collab_filtering_cpp 06_skill_scaling_sloth 07_observational_scaling; do
  ./run_R.sh related_methods/$m/fit.R > logs/related_methods/$m.log 2>&1 &
done
wait
./run_R.sh related_methods/compare.R > logs/related_methods/compare.log 2>&1
echo ALLDONE
