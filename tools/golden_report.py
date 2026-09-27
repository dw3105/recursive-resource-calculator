#!/usr/bin/env python3
"""Render golden_profile JSON files into one self-contained HTML report."""
import argparse, html, json
from pathlib import Path

def esc(x): return html.escape(str(x if x is not None else ""))
def num(x, digits=3):
    try: return f"{float(x):.{digits}f}"
    except (TypeError, ValueError): return ""
def table(headers, rows):
    return '<div class="scroll"><table><thead><tr>'+''.join('<th>'+esc(h)+'</th>' for h in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+esc(c)+'</td>' for c in r)+'</tr>' for r in rows)+'</tbody></table></div>'
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('directory'); ap.add_argument('out'); ap.add_argument('--title',default='RRC golden profile'); args=ap.parse_args()
    files=sorted(Path(args.directory).glob('*.json')); data=[]
    for p in files:
        try: d=json.loads(p.read_text()); d.setdefault('case',p.stem); data.append(d)
        except (OSError,json.JSONDecodeError): continue
    data.sort(key=lambda d: float(d.get('cpu_total') or 0),reverse=True)
    summary=[]
    for d in data:
        calls=sorted((d.get('calls') or {}).items(),key=lambda x:float((x[1] or {}).get('cpu') or 0),reverse=True)
        stages=d.get('stages') or {}; slow=max(stages.items(),key=lambda x:float((x[1] or {}).get('cpu') or 0))[0] if stages else ''
        summary.append([d.get('case'),d.get('ok'),num(d.get('cpu_total')),d.get('ticks'),d.get('entities'),slow,', '.join(k for k,v in calls[:3]),len(d.get('grids') or []),(d.get('route') or {}).get('restarts'),(d.get('first_valid') or {}).get('tick')])
    chunks=['<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>'+esc(args.title)+'</title><style>:root{color-scheme:light dark;--bg:#fff;--fg:#17202a;--line:#ccd3da;--head:#edf1f5;--link:#075da8} @media(prefers-color-scheme:dark){:root{--bg:#15191e;--fg:#e4e8ed;--line:#424a53;--head:#252c34;--link:#8fc4ff}}*{box-sizing:border-box}body{margin:0 16px;background:var(--bg);color:var(--fg);font:14px system-ui,sans-serif}h1{font-size:1.5rem}h2{font-size:1.2rem;margin-top:2.2rem}.scroll{max-width:100%;overflow-x:auto;margin:10px 0 20px}table{border-collapse:collapse;white-space:nowrap;width:100%}th,td{border:1px solid var(--line);padding:6px 9px;text-align:left}th{background:var(--head);position:sticky;top:0}section{margin-bottom:32px}</style></head><body><h1>'+esc(args.title)+'</h1><h2>Summary</h2>'+table(['case','ok','cpu s','ticks','entities','slowest stage','top 3 calls','grids tried','route restarts','first valid tick'],summary)]
    for d in data:
        chunks.append('<section><h2>'+esc(d.get('case'))+'</h2>')
        chunks.append('<h3>Phases</h3>'+table(['phase','entries','ticks','cpu s','ops'],[[p.get('name'),p.get('entries'),p.get('ticks'),num(p.get('cpu')),p.get('ops')] for p in d.get('phases') or []]))
        chunks.append('<h3>Grids</h3>'+table(['#','grid','w','h','attempt','layered','start tick','cpu s','ops','outcome stage','reject codes'],[[g.get('nth'),g.get('grid_index'),g.get('w'),g.get('h'),g.get('attempt'),g.get('layered'),g.get('start_tick'),num(g.get('cpu')),g.get('ops'),g.get('outcome_stage'),', '.join(g.get('reject_codes') or [])] for g in d.get('grids') or []]))
        chunks.append('<h3>Stages</h3>'+table(['stage','calls','cpu s','worst s'],[[k,v.get('calls'),num(v.get('cpu')),num(v.get('worst'))] for k,v in sorted((d.get('stages') or {}).items())]))
        calls=sorted((d.get('calls') or {}).items(),key=lambda x:float((x[1] or {}).get('cpu') or 0),reverse=True)[:10]
        chunks.append('<h3>Top calls</h3>'+table(['call','n','cpu s','worst s'],[[k,v.get('n'),num(v.get('cpu')),num(v.get('worst'))] for k,v in calls]))
        ds=sorted(d.get('route_demands_top') or [],key=lambda x:float(x.get('cpu') or 0),reverse=True)[:10]
        chunks.append('<h3>Top route demands</h3>'+table(['flow id','kind','cpu s','expansions','outcome'],[[x.get('flow_id'),x.get('kind'),num(x.get('cpu')),x.get('expansions'),x.get('outcome')] for x in ds]))
        rej=d.get('rejections') or {}; chunks.append('<h3>Rejections</h3>'+table(['code','count','stages'],[[k,v.get('count'),', '.join(f'{s}: {n}' for s,n in (v.get('stages') or {}).items())] for k,v in sorted(rej.items())])); chunks.append('</section>')
    chunks.append('</body></html>'); Path(args.out).write_text('\n'.join(chunks),encoding='utf-8')
if __name__=='__main__': main()
