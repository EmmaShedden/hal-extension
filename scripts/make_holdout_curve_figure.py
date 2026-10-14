"""Part 2c figure and table: cell-holdout run-accuracy MAE vs holdout fraction (DESIGN.md "Part 2c").
Reads results/part2_curve/; writes results/figures/holdout_curve_mae.png and results/tables/holdout_curve.md.
Palette: reference dataviz palette, light mode, categorical slots 1-5 in fixed order (adjacent pairlist);
references (full-data model, noise floor) in secondary ink. Every series also has its own marker and a direct label.
"""
import os
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

IN, OUT, TAB = "results/part2_curve", "results/figures", "results/tables"
os.makedirs(OUT, exist_ok=True); os.makedirs(TAB, exist_ok=True)
SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": GRID, "axes.labelcolor": INK2, "xtick.color": INK2, "ytick.color": INK2,
    "text.color": INK, "font.size": 10, "axes.titlesize": 11, "axes.titleweight": "bold",
    "axes.spines.top": False, "axes.spines.right": False, "axes.grid": True, "grid.color": GRID,
    "grid.linewidth": 0.8, "axes.axisbelow": True, "legend.frameon": False,
})

s = pd.read_csv(f"{IN}/holdout_summary.csv")
nf = pd.read_csv(f"{IN}/noise_floor.csv").set_index("quantity").mae_pp
s["pct"] = (100 * s.frac).round().astype(int)

# (predictor, label, colour, marker, x-offset in pct points so the error bars do not overlap)
SERIES = [
    ("refit", "GLMM refit (selected formula)", "#2a78d6", "o", 0.0),
    ("naive_additive", "Additive logit: benchmark + model", "#eb6834", "s", -0.9),
    ("naive_bench_mean", "Benchmark mean of training cells", "#1baf7a", "D", 0.9),
    ("naive_model_bench", "Same model, same benchmark (else additive)", "#eda100", "^", -1.8),
    ("naive_grand_mean", "Grand mean of training cells", "#e87ba4", "v", 1.8),
]

fig, ax = plt.subplots(figsize=(10, 7.4))
YMAX = 20  # the 90 % refit mean is far above; it is drawn as a labelled off-scale arrow
for key, label, col, mk, dx in SERIES:
    g = s[s.predictor == key].sort_values("pct")
    main = key == "refit"
    ax.errorbar(g.pct + dx, g.run_mae_pp, yerr=[g.run_mae_pp - g.ci_lo, g.ci_hi - g.run_mae_pp], color=col, marker=mk,
                ms=8 if main else 6, lw=2.5 if main else 1.5, elinewidth=1.8 if main else 1.2, capsize=4 if main else 3,
                mec=SURFACE, mew=1.2, label=label, zorder=5 if main else 3)
# references: full-data model (in-sample, per split) and the model-based run-to-run noise floor
g = s[s.predictor == "full_model"].sort_values("pct")
ax.errorbar(g.pct, g.run_mae_pp, yerr=[g.run_mae_pp - g.ci_lo, g.ci_hi - g.run_mae_pp], color=INK2, ls="--", marker="x",
            ms=6, lw=1.3, capsize=3, label="Full-data model, in-sample (sees the held-out runs)", zorder=2)
ax.axhline(nf["floor_run_plus_binomial"], color=INK, ls=":", lw=1.8, zorder=1,
           label="Run-to-run noise floor: run effect + binomial (model-based)")
ax.axhline(nf["floor_binomial_only"], color=INK2, ls=":", lw=1.2, zorder=1,
           label="Binomial-only floor (task coin flips, run effect known)")

# direct labels for the reference lines at the left edge
ax.text(1, nf["floor_run_plus_binomial"] + 0.25, f"noise floor {nf['floor_run_plus_binomial']:.1f} pp", color=INK, fontsize=8.5, va="bottom")
ax.text(1, nf["floor_binomial_only"] + 0.25, f"binomial only {nf['floor_binomial_only']:.1f} pp", color=INK2, fontsize=8.5, va="bottom")

pcts = sorted(s.pct.unique())
ax.set_xticks(pcts); ax.set_xticklabels([f"{p}%" for p in pcts]); ax.set_xlim(0, 94)
ax.set_ylim(0, YMAX)
for key, label, col, mk, dx in SERIES:  # off-scale points: arrow at the top edge with the value and CI
    for _, x in s[(s.predictor == key) & (s.run_mae_pp > YMAX)].iterrows():
        ax.annotate(f"{x.pct}%: {x.run_mae_pp:.1f} pp\n[{x.ci_lo:.1f}, {x.ci_hi:.1f}]", xy=(x.pct + dx, YMAX), xytext=(x.pct + dx - 16, YMAX - 1.6),
                    color=INK, fontsize=8.5, ha="center", arrowprops=dict(arrowstyle="->", color=col, lw=1.8), zorder=6)
ax.set_xlabel("Cells held out (model × scaffold × benchmark × effort), % of 172")
ax.set_ylabel("Run-accuracy MAE on held-out runs (pp)")
nrep = s[s.predictor == "refit"].set_index("pct").n
ax.set_title("Cell-holdout error vs holdout fraction", loc="left", pad=34)
ax.text(0, 1.015, "Mean over random splits; bars = 95% CI of the mean.\nSplits per fraction: "
        + ", ".join(f"{p}%: {nrep[p]}" for p in pcts), transform=ax.transAxes, fontsize=8, color=INK2, va="bottom")
ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.11), fontsize=8.5, ncol=2)
fig.tight_layout()
fig.savefig(f"{OUT}/holdout_curve_mae.png", dpi=160)

# ---- table ------------------------------------------------------------------------------------
cols = [k for k, *_ in SERIES] + ["full_model"]
names = {"refit": "GLMM refit", "naive_additive": "Additive", "naive_bench_mean": "Benchmark mean",
         "naive_model_bench": "Same model × benchmark", "naive_grand_mean": "Grand mean", "full_model": "Full-data (in-sample)"}
r = s[s.predictor == "refit"].set_index("pct")
lines = ["| Held out | Cells | Splits | " + " | ".join(names[c] for c in cols) + " | Refit Brier | Refit AUC | Fallback fits | Mean redraws |",
         "|" + "---|" * (len(cols) + 7)]
for p in pcts:
    cells = [f"{p} %", f"{r.loc[p, 'n_held_cells']:.0f}", f"{r.loc[p, 'n']:.0f}"]
    for c in cols:
        x = s[(s.predictor == c) & (s.pct == p)].iloc[0]
        cells.append(f"{x.run_mae_pp:.2f} [{x.ci_lo:.2f}, {x.ci_hi:.2f}]")
    cells += [f"{r.loc[p, 'brier']:.3f}", f"{r.loc[p, 'auc']:.3f}", f"{r.loc[p, 'n_fallback_fit']:.0f}", f"{r.loc[p, 'mean_redraws']:.1f}"]
    lines.append("| " + " | ".join(cells) + " |")
lines += ["", "Run-accuracy MAE in pp: mean over splits [t-based 95 % CI of the mean].",
          f"Noise floor (model-based, run effect + binomial): {nf['floor_run_plus_binomial']:.2f} pp; binomial only: "
          f"{nf['floor_binomial_only']:.2f} pp; the 2 replicate-run pairs differ by {nf['replicate_pairs_mean_abs_diff']:.2f} pp on average."]
open(f"{TAB}/holdout_curve.md", "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
