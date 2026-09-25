#!/usr/bin/env python3
"""Independent belt simulation on delivered blueprint bytes. Game rules only:

- an inserter's published dir points at its PICKUP; a long-handed inserter reaches two tiles;
- an inserter drops on the FAR lane of the belt it drops on;
- a belt fed only from one side is a curve and keeps lanes; a belt fed from behind takes side entries onto the
  NEAR lane;
- a belt never feeds a belt that faces it head-on;
- a splitter covers two tiles across its facing, takes items ONLY from a belt/underground exit/splitter behind it
  facing the same way, and sends every lane to the tile in front of both of its tiles (lanes kept).

For every inserter that drops into a machine it prints the items on each lane of its pickup tile.
MIXED: one lane carries two items that also appear on the other lane.
STARVED: nothing reaches the pickup tile, or (recipe known) nothing on it is an ingredient.
BLEED: (recipe known) an item on the pickup tile is no ingredient of the machine: another flow ran into this belt
(player, green v2, 2026-09-24: circuits on the science belt). Smelter/external sources count as wildcards.
Last line: `LANE-SIM mixed=M starved=S bleed=B`.

Usage: lane_sim.py bp.txt [--input prepared_input.json]   (machine sizes and recipes from its catalog)"""
import json, math, sys
from collections import defaultdict, deque
from pathlib import Path

VEC = {0: (0, -1), 4: (1, 0), 8: (0, 1), 12: (-1, 0)}
SIZE_FALLBACK = {'foundry': 5, 'electromagnetic-plant': 4, 'roboport': 4, 'beacon': 3}

args = [a for a in sys.argv[1:]]
catalog = {}
if '--input' in args:
    i = args.index('--input')
    catalog = json.load(open(args[i + 1])).get('catalog', {})
    del args[i:i + 2]
if not args or not args[0].endswith('.txt'):
    sys.exit('pass the delivered bp.txt, never r.json (internal inserter dirs differ)')
sys.path.insert(0, str(Path(__file__).resolve().parent))
from blueprint_audit import load_entities
ents = load_entities(Path(args[0]))[0]
tile = lambda e: (math.floor(e['position']['x']), math.floor(e['position']['y']))

def size_of(name):
    spec = (catalog.get('entity') or {}).get(name) or {}
    if spec.get('tile_w') and spec.get('tile_h'): return int(spec['tile_w']), int(spec['tile_h'])
    s = SIZE_FALLBACK.get(name, 3)
    return s, s

def ingredients(recipe):
    r = (catalog.get('recipe') or {}).get(recipe)
    if not r: return None
    return {i['name'] for i in r.get('ingredients', []) if i.get('type', 'item') == 'item'}

def products(recipe):
    r = (catalog.get('recipe') or {}).get(recipe)
    if not r: return {recipe}
    return {p['name'] for p in r.get('products', []) if p.get('type', 'item') == 'item'} or {recipe}

belts, ugs, splitter_of, machines, hands = {}, {}, {}, [], []
for e in ents:
    n, d = e['name'], e.get('direction', 0)
    if n.endswith('transport-belt'): belts[tile(e)] = d
    elif 'underground' in n: ugs[tile(e)] = (d, e.get('type'))
    elif 'splitter' in n:
        cx, cy = e['position']['x'], e['position']['y']
        if d in (0, 8): cells = [(math.floor(cx - 0.5), math.floor(cy)), (math.floor(cx + 0.5), math.floor(cy))]
        else: cells = [(math.floor(cx), math.floor(cy - 0.5)), (math.floor(cx), math.floor(cy + 0.5))]
        for c in cells: splitter_of[c] = (d, cells)
    elif 'inserter' in n: hands.append(e)
    elif n == 'roboport' or 'pole' in n or 'substation' in n or 'pipe' in n or 'beacon' in n: pass
    else:
        w, h = size_of(n)
        x0, y0 = round(e['position']['x'] - w / 2), round(e['position']['y'] - h / 2)
        machines.append({'e': e, 'x0': x0, 'y0': y0, 'w': w, 'h': h})

def machine_at(p):
    for m in machines:
        if m['x0'] <= p[0] < m['x0'] + m['w'] and m['y0'] <= p[1] < m['y0'] + m['h']: return m

pair = {}
for p, (d, t) in ugs.items():
    if t != 'input': continue
    vx, vy = VEC[d]
    for k in range(1, 12):
        q = (p[0] + vx * k, p[1] + vy * k)
        if q in ugs and ugs[q][0] == d:
            if ugs[q][1] == 'output': pair[p] = q
            break

def is_transport(p): return p in belts or p in ugs or p in splitter_of
def dir_of(p):
    if p in belts: return belts[p]
    if p in ugs: return ugs[p][0]
    if p in splitter_of: return splitter_of[p][0]

