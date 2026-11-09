"""Exercise all Unicode case mappings and contextual casing via external oracle."""
from pathlib import Path
import json
import random
import re
import subprocess
import unicodedata
import conformance as c
from bql_table_differential import error_category


def run(ours, oracle):
    if unicodedata.unidata_version!='16.0.0':
        return [dict(query='Unicode version',ok=False,detail='requires Python Unicode 16.0.0')]
    texts=['ΟΣ ΟΣΑ AΣ AΣA ßİıﬃ𐐀𐐨', 'AΣ\u0301 AΣ\u0301A', '', '中文😀']
    changed=''.join(chr(n) for n in range(0x110000) if chr(n).upper()!=chr(n) or chr(n).lower()!=chr(n))
    texts.extend(changed[i:i+96] for i in range(0,len(changed),96))
    generated=Path('query/unicode_data.mbt').read_text()
    points=set()
    for block in generated.split('let unicode_')[1:]:
        for a,b in re.findall(r'\((\d+), (\d+)\)',block):
            points.update(range(int(a),int(b)+1))
    for n in sorted(points):
        ch=chr(n)
        texts.append('A'+ch+'Σ .'+ch+'Σ AΣ'+ch+'. AΣ'+ch+'A')
    rng=random.Random(20261101)
    for _ in range(100):
        texts.append(''.join(rng.choice(changed+' Σ\u0301\u0345\u200d中文😀') for _ in range(80)))
    folder=Path('.oracle-cache/r2-return');folder.mkdir(parents=True,exist_ok=True)
    ledger=(folder/'unicode.beancount').resolve()
    ledger.write_text('2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Opening USD\n'+''.join(
        '2024-01-02 * '+json.dumps(t,ensure_ascii=False)+'\n  Assets:Cash 0 USD\n  Equity:Opening 0 USD\n' for t in texts))
    query='SELECT upper(narration),lower(narration) FROM transactions'
    ours_rows=c.ours_query(ours,str(ledger),query);oracle_rows=c.oracle_query(oracle,str(ledger),query)
    ok,detail=c.compare_scalar_query(ours_rows,oracle_rows) if ours_rows else (False,'ours failed')
    result=[dict(query=query,ok=ok,detail=detail,rows=len(texts),changed_scalars=len(changed),context_scalars=len(points))]
    for expr in ["upper(1)","lower(NULL)","upper(date)","lower(tags)","upper('x',1)"]:
        query='SELECT '+expr+' LIMIT 1'
        a=subprocess.run([ours,'query',str(ledger),query,'--json'],capture_output=True,text=True)
        b=c.run([str(Path(oracle)/'bean-query'),'-f','csv',str(ledger),query])
        ac=error_category(a.stdout+a.stderr,True);bc=error_category(b.stdout+b.stderr)
        result.append(dict(query=query,ok=a.returncode!=0 and b.returncode!=0 and ac==bc,detail=f'{ac}/{bc}'))
    return result
