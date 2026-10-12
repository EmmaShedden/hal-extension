"""Build data/meta/hf_runs.csv: one row per HAL trace zip on HuggingFace (agent-evals/hal_traces).

Usage:
  python -I build_hf_runs.py <src_dir> <out_csv>

<src_dir> must contain (see data/meta/README.md for provenance):
  hf_tree_current.json         HF tree listing (main)
  hf_tree_paper_snapshot.json  HF tree listing at the last commit before the arXiv submission
  hf_commits.json              full HF commit history
  hal_leaderboard_scrape_*.csv output of scrape_hal_leaderboard.py
  paper_appendix_runs.csv      output of parse_paper_tables.py
"""
import csv, datetime as dt, glob, json, os, re, sys
from collections import defaultdict

SRC, OUT = sys.argv[1], sys.argv[2]
PAPER_SUBMIT = '2025-10-13'          # arXiv v1 submitted Mon 13 Oct 2025 22:22 UTC

# ---------------------------------------------------------------- inputs
tree = [x for x in json.load(open(f'{SRC}/hf_tree_current.json')) if x['path'].endswith('.zip')]
snap = {x['path'] for x in json.load(open(f'{SRC}/hf_tree_paper_snapshot.json'))}
commits = json.load(open(f'{SRC}/hf_commits.json'))
lb_rows = list(csv.DictReader(open(sorted(glob.glob(f'{SRC}/hal_leaderboard_scrape_*.csv'))[-1])))
paper = list(csv.DictReader(open(f'{SRC}/paper_appendix_runs.csv')))

upload = defaultdict(list)            # filename -> dates of 'Add' commits (uploads / re-uploads)
for c in commits:
    m = re.match(r'Add encrypted results for (\S+?)\.?$', c['title'])
    if m:
        name = m.group(1)
        upload[name if name.endswith('.zip') else name + '.zip'].append(c['date'][:10])
snap_size = {x['path']: x.get('size') for x in json.load(open(f'{SRC}/hf_tree_paper_snapshot.json'))}
SNAP_REV = '1bf4166d052cdd3445127e17c15139cbb5505ca5'   # last HF commit before arXiv submission (2025-10-08)

lb_by_zip = {r['zip']: r for r in lb_rows}

# ---------------------------------------------------------------- filename parsing
BENCH = [  # (prefix, benchmark page id, canonical benchmark)
    ('colbench_backend_programming_', 'colbench_backend_programming', 'ColBench Backend Programming'),
    ('colbench_frontend_design_', 'colbench_frontend_design', 'ColBench Frontend Design'),
    ('swebench_verified_mini', 'swebench_verified_mini', 'SWE-bench Verified Mini'),
    ('taubench_airline', 'taubench_airline', 'TAU-bench Airline'),
    ('corebench_hard_', 'corebench_hard', 'CORE-Bench Hard'),
    ('scienceagentbench_', 'scienceagentbench', 'ScienceAgentBench'),
    ('assistantbench_', 'assistantbench', 'AssistantBench'),
    ('browser-use_', 'online_mind2web', 'Online Mind2Web'),
    ('seeact_', 'online_mind2web', 'Online Mind2Web'),
    ('scicode_', 'scicode', 'SciCode'),
    ('gaia_', 'gaia', 'GAIA'),
    ('usaco_', 'usaco', 'USACO'),
]
AGENTS = [  # (regex on remainder after benchmark prefix, canonical scaffold) -- first match wins
    (r'^assistantbench_browser_agent_?', 'Browser-Use'),
    (r'^hal_?generalist(_agent)?_?|^halgeneralist(agent)?_?', 'HAL Generalist Agent'),
    (r'^claude_code_', 'Claude Code'),
    (r'^core_?agent_?', 'CORE-Agent'),
    (r'^hf_open_deep_research_', 'HF Open Deep Research'),
    (r'^scicode[-_]tool_calling_agent_', 'Scicode Tool Calling Agent'),
    (r'^scicode_zero_shot_agent_', 'Scicode Zero Shot Agent'),
    (r'^sab_selfdebug_', 'SAB Self-Debug'),
    (r'^sweagent', 'SWE-Agent'),
    (r'^my_agent', 'SWE-Agent'),               # leaderboard labels all swebench my_agent* runs as SWE-Agent
    (r'^taubench_few_?shot_', 'TAU-bench Few Shot'),
    (r'^taubench_toolcalling_', 'TAU-bench Tool Calling'),
    (r'^usaco_episodic__semantic_', 'USACO Episodic + Semantic'),
    (r'^colbench_example_agent_?|^colbench_backend_programming_colbench_example_agent', 'ColBench Example Agent'),
    (r'^colbench_text_|^colbench_frontend_|^colbench_', 'ColBench Agent'),
]


