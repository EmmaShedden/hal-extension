"""Join task rows + run metadata (hf_runs.csv) + model metadata (Epoch) into the analysis table.

Usage: python build_analysis_table.py   (paths are fixed relative to repo root)
Outputs: data/processed/runs.csv, data/processed/tasks.csv.gz, data/processed/model_meta.csv
"""
import csv, gzip, os, collections
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = lambda *a: os.path.join(ROOT, *a)

# canonical HAL model -> Epoch model_metadata.csv model_version (join key only; values come from Epoch)
EPOCH_KEY = {
    "claude-3.7-sonnet": "claude-3-7-sonnet-20250219", "claude-opus-4": "claude-opus-4-20250514",
    "claude-opus-4.1": "claude-opus-4-1-20250805", "claude-sonnet-4": "claude-sonnet-4-20250514",
    "claude-sonnet-4.5": "claude-sonnet-4-5-20250929", "claude-haiku-4.5": "claude-haiku-4-5-20251001",
    "claude-opus-4.5": "claude-opus-4-5-20251101",
    "gpt-4.1": "gpt-4.1-2025-04-14", "gpt-5": "gpt-5-2025-08-07_medium", "o3": "o3-2025-04-16_medium",
    "o4-mini": "o4-mini-2025-04-16_medium", "o3-mini": "o3-mini-2025-01-31_medium", "gpt-oss-120b": "gpt-oss-120b",
    "gpt-4o": "gpt-4o-2024-11-20",
    "deepseek-v3": "DeepSeek-V3", "deepseek-r1": "DeepSeek-R1", "deepseek-r1-0528": "DeepSeek-R1-0528",
    "deepseek-v3.1": "DeepSeek-V3.1", "gemini-2.0-flash": "gemini-2.0-flash-001",
    "gemini-2.5-pro-preview": "gemini-2.5-pro-preview-03-25", "gemini-2.5-pro": "gemini-2.5-pro",
}
DOMAIN = {"SWE-bench Verified Mini": "coding", "USACO": "coding", "SciCode": "coding",
          "CORE-Bench Hard": "science", "ScienceAgentBench": "science", "GAIA": "web",
          "Online Mind2Web": "web", "TAU-bench Airline": "customer_service", "AssistantBench": "web",
          "ColBench": "coding"}
CUTOFF = "2025-10-08"


def main():
    os.makedirs(P("data/processed"), exist_ok=True)
    epoch = {r["model_version"]: r for r in csv.DictReader(open(P("data/external/epoch/benchmark_data/model_metadata.csv")))}
    meta = {r["filename"]: r for r in csv.DictReader(open(P("data/meta/hf_runs.csv")))}
    ext = {r["source_file"]: r for r in csv.DictReader(open(P("data/processed/extracted_runs.csv")))}

    models = sorted({m["model_canonical"] for m in meta.values() if m["model_canonical"] not in ("", "unknown")})
    mm = {}
    for m in models:
        e = epoch.get(EPOCH_KEY.get(m, ""), {})
        mm[m] = {"model": m, "epoch_key": EPOCH_KEY.get(m, ""), "release_date": e.get("date", ""),
                 "epoch_org": e.get("organization", "")}
    with open(P("data/processed/model_meta.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["model", "epoch_key", "release_date", "epoch_org"]); w.writeheader(); w.writerows(mm.values())

    runs = []
    for fn, m in meta.items():
        e = ext.get(fn)
        if e is None:
            continue
        run_acc = None
        if e["n_success"] and e["n_fail"]:
            ns, nf = int(e["n_success"]), int(e["n_fail"]); run_acc = ns / (ns + nf) if ns + nf else None
        upload = m["hf_first_upload"]
        if m["in_paper"] == "TRUE":
            split = "paper"
        elif (m["in_paper"] == "FALSE" and upload > CUTOFF and m["benchmark"] in DOMAIN and m["benchmark"] not in ("ColBench", "AssistantBench")
              and m["model_canonical"] not in ("", "unknown") and "few" not in m["scaffold"].lower()):
            split = "post_paper"
        elif m["in_paper"] == "UNSURE":
            split = "unsure"
        else:
            split = "unused"
        runs.append({
            "source_file": fn, "split": split, "benchmark": m["benchmark"], "domain": DOMAIN.get(m["benchmark"], ""),
            "scaffold": m["scaffold"], "model": m["model_canonical"], "provider": m["provider"],
            "reasoning_model": m["reasoning_capable"], "effort": m["effort"] or "default",
            "release_date": mm.get(m["model_canonical"], {}).get("release_date", ""),
            "paper_acc_pct": m["paper_acc_pct"], "hal_lb_acc_pct": m["hal_lb_acc_pct"],
            "extracted_acc_pct": round(100 * run_acc, 2) if run_acc is not None else "",
            "reported_accuracy": e["reported_accuracy"], "reported_average_score": e["reported_average_score"],
            "n_tasks": (int(e["n_success"]) + int(e["n_fail"])) if e["n_success"] and e["n_fail"] else "",
            "n_latencies": e["n_latencies"], "total_cost": e["total_cost"], "hf_first_upload": upload,
        })
    with open(P("data/processed/runs.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(runs[0].keys())); w.writeheader(); w.writerows(runs)
    print(collections.Counter(r["split"] for r in runs))
    keep = {r["source_file"] for r in runs if r["split"] in ("paper", "post_paper", "unsure")}
    n = 0
    with gzip.open(P("data/processed/extracted_tasks.csv.gz"), "rt") as fi, gzip.open(P("data/processed/tasks.csv.gz"), "wt", newline="") as fo:
        r = csv.reader(fi); w = csv.writer(fo); w.writerow(next(r))
        for row in r:
            if row[0] in keep:
                w.writerow(row); n += 1
    print("task rows kept", n)


if __name__ == "__main__":
    main()
