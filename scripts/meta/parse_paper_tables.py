"""Parse the HAL paper's appendix full-results tables (arXiv 2510.11977v1 LaTeX source, tables/*_full_results.tex).

Usage: python -I parse_paper_tables.py <tables_dir> <out_csv>
"""
import csv, os, re, sys

PAGE = {'assistantbench': 'assistantbench', 'corebench_hard': 'corebench_hard', 'gaia': 'gaia',
        'online_mind2web': 'online_mind2web', 'scicode': 'scicode', 'scienceagentbench': 'scienceagentbench',
        'swebench_verified_mini': 'swebench_verified_mini', 'taubench_airline': 'taubench_airline', 'usaco': 'usaco'}

rows = []
d = sys.argv[1]
for fn in sorted(os.listdir(d)):
    m = re.match(r'(.*)_full_results\.tex$', fn)
    if not m:
        continue
    for line in open(os.path.join(d, fn)):
        parts = [p.strip() for p in line.strip().rstrip('\\').split('&')]
        if len(parts) != 5 or parts[0] == 'Scaffold':
            continue
        acc = re.match(r'([\d.]+)\\%', parts[2]).group(1)
        cost = re.match(r'\\\$([\d.]+)', parts[3]).group(1)
        rows.append(dict(page=PAGE[m.group(1)], scaffold=parts[0], model=parts[1], paper_acc_pct=acc,
                         paper_cost_usd=cost, paper_pareto=(parts[4] == 'Yes')))
with open(sys.argv[2], 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
print(len(rows), 'paper rows')
