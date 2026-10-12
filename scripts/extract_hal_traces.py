"""Stream each HAL trace zip from HuggingFace, decrypt (public password from hal-harness
hal/utils/upload.py), and keep only config/results/raw_eval_results/usage. Long strings are
truncated so per-task scores and metadata survive but raw agent logs (the bulk) are dropped.

Usage: [HAL_REVISION=<commit>] [HAL_ONLY=<list.txt>] python -I extract_hal_traces.py <hf_tree.json> <out_dir> <tmp_dir> [n_workers]
"""
import base64, gzip, json, os, sys, time, urllib.request, zipfile
from concurrent.futures import ProcessPoolExecutor, as_completed
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

BASE = "https://huggingface.co/datasets/agent-evals/hal_traces/resolve/%s/"
REVISION = os.environ.get("HAL_REVISION", "main")  # paper snapshot: 1bf4166d052cdd3445127e17c15139cbb5505ca5
KEEP = ["config", "results", "raw_eval_results", "total_usage", "total_cost", "git_info"]
MAXSTR = 2000


def trunc(o):
    if isinstance(o, str):
        return o if len(o) <= MAXSTR else o[:MAXSTR] + f"...[truncated {len(o)}]"
    if isinstance(o, dict):
        return {k: trunc(v) for k, v in o.items()}
    if isinstance(o, list):
        return [trunc(v) for v in o]
    return o


def decrypt(blob):
    salt = base64.b64decode(blob["salt"])
    kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=480000)
    key = base64.urlsafe_b64encode(kdf.derive(b"hal1234"))
    return json.loads(Fernet(key).decrypt(base64.b64decode(blob["encrypted_data"])))


def process(name, out_dir, tmp_dir):
    out = os.path.join(out_dir, name.replace("_UPLOAD.zip", ".json.gz"))
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
        rec = {"source_file": name}
        with zipfile.ZipFile(tmp) as z:
            members = z.namelist()
            rec["members"] = members
            for m in members:
                blob = json.loads(z.read(m))
                if isinstance(blob, dict) and "encrypted_data" in blob:
                    d = decrypt(blob)
                else:
                    d = blob
                del blob
                if isinstance(d, dict):
                    rec.setdefault("payloads", []).append(
                        {"member": m, "top_keys": list(d.keys()), **{k: trunc(d[k]) for k in KEEP if k in d}}
                    )
                del d
        with gzip.open(out + ".part", "wt") as f:
            json.dump(rec, f)
        os.replace(out + ".part", out)
        return name, "ok"
    except Exception as e:
        return name, f"error: {type(e).__name__}: {e}"
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


if __name__ == "__main__":
    tree, out_dir, tmp_dir = sys.argv[1:4]
    n = int(sys.argv[4]) if len(sys.argv) > 4 else 8
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(tmp_dir, exist_ok=True)
    files = sorted((x for x in json.load(open(tree)) if x["path"].endswith(".zip")), key=lambda x: x["size"])
    only = os.environ.get("HAL_ONLY")  # optional file with one zip name per line
    if only:
        keep = set(open(only).read().split())
        files = [x for x in files if x["path"] in keep]
    with ProcessPoolExecutor(n) as ex:
        futs = [ex.submit(process, x["path"], out_dir, tmp_dir) for x in files]
        for i, fu in enumerate(as_completed(futs)):
            name, status = fu.result()
            print(f"[{i+1}/{len(futs)}] {status} {name}", flush=True)
