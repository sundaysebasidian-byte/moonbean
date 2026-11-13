#!/usr/bin/env python3
"""Sample stage RSS in an instrumented source snapshot, using the default heap.

Snapshots and raw logs are retained for stage-memory diagnosis. Gate runs use
the pristine benchmark driver. RSS includes runtime residency and retained objects.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tarfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True)
    parser.add_argument('--ref', help='Git revision; omit to include working source edits')
    parser.add_argument('--count', type=int, default=1000000)
    parser.add_argument('--target', choices=['native', 'js', 'wasm-gc'], default='wasm-gc')
    parser.add_argument('--timeout', type=int, default=900)
    args = parser.parse_args()
    if args.count < 8 or args.count % 8:
        parser.error('count must be a positive multiple of eight')
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = out / 'source'
    source.mkdir()
    archive = subprocess.check_output(['git', 'archive', args.ref or 'HEAD'], cwd=ROOT)
    (out / 'source.tar').write_bytes(archive)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(source, filter='data')
    if not args.ref:
        names = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], cwd=ROOT).split(b'\0')
        for name in names:
            if not name:
                continue
            path = Path(os.fsdecode(name))
            if (ROOT / path).is_file():
                (source / path).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / path, source / path)
            elif (source / path).is_file():
                (source / path).unlink()
    driver = source / 'bench/main.mbt'
    original = driver.read_text()
    instrumented = original
    for before, stage in [('  let source = generate(count, policy)', 'generate'),
                          ('  let parsed = @syntax.parse_source', 'parse_setup'),
                          ('  let valid = @validation.validate_ledger', 'validate_setup')]:
        assert instrumented.count(before) == 1
        instrumented = instrumented.replace(before, f'  println("PROFILE {stage}")\n' + before)
    instrumented = instrumented.replace('  let mut sink = 0', '  println("PROFILE " + name)\n  let mut sink = 0')
    driver.write_text(instrumented)
    with (out / 'build.log').open('w') as log:
        subprocess.run(['moon', 'build', '--release', '--target', args.target, 'bench'], cwd=source, stdout=log, stderr=log, check=True)
    extension = {'native': 'exe', 'js': 'js', 'wasm-gc': 'wasm'}[args.target]
    artifact = source / f'_build/{args.target}/release/build/bench/bench.{extension}'
    command = {'native': [], 'js': ['node'], 'wasm-gc': ['moonrun']}[args.target] + [str(artifact)]
    result = dict(target=args.target, count=args.count, ref=args.ref,
                  source_archive_sha256=hashlib.sha256(archive).hexdigest(),
                  original_driver_sha256=hashlib.sha256(original.encode()).hexdigest(),
                  instrumented_driver_sha256=hashlib.sha256(instrumented.encode()).hexdigest(),
                  artifact_sha256=hashlib.sha256(artifact.read_bytes()).hexdigest(),
                  sample_interval_seconds=0.1, stage_peaks_rss_bytes={}, samples=[])
    stage = ['startup']
    stop = threading.Event()
    env = dict(os.environ, BENCH_COUNT=str(args.count), BENCH_METHOD='FIFO', BENCH_RUNS='15')
    with (out / 'stderr.log').open('w') as err, (out / 'stdout.log').open('w') as log:
        proc = subprocess.Popen(command, cwd=source, env=env, stdout=subprocess.PIPE, stderr=err, text=True, bufsize=1, start_new_session=True)
        def monitor():
            started = time.monotonic()
            while not stop.is_set():
                if time.monotonic() - started > args.timeout:
                    result['timeout'] = True
                    os.killpg(proc.pid, signal.SIGKILL)
                    return
                rss = subprocess.run(['ps', '-o', 'rss=', '-p', str(proc.pid)], capture_output=True, text=True).stdout.strip()
                if rss:
                    size = int(rss) * 1024
                    name = stage[0]
                    result['stage_peaks_rss_bytes'][name] = max(size, result['stage_peaks_rss_bytes'].get(name, 0))
                    result['samples'].append([time.monotonic() - started, name, size])
                stop.wait(0.1)
        thread = threading.Thread(target=monitor)
        thread.start()
        try:
            for line in proc.stdout:
                log.write(line)
                log.flush()
                if line.startswith('PROFILE '):
                    stage[0] = line.strip()[8:]
            result['returncode'] = proc.wait()
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
            proc.stdout.close()
            stop.set()
            thread.join()
    (out / 'memory.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({key: value for key, value in result.items() if key != 'samples'}, indent=2))
    return int(result['returncode'] != 0)


if __name__ == '__main__':
    raise SystemExit(main())
