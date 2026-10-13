"""Per-task timing from HAL's per-call Weave logs (raw_logging_results), for Extension 2 (AUDIT.md M2).

HAL's results.latencies[task].total_time is last_call.started_at - first_call.started_at. It leaves out the duration
of the last LLM call, so a single-call task records ~0 s. This script streams each zip again, decrypts it, and
summarises every logged call by weave_task_id:
  span_s      = max(ended_at) - min(started_at)   first LLM call start to last LLM call end (the E2 outcome)
  llm_time_s  = sum of the calls' own durations   (ended_at - started_at; overlapping calls are counted twice)
  n_calls     = number of logged calls for the task
  hal_total_s = HAL's total_time, kept for comparison
Calls without a task id are counted per run in `untagged_calls`.

Usage: [HAL_REVISION=<commit>] python -I extract_call_timing.py <zip_list.txt> <out_dir> <tmp_dir> [n_workers]
  writes <out_dir>/<zip stem>.csv.gz per zip (cached), then concatenate with --merge <out_dir> <out.csv.gz>
"""
import base64, csv, glob, gzip, json, os, sys, time, urllib.request, zipfile
from concurrent.futures import ProcessPoolExecutor, as_completed
from datetime import datetime
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

BASE = "https://huggingface.co/datasets/agent-evals/hal_traces/resolve/%s/"
REVISION = os.environ.get("HAL_REVISION", "main")
COLS = ["source_file", "task_id", "n_calls", "span_s", "llm_time_s", "hal_total_s", "untagged_calls"]


def decrypt(blob):
    kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=base64.b64decode(blob["salt"]), iterations=480000)
    return json.loads(Fernet(base64.urlsafe_b64encode(kdf.derive(b"hal1234"))).decrypt(base64.b64decode(blob["encrypted_data"])))


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp() if isinstance(s, str) else None


def summarise(name, d):
    calls = d.get("raw_logging_results") or []
    if isinstance(calls, dict):
        calls = calls.get("calls") or list(calls.values())
    lat = ((d.get("results") or {}).get("latencies")) or {}
    per, untagged = {}, 0
    for c in calls:
        if not isinstance(c, dict):
            continue
        t = c.get("weave_task_id") or ((c.get("attributes") or {}).get("weave_task_id"))
        s, e = ts(c.get("started_at")), ts(c.get("ended_at"))
        if t is None or s is None:
            untagged += 1
            continue
        p = per.setdefault(str(t), [0, s, s, 0.0])
        p[0] += 1
        p[1] = min(p[1], s)
        p[2] = max(p[2], e if e is not None else s)
        p[3] += (e - s) if e is not None else 0.0
    rows = []
    for t in sorted(set(per) | set(map(str, lat))):
        p = per.get(t)
        hl = lat.get(t) if isinstance(lat, dict) else None
        rows.append([name, t, p[0] if p else 0, (p[2] - p[1]) if p else "", p[3] if p else "",
                     hl.get("total_time") if isinstance(hl, dict) else "", untagged])
    return rows


def process(name, out_dir, tmp_dir):
    out = os.path.join(out_dir, name.replace(".zip", ".csv.gz"))
    if os.path.exists(out):
        return name, "cached"
    tmp = os.path.join(tmp_dir, name)
    for attempt in range(4):
        try:
            urllib.request.urlretrieve((BASE % REVISION) + name, tmp)
            break
        except Exception as e:
            if attempt == 3:
                return name, f"download failed: {e}"
            time.sleep(10 * (attempt + 1))
    try:
        rows = []
        with zipfile.ZipFile(tmp) as z:
            for m in z.namelist():
                blob = json.loads(z.read(m))
                d = decrypt(blob) if isinstance(blob, dict) and "encrypted_data" in blob else blob
                del blob
                if isinstance(d, dict):
                    rows += summarise(name, d)
                del d
        with gzip.open(out + ".part", "wt", newline="") as f:
            w = csv.writer(f)
            w.writerow(COLS)
            w.writerows(rows)
        os.replace(out + ".part", out)
        return name, f"ok {len(rows)} tasks"
    except Exception as e:
        return name, f"error: {type(e).__name__}: {e}"
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def merge(out_dir, out_file):
    with gzip.open(out_file, "wt", newline="") as fo:
        w = csv.writer(fo)
        w.writerow(COLS)
        for f in sorted(glob.glob(os.path.join(out_dir, "*.csv.gz"))):
            r = csv.reader(gzip.open(f, "rt"))
            next(r)
            w.writerows(r)


if __name__ == "__main__":
    if sys.argv[1] == "--merge":
        merge(sys.argv[2], sys.argv[3])
        sys.exit(0)
    lst, out_dir, tmp_dir = sys.argv[1:4]
    n = int(sys.argv[4]) if len(sys.argv) > 4 else 8
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(tmp_dir, exist_ok=True)
    names = open(lst).read().split()
    with ProcessPoolExecutor(n) as ex:
        futs = [ex.submit(process, x, out_dir, tmp_dir) for x in names]
        for i, fu in enumerate(as_completed(futs)):
            name, status = fu.result()
            print(f"[{i+1}/{len(futs)}] {status} {name}", flush=True)