def outs(p):
    """Tiles p hands items to, by game rules (receiver acceptance included)."""
    if p in ugs and ugs[p][1] == 'input':
        return [pair[p]] if p in pair else []
    d = dir_of(p); vx, vy = VEC[d]
    src = splitter_of[p][1] if p in splitter_of else [p]
    result = []
    for s in src:
        q = (s[0] + vx, s[1] + vy)
        if not is_transport(q) or q in src: continue
        dq = dir_of(q)
        if (dq + 8) % 16 == d: continue                 # head-on
        if q in splitter_of and dq != d: continue       # splitter only from behind
        if q in ugs and ugs[q][1] == 'output': continue  # an exit takes nothing from the surface
        result.append(q)
    return result

succ = {p: outs(p) for p in list(belts) + list(ugs) + list(splitter_of)}
pred = defaultdict(list)
for p, qs in succ.items():
    for q in qs: pred[q].append(p)

def right_of(d): vx, vy = VEC[d]; return (-vy, vx)
lanes = defaultdict(set)
queue = deque()
def add(p, lane, item):
    if is_transport(p) and item not in lanes[(p, lane)]:
        lanes[(p, lane)].add(item); queue.append((p, lane, item))

def hand_receivers(drop):
    """Tiles directly seeded by a hand; splitter input is shared across its two halves."""
    return splitter_of[drop][1] if drop in splitter_of else [drop]

def reach(h):
    return 2 if 'long' in h['name'] else 1

for h in hands:
    hx, hy = tile(h); vx, vy = VEC[h.get('direction', 0)]; k = reach(h)
    pick, drop = (hx + vx * k, hy + vy * k), (hx - vx * k, hy - vy * k)
    m = machine_at(pick)
    if m and is_transport(drop):
        rx, ry = right_of(dir_of(drop))
        far = 'R' if (drop[0] - hx) * rx + (drop[1] - hy) * ry > 0 else 'L'
        recipe = m['e'].get('recipe')
        for item in (products(recipe) if recipe else {'smelt@%d,%d' % (m['x0'], m['y0'])}):
            # A hand can side-load either half of a splitter; the receiving half is an input,
            # and the splitter carries that input to both halves before forwarding it.
            for cell in hand_receivers(drop):
                add(cell, far, item)
def fed(p):
    # A splitter takes from behind either of its two tiles and mixes both into both outputs.
    cells = splitter_of[p][1] if p in splitter_of else [p]
    return any(pred[c] for c in cells)
for p in succ:
    if not fed(p) and not (p in ugs and ugs[p][1] == 'output'):
        if not any(lanes[(p, l)] for l in 'LR'):
            add(p, 'L', 'ext@%d,%d' % p); add(p, 'R', 'ext@%d,%d' % p)
while queue:
    p, lane, item = queue.popleft()
    for q in succ[p]:
        dq, dp = dir_of(q), dir_of(p)
        if q in splitter_of:
            for c in splitter_of[q][1]: add(c, lane, item)  # both halves carry every input lane
            continue
        if p in splitter_of or dp == dq or (q in ugs and ugs[q][1] == 'output'):
            add(q, lane, item)
            continue
        behind = [f for f in pred[q] if dir_of(f) == dq]
        if not behind and len(pred[q]) == 1:
            add(q, lane, item)  # curve keeps lanes
        else:
            rx, ry = right_of(dq)
            near = 'R' if (p[0] - q[0]) * rx + (p[1] - q[1]) * ry > 0 else 'L'
            add(q, near, item)

bad = starved = bleed = 0
for h in sorted(hands, key=lambda e: tile(e)):
    hx, hy = tile(h); vx, vy = VEC[h.get('direction', 0)]; k = reach(h)
    pick, drop = (hx + vx * k, hy + vy * k), (hx - vx * k, hy - vy * k)
    m = machine_at(drop)
    if m and is_transport(pick):
        L, R = sorted(lanes[(pick, 'L')]), sorted(lanes[(pick, 'R')])
        mixed = bool(set(L) & set(R)) and len(set(L) | set(R)) > 1
        recipe = m['e'].get('recipe')
        need = ingredients(recipe) if recipe else None
        items = set(L) | set(R)
        wild = any(i.startswith('ext@') or i.startswith('smelt@') for i in items)
        hungry = not items or (need is not None and not wild and not (items & need))
        stray = sorted(i for i in items if need is not None and i not in need
                       and not i.startswith('ext@') and not i.startswith('smelt@'))
        bad += mixed; starved += hungry; bleed += bool(stray)
        print('%s hand %s -> %s L=%s R=%s%s%s' % (recipe or 'smelt', (hx, hy), m['e']['name'], L, R,
              '  MIXED' if mixed else '', '  STARVED' if hungry else '') + ('  BLEED %s' % stray if stray else ''))
print('LANE-SIM mixed=%d starved=%d bleed=%d' % (bad, starved, bleed))
