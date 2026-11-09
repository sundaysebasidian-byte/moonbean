#!/usr/bin/env python3
"""Serialize public beanquery values without reading implementation source."""
import sys,json,datetime,decimal,enum
from beanquery import connect

def encode(v):
    if v is None or isinstance(v,(str,bool,int)):return v
    if isinstance(v,decimal.Decimal):return {'_decimal':str(v)}
    if isinstance(v,datetime.date):return {'_date':v.isoformat()}
    if isinstance(v,enum.Enum):return {'_enum':type(v).__name__,'value':v.value}
    if isinstance(v,type):return {'_python_type':v.__qualname__ if v.__module__=='builtins' else v.__module__+'.'+v.__qualname__}
    if type(v).__name__=='Inventory':return [encode(p) for p in v.get_positions()]
    if isinstance(v,dict):return {str(k):encode(x) for k,x in v.items()}
    if isinstance(v,(set,frozenset)):return sorted(v)
    if type(v).__name__=='Position':return {'units':encode(v.units),'cost':None if v.cost is None else {'number':str(v.cost.number),'currency':v.cost.currency,'date':None if v.cost.date is None else v.cost.date.isoformat(),'label':v.cost.label}}
    if type(v).__name__=='Amount':return {'number':str(v.number),'currency':v.currency}
    if hasattr(v,'_fields'):return {'_type':type(v).__name__,**{k:encode(getattr(v,k)) for k in v._fields}}
    if isinstance(v,(list,tuple)):return [encode(x) for x in v]
    raise TypeError('unhandled public value '+type(v).__name__)

try:
    cur=connect('beancount:'+sys.argv[1]).execute(sys.argv[2])
    print(json.dumps([[encode(v) for v in row] for row in cur.fetchall()],ensure_ascii=False))
except Exception as e:
    print(json.dumps({'error_type':type(e).__name__,'message':str(e)}))
    sys.exit(1)
