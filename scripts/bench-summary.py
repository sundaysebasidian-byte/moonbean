#!/usr/bin/env python3
"""Produce a stage timing profile from saved matrix samples (no extra profiling overhead)."""
import argparse
import json
import re
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('directory')
a = p.parse_args()
root = Path(a.directory)
cases = []
for path in sorted(root.glob('*-*-*.json')):
    r = json.loads(path.read_text())
    case = {k:r[k] for k in ['target', 'postings', 'method', 'status']}
    case['skipped_stages'] = r.get('skipped_stages', {})
    if r['status'] == 'complete':
        case['peak_rss_bytes'] = r['peak_rss_bytes']
        case['stages'] = {name:dict(p50=s['p50'], p95=s['p95'], p99=s['p99'],
                                   postings_per_second=s['postings_per_second'],
                                   max_over_p50=max(x['seconds'] for x in s['samples'] if not x['warmup'])/s['p50'])
                          for name,s in r['stages'].items()}
    else:
        case['reason'] = r['reason']
        rss = re.search(r'(\d+)\s+maximum resident set size', r['reason'])
        if rss:
            case['failed_process_peak_rss_bytes'] = int(rss[1])
    cases.append(case)
(root/'stage-profile.json').write_text(json.dumps(dict(
    note='Independent stage timings, not additive CPU stack shares; validation includes booking and pad. RSS is process-wide, includes generation/setup and runtime. API results are consumed without text/JSON rendering.',
    cases=cases), indent=2)+'\n')
for r in cases:
    if r['method'] == 'FIFO':
        print(r['target'], r['postings'], r['status'],
              ' '.join(f'{k}={v["p50"]:.6f}s' for k,v in r.get('stages',{}).items()))
