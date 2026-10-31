#!/usr/bin/env python3
"""Retained benchmark input, repeat timings, and optional macOS CPU sampling."""
import argparse
import json
import platform
from pathlib import Path
import statistics
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--count', type=int, default=100000)
p.add_argument('--runs', type=int, default=5)
p.add_argument('--out', default='.oracle-cache/performance')
p.add_argument('--sample', action='store_true')
a = p.parse_args()
out = Path(a.out)
out.mkdir(parents=True, exist_ok=True)
ledger = out / 'ledger.beancount'
with ledger.open('w') as f:
    f.write('2024-01-01 open Assets:Cash USD\n2024-01-01 open Expenses:Food USD\n')
    for i in range(a.count):
        f.write(f'2024-01-02 * "Purchase {i}"\n  Assets:Cash -1.00 USD\n  Expenses:Food 1.00 USD\n')
exe = '_build/native/release/build/cmd/main/main.exe'
measurements = {}
for name, args in [('check', ['check']), ('bal', ['bal']), ('query', ['query'])]:
    cmd = [exe] + args + [str(ledger)]
    if name == 'query':
        cmd += ['SELECT account, sum(units) GROUP BY account ORDER BY account']
    subprocess.run(cmd, stdout=subprocess.DEVNULL, check=True)
    times = []
    for _ in range(a.runs):
        start = time.perf_counter()
        subprocess.run(cmd, stdout=subprocess.DEVNULL, check=True)
        times.append(time.perf_counter() - start)
    measurements[name] = dict(seconds=times, median=statistics.median(times))
if a.sample:
    proc = subprocess.Popen([exe, 'check', str(ledger)], stdout=subprocess.DEVNULL)
    subprocess.run(['/usr/bin/sample', str(proc.pid), '1', '1', '-file', str(out / 'sample.txt')], check=True)
    if proc.wait() != 0:
        raise RuntimeError('profiled command failed')
result = dict(platform=platform.platform(), count=a.count, runs=a.runs, measurements=measurements)
(out / 'results.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
