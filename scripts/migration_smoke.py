#!/usr/bin/env python3
"""Check independently authored migration fixtures through the native CLI."""
import json
from pathlib import Path
import shlex
import subprocess

exe = '_build/native/debug/build/cmd/main/main.exe'
root = Path('examples/migration')
records = []
for file, status, diagnostics in [
    ('plugin.beancount', 0, [('validation.plugin', 1)]),
    ('document.beancount', 0, [('validation.document_unchecked', 2)]),
    ('include.beancount', 1, [('include.missing', 2), ('validation.document_unchecked', 2)]),
    ('cycle.beancount', 1, [('include.cycle', 1)]),
    ('queries.beancount', 0, []),
]:
    proc = subprocess.run([exe, 'check', str(root / file)], text=True, capture_output=True)
    assert proc.returncode == status, (file, proc)
    for code, line in diagnostics:
        assert f'{root / file}:{line}: {code}:' in proc.stderr, (file, proc.stderr)
    records.append(dict(file=file, status=proc.returncode, diagnostics=proc.stderr))
for line_number, line in enumerate((root / 'queries.beancount').read_text().splitlines(), 1):
    words = shlex.split(line)
    if len(words) > 1 and words[1] == 'query':
        name, text = words[2:]
        proc = subprocess.run([exe, 'query', str(root / 'queries.beancount'), text], text=True, capture_output=True)
        column = {'subquery': 22, 'join': 30, 'pivot': 16}[name]
        assert proc.returncode == 1, proc
        assert f'query.unsupported.{name} at BQL:1:{column}' in proc.stdout, proc.stdout
        records.append(dict(file='queries.beancount', directive_line=line_number, query=text,
                            status=proc.returncode, error=proc.stdout))
Path('docs/evidence/migration.json').write_text(json.dumps(records, indent=2) + '\n')
print('Migration fixtures: 5 ledger checks, 3 unsupported queries PASS')
