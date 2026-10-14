"""Part 2c figure and table: cell-holdout run-accuracy MAE vs holdout fraction (DESIGN.md "Part 2c").
Reads results/part2_curve/; writes results/figures/holdout_curve_mae.png and results/tables/holdout_curve.md.
Default matplotlib styling (colour cycle, background, text, legend); only sizes, markers and line styles are set.
"""
import os
import pandas as pd
import matplotlib
import matplotlib.patches
matplotlib.use("Agg")
import matplotlib.pyplot as plt

IN, OUT, TAB = "results/part2_curve", "results/figures", "results/tables"
os.makedirs(OUT, exist_ok=True); os.makedirs(TAB, exist_ok=True)

s = pd.read_csv(f"{IN}/holdout_summary.csv")
nf = pd.read_csv(f"{IN}/noise_floor.csv").set_index("quantity").mae_pp
s["pct"] = (100 * s.frac).round().astype(int)

# (predictor, label, colour, marker, x-offset in pct points so the error bars do not overlap)
SERIES = [
    ("refit", "GLMER model, selected formula (mine)", "C0", "o", 0.0),
    ("naive_additive", "Linear model, logit(cell acc) ~ benchmark + LLM", "C1", "s", -0.9),
    ("naive_bench_mean", "Training avg: same benchmark", "C2", "D", 0.9),
    ("naive_model_bench", "Training avg: same benchmark, LLM (else LR)", "C3", "^", -1.8),
    ("naive_grand_mean", "Training avg (cell acc): overall", "C4", "v", 1.8),
]

fig, ax = plt.subplots(figsize=(10, 7.4))
YMAX = 20  # the 90 % refit (30.2 pp) runs off the top and is clipped; its value is printed for the text beside the figure
for key, label, col, mk, dx in SERIES:
    g = s[s.predictor == key].sort_values("pct")
    main = key == "refit"
    ax.errorbar(g.pct + dx, g.run_mae_pp, yerr=[g.run_mae_pp - g.ci_lo, g.ci_hi - g.run_mae_pp], color=col, marker=mk,
                ms=8 if main else 6, lw=2.5 if main else 1.5, elinewidth=1.8 if main else 1.2, capsize=4 if main else 3,
                label=label, zorder=5 if main else 3)
# references: full-data model (in-sample, per split) and the model-based run-to-run noise floor
g = s[s.predictor == "full_model"].sort_values("pct")
ax.errorbar(g.pct, g.run_mae_pp, yerr=[g.run_mae_pp - g.ci_lo, g.ci_hi - g.run_mae_pp], color="C5", ls="--", marker="x",
            ms=6, lw=1.3, capsize=3, label="GLMER model, full-data (in-sample)", zorder=2)
ax.axhline(nf["floor_run_plus_binomial"], color="C7", ls="-.", lw=1.8, zorder=1,
           label="Run-to-run noise floor (model based)")

# direct labels for the reference lines at the left edge
ax.text(1, nf["floor_run_plus_binomial"] + 0.25, f"noise floor {nf['floor_run_plus_binomial']:.1f} pp", fontsize=8.5, va="bottom")

pcts = sorted(s.pct.unique())
ax.set_xticks(pcts); ax.set_xticklabels([f"{p}%" for p in pcts]); ax.set_xlim(0, 94)
ax.tick_params(labelsize=12)
ax.set_ylim(0, YMAX)
off = s[(s.predictor.isin([k for k, *_ in SERIES])) & (s.run_mae_pp > YMAX)]
for _, x in off.iterrows():
    print(f"clipped (above {YMAX} pp): {x.predictor} at {x.pct}%: {x.run_mae_pp:.1f} pp [{x.ci_lo:.1f}, {x.ci_hi:.1f}]")
ax.set_xlabel("Cells held out (LLM × scaffold × benchmark × LLM settings), % of 172", fontsize=14)
ax.set_ylabel("Run-accuracy MAE on held-out runs (pp)", fontsize=14)
ax.set_title("MAE of predicted success rates on heldout cells vs holdout fraction", fontsize=16)
ax.grid(True)
# legend grouped by column (filled column-wise): left = GLMER model and its noise floor, right = linear model and training averages
ORDER = ["GLMER model, selected formula (mine)", "GLMER model, full-data (in-sample)",
         "Run-to-run noise floor (model based)", "",
         "Linear model, logit(cell acc) ~ benchmark + LLM", "Training avg (cell acc): overall",
         "Training avg: same benchmark", "Training avg: same benchmark, LLM (else LR)"]
hl = dict(zip(*reversed(ax.get_legend_handles_labels())))
hl[""] = matplotlib.patches.Rectangle((0, 0), 1, 1, visible=False)  # blank slot so the left column holds only GLMER entries
assert set(hl) == set(ORDER)
ax.legend([hl[k] for k in ORDER], ORDER, loc="upper center", bbox_to_anchor=(0.5, -0.12), fontsize=10, ncol=2)
fig.tight_layout()
fig.savefig(f"{OUT}/holdout_curve_mae.png", dpi=160)

# ---- table ------------------------------------------------------------------------------------
cols = [k for k, *_ in SERIES] + ["full_model"]
names = {"refit": "GLMER model refit", "naive_additive": "Additive", "naive_bench_mean": "Benchmark mean",
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
