"""Build the run x task long table from decrypted HAL summaries.

Outcome = HAL's own per-task success flag (results.successful_tasks / failed_tasks), which is what
HAL's headline accuracy is computed from for every benchmark except AssistantBench (whose headline is
average partial score; its per-task partial scores are stored without task ids, see DESIGN.md).
Latency = results.latencies[task].total_time (seconds) when present.

ScienceAgentBench has no id lists; its per-task success is raw_eval_results.eval_result[task].success_rate.
Tasks missing from a run's lists (agent errors) are counted as failures when that is how HAL's reported
accuracy was computed (reported accuracy == n_success / |benchmark task universe|); `filled_missing` records this.
The task universe is the union of task ids over all runs of the benchmark.

Usage: python build_task_table.py <out_runs.csv> <out_tasks.csv.gz> <hal_slim_dir> [<override_dir> ...]
       files in later dirs replace same-named files from earlier dirs (paper-revision zips)
"""
import csv, glob, gzip, json, os, sys


def as_ids(x):
    if isinstance(x, list):
        return [str(t) for t in x]
    return None


def task_lists(p):
    res = p.get("results", {}) or {}
    succ, fail = as_ids(res.get("successful_tasks")), as_ids(res.get("failed_tasks"))
    rer = p.get("raw_eval_results")
    if (succ is None or fail is None) and isinstance(rer, dict) and isinstance(rer.get("eval_result"), dict):
        er = rer["eval_result"]
        succ = [t for t, v in er.items() if isinstance(v, dict) and v.get("success_rate") == 1]
        fail = [t for t, v in er.items() if isinstance(v, dict) and v.get("success_rate") != 1]
    return succ, fail


def main(out_runs, out_tasks, *src_dirs):
    files = {}
    for src in src_dirs:
        for f in glob.glob(os.path.join(src, "*.json.gz")):
            files[os.path.basename(f)] = f
    recs = []
    for name in sorted(files):
        rec = json.load(gzip.open(files[name]))
        rec["_dir"] = os.path.dirname(files[name])
        recs.append(rec)
    universe = {}
    for rec in recs:
        for p in rec.get("payloads", []):
            s_, f_ = task_lists(p)
            b = (p.get("config", {}) or {}).get("benchmark_name")
            if s_ is not None and f_ is not None:
                universe.setdefault(b, set()).update(s_ + f_)
    runs, n_rows = [], 0
    with gzip.open(out_tasks, "wt", newline="") as ft:
        wt = csv.writer(ft)
        wt.writerow(["source_file", "task_id", "success", "latency_s"])
        for rec in recs:
            for p in rec.get("payloads", []):
                cfg, res = p.get("config", {}) or {}, p.get("results", {}) or {}
                args = cfg.get("agent_args", {}) or {}
                succ, fail = task_lists(p)
                filled = 0
                rep = res.get("accuracy", res.get("success_rate"))
                U = universe.get(cfg.get("benchmark_name"), set())
                if succ is not None and fail is not None and isinstance(rep, (int, float)) and U:
                    listed = set(succ) | set(fail)
                    missing = sorted(U - listed)
                    if missing and abs(rep - len(succ) / len(U)) < abs(rep - len(succ) / max(len(listed), 1)):
                        fail = fail + missing
                        filled = len(missing)
                lat = res.get("latencies") or {}
                row = {
                    "source_file": rec["source_file"],
                    "run_id": cfg.get("run_id"),
                    "benchmark_name": cfg.get("benchmark_name"),
                    "agent_name": cfg.get("agent_name"),
                    "date": cfg.get("date"),
                    "model_name_arg": args.get("model_name"),
                    "reasoning_effort_arg": args.get("reasoning_effort"),
                    "agent_args_json": json.dumps(args, sort_keys=True),
                    "reported_accuracy": res.get("accuracy", res.get("success_rate")),
                    "reported_average_score": res.get("average_score"),
                    "total_cost": p.get("total_cost", res.get("total_cost")),
                    "n_success": len(succ) if succ is not None else None,
                    "n_fail": len(fail) if fail is not None else None,
                    "has_task_ids": succ is not None and fail is not None,
                    "n_latencies": len(lat),
                    "filled_missing": filled,
                    "source_dir": os.path.basename(rec["_dir"]),
                    "usage_models": ";".join(sorted((p.get("total_usage") or {}).keys())),
                }
                runs.append(row)
                if succ is None or fail is None:
                    continue
                for ok, ids in ((1, succ), (0, fail)):
                    for t in ids:
                        tl = lat.get(t) if isinstance(lat, dict) else None
                        wt.writerow([rec["source_file"], t, ok, tl.get("total_time") if isinstance(tl, dict) else ""])
                        n_rows += 1
    with open(out_runs, "w", newline="") as fr:
        w = csv.DictWriter(fr, fieldnames=list(runs[0].keys()))
        w.writeheader()
        w.writerows(runs)
    print(f"{len(runs)} runs, {n_rows} task rows")


if __name__ == "__main__":
    main(*sys.argv[1:])
