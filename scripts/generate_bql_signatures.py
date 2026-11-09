#!/usr/bin/env python3
"""Generate argument/schema data from the committed black-box inventory; run moon fmt afterward."""
import json,re
x=json.load(open('docs/evidence/compatibility-inventory.json'))
sigs=[]
for s in x['functions']+x['aggregates']:
 n,a=s.split('('); args=a[:-1].split(', ') if a[:-1] else []
 sigs.append((n,args))
with open('query/signatures.mbt','w') as f:
 f.write('// Argument signatures from public beanquery 0.2.0 .help targets.\n///|\nlet oracle_signatures : Array[(String, Array[String])] = [\n')
 for n,a in sigs:f.write('  ('+json.dumps(n)+', ['+', '.join(json.dumps(t) for t in a)+']),\n')
 f.write(']\n\n///|\nfn column_type(source : QuerySource, name : String) -> String {\n  let table = match source { SrcDirectives(t) => t; SrcTransactions => "entries"; _ => "postings" }\n  match (table, name) {\n')
 for table,desc in x['tables'].items():
  for col,t in re.findall(r'^  (\w+) \(([^)]+)\)',desc,re.M):
   t={'metadata':'dict','set[str]':'generic_set','transaction':'directive','open':'directive','close':'directive'}.get(t,t)
   f.write(f'    ({json.dumps(table)}, {json.dumps(col)}) => {json.dumps(t)}\n')
 f.write('    (_, "units" | "weight" | "cost" | "value") => "amount"\n    (_, "root" | "parent" | "leaf") => "str"\n    _ => "unknown"\n  }\n}\n')