def parse_name(path):
    s = re.sub(r'_UPLOAD.*\.zip$', '', path)
    m = re.search(r'_(\d{10})(slim)?$', s)
    ts = int(m.group(1)) if m else None
    if m:
        s = s[:m.start()]
    for pre, page, bname in BENCH:
        if s.startswith(pre):
            rest = s[len(pre):].lstrip('_')
            break
    else:
        raise ValueError(path)
    if pre == 'browser-use_':
        agent, rest2 = 'Browser-Use', rest
    elif pre == 'seeact_':
        agent, rest2 = 'SeeAct', rest
    else:
        agent, rest2 = '', rest
        for rx, a in AGENTS:
            mm = re.match(rx, rest)
            if mm:
                agent, rest2 = a, rest[mm.end():]
                break
    return page, bname, agent, rest2, ts


# ---------------------------------------------------------------- model canonicalisation
REASONING = {'o3', 'o4-mini', 'o3-mini', 'gpt-5', 'gpt-oss-120b', 'deepseek-r1', 'deepseek-r1-0528',
             'gemini-2.5-pro-preview', 'gemini-3-pro-preview'}
HYBRID = {'claude-3.7-sonnet', 'claude-sonnet-4', 'claude-opus-4', 'claude-opus-4.1', 'claude-sonnet-4.5',
          'claude-haiku-4.5', 'claude-opus-4.5', 'deepseek-v3.1'}   # thinking can be switched off
PROVIDER = lambda m: ('Anthropic' if m.startswith('claude') else 'OpenAI' if m.startswith(('gpt', 'o3', 'o4'))
                      else 'DeepSeek' if m.startswith('deepseek') else 'Google' if m.startswith('gemini') else '')

LABEL_MODEL = [  # HAL leaderboard label (without effort/date) -> canonical
    ('Claude-3.7 Sonnet', 'claude-3.7-sonnet'), ('Claude Opus 4.1', 'claude-opus-4.1'),
    ('Claude Opus 4.5', 'claude-opus-4.5'), ('Claude Opus 4', 'claude-opus-4'),
    ('Claude Sonnet 4.5', 'claude-sonnet-4.5'), ('Claude Sonnet 4', 'claude-sonnet-4'),
    ('Claude Haiku 4.5', 'claude-haiku-4.5'), ('GPT-4.1', 'gpt-4.1'), ('GPT-5', 'gpt-5'),
    ('GPT-OSS-120B', 'gpt-oss-120b'), ('o3', 'o3'), ('o4-mini', 'o4-mini'),
    ('DeepSeek V3.1', 'deepseek-v3.1'), ('DeepSeek V3', 'deepseek-v3'), ('DeepSeek R1', 'deepseek-r1'),
    ('Gemini 2.0 Flash', 'gemini-2.0-flash'), ('Gemini 2.5 Pro Preview', 'gemini-2.5-pro-preview'),
    ('Gemini 3 Pro Preview', 'gemini-3-pro-preview'),
]


def model_from_label(label):
    """'Claude Opus 4.1 High (August 2025)' -> ('claude-opus-4.1', 'high')"""
    lab = re.sub(r'\s*\(.*\)$', '', label).strip()
    m = re.match(r'^(.*?)\s+(High|Low|Medium|Minimal)$', lab)
    base, eff = (m.group(1), m.group(2).lower()) if m else (lab, '')
    for k, v in LABEL_MODEL:
        if base == k:
            if v == 'deepseek-r1' and '(May 2025)' in label:
                v = 'deepseek-r1-0528'
            return v, eff
    return 'unknown:' + label, eff


