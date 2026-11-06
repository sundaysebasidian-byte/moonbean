#!/usr/bin/env python3
"""Offline, fixed-LCG library-stage benchmark; run on an otherwise idle host."""
import argparse
import datetime
import hashlib
import json
import math
import os
import signal
from pathlib import Path
import platform
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def capture(*cmd):
    return subprocess.check_output(cmd, text=True).strip()

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def percentile(values, q):
    return sorted(values)[max(0, math.ceil(len(values) * q) - 1)]

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', default='.oracle-cache/performance-new')
    p.add_argument('--runs', type=int, default=21)
    p.add_argument('--sizes', type=int, nargs='+', default=[1000, 10000, 100000, 1000000])
    p.add_argument('--targets', nargs='+', choices=['native', 'js', 'wasm-gc'], default=['native', 'js', 'wasm-gc'])
    p.add_argument('--timeout', type=int, default=600)
    a = p.parse_args()
    if a.runs < 15 or any(n < 4 or n % 8 for n in a.sizes):
        p.error('at least 15 samples; posting counts must be positive multiples of eight')
    os.chdir(ROOT)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    env = dict(platform=platform.platform(), machine=platform.machine(), cores=os.cpu_count(),
               python=platform.python_version(), moon=capture('moon', 'version', '--all'),
               node=capture('node', '--version'), commit=capture('git', 'rev-parse', 'HEAD'),
               driver_sha256=digest('bench/main.mbt'), runner_sha256=digest(__file__))
    if platform.system() == 'Darwin':
        env.update(model=capture('sysctl', '-n', 'hw.model'), cpu=capture('sysctl', '-n', 'machdep.cpu.brand_string'), memory_bytes=int(capture('sysctl', '-n', 'hw.memsize')))
    else:
        p.error('RSS collection currently requires macOS /usr/bin/time -l')
    for target in a.targets:
        subprocess.run(['moon', 'build', '--release', '--target', target, 'bench'], check=True)
        artifact = Path(f'_build/{target}/release/build/bench/bench.' + {'native':'exe', 'js':'js', 'wasm-gc':'wasm'}[target])
        cmd = {'native':[], 'js':['node'], 'wasm-gc':['moonrun']}[target] + [str(artifact)]
        for count in a.sizes:
            for method in ['FIFO', 'AVERAGE', 'STRICT']:
                record = dict(schema=1, timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat(), environment=env,
                              target=target, postings=count, generated_pad_postings=2, method=method, seed=20261101,
                              runs=a.runs, warmups=2, min_batch_ms=20, command=cmd, artifact_sha256=digest(artifact), stages={})
                record['skipped_stages'] = {'order': 'Not completed at >=100000: insertion sort in query/eval.mbt; 10x postings measured about 100x time at smaller native sizes; bounded run avoids quadratic sort.'} if count >= 100000 and method == 'FIFO' else {}
                try:
                    proc = subprocess.Popen(['/usr/bin/time', '-l', *cmd], env=dict(os.environ, BENCH_COUNT=str(count), BENCH_METHOD=method, BENCH_RUNS=str(a.runs)), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
                    try:
                        stdout, stderr = proc.communicate(timeout=a.timeout)
                    except subprocess.TimeoutExpired:
                        os.killpg(proc.pid, signal.SIGKILL)
                        proc.communicate()
                        raise
                    proc.stdout, proc.stderr = stdout, stderr
                    if proc.returncode:
                        raise RuntimeError(f'exit {proc.returncode}: {proc.stderr[-1500:]}')
                    rows = [json.loads(line) for line in proc.stdout.splitlines()]
                    for name in dict.fromkeys(r['stage'] for r in rows):
                        raw = [r for r in rows if r['stage'] == name]
                        values = [r['seconds'] for r in raw if not r['warmup']]
                        if len(values) != a.runs or any(v <= 0 for v in values):
                            raise RuntimeError('invalid sample count or time')
                        stats = {f'p{q}': percentile(values, q/100) for q in [50, 95, 99]}
                        record['stages'][name] = dict(samples=raw, **stats, postings_per_second=count/stats['p50'])
                    match = re.search(r'(\d+)\s+maximum resident set size', proc.stderr)
                    if not match:
                        raise RuntimeError('RSS missing')
                    record.update(status='complete', peak_rss_bytes=int(match[1]))
                except (subprocess.TimeoutExpired, RuntimeError) as error:
                    record.update(status='incomplete', reason=str(error).replace(str(ROOT), '<repo>'))
                path = out / f'{target}-{count}-{method}.json'
                path.write_text(json.dumps(record, indent=2)+'\n')
                print(path.name, record['status'], flush=True)

if __name__ == '__main__':
    main()
