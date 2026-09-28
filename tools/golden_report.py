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

STAGES = ['groups', 'pack', 'route', 'tidy', 'power', 'validate', 'other']
SERIES_LIGHT = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#4a3aa7']
SERIES_DARK = ['#3987e5', '#d95926', '#199e70', '#c98500', '#d55181', '#008300', '#9085e9']

def stage_split(d):
    phases = {p.get('name'): float(p.get('cpu') or 0) for p in d.get('phases') or []}
    total = float(d.get('cpu_total') or 0)
    split = {k: phases.get(k, 0.0) for k in STAGES[:-1]}
    split['other'] = max(0.0, total - sum(split.values()))
    return split

def svg_stage_bars(data):
    rows = [d for d in data if float(d.get('cpu_total') or 0) >= 0.05]
    if not rows: return ''
    label_w, bar_w, row_h, top = 250, 520, 24, 34
    vmax = max(float(d.get('cpu_total') or 0) for d in rows)
    h = top + row_h * len(rows) + 30
    out = [f'<svg class="chart" viewBox="0 0 {label_w + bar_w + 90} {h}" role="img" aria-label="CPU seconds by stage per case">']
    lx = label_w
    for i, st in enumerate(STAGES):
        out.append(f'<rect x="{lx}" y="8" width="12" height="12" rx="3" class="s{i}"/><text x="{lx + 16}" y="18" class="lg">{esc(st)}</text>')
        lx += 16 + 8 * len(st) + 14
    for r, d in enumerate(rows):
        y = top + r * row_h
        out.append(f'<text x="{label_w - 8}" y="{y + 15}" class="lb" text-anchor="end">{esc(d.get("case"))}</text>')
        x = label_w
        split = stage_split(d)
        for i, st in enumerate(STAGES):
            v = split[st]
            w = bar_w * v / vmax if vmax else 0
            if w < 0.5: continue
            gap = 2 if w > 3 else 0
            out.append(f'<rect x="{x:.1f}" y="{y + 4}" width="{max(0.5, w - gap):.1f}" height="{row_h - 8}" rx="2" class="s{i}"><title>{esc(d.get("case"))} {esc(st)}: {v:.1f} s</title></rect>')
            x += w
        out.append(f'<text x="{x + 6:.1f}" y="{y + 15}" class="val">{float(d.get("cpu_total") or 0):.1f} s</text>')
    out.append(f'<line x1="{label_w}" y1="{h - 26}" x2="{label_w + bar_w}" y2="{h - 26}" class="axis"/>')
    import math
    raw = vmax / 4 if vmax > 0 else 1
    mag = 10 ** math.floor(math.log10(raw))
    step = min((m * mag for m in (1, 2, 5, 10) if m * mag >= raw), default=raw)
    v = 0.0
    while v <= vmax + 1e-9:
        xx = label_w + bar_w * v / vmax
        out.append(f'<text x="{xx:.1f}" y="{h - 10}" class="tick" text-anchor="middle">{v:g} s</text>')
        v += step
    out.append('</svg>')
    return ''.join(out)