FILE_MODEL = [  # regex on normalised filename remainder -> canonical (order matters)
    (r'claude37|sonnet37|claude3?7sonnet|sonnet$', 'claude-3.7-sonnet'),
    (r'opus45|claudeopus45', 'claude-opus-4.5'), (r'opus41|claudeopus412025', 'claude-opus-4.1'),
    (r'claudeopus4', 'claude-opus-4'), (r'claudesonnet45', 'claude-sonnet-4.5'),
    (r'claudesonnet4', 'claude-sonnet-4'), (r'claudehaiku45', 'claude-haiku-4.5'),
    (r'gptoss120b', 'gpt-oss-120b'), (r'gpt4o', 'gpt-4o'), (r'gpt41', 'gpt-4.1'), (r'gpt5', 'gpt-5'),
    (r'o4mini|^o4', 'o4-mini'), (r'o3mini', 'o3-mini'), (r'^o3|o3medium|o320250416', 'o3'),
    (r'r10528', 'deepseek-r1-0528'), (r'deepseekr1|dsr1', 'deepseek-r1'),
    (r'deepseekv31', 'deepseek-v3.1'), (r'deepseekv3|dsv3|deepseekchatv3', 'deepseek-v3'),
    (r'gemini25pro', 'gemini-2.5-pro-preview'), (r'gemini3pro', 'gemini-3-pro-preview'),
    (r'gemini20flash|gemmini2flash|^gemini$', 'gemini-2.0-flash'),
]


def model_from_file(rest):
    n = re.sub(r'[^a-z0-9]', '', rest.lower().replace('together_ai', ''))
    n = n.replace('deepseekai', '').replace('openai', '').replace('geminigemini', 'gemini')
    model = 'unknown'
    for rx, v in FILE_MODEL:
        if re.search(rx, n):
            model = v
            break
    r = rest.lower()
    eff = ''
    if re.search(r'minimal', r): eff = 'minimal'
    elif re.search(r'no_reasoning', r): eff = 'none'
    elif re.search(r'high', r): eff = 'high'
    elif re.search(r'(^|_|mini|o4)low', r): eff = 'low'
    elif re.search(r'medium', r): eff = 'medium'
    elif re.search(r'thinking', r): eff = 'thinking(unspecified)'
    return model, eff


def collapse_effort(model, eff_raw):
    if eff_raw in ('high', 'low', 'minimal'):
        return eff_raw
    if eff_raw == 'medium':
        return 'default'          # OpenAI / budget default
    if model in HYBRID and eff_raw in ('', 'none'):
        return 'none'             # extended thinking off (paper: "no reasoning")
    if model in REASONING or model == 'unknown' or eff_raw.startswith('thinking'):
        return 'default'          # reasoning model at provider default, or unknown -> default
    return 'none'                 # non-reasoning model (gpt-4.1, gpt-4o, deepseek-v3, gemini-2.0-flash)


# ---------------------------------------------------------------- paper <-> leaderboard matching
lb_idx = defaultdict(list)
for r in lb_rows:
    lb_idx[(r['page'], r['scaffold'], r['model'])].append(r)

paper_of_zip = {}        # zip -> (status, evidence, paper row)
unmatched_paper = []
for p in paper:
    c = lb_idx.get((p['page'], p['scaffold'], p['model']), [])
    l = c[0] if len(c) == 1 else None
    tag = f"paper App. table {p['page']}: {p['scaffold']} / {p['model']} = {p['paper_acc_pct']}% ${p['paper_cost_usd']}"
    if l and abs(float(l['accuracy_pct']) - float(p['paper_acc_pct'])) < 0.06 \
            and abs(float(l['cost_usd']) - float(p['paper_cost_usd'])) < 0.006:
        how = 'exact match to leaderboard row linking this zip' if l['n_runs'] == '1' else \
              f"matches leaderboard {l['n_runs']}-run aggregate (this zip is the linked run)"
        paper_of_zip[l['zip']] = ('TRUE', f'{tag}; {how}', p)
    else:
        unmatched_paper.append((p, l))

