"""Context for the pp-MAE numbers: distribution of HAL scores and error comparisons.
Writes results/figures/*.png and results/context_stats.csv / .md.
Palette: reference dataviz palette, light mode, slots 1-3 (validated all-pairs for light surface).
"""
import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

OUT = "results/figures"
os.makedirs(OUT, exist_ok=True)
SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
BLUE, ORANGE, AQUA = "#2a78d6", "#eb6834", "#1baf7a"
plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": GRID, "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "text.color": INK, "font.size": 10, "axes.titlesize": 11, "axes.titleweight": "bold",
    "axes.spines.top": False, "axes.spines.right": False, "axes.grid": True, "grid.color": GRID,
    "grid.linewidth": 0.8, "axes.axisbelow": True, "legend.frameon": False,
})

# ---- data -----------------------------------------------------------------------------------
runs = pd.read_csv("data/processed/runs.csv")
tasks = pd.read_csv("data/processed/tasks.csv.gz", dtype={"task_id": str})
fit = pd.read_csv("results/part1/run_level_fit.csv")            # paper runs used in the model (174)
paper = fit[["run", "benchmark", "obs", "pred"]].copy()
paper["acc"] = 100 * paper.obs
ho = pd.read_csv("results/part2/main/holdout_per_run.csv")
ho["err"] = 100 * (ho.pred - ho.obs).abs()
hm = pd.read_csv("results/part2/main/holdout_metrics.csv")

order = paper.groupby("benchmark").acc.median().sort_values().index.tolist()

# ---- context statistics ---------------------------------------------------------------------
def stats(g):
    a = g.acc
    return pd.Series({
        "runs": len(a), "mean_acc": a.mean(), "sd_acc": a.std(), "min": a.min(), "q25": a.quantile(.25),
        "median": a.median(), "q75": a.quantile(.75), "max": a.max(),
        "mad_from_bench_mean": (a - a.mean()).abs().mean(),
    })
st = paper.groupby("benchmark").apply(stats).reindex(order)
allrow = stats(paper); allrow.name = "ALL"
# for ALL, spread is measured around each run's own benchmark mean (what a benchmark-average guess would miss by)
allrow["mad_from_bench_mean"] = (paper.acc - paper.groupby("benchmark").acc.transform("mean")).abs().mean()
st = pd.concat([st, allrow.to_frame().T])
# per-benchmark holdout error (refit, pooled over fractions and reps) and in-sample error
st["holdout_refit_mae"] = ho.groupby("benchmark").err.mean().reindex(st.index)
st.loc["ALL", "holdout_refit_mae"] = ho.err.mean()
fit["err"] = 100 * (fit.pred - fit.obs).abs()
st["insample_mae"] = fit.groupby("benchmark").err.mean().reindex(st.index)
st.loc["ALL", "insample_mae"] = fit.err.mean()
# ratio: how much of the naive spread the refit removes
st["refit_over_naive"] = st.holdout_refit_mae / st.mad_from_bench_mean
st.round(2).to_csv("results/context_stats.csv")
open("results/context_stats.md", "w").write(st.round(1).reset_index().rename(columns={"index": "benchmark"}).to_markdown(index=False) + "\n")

# task solve rates: share of paper runs solving each task
tp = tasks.merge(runs[["source_file", "benchmark", "split"]], on="source_file")
tp = tp[(tp.split == "paper") & (tp.benchmark != "AssistantBench") & tp.source_file.isin(fit.run)]
sr = tp.groupby(["benchmark", "task_id"]).success.agg(["mean", "size"]).reset_index()
sr_summary = sr.groupby("benchmark").agg(
    tasks=("mean", "size"), never_solved=("mean", lambda x: (x == 0).mean() * 100),
    always_solved=("mean", lambda x: (x == 1).mean() * 100)).reindex(order)
sr_summary.round(1).to_csv("results/task_solve_rate_summary.csv")

# ---- F1: run accuracy distribution by benchmark (strip + median) ----------------------------
fig, ax = plt.subplots(figsize=(8, 4.6))
rng = np.random.default_rng(0)
for i, b in enumerate(order):
    a = paper.loc[paper.benchmark == b, "acc"].values
    y = i + rng.uniform(-0.18, 0.18, len(a))
    ax.scatter(a, y, s=26, color=BLUE, alpha=0.75, edgecolor=SURFACE, linewidth=1.2, zorder=3)
    med = np.median(a)
    ax.plot([med, med], [i - 0.32, i + 0.32], color=INK, lw=2, zorder=4, solid_capstyle="round")
    ax.text(101, i, f"median {med:.0f}%  ·  SD {a.std(ddof=1):.0f} pp", va="center", fontsize=8.5, color=INK2)
ax.set_yticks(range(len(order))); ax.set_yticklabels(order)
ax.set_xlim(0, 100); ax.set_xlabel("Run accuracy (%)  —  one dot per paper run")
ax.grid(axis="y", visible=False)
ax.set_title(f"HAL run accuracies span 0–{paper.acc.max():.0f}%; three-quarters are below {paper.acc.quantile(.75):.0f}%", loc="left")
fig.text(0.01, 0.01, f"174 paper runs (AssistantBench excluded). Overall mean {paper.acc.mean():.1f}%, SD {paper.acc.std():.1f} pp. Black tick = median.",
         fontsize=8, color=INK2)
fig.subplots_adjust(left=0.24, right=0.74, bottom=0.17, top=0.9)
fig.savefig(f"{OUT}/run_accuracy_by_benchmark.png", dpi=170); plt.close(fig)