def svg_worst_tick(data):
    import math
    rows = [d for d in data if float((d.get('worst_tick') or {}).get('cpu') or 0) >= 0.001]
    if not rows: return ''
    rows.sort(key=lambda d: -float(d['worst_tick']['cpu']))
    label_w, bar_w, row_h, top = 250, 520, 22, 30
    lo, hi = math.log10(0.01), math.log10(10)
    def px(v): return label_w + bar_w * (math.log10(max(v, 0.01)) - lo) / (hi - lo)
    h = top + row_h * len(rows) + 30
    out = [f'<svg class="chart" viewBox="0 0 {label_w + bar_w + 110} {h}" role="img" aria-label="Worst single tick per case, log scale">']
    for r, d in enumerate(rows):
        y = top + r * row_h
        v = float(d['worst_tick']['cpu'])
        out.append(f'<text x="{label_w - 8}" y="{y + 14}" class="lb" text-anchor="end">{esc(d.get("case"))}</text>')
        out.append(f'<rect x="{label_w}" y="{y + 4}" width="{max(1, px(v) - label_w):.1f}" height="{row_h - 8}" rx="2" class="s0"><title>{esc(d.get("case"))}: {v * 1000:.0f} ms in {esc(d["worst_tick"].get("phase"))}</title></rect>')
        out.append(f'<text x="{px(v) + 6:.1f}" y="{y + 14}" class="val">{v * 1000:.0f} ms ({esc(d["worst_tick"].get("phase"))})</text>')
    bx = px(1 / 60)
    out.append(f'<line x1="{bx:.1f}" y1="{top - 6}" x2="{bx:.1f}" y2="{h - 26}" class="budget"/><text x="{bx + 4:.1f}" y="{top - 10}" class="tick">16.7 ms tick budget</text>')
    out.append(f'<line x1="{label_w}" y1="{h - 26}" x2="{label_w + bar_w}" y2="{h - 26}" class="axis"/>')
    for v, t in ((0.01, '10 ms'), (0.1, '100 ms'), (1, '1 s'), (10, '10 s')):
        out.append(f'<text x="{px(v):.1f}" y="{h - 10}" class="tick" text-anchor="middle">{t}</text>')
    out.append('</svg>')
    return ''.join(out)

def svg_top_calls(d):
    calls = sorted((d.get('calls') or {}).items(), key=lambda x: -float((x[1] or {}).get('cpu') or 0))[:10]
    calls = [c for c in calls if float(c[1].get('cpu') or 0) > 0]
    if not calls: return ''
    label_w, bar_w, row_h, top = 200, 480, 20, 6
    vmax = float(calls[0][1]['cpu'])
    h = top + row_h * len(calls) + 6
    out = [f'<svg class="chart small" viewBox="0 0 {label_w + bar_w + 90} {h}" role="img" aria-label="Top calls by CPU">']
    for r, (k, v) in enumerate(calls):
        y = top + r * row_h
        cpu = float(v.get('cpu') or 0)
        w = bar_w * cpu / vmax if vmax else 0
        out.append(f'<text x="{label_w - 8}" y="{y + 14}" class="lb" text-anchor="end">{esc(k)}</text>')
        out.append(f'<rect x="{label_w}" y="{y + 3}" width="{max(1, w):.1f}" height="{row_h - 6}" rx="2" class="s0"><title>{esc(k)}: {cpu:.2f} s, {v.get("n")} calls, worst {float(v.get("worst") or 0):.3f} s</title></rect>')
        out.append(f'<text x="{label_w + w + 6:.1f}" y="{y + 14}" class="val">{cpu:.1f} s</text>')
    out.append('</svg>')
    return ''.join(out)

