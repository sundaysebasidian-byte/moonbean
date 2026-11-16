#!/usr/bin/env python3
"""Part B extra: typed metadata / multiline narration query values, candidate vs oracle."""
import concurrent.futures as cf, json, os, subprocess
B = "/tmp/r14-base/_build/native/release/build/cmd/main/main.exe"
C = "/tmp/r14/_build/native/release/build/cmd/main/main.exe"
O = "/tmp/moonbean-r4-oracle/bin/bean-query"
ENV = dict(os.environ, TZ="UTC")
res = {r["path"]: r for r in json.load(open("/tmp/r14-review/results.json"))}
QS = ["SELECT entry_meta('kk') AS v", "SELECT meta('kk') AS v", "SELECT narration AS v", "SELECT payee AS v",
      "SELECT entry_meta('memo') AS v", "SELECT meta('memo') AS v", "SELECT type(entry_meta('kk')) AS v",
      "SELECT type(meta('kk')) AS v"]

def rows(s):
    l = [x.rstrip() for x in s.splitlines()]
    l = [x for x in l if x.strip()]
    return [x.strip() for x in l[2:]]

def one(job):
    p, q = job
    c = subprocess.run([C, "query", p, q], capture_output=True, env=ENV, timeout=60)
    b = subprocess.run([B, "query", p, q], capture_output=True, env=ENV, timeout=60)
    o = subprocess.run([O, p, q], capture_output=True, env=ENV, timeout=120)
    return p, q, c.returncode, o.returncode, rows(c.stdout.decode()), rows(o.stdout.decode()), c.stderr.decode()[:200], o.stderr.decode()[-200:], rows(b.stdout.decode())

jobs = [(p, q) for p, r in res.items()
        if r["o_check"]["rc"] == 0 and os.path.basename(p).startswith(("meta", "ml-", "pc", "05-", "06-", "68-"))
        for q in QS]
bad, n = [], 0
with cf.ThreadPoolExecutor(8) as ex:
    for p, q, crc, orc, cr, orow, ce, oe, br in ex.map(one, jobs):
        if orc != 0:
            continue
        n += 1
        if cr != orow or crc != 0:
            bad.append({"path": p, "q": q, "c": cr[:5], "o": orow[:5], "crc": crc, "cerr": ce, "b": br[:5], "baseline_matched": br == orow})
json.dump(bad, open("/tmp/r14-review/typed.json", "w"), indent=1)
print("compared", n, "mismatch", len(bad))
for b in bad[:10]:
    print(os.path.basename(b["path"]), b["q"], "B=", b["b"][:2], "C=", b["c"][:3], "O=", b["o"][:3], b["cerr"][:80])
