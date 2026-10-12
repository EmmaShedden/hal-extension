"""Scrape HAL leaderboard pages (hal.cs.princeton.edu/<benchmark>) into a CSV.

Usage: python -I scrape_hal_leaderboard.py <html_dir> <out_csv>

Pages were fetched with e.g. `curl -s https://hal.cs.princeton.edu/taubench_airline > taubench_airline.html`.
Each leaderboard table row -> rank, scaffold, model, verified, accuracy (+min/max CI when the
row aggregates several runs), total cost (+CI), number of runs, and the HF trace zip linked
from the row (the leaderboard links only ONE zip per row, even when n_runs > 1).
"""
import csv, os, re, sys
from html.parser import HTMLParser


class P(HTMLParser):
    def __init__(self):
        super().__init__()
        self.tables, self.headers = [], []
        self.row = self.cell = self.th = None
        self.depth = 0

    def handle_starttag(self, t, a):
        a = dict(a)
        if t == 'table':
            self.depth += 1
            if self.depth == 1:
                self.tables.append([]); self.headers.append([])
        elif t == 'th' and self.depth == 1:
            self.th = []
        elif t == 'tr' and self.depth == 1:
            self.row = []
        elif t == 'td' and self.row is not None:
            self.cell = {'text': '', 'hrefs': []}
        elif t == 'a' and self.cell is not None and a.get('href'):
            self.cell['hrefs'].append(a['href'])

    def handle_endtag(self, t):
        if t == 'table':
            self.depth -= 1
        elif t == 'th' and self.th is not None:
            chunks = [c.strip() for c in self.th if c.strip()]
            self.headers[-1].append(chunks[0] if chunks else '')
            self.th = None
        elif t == 'td' and self.cell is not None:
            self.row.append(self.cell); self.cell = None
        elif t == 'tr' and self.row is not None:
            if self.row:
                self.tables[-1].append(self.row)
            self.row = None

    def handle_data(self, d):
        if self.cell is not None:
            self.cell['text'] += d
        elif self.th is not None:
            self.th.append(d)


def num(s):
    return s.replace(',', '') if s else ''


def main(html_dir, out):
    rows = []
    for fn in sorted(os.listdir(html_dir)):
        if not fn.endswith('.html'):
            continue
        bench = fn[:-5]
        p = P(); p.feed(open(os.path.join(html_dir, fn), encoding='utf-8').read())
        for ti, tab in enumerate(p.tables):
            hdr = p.headers[ti]
            for r in tab:
                txt = [re.sub(r'\s+', ' ', c['text']).strip() for c in r]
                if len(r) != len(hdr):
                    print('skip', bench, len(r), hdr, txt[:3]); continue
                d = dict(zip(hdr, txt))
                links = [h for c in r for h in c['hrefs'] if 'hal_traces' in h]
                zips = [re.search(r'/main/([^?]+)', h).group(1) for h in links]
                acc = re.match(r'([\d.]+)%(?: \(-([\d.]+)/\+([\d.]+)\))?', d['Accuracy'])
                cost = re.match(r'\$([\d.,]+)(?: \(-([\d.,]+)/\+([\d.,]+)\))?', d['Cost (USD)'])
                rows.append(dict(
                    page=bench, rank=d['Rank'],
                    scaffold=d['Scaffold'].replace('Pareto optimal', '').strip(),
                    pareto=('Pareto optimal' in d['Scaffold']),
                    model=d.get('Primary Model', d.get('Models')), verified=('✓' in d.get('Verified', '')),
                    accuracy_pct=acc.group(1), acc_ci_minus=acc.group(2) or '', acc_ci_plus=acc.group(3) or '',
                    cost_usd=num(cost.group(1)), cost_ci_minus=num(cost.group(2)), cost_ci_plus=num(cost.group(3)),
                    n_runs=d['Runs'], zip=';'.join(zips)))
    with open(out, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
    print(len(rows), 'rows ->', out)


if __name__ == '__main__':
    main(*sys.argv[1:])
