#!/usr/bin/env python3
"""Exercise the real async CLI include host, retaining files for diagnosis."""
import argparse
import json
from pathlib import Path
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--ours',default='_build/native/debug/build/cmd/main/main.exe')
a=p.parse_args()
root=Path('.oracle-cache/differential/include-cases').resolve()
root.mkdir(parents=True,exist_ok=True)
(root/'self.beancount').write_text('include "./self.beancount"\n')
(root/'a.beancount').write_text('include "sub/../b.beancount"\n')
(root/'b.beancount').write_text('include "a.beancount"\n')
(root/'absolute.beancount').write_text('include "'+str(root/'absolute.beancount').replace('\\','/')+'"\n')
(root/'missing.beancount').write_text('include "not-present.beancount"\n')
for i in range(100):
    (root/f'deep-{i}.beancount').write_text(f'include "deep-{i+1}.beancount"\n')
(root/'deep-100.beancount').write_text('2024-01-01 open Assets:Cash USD\n')
for file, code in [('self.beancount','include.cycle'),('a.beancount','include.cycle'),('absolute.beancount','include.cycle'),('missing.beancount','include.missing')]:
    proc=subprocess.run([a.ours,'check',str(root/file)],text=True,capture_output=True,timeout=5)
    assert proc.returncode==1 and code in proc.stderr,(file,proc.returncode,proc.stdout,proc.stderr)
proc=subprocess.run([a.ours,'check',str(root/'deep-0.beancount')],text=True,capture_output=True,timeout=5)
assert proc.returncode==0,(proc.stdout,proc.stderr)
print('CLI include self/mutual/absolute cycles, missing file and depth 100: 5/5 PASS')

(root/'child.beancount').write_text('2024-01-01 open Assets:Cash USD\n2024-01-02 note Assets:Cash "kept"\n2024-01-03 note Assets:Cash "still"\n2024-01-04 note Assets:Cash "here"\n2024-01-05 document Assets:Cash "missing-receipt.pdf"\n2024-01-06 balance Assets:Cash 1 USD\n')
(root/'middle.beancount').write_text('include "child.beancount"\n')
for included in ['child.beancount', 'middle.beancount']:
    (root/'root.beancount').write_text(f'2024-01-01 open Equity:Opening USD\ninclude "{included}"\ninclude "not-present.beancount"\n')
    proc=subprocess.run([a.ours,'check',str(root/'root.beancount')],text=True,capture_output=True)
    assert proc.returncode==1,proc
    for file,line,code in [('child.beancount',5,'validation.document_unchecked'),('child.beancount',6,'validation.balance'),('root.beancount',3,'include.missing')]:
        assert f'{root/file}:{line}: {code}:' in proc.stderr,proc.stderr
    (root/'valid.beancount').write_text(f'include "{included}"\n')
    (root/'child.beancount').write_text((root/'child.beancount').read_text().replace('2024-01-06 balance Assets:Cash 1 USD\n',''))
    proc=subprocess.run([a.ours,'export',str(root/'valid.beancount'),'--json'],text=True,capture_output=True)
    assert proc.returncode==0,proc.stderr
    data=json.loads(proc.stdout)
    assert not data['errors'],data
    assert len(data['warnings'])==1,data
    assert data['warnings'][0]['file']==str(root/'child.beancount'),data
    assert data['warnings'][0]['line']==5,data
    with (root/'child.beancount').open('a') as file:
        file.write('2024-01-06 balance Assets:Cash 1 USD\n')
print('CLI nested include source locations in text and JSON: PASS')
