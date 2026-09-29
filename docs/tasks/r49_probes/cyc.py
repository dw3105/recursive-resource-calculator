import sys, importlib.util
from pathlib import Path
sys.setrecursionlimit(100000)
spec=importlib.util.spec_from_file_location("ba","tools/blueprint_audit.py"); ba=importlib.util.module_from_spec(spec); spec.loader.exec_module(ba)
ents,_,_=ba.load_entities(Path(sys.argv[1]))
_,_,pairs=ba.audit_underground(ents)
T={t:e for e in ents if e.get("name") in ba.BELTS|ba.UG_BELTS|ba.SPLITTERS for t in ba.occupied_tiles(e)}
pm={a:b for a,b in pairs}|{b:a for a,b in pairs}
G={}
for c,e in T.items():
    v=ba.VEC.get(e.get("direction",0)); d=[]
    if e.get("name") in ba.UG_BELTS and e.get("type")=="input":
        q=pm.get(c); d=[q] if q in T else []
    elif v:
        if e.get("name") in ba.SPLITTERS: d=[q for t in ba.occupied_tiles(e) if (q:=(t[0]+v[0],t[1]+v[1])) in T]
        else:
            q=(c[0]+v[0],c[1]+v[1]); d=[q] if q in T else []
    G[c]=d
stack=[];on=set();done=set()
def visit(n):
    if n in on:
        i=stack.index(n); cyc=stack[i:]
        print("CYCLE", len(cyc)); 
        for t in cyc: e=T[t]; print("  ",t,e["name"],e.get("type",""),"dir",e.get("direction",0))
        return
    if n in done: return
    on.add(n); stack.append(n)
    for q in G[n]: visit(q)
    stack.pop(); on.remove(n); done.add(n)
for c in G: visit(c)