# Manual resolutions for the 8 paper rows whose current leaderboard row differs (see README).
MANUAL = {
    # 2-run aggregates that equal the paper value: the second (unlinked) run is also in the paper
    'corebench_hard_coreagentdeepseekr1_1757604883_UPLOAD.zip':
        ('TRUE', 'paper CORE-Agent / DeepSeek R1 (Jan) 6.7% $81.11 equals the leaderboard 2-run aggregate; '
                 'inferred 2nd run = only other R1-labelled CORE-Agent zip (uploaded 2025-09-11)', 'corebench_hard|CORE-Agent|DeepSeek R1 (January 2025)'),
    'scicode_scicode_tool_calling_agent_claudeopus41_high_1755107101_UPLOAD.zip':
        ('TRUE', 'paper SciCode Tool Calling / Opus 4.1 High 6.9% $550.54 equals leaderboard 2-run aggregate; '
                 'inferred 2nd run = only other Opus-4.1-High tool-calling zip', 'scicode|Scicode Tool Calling Agent|Claude Opus 4.1 High (August 2025)'),
    # leaderboard row now aggregates the paper run with a later run
    'gaia_hal_generalist_agent_deepseekaideepseekv3_1744673872_UPLOAD.zip':
        ('TRUE', 'paper GAIA HAL Generalist / DeepSeek V3 36.4% $29.27 = upper end of leaderboard 2-run range; '
                 'other run (deepseekchatv30324_1760455632) uploaded after the paper', 'gaia|HAL Generalist Agent|DeepSeek V3 (March 2025)'),
    'swebench_verified_mini_sweagentclaudeopus4120250805_1754598086_UPLOAD.zip':
        ('TRUE', 'paper SWE-Agent / Opus 4.1 54.0% $1789.67 = lower end of leaderboard 2-run range; leaderboard now '
                 'links the 2025-10-06 rerun; inferred = remaining Aug-2025 Opus-4.1 SWE-Agent zip (the other is the High run)',
         'swebench_verified_mini|SWE-Agent|Claude Opus 4.1 (August 2025)'),
    # leaderboard now links 2026 reruns that are not on HF
    'usaco_usaco_episodic__semantic_gpt520250807_1756136988_UPLOAD.zip':
        ('TRUE', 'paper USACO E+S / GPT-5 Medium 69.7% $64.13; leaderboard now shows a 2026 rerun (not on HF); '
                 'inferred = only pre-paper GPT-5 USACO zip', 'usaco|USACO Episodic + Semantic|GPT-5 Medium (August 2025)'),
    'usaco_usaco_episodic__semantic_o4mini20250416_high_1746405235_UPLOAD.zip':
        ('TRUE', 'paper USACO E+S / o4-mini High 58.0% $44.04; leaderboard now shows a 2026 rerun (not on HF); '
                 'inferred = only remaining o4-mini-high USACO zip (an earlier one was deleted 2025-04-24)',
         'usaco|USACO Episodic + Semantic|o4-mini High (April 2025)'),
    'usaco_usaco_episodic__semantic_o4mini20250416_low_1746039070_UPLOAD.zip':
        ('TRUE', 'paper USACO E+S / o4-mini Low 30.9% $21.14; leaderboard now shows a 2026 rerun (not on HF); '
                 'inferred = only o4-mini-low USACO zip', 'usaco|USACO Episodic + Semantic|o4-mini Low (April 2025)'),
    # ambiguous: exactly one of these two is the paper's single run (2.2%, $13.87)
    'corebench_hard_hal_generalist_agent_1747247500_UPLOAD.zip':
        ('UNSURE', 'paper CORE HAL Generalist / DeepSeek R1 (Jan) reports ONE run 2.2% $13.87; leaderboard row (this zip linked) '
                   'now aggregates 2 runs (2.22%/6.67%); exactly one of {this, hal_generalist_agentdeepseekr1_1757615687} is the paper run',
         'corebench_hard|HAL Generalist Agent|DeepSeek R1 (January 2025)'),
    'corebench_hard_hal_generalist_agentdeepseekr1_1757615687_UPLOAD.zip':
        ('UNSURE', 'paper CORE HAL Generalist / DeepSeek R1 (Jan) reports ONE run 2.2% $13.87; exactly one of '
                   '{this, hal_generalist_agent_1747247500} is the paper run (leaderboard aggregates both)',
         'corebench_hard|HAL Generalist Agent|DeepSeek R1 (January 2025)'),
}
paper_by_key = {f"{p['page']}|{p['scaffold']}|{p['model']}": p for p in paper}
for z, (st, ev, key) in MANUAL.items():
    paper_of_zip[z] = (st, ev, paper_by_key[key])
resolved = {k for _, (_, _, k) in MANUAL.items()}
still = [p for p, _ in unmatched_paper if f"{p['page']}|{p['scaffold']}|{p['model']}" not in resolved]
assert not still, still

PAPER_MODELS = {(p['page'], p['scaffold']) for p in paper}

