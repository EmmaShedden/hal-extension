"""Task-level (row) holdout, Part 2b: figure + tables.
Writes results/figures/task_holdout_*.png and results/part2_task/main/{per_benchmark,comparison}.csv / .md.
Same palette and styling as make_figures.py.
"""
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

OUT = "results/figures"
SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": GRID, "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "text.color": INK, "font.size": 10, "axes.titlesize": 10.5, "axes.titleweight": "bold",
    "axes.spines.top": False, "axes.spines.right": False, "axes.grid": True, "grid.color": GRID,
    "grid.linewidth": 0.8, "axes.axisbelow": True, "legend.frameon": False,
})
FR = [0.10, 0.25, 0.50]

SEL = open("results/selected_formula.txt").read().split()[0]
ts = pd.read_csv("results/part2_task/main/holdout_summary.csv")
cs = pd.read_csv("results/part2/main/holdout_summary.csv")
g = lambda df, p, c: df[df.predictor == p].set_index("frac").loc[FR, c].values

# ---- comparison table: task holdout vs cell holdout -------------------------------------------------
cmp = pd.DataFrame({
    "frac_held_out": FR,
    "task_subset_refit": g(ts, "refit", "run_mae_pp"),
    "task_subset_run_mean": g(ts, "naive_run_mean", "run_mae_pp"),
    "task_subset_additive": g(ts, "naive_additive", "run_mae_pp"),
    "task_subset_noise_floor": g(ts, "refit", "noise_floor_pp"),
    "task_completed_refit": g(ts, "refit", "completed_run_mae_pp"),
    "task_completed_run_mean": g(ts, "naive_run_mean", "completed_run_mae_pp"),
    "task_completed_additive": g(ts, "naive_additive", "completed_run_mae_pp"),
    "cell_refit": g(cs, "refit", "run_mae_pp"),
    "task_brier_refit": g(ts, "refit", "brier"), "cell_brier_refit": g(cs, "refit", "brier"),
    "task_auc_refit": g(ts, "refit", "auc"), "cell_auc_refit": g(cs, "refit", "auc"),
})
# rough systematic component: subset MAE with the sampling noise removed in quadrature (approximation)
cmp["task_subset_refit_excess"] = np.sqrt(np.maximum(cmp.task_subset_refit**2 - cmp.task_subset_noise_floor**2, 0))
cmp.round(3).to_csv("results/part2_task/main/comparison.csv", index=False)

# ---- per benchmark at each fraction ---------------------------------------------------------------
p = pd.read_csv("results/part2_task/main/holdout_per_run.csv")
for c in ["pred", "pred_run", "pred_add", "pred_full"]:
    p["e_" + c] = 100 * (p[c] - p.obs).abs()
pb = p.groupby(["frac", "benchmark"]).agg(
    heldout_tasks_per_run=("n", "mean"), refit=("e_pred", "mean"), run_subsample=("e_pred_run", "mean"),
    additive=("e_pred_add", "mean"), full_model=("e_pred_full", "mean"), noise_floor=("noise_pp", "mean")).reset_index()
pb.round(2).to_csv("results/part2_task/main/per_benchmark.csv", index=False)
open("results/part2_task/main/per_benchmark.md", "w").write(
    pb[pb.frac == 0.25].drop(columns="frac").round(1).to_markdown(index=False) + "\n")

# ---- figure: two panels -----------------------------------------------------------------------------
fig, (a1, a2) = plt.subplots(1, 2, figsize=(10.5, 4.3))
x = np.array(FR) * 100
# left: error on the held-out tasks of each run
a1.fill_between(x, 0, cmp.task_subset_noise_floor, color=GRID, lw=0, zorder=1)
a1.text(30, 1.0, "sampling-noise floor:\na perfect p would still\nmiss by this much", fontsize=8, color=INK2, va="bottom")
for col, lab, c, mk in [("task_subset_run_mean", "Run's own accuracy on its other tasks", ORANGE, "D"),
                        ("task_subset_refit", "GLMM refit", BLUE, "o")]:
    a1.plot(x, cmp[col], color=c, lw=2, marker=mk, ms=7, mec=SURFACE, mew=1.5, zorder=3, label=lab)
a1.set_xticks(x); a1.set_xticklabels([f"{int(v)}%" for v in x]); a1.set_xlim(7, 53)
a1.set_ylim(0, 13.5); a1.set_xlabel("Share of task scores held out"); a1.set_ylabel("Run accuracy MAE (pp)")
a1.set_title("Accuracy on each run's held-out tasks", loc="left")
a1.legend(loc="upper right", fontsize=8)
# right: error in the run's full accuracy, task holdout (completed) vs cell holdout (predicted outright)
w = 0.27; xc = np.arange(3)
for k, (col, lab, c) in enumerate([("task_completed_refit", "Task holdout: observed + GLMM-filled tasks", BLUE),
                                   ("task_completed_run_mean", "Task holdout: observed tasks only (subsample)", ORANGE),
                                   ("cell_refit", "Cell holdout: whole run predicted by GLMM", AQUA)]):
    xs = xc + (k - 1) * w
    a2.bar(xs, cmp[col], width=w - 0.03, color=c, zorder=3, label=lab)
    for xi, v in zip(xs, cmp[col]):
        a2.text(xi, v + 0.15, f"{v:.1f}", ha="center", fontsize=7.5, color=INK2)
a2.set_xticks(xc); a2.set_xticklabels([f"{int(v)}%" for v in x])
a2.set_xlabel("Share held out (task scores, or whole cells)"); a2.set_ylabel("Error in full run accuracy (pp)")
a2.set_title("Error in each run's full-benchmark accuracy", loc="left"); a2.grid(axis="x", visible=False)
a2.legend(loc="upper left", fontsize=7.5); a2.set_ylim(0, 11)
fig.suptitle("Task-level holdout: most remaining error is sampling noise; the GLMM beats subsampling only modestly",
             x=0.01, ha="left", fontweight="bold", fontsize=11)
fig.text(0.01, 0.01, f"Primary design {SEL}, 20 random holdouts per fraction. Left: |mean predicted − observed| over the run's held-out tasks only. "
         "Right: run accuracy over all its tasks.", fontsize=7.5, color=INK2)
fig.subplots_adjust(left=0.06, right=0.99, bottom=0.17, top=0.86, wspace=0.22)
fig.savefig(f"{OUT}/task_holdout_error.png", dpi=170); plt.close(fig)

print(cmp.round(2).to_string(index=False))
print(pb[pb.frac == 0.25].round(1).to_string(index=False))
