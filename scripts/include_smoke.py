#!/usr/bin/env python3
"""Exercise the real async CLI include host, retaining files for diagnosis."""
import argparse
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