# ---------------------------------------------------------------- build rows
rows = []
for x in sorted(tree, key=lambda x: x['path']):
    path = x['path']
    page, bname, agent, rest, ts = parse_name(path)
    fmodel, feff = model_from_file(rest)
    lb = lb_by_zip.get(path)
    if lb:
        lmodel, leff = model_from_label(lb['model'])
        model, eff_raw, src = lmodel, leff, 'leaderboard label'
        scaffold = re.sub(r'\s*Submitted by.*$', '', lb['scaffold'])
    else:
        model, eff_raw, src = fmodel, feff, 'filename' if fmodel != 'unknown' else 'unknown'
        scaffold = agent or 'unknown'
        if path in paper_of_zip:      # not linked from leaderboard, but resolved to a paper row: use the paper label
            pr = paper_of_zip[path][2]
            model, eff_raw = model_from_label(pr['model'])
            src, scaffold = 'paper table label', pr['scaffold']
    effort = collapse_effort(model, eff_raw)
    dates = sorted(upload.get(path, []))
    first_up, last_up = (dates[0], dates[-1]) if dates else ('', '')
    in_snap = path in snap

    if path in paper_of_zip:
        st, ev, p = paper_of_zip[path]
    else:
        p = None
        if not in_snap:
            st, ev = 'FALSE', f'not on HF at paper submission (first upload {first_up}; absent from HF tree at last pre-paper commit 2025-10-08)'
        elif page.startswith('colbench'):
            st, ev = 'FALSE', 'ColBench is not one of the 9 benchmarks in the paper'
        elif scaffold == 'TAU-bench Few Shot':
            st, ev = 'FALSE', 'TAU-bench Few Shot scaffold excluded from the paper (data leakage, Sec. 5 / App.)'
        elif model in ('claude-sonnet-4.5', 'claude-haiku-4.5', 'o3-mini', 'gpt-4o'):
            st, ev = 'FALSE', f'model {model} not in any paper appendix table'
        elif lb:
            st, ev = 'FALSE', 'linked from leaderboard but no matching row in paper appendix tables'
        else:
            st, ev = 'FALSE', ('on HF before the paper but not linked from the leaderboard and no paper row left unaccounted for '
                               '(all 184 table rows / 186 runs are assigned to other zips); likely superseded, failed, or exploratory run')
    lbn = lb['n_runs'] if lb else ''
    # best estimate of THIS run's own accuracy/cost
    run_acc = run_cost = ''
    if p is not None and st == 'TRUE' and 'aggregate' not in ev:
        run_acc, run_cost = p['paper_acc_pct'], p['paper_cost_usd']
    elif lb and lbn == '1':
        run_acc, run_cost = lb['accuracy_pct'], lb['cost_usd']
    rows.append(dict(
        filename=path, size_bytes=x.get('size', ''), benchmark=bname, benchmark_id=page,
        scaffold=scaffold, model_canonical=model, provider=PROVIDER(model),
        reasoning_capable=(model in REASONING or model in HYBRID),
        effort=effort, effort_raw=eff_raw, model_source=src,
        hal_model_label=lb['model'] if lb else '', filename_model=fmodel, filename_effort=feff,
        run_timestamp=(dt.datetime.fromtimestamp(ts, dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ') if ts else ''),
        hf_first_upload=first_up, hf_last_upload=last_up, on_hf_at_paper_submission=in_snap,
        hf_size_at_paper_snapshot=snap_size.get(path, ''),
        hf_reuploaded_after_paper=(in_snap and last_up > PAPER_SUBMIT),
        in_paper=st, paper_evidence=ev,
        paper_scaffold=p['scaffold'] if p is not None else '', paper_model_label=p['model'] if p is not None else '',
        paper_acc_pct=p['paper_acc_pct'] if p is not None else '', paper_cost_usd=p['paper_cost_usd'] if p is not None else '',
        hal_lb_linked=bool(lb), hal_lb_acc_pct=lb['accuracy_pct'] if lb else '', hal_lb_cost_usd=lb['cost_usd'] if lb else '',
        hal_lb_n_runs=lbn,
        hal_lb_acc_range=(f"-{lb['acc_ci_minus']}/+{lb['acc_ci_plus']}" if lb and lb['acc_ci_minus'] else ''),
        hal_lb_verified=lb['verified'] if lb else '',
        run_acc_pct=run_acc, run_cost_usd=run_cost,
    ))

with open(OUT, 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

from collections import Counter
print(len(rows), 'rows ->', OUT)
print(Counter(r['in_paper'] for r in rows))
for b in sorted({r['benchmark'] for r in rows}):
    c = Counter(r['in_paper'] for r in rows if r['benchmark'] == b)
    print(f"{b:30s} TRUE={c['TRUE']:3d} FALSE={c['FALSE']:3d} UNSURE={c['UNSURE']:2d}")
