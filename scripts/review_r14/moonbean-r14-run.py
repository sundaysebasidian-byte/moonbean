#!/usr/bin/env python3
"""Run baseline / candidate / oracle over all inputs; store raw results."""
import concurrent.futures as cf, hashlib, json, os, subprocess, sys

B = "/tmp/r14-base/_build/native/release/build/cmd/main/main.exe"
C = "/tmp/r14/_build/native/release/build/cmd/main/main.exe"
O = "/tmp/moonbean-r4-oracle/bin"
ENV = dict(os.environ, TZ="UTC")
QUERIES = {"print": "PRINT", "count": "SELECT count(*)"}

def run(cmd, cwd, timeout):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout, env=ENV)
        return {"rc": p.returncode, "out": p.stdout.decode("utf-8", "replace"), "err": p.stderr.decode("utf-8", "replace")[:4000]}
    except subprocess.TimeoutExpired:
        return {"rc": "timeout", "out": "", "err": ""}

def one(path):
    cwd = os.path.dirname(path)
    r = {"path": path}
    r["b_check"] = run([B, "check", path], cwd, 60)
    r["c_check"] = run([C, "check", path], cwd, 60)
    r["o_check"] = run([O + "/bean-check", path], cwd, 180)
    for k, q in QUERIES.items():
        r["b_" + k] = run([B, "query", path, q], cwd, 60)
        r["c_" + k] = run([C, "query", path, q], cwd, 60)
        r["o_" + k] = run([O + "/bean-query", path, q], cwd, 180)
    for k in list(r):
        if isinstance(r[k], dict) and len(r[k]["out"]) > 200000:
            o = r[k]["out"]
            r[k]["out"] = "SHA256:" + hashlib.sha256(o.encode()).hexdigest() + ":LEN" + str(len(o))
    return r

if __name__ == "__main__":
    inp = json.load(open(sys.argv[1]))
    paths = inp["seeds"] + inp["generated"]
    res = []
    with cf.ThreadPoolExecutor(max_workers=8) as ex:
        for i, r in enumerate(ex.map(one, paths)):
            res.append(r)
            if i % 50 == 0:
                print(i, file=sys.stderr, flush=True)
    json.dump(res, open(sys.argv[2], "w"))
    print("done", len(res))
