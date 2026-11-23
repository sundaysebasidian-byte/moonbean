#!/usr/bin/env python3
"""R14 review: exact parser diagnostics/recovery plus the 733-ledger classification corpus.

The retained reviewer scripts under review_r14/ preserve their original commands.
This runner materializes immutable inputs in a private portable filesystem context.
Oracle access uses only its public loader, printer and cursor APIs.
"""
import hashlib,json,os,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'tests/r14/rework'

def worker(paths):
    from beancount.loader import load_file
    from beancount.parser.printer import print_entries
    from beanquery import connect
    from io import StringIO
    rows=[]
    for path in paths:
        entries,errors,_=load_file(path)
        printed=StringIO();print_entries(entries,file=printed)
        cur=connect('beancount:'+path).execute('SELECT count(*)')
        rows.append(dict(exit=int(bool(errors)),printed=printed.getvalue(),count=[list(r) for r in cur.fetchall()],diagnostics=[dict(kind=type(e).__name__,line=e.source.get('lineno'),message=e.message) for e in errors]))
    return rows

def materialize():
    cache=ROOT/'.oracle-cache/r14-rework/corpus';cache.mkdir(parents=True,exist_ok=True)
    cases=json.loads((DATA/'cases.json').read_text())
    def copy(path,relative):
        data=path.read_bytes();target=cache/relative;target.parent.mkdir(parents=True,exist_ok=True)
        data=data.replace(b'/tmp/r14-review/mut',str(cache/'mut').encode()).replace(b'/tmp/r14/',(str(cache/'seed')+'/').encode())
        target.write_bytes(data);return str(target)
    case_paths={c['path'] for c in cases}
    for extra in (DATA/'corpus').rglob('*'):
        if extra.is_file() and str(extra.relative_to(DATA/'corpus')) not in case_paths and extra.name!='.gitattributes':copy(extra,extra.relative_to(DATA/'corpus'))
    for rel in ['exists.pdf','docs/a.pdf','docs/sub/b.pdf','sp ace.pdf','ünï.pdf']:
        p=cache/'mut'/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('x')
    # A seed's ordinary document may refer to the repository README.
    (cache/'seed').mkdir(exist_ok=True)
    (cache/'seed/README.md').write_text('document existence fixture\n')
    paths=[]
    for case in cases:
        source=DATA/'corpus'/case['path'];assert hashlib.sha256(source.read_bytes()).hexdigest()==case['sha256']
        paths.append(copy(source,case['path']))
    authored=json.loads((DATA/'authored.json').read_text())
    for case in authored:
        p=cache/'authored'/(case['name']+'.beancount');p.parent.mkdir(exist_ok=True)
        p.write_bytes(case['source'].replace('{{corpus}}',str(cache)).encode());paths.append(str(p))
    return cases,authored,paths

def run(ours,oracle):
    cases,authored,paths=materialize()
    process=subprocess.run([str(Path(oracle)/'python'),__file__,'--worker'],input=json.dumps(paths),capture_output=True,text=True,check=True,timeout=240)
    expected=json.loads(process.stdout);results=[]
    for i,(case,path,b) in enumerate(zip(cases+authored,paths,expected)):
        a=subprocess.run([ours,'check',path],capture_output=True,text=True,timeout=30)
        boundary=case.get('boundary')
        ok=a.returncode==b['exit'] if not boundary else a.returncode==0 and b['exit']==1
        if case.get('expect_unknown_option_rejection'):
            # The old pass-through stopped at R201–250. Require the exact
            # rejection now, including the original option name and line.
            unknown = [e for e in b['diagnostics']
                       if e['kind'] == 'ParserError' and e['message'].startswith('Invalid option: ')]
            ok = ok and a.returncode == 1 and len(unknown) == 1
            if ok:
                e = unknown[0]
                ok = f"{path}:{e['line']}: parse.option: {e['message']}" in a.stderr.splitlines()
        if i<len(cases):ok=ok and b['exit']==case['review_oracle_exit']
        results.append(dict(feature='r14-rework-classification',case=case.get('name',case.get('path')),ok=ok,conformant=a.returncode==b['exit'],boundary=boundary,ours_exit=a.returncode,oracle_exit=b['exit'],ours=a.stdout+a.stderr,oracle=b['diagnostics']))
        if i<len(cases):continue
        lexical=[e for e in b['diagnostics'] if e['kind']=='LexerError']
        if lexical:
            lines=sorted(set(e['line'] for e in lexical));actual=sorted(set(int(n) for n in re.findall(r':(\d+): parse.token:',a.stderr)))
            match=actual==lines
            if case['name'].startswith(('recovery','quoted-','g00-')):
                match=match and all(e['message'] in a.stderr for e in lexical)
            results.append(dict(feature='r14-rework-lexer-lines',case=case['name'],ok=match,ours=a.stderr,oracle=lexical))
        printed=subprocess.run([ours,'query',path,'PRINT'],capture_output=True,timeout=30)
        results.append(dict(feature='r14-rework-print',case=case['name'],ok=printed.returncode==0 and printed.stdout==b['printed'].encode(),ours=printed.stdout.decode(errors='replace'),oracle=b['printed']))
        count=subprocess.run([ours,'query',path,'SELECT count(*)','--json'],capture_output=True,text=True,timeout=30)
        actual=json.loads(count.stdout).get('rows') if count.returncode==0 else count.stdout+count.stderr
        results.append(dict(feature='r14-rework-count',case=case['name'],ok=actual==b['count'],ours=actual,oracle=b['count']))
    return results

if __name__=='__main__':
    if '--worker' in sys.argv:print(json.dumps(worker(json.load(sys.stdin)),ensure_ascii=False))
    else:
        rows=run(sys.argv[1] if len(sys.argv)>1 else '_build/native/release/build/cmd/main/main.exe','/tmp/moonbean-r4-oracle/bin');print(json.dumps(rows,indent=2,ensure_ascii=False));sys.exit(any(not r['ok'] for r in rows))
