#!/usr/bin/env python3
"""Paired shared-host measurements for the R14 acceptance packet.

Uses pristine Git archives, default heaps, three process rounds, and load traces.
The Node WasmGC host supplements moonrun RSS with public V8 heap statistics.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tarfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
STAGES = {'parse','booking_FIFO','validate_pad_FIFO','realize','format','aggregate','group','regex','transactions','length','substr'}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def snapshot(ref, destination):
    commit = subprocess.check_output(['git','rev-parse',ref], cwd=ROOT, text=True).strip()
    archive = subprocess.check_output(['git','archive',commit], cwd=ROOT)
    destination.mkdir(parents=True)
    (destination / 'source.tar').write_bytes(archive)
    source = destination / 'source'
    source.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as handle:
        handle.extractall(source, filter='data')
    identity = dict(commit=commit, archive_sha256=hashlib.sha256(archive).hexdigest(),
                    driver_sha256=digest(source/'bench/main.mbt'))
    (destination/'source.json').write_text(json.dumps(identity,indent=2)+'\n')
    return source, identity


def invoke(source, identity, side, host, count, runs, round_index, out, env):
    target = 'wasm-gc' if host in ('moonrun','node-wasm') else host
    extension = {'native':'exe','js':'js','wasm-gc':'wasm'}[target]
    artifact = source / f'_build/{target}/release/build/bench/bench.{extension}'
    command = {'native':[], 'js':['node'], 'moonrun':['moonrun'],
               'node-wasm':['node', str(ROOT/'scripts/wasm-bench-host.mjs')]}[host] + [str(artifact)]
    directory = out / host / f'round-{round_index+1}' / side
    directory.mkdir(parents=True,exist_ok=True)
    name = str(count)+'-FIFO'
    loads = []
    stop = threading.Event()
    def monitor():
        while True:
            loads.append(dict(time=time.time(),load=list(os.getloadavg())))
            if stop.wait(2):
                return
    thread = threading.Thread(target=monitor)
    started = time.time()
    thread.start()
    process = subprocess.Popen(['/usr/bin/time','-l',*command], cwd=source,
                               env=dict(env,BENCH_COUNT=str(count),BENCH_METHOD='FIFO',BENCH_RUNS=str(runs)),
                               stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=900)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid,signal.SIGKILL)
        stdout, stderr = process.communicate()
    finally:
        stop.set()
        thread.join()
    (directory/(name+'.stdout.log')).write_text(stdout)
    (directory/(name+'.stderr.log')).write_text(stderr)
    rows = [json.loads(line) for line in stdout.splitlines() if line.startswith('{')]
    stages = {}
    for stage in STAGES:
        samples = [row for row in rows if row.get('stage') == stage]
        measured = [row['seconds'] for row in samples if not row['warmup']]
        if len(measured) == runs:
            stages[stage] = dict(samples=samples,p50=sorted(measured)[(runs-1)//2])
    rss = re.search(r'(\d+)\s+maximum resident set size',stderr)
    record = dict(side=side,host=host,target=target,count=count,round=round_index+1,
                  runs=runs,warmups=2,min_batch_ms=20,source=identity,command=command,
                  artifact_sha256=digest(artifact),started=started,finished=time.time(),
                  returncode=process.returncode,timed_out=timed_out,load_samples=loads,stages=stages,
                  heap=next((row['heap'] for row in rows if 'heap' in row),None),
                  skipped_stages={'order':'Existing >=100k FIFO benchmark skip'},
                  peak_rss_bytes=int(rss[1]) if rss else None)
    record['status'] = 'complete' if process.returncode == 0 and rss and set(stages) == STAGES else 'incomplete'
    (directory/(name+'.json')).write_text(json.dumps(record,indent=2)+'\n')
    print(host,count,side,'round',round_index+1,record['status'],'RSS',record['peak_rss_bytes'],flush=True)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline',default='e33a3fc')
    parser.add_argument('--candidate',default='HEAD')
    parser.add_argument('--out',default='.oracle-cache/r14/performance')
    parser.add_argument('--rounds',type=int,default=3)
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error('rounds must be positive')
    out = (ROOT/args.out).resolve()
    out.mkdir(parents=True,exist_ok=False)
    (out/'pid').write_text(str(os.getpid()))
    env = dict(os.environ,MOON_HOME='/tmp/moon-new',PATH='/tmp/moon-new/bin:'+os.environ['PATH'])
    env.pop('NODE_OPTIONS',None)
    sources, identities = {}, {}
    for side, ref in [('baseline',args.baseline),('candidate',args.candidate)]:
        sources[side], identities[side] = snapshot(ref,out/('input-'+side))
        for target in ['native','js','wasm-gc']:
            with (out/f'build-{side}-{target}.log').open('w') as log:
                subprocess.run(['moon','build','--release','--target',target,'bench'],cwd=sources[side],
                               env=env,stdout=log,stderr=log,check=True)
    environment = dict(moon=subprocess.check_output(['moon','version','--all'],env=env,text=True),
                       node=subprocess.check_output(['node','--version'],env=env,text=True).strip(),
                       v8=subprocess.check_output(['node','-p','process.versions.v8'],env=env,text=True).strip(),
                       node_options_cleared=True,heap_flags=[],load_policy='Record shared-host load without waiting for idle',
                       runner_sha256=digest(__file__),node_host_sha256=digest(ROOT/'scripts/wasm-bench-host.mjs'))
    records = []
    def run_pair(host,count,runs,index):
        order = ['baseline','candidate'] if index%2==0 else ['candidate','baseline']
        for side in order:
            record = invoke(sources[side],identities[side],side,host,count,runs,index,out,env)
            records.append(record)
            (out/'results.json').write_text(json.dumps(dict(environment=environment,records=records),indent=2)+'\n')
    for index in range(args.rounds):
        run_pair('moonrun',1000000,15,index)
        run_pair('node-wasm',1000000,1,index)
    for index in range(args.rounds):
        for offset, (host,count) in enumerate([('native',100000),('js',100000),('native',1000000),('js',1000000)]):
            # Alternate whole-case order within each process round.
            order = index if offset%2==0 else index+1
            for side in (['baseline','candidate'] if order%2==0 else ['candidate','baseline']):
                record=invoke(sources[side],identities[side],side,host,count,1,index,out,env)
                records.append(record)
                (out/'results.json').write_text(json.dumps(dict(environment=environment,records=records),indent=2)+'\n')
    return int(any(record['status']!='complete' for record in records))


if __name__ == '__main__':
    raise SystemExit(main())
