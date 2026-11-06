#!/usr/bin/env python3
"""Serialize public loader output from the external pinned oracle."""
import json
import sys
from beancount import loader
entries, _, _ = loader.load_file(sys.argv[1])
print(json.dumps([(str(e.date), e.currency, str(e.amount.number), e.amount.currency)
                  for e in entries if type(e).__name__ == 'Price']))
