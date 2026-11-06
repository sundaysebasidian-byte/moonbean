#!/usr/bin/env python3
"""Compare complete stage medians and process RSS against committed evidence."""
import argparse
import json
from pathlib import Path


def compare(baseline, current, tolerance=0.30):
    failures = []
    paths = sorted(Path(baseline).glob('*-*-*.json'))
    if not paths:
        return ['no baseline cases']
    completed = 0
    for path in paths:
        old = json.loads(path.read_text())
        if old.get('status') != 'complete':
            continue
        completed += 1
        new_path = Path(current) / path.name
        if not new_path.exists():
            failures.append(f'{path.name}: missing measurement')
            continue
        new = json.loads(new_path.read_text())
        keys = ['skipped_stages', 'target', 'postings', 'method', 'seed', 'runs', 'warmups', 'min_batch_ms']
        env_keys = ['model', 'cpu', 'cores', 'memory_bytes', 'platform', 'moon', 'node']
        if (new.get('status') != 'complete' or any(old[k] != new.get(k) for k in keys)
                or any(old['environment'].get(k) != new.get('environment', {}).get(k) for k in env_keys)):
            failures.append(f'{path.name}: incomplete or incompatible measurement/environment')
            continue
        for stage, stats in old['stages'].items():
            measured = new['stages'].get(stage, {}).get('p50')
            if measured is None or not 0 < measured <= stats['p50'] * (1+tolerance):
                failures.append(f'{path.name}/{stage}: p50 {measured}, baseline {stats["p50"]:.6f}s')
        if not 0 < new.get('peak_rss_bytes', 0) <= old['peak_rss_bytes'] * (1+tolerance):
            failures.append(f'{path.name}: peak RSS regression/missing')
    if not completed:
        failures.append("no complete baseline cases")
    return failures


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('current')
    p.add_argument('--baseline', default='docs/evidence/performance/baseline')
    p.add_argument('--tolerance', type=float, default=0.30)
    a = p.parse_args()
    if not 0 <= a.tolerance <= 1:
        p.error('tolerance must be in [0,1]')
    failures = compare(a.baseline, a.current, a.tolerance)
    excluded = [p.name for p in sorted(Path(a.baseline).glob('*-*-*.json'))
                if json.loads(p.read_text()).get('status') != 'complete']
    if excluded:
        print('NOT GATED (incomplete baseline): ' + ', '.join(excluded))
    print('\n'.join(failures) if failures else 'PASS: all baseline stage medians and RSS within tolerance')
    return int(bool(failures))

if __name__ == '__main__':
    raise SystemExit(main())
