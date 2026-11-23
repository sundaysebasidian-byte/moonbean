"""Compare native include/export and Beancount 3.2.3 on actual physical files."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import beancount
from beancount import loader
from beancount.core.data import Transaction

def transaction(date, name):
    return f'{date} * "{name}"\n  Assets:Cash 1 USD\n  Equity:Opening -1 USD\n'

def main(exe):
    assert beancount.__version__ == "3.2.3"
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        parent, child = root / "parent.bean", root / "child.bean"
        parent.write_text("2024-01-01 open Assets:Cash USD\n2024-01-01 open Equity:Opening USD\n"
                          'pushmeta project: "parent"\n' + transaction("2024-01-02", "before")
                          + 'include "child.bean"\n' + transaction("2024-01-04", "after")
                          + "popmeta project:\n", encoding="utf-8")
        results = []
        for invalid in (False, True):
            child.write_text(("popmeta project:\n" if invalid else "")
                             + transaction("2024-01-03", "child"), encoding="utf-8")
            entries, errors, _ = loader.load_file(str(parent))
            ref = {e.narration: e.meta.get("project") for e in entries if isinstance(e, Transaction)}
            ref_errors = [(Path(e.source["filename"]).name, e.source["lineno"]) for e in errors]
            assert ref == {"before":"parent", "after":"parent", "child":None}
            assert ref_errors == ([("child.bean",1)] if invalid else [])
            if invalid:
                assert "absent metadata" in errors[0].message
            run = subprocess.run([exe, "export", str(parent), "--json"], capture_output=True, text=True, timeout=12)
            payload = json.loads(run.stdout)
            actual = {e["narration"]: e["meta"].get("project") for e in payload["entries"] if e["type"]=="transaction"}
            diagnostics = [(Path(e["file"]).name,e["line"],e["code"]) for e in payload["errors"]]
            aligned = actual == ref and diagnostics == [(f,n,"parse.popmeta") for f,n in ref_errors] and run.returncode == int(invalid)
            results.append(aligned)
            print(json.dumps(dict(invalid_child_pop=invalid, reference=ref, reference_errors=ref_errors, actual=actual,
                                  actual_errors=diagnostics, exit=run.returncode, aligned=aligned),sort_keys=True))
        return 0 if all(results) else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
