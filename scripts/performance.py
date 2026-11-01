#!/usr/bin/env python3
"""Seeded native release wall timings, raw evidence and optional query profile.

The decimal comparison changes only the historical decimal parser in an isolated
archive of HEAD. It never rewrites the current working tree.
"""
import argparse
import datetime
import hashlib
import io
import json
import platform
from pathlib import Path
import random
import shutil
import tempfile
import statistics
import subprocess
import tarfile
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--count', type=int, default=100000)
p.add_argument('--runs', type=int, default=7)
p.add_argument('--seed', type=int, default=20261101)
p.add_argument('--out', default='docs/evidence/performance')
p.add_argument('--compare-decimal', action='store_true')
p.add_argument('--sample', action='store_true')
a = p.parse_args()
if a.count < 1 or a.runs < 5:
    p.error('count must be positive; at least five measured runs required')
out = Path(a.out).resolve()
out.mkdir(parents=True, exist_ok=True)
ledger = out / 'ledger.beancount'
rng = random.Random(a.seed)
with ledger.open('w') as f:
    f.write('2024-01-01 open Assets:Cash USD\n2024-01-01 open Expenses:Food USD\n')
    for i in range(a.count):
        cents = rng.randint(1, 10000)
        amount = f'{cents // 100}.{cents % 100:02d}'
        f.write(f'2024-01-02 * "Purchase {i}"\n  Assets:Cash -{amount} USD\n  Expenses:Food {amount} USD\n')
exe = Path('_build/native/release/build/cmd/main/main.exe').resolve()
subprocess.run(['moon', 'build', '--target', 'native', '--release'], check=True)
query = 'SELECT account, sum(units) GROUP BY account ORDER BY account'
commands = {name: [str(exe), command, str(ledger)] for name, command in
            [('check', 'check'), ('realize', 'bal'), ('query', 'query'), ('fmt', 'fmt')]}
commands['query'].append(query)
comparison = None
if a.compare_decimal:
    Path('.oracle-cache').mkdir(exist_ok=True)
    baseline = Path(tempfile.mkdtemp(prefix='performance-baseline-', dir='.oracle-cache')).resolve()
    archive = subprocess.check_output(['git', 'archive', 'HEAD'])
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(baseline, filter='data')
    # Include this working tree's tracked edits so decimal is the sole variable.
    for name in subprocess.check_output(['git', 'diff', 'HEAD', '--name-only'], text=True).splitlines():
        source = Path(name)
        if source.is_file():
            (baseline / name).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, baseline / name)
    old = subprocess.check_output(['git', 'show', 'e7c98b1:decimal/decimal.mbt'])
    old = old.replace(b'pub let decimal_precision', b'let decimal_precision')
    (baseline / 'decimal/decimal.mbt').write_bytes(old)
    subprocess.run(['moon', 'build', '--target', 'native', '--release'], cwd=baseline, check=True)
    commands['query_old_decimal'] = [str(baseline / '_build/native/release/build/cmd/main/main.exe'),
                                     'query', str(ledger), query]
    comparison = dict(base_head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                      decimal_ref='e7c98b1:decimal/decimal.mbt',
                      decimal_sha256=hashlib.sha256(old).hexdigest(),
                      note='HEAD plus tracked working edits; only historical decimal parser substituted; precision constant kept private')
measurements = {}
for name, cmd in commands.items():
    subprocess.run(cmd, stdout=subprocess.DEVNULL, check=True)
    measurements[name] = dict(command=cmd, seconds=[])
# Alternate query order on each round to reduce order/thermal bias.
for round_index in range(a.runs):
    names = list(commands)
    if round_index % 2:
        names.reverse()
    for name in names:
        start = time.perf_counter()
        subprocess.run(commands[name], stdout=subprocess.DEVNULL, check=True)
        measurements[name]['seconds'].append(time.perf_counter() - start)
for measurement in measurements.values():
    measurement['median'] = statistics.median(measurement['seconds'])
    measurement['min'] = min(measurement['seconds'])
    measurement['max'] = max(measurement['seconds'])
if a.sample:
    if platform.system() != 'Darwin':
        p.error('--sample currently requires macOS sample')
    for name in ['query', 'query_old_decimal'] if comparison else ['query']:
        proc = subprocess.Popen(commands[name], stdout=subprocess.DEVNULL)
        sampled = subprocess.run(['/usr/bin/sample', str(proc.pid), '1', '1', '-file',
                                  str(out / f'{name}-sample.txt')], capture_output=True, text=True)
        (out / f'{name}-sample-status.txt').write_text(sampled.stdout + sampled.stderr)
        if proc.wait() != 0 or sampled.returncode != 0:
            raise RuntimeError(f'{name} profile failed')
result = dict(timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat(),
              platform=platform.platform(), cpu=subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()
              if platform.system() == 'Darwin' else platform.processor(),
              moon=subprocess.check_output(['moon', 'version', '--all'], text=True),
              python=platform.python_version(), count=a.count, seed=a.seed, runs=a.runs, warmups=1,
              ledger_sha256=hashlib.sha256(ledger.read_bytes()).hexdigest(), ledger_bytes=ledger.stat().st_size,
              executable_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(), comparison=comparison,
              measurements=measurements)
(out / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