# ---- F2: error in context, per benchmark (dot plot, 3 series) --------------------------------
rows = order + ["ALL"]
fig, ax = plt.subplots(figsize=(8, 4.8))
series = [("In-sample (full-data model)", "insample_mae", AQUA, "o"),
          ("Held-out refit", "holdout_refit_mae", BLUE, "o"),
          ("Naive: guess the benchmark mean", "mad_from_bench_mean", ORANGE, "D")]
for i, b in enumerate(rows):
    vals = [st.loc[b, c] for _, c, _, _ in series]
    ax.plot([min(vals), max(vals)], [i, i], color=GRID, lw=2, zorder=1)
    for (lab, c, col, mk) in series:
        ax.scatter(st.loc[b, c], i, s=60, color=col, marker=mk, edgecolor=SURFACE, linewidth=1.6, zorder=3, label=lab if i == 0 else None)
ax.set_yticks(range(len(rows))); ax.set_yticklabels(order + ["All benchmarks"])
ax.get_yticklabels()[-1].set_fontweight("bold")
ax.axhline(len(order) - 0.5, color=INK2, lw=0.8)
ax.set_xlabel("Mean absolute error in run accuracy (pp)")
ax.set_xlim(0, max(st[[c for _, c, _, _ in series]].max()) * 1.08)
ax.grid(axis="y", visible=False)
ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.13), ncol=3, fontsize=8.5, handletextpad=0.3)
ax.set_title("Refit beats the naive guess overall, not on every benchmark", loc="left")
fig.text(0.01, 0.01, "Naive = mean |run accuracy − its benchmark's mean accuracy| (in-sample, so slightly optimistic). Held-out refit pooled over 10/25/50% holdouts.", fontsize=7.5, color=INK2)
fig.subplots_adjust(left=0.24, right=0.97, bottom=0.24, top=0.9)
fig.savefig(f"{OUT}/error_in_context.png", dpi=170); plt.close(fig)

# ---- F3: predicted vs observed held-out run accuracy (small multiples by fraction) ----------
fig, axes = plt.subplots(1, 3, figsize=(10, 3.8), sharex=True, sharey=True)
for ax, f in zip(axes, [0.10, 0.25, 0.50]):
    h = ho[ho.frac == f]
    x = np.linspace(0, 100, 2)
    ax.fill_between(x, x - 7.5, x + 7.5, color=GRID, alpha=0.7, lw=0, zorder=1)
    ax.plot(x, x, color=INK2, lw=1, zorder=2)
    ax.scatter(100 * h.obs, 100 * h.pred, s=12, color=BLUE, alpha=0.35, lw=0, zorder=3)
    mae = h.err.mean(); within = (h.err <= 7.5).mean() * 100
    ax.set_title(f"{int(f*100)}% of cells held out", loc="left", fontsize=10)
    ax.text(3, 93, f"MAE {mae:.1f} pp\n{within:.0f}% of runs within ±7.5 pp", fontsize=8.5, va="top", color=INK)
    ax.set_xlim(0, 100); ax.set_ylim(0, 100); ax.set_aspect("equal")
    ax.set_xlabel("Observed accuracy (%)")
axes[0].set_ylabel("Predicted accuracy (%)")
fig.suptitle("Held-out runs: predicted vs observed (20 repetitions each; gray band = ±7.5 pp)", x=0.01, ha="left", fontweight="bold", fontsize=11)
fig.subplots_adjust(left=0.07, right=0.99, bottom=0.15, top=0.84, wspace=0.12)
fig.savefig(f"{OUT}/holdout_pred_vs_obs.png", dpi=170); plt.close(fig)

# ---- F4: per-task solve-rate distribution (small multiples per benchmark) --------------------
fig, axes = plt.subplots(2, 4, figsize=(11, 5.2), sharex=True)
bins = np.linspace(0, 1, 11)
for ax, b in zip(axes.flat, order):
    v = sr.loc[sr.benchmark == b, "mean"].values
    w = np.ones_like(v) * 100 / len(v)
    ax.hist(v, bins=bins, weights=w, color=BLUE, edgecolor=SURFACE, linewidth=2, zorder=3)
    ax.set_title(f"{b.replace(' Verified Mini', ' VM')} ({len(v)})", loc="left", fontsize=9)
    ax.set_xticks([0, 0.5, 1]); ax.set_xticklabels(["0%", "50%", "100%"])
    ax.text(0.98, 0.95, f"{(v == 0).mean()*100:.0f}% never solved", transform=ax.transAxes, ha="right", va="top", fontsize=8, color=INK2)
    ax.grid(axis="x", visible=False)
fig.supxlabel("Share of paper runs that solved the task (panel title: benchmark, number of tasks)", fontsize=9.5, color=INK2)
for ax in axes[:, 0]: ax.set_ylabel("% of tasks")
fig.suptitle("Task solve rates are skewed: many tasks are never solved, few are solved by most runs", x=0.01, ha="left", fontweight="bold", fontsize=11)
fig.subplots_adjust(left=0.07, right=0.98, bottom=0.13, top=0.86, hspace=0.45, wspace=0.28)
fig.savefig(f"{OUT}/task_solve_rates.png", dpi=170); plt.close(fig)

print(st.round(1).to_string()); print(sr_summary.round(1).to_string())
print("holdout: share of runs within 5/7.5/10 pp:", [(ho.err <= t).mean().round(3) for t in (5, 7.5, 10)])