def chart_css():
    light = ''.join(f'--series-{i}:{c};' for i, c in enumerate(SERIES_LIGHT))
    dark = ''.join(f'--series-{i}:{c};' for i, c in enumerate(SERIES_DARK))
    cls = ''.join(f'.s{i}{{fill:var(--series-{i})}}' for i in range(len(STAGES)))
    return ('.viz{' + light + '--ink2:#52514e;--grid:#c9c8c3}'
            '@media(prefers-color-scheme:dark){:root:where(:not([data-theme="light"])) .viz{' + dark + '--ink2:#c3c2b7;--grid:#4a4a47}}'
            ':root[data-theme="dark"] .viz{' + dark + '--ink2:#c3c2b7;--grid:#4a4a47}'
            + cls +
            '.chart{width:100%;height:auto;max-width:900px;display:block;margin:8px 0 20px}.chart.small{max-width:780px}'
            '.chart text{font:12px system-ui,sans-serif;fill:var(--fg)}.chart .tick,.chart .lg{fill:var(--ink2)}.chart .val{fill:var(--fg)}'
            '.chart .axis{stroke:var(--grid);stroke-width:1}.chart .budget{stroke:var(--fg);stroke-width:1.5;stroke-dasharray:4 3}'
            '.chart rect:hover{opacity:.8}')

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
    chunks=['<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>'+esc(args.title)+'</title><style>:root{color-scheme:light dark;--bg:#fff;--fg:#17202a;--line:#ccd3da;--head:#edf1f5;--link:#075da8} @media(prefers-color-scheme:dark){:root{--bg:#15191e;--fg:#e4e8ed;--line:#424a53;--head:#252c34;--link:#8fc4ff}}*{box-sizing:border-box}body{margin:0 16px;background:var(--bg);color:var(--fg);font:14px system-ui,sans-serif}h1{font-size:1.5rem}h2{font-size:1.2rem;margin-top:2.2rem}.scroll{max-width:100%;overflow-x:auto;margin:10px 0 20px}table{border-collapse:collapse;white-space:nowrap;width:100%}th,td{border:1px solid var(--line);padding:6px 9px;text-align:left}th{background:var(--head);position:sticky;top:0}section{margin-bottom:32px}'+chart_css()+'</style></head><body class="viz"><h1>'+esc(args.title)+'</h1><h2>Summary</h2>'+table(['case','ok','cpu s','ticks','entities','slowest stage','top 3 calls','grids tried','route restarts','first valid tick'],summary)
              +'<h2>CPU by stage</h2>'+svg_stage_bars(data)+'<h2>Worst single tick</h2>'+svg_worst_tick(data)]
    for d in data:
        chunks.append('<section><h2>'+esc(d.get('case'))+'</h2>')
        chunks.append('<h3>Phases</h3>'+table(['phase','entries','ticks','cpu s','ops'],[[p.get('name'),p.get('entries'),p.get('ticks'),num(p.get('cpu')),p.get('ops')] for p in d.get('phases') or []]))
        chunks.append('<h3>Grids</h3>'+table(['#','grid','w','h','attempt','layered','start tick','cpu s','ops','outcome stage','reject codes'],[[g.get('nth'),g.get('grid_index'),g.get('w'),g.get('h'),g.get('attempt'),g.get('layered'),g.get('start_tick'),num(g.get('cpu')),g.get('ops'),g.get('outcome_stage'),', '.join(g.get('reject_codes') or [])] for g in d.get('grids') or []]))
        chunks.append('<h3>Stages</h3>'+table(['stage','calls','cpu s','worst s'],[[k,v.get('calls'),num(v.get('cpu')),num(v.get('worst'))] for k,v in sorted((d.get('stages') or {}).items())]))
        calls=sorted((d.get('calls') or {}).items(),key=lambda x:float((x[1] or {}).get('cpu') or 0),reverse=True)[:10]
        chunks.append('<h3>Top calls</h3>'+svg_top_calls(d)+table(['call','n','cpu s','worst s'],[[k,v.get('n'),num(v.get('cpu')),num(v.get('worst'))] for k,v in calls]))
        ds=sorted(d.get('route_demands_top') or [],key=lambda x:float(x.get('cpu') or 0),reverse=True)[:10]
        chunks.append('<h3>Top route demands</h3>'+table(['flow id','kind','cpu s','expansions','outcome'],[[x.get('flow_id'),x.get('kind'),num(x.get('cpu')),x.get('expansions'),x.get('outcome')] for x in ds]))
        rej=d.get('rejections') or {}; chunks.append('<h3>Rejections</h3>'+table(['code','count','stages'],[[k,v.get('count'),', '.join(f'{s}: {n}' for s,n in (v.get('stages') or {}).items())] for k,v in sorted(rej.items())])); chunks.append('</section>')
    chunks.append('</body></html>'); Path(args.out).write_text('\n'.join(chunks),encoding='utf-8')
if __name__=='__main__': main()
