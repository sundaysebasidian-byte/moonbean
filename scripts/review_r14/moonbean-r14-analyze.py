#!/usr/bin/env python3
"""Classify baseline-vs-candidate differences against the oracle."""
import collections, json, sys

res = json.load(open(sys.argv[1]))
out = collections.defaultdict(list)

def cls(rc):
    return "ok" if rc == 0 else ("err" if rc == 1 else f"crash:{rc}")

def norm(q, s):
    if q != "count":
        return s
    lines = [l.strip() for l in s.splitlines() if l.strip()]
    return lines[2:] if len(lines) >= 2 else lines


for r in res:
    p = r["path"].replace("/tmp/r14-review/mut/", "mut/").replace("/tmp/r14/", "")
    b, c, o = cls(r["b_check"]["rc"]), cls(r["c_check"]["rc"]), cls(r["o_check"]["rc"])
    if c.startswith("crash"):
        out["CAND_CRASH_check"].append((p, b, c, o))
    for q in ("print", "count"):
        if r["c_" + q]["rc"] not in (0, 1):
            out[f"CAND_CRASH_{q}"].append((p, r["c_" + q]["rc"]))
    if b != c:
        out["check_diff_intended" if c == o else "CHECK_DIFF_AWAY"].append((p, b, c, o))
    if c != o:
        out["check_remaining_mismatch"].append((p, b, c, o))
    if o != "ok":
        for q in ("print", "count"):
            if norm(q, r["b_" + q]["out"]) != norm(q, r["c_" + q]["out"]):
                out[f"{q}_diff_oracle_rejects(info)"].append(p)
        continue
    for q in ("print", "count"):
        bo, co, oo = (norm(q, r[k + "_" + q]["out"]) for k in "bco")
        if bo != co:
            if co == oo:
                out[f"{q}_diff_intended"].append(p)
            elif bo == oo:
                out[f"{q.upper()}_DIFF_AWAY"].append(p)
            else:
                out[f"{q.upper()}_DIFF_BOTH_WRONG"].append(p)
        if co != oo:
            out[f"{q}_cand_vs_oracle_mismatch"].append((p, "baseline_also" if bo != oo else "baseline_matched"))
        if b != "ok" and c == "ok" and co == oo:
            out[f"{q}_newly_accepted_exact"].append(p)

json.dump(out, open(sys.argv[2], "w"), indent=1)
print("total ledgers", len(res))
for k in sorted(out):
    print(f"{k}: {len(out[k])}")
    for x in out[k][:10 if k.isupper() or 'AWAY' in k or 'CRASH' in k else 0]:
        print("   ", x)
