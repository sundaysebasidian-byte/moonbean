"""Black-box oracle PRINT renderer using public cursor and printer APIs."""
import io
import json
import sys
from beanquery import connect
from beancount.parser.printer import print_entries

connections = {}
results = []
for case in json.load(sys.stdin):
    ledger = case['ledger']
    try:
        if ledger not in connections:
            connections[ledger] = connect('beancount:' + ledger)
        cursor = connections[ledger].execute(case['query'])
        buffer = io.StringIO()
        print_entries([row[0] for row in cursor.fetchall()], file=buffer)
        results.append(dict(exit=0, output=buffer.getvalue()))
    except Exception as error:
        results.append(dict(exit=1, output='', error=type(error).__name__, message=str(error)))
print(json.dumps(results, ensure_ascii=False))
