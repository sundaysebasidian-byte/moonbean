import json, collections, sys
sys.path.insert(0, '.')
res = json.load(open('results.json'))
def norm(q, s):
    if q != "count": return s
    l = [x.strip() for x in s.splitlines() if x.strip()]
    return l[2:]
st = collections.Counter(); ex = collections.defaultdict(list)
for r in res:
    if r['o_check']['rc'] == 0: continue
    for q in ('print', 'count'):
        b, c, o = (norm(q, r[k+'_'+q]['out']) for k in 'bco')
        if b == c: continue
        key = f"{q}: " + ("toward" if c == o else "away" if b == o else "neither")
        st[key] += 1; ex[key].append(r['path'].split('/')[-1])
for k, v in sorted(st.items()):
    print(k, v, ex[k][:8])
