# Cell-holdout error stratified by what the training set knows about the held-out cell's model x scaffold.
# Usage: python3 -I audit/a4_holdout_by_sibling.py   (from repo root)
import csv, collections, statistics as st
rows = list(csv.DictReader(open('results/part2/main/holdout_per_run.csv')))
allcells = set(r['cell'] for r in csv.DictReader(open('results/part1/run_level_fit.csv')))
by = collections.defaultdict(list)
for r in rows: by[(r['frac'], r['rep'])].append(r)
out = collections.defaultdict(list)
for k, rs in by.items():
    train = allcells - set(r['cell'] for r in rs)
    for r in rs:
        m, s, b, e = r['cell'].split('|')
        if any(c.split('|')[:3] == [m, s, b] for c in train): cat = 'other effort of same model/scaffold/benchmark in train'
        elif any(c.split('|')[0] == m and c.split('|')[1] == s for c in train): cat = 'same model+scaffold on another benchmark in train'
        else: cat = 'no same model+scaffold in train'
        out[(k[0], cat)].append(float(r['abs_err_pp']))
for k in sorted(out): print(k, len(out[k]), round(st.mean(out[k]), 2))
