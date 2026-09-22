# 153 audit: the byte auditor has never seen a splitter, and it covers two tiles

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-153`, branch
`lane/153`, base tag `round-18-audit-base` (resolve with `git rev-parse round-18-audit-base`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**The generator now delivers a blueprint.** Measured 2026-09-22 on this host: the player's sheet produces
`ok=true`, encodes to **3314 bytes, 352 entities**, and is written to
`~/share/RRC/player-red-science-1s-20260922.txt`. The byte auditor then refuses it:

```
invalid_inserters        4
unused_belt_tiles        9
unpairable_underground   0

inserter endpoints (contract 26.3): 4
  inserter at (5.5,5.5) facing east: picks up from empty ground, drops onto machine
  inserter at (5.5,17.5) facing east: picks up from empty ground, drops onto machine
  inserter at (9.5,43.5) facing south: picks up from empty ground, drops onto machine
  inserter at (13.5,43.5) facing south: picks up from empty ground, drops onto machine

unused transport (contract 26.2): 9
  splitter at (4, 12.5) serves no obligation: no source reaches it
  splitter at (4, 17.5) serves no obligation: no source reaches it
  splitter at (4.5, 5) serves no obligation: no source reaches it
  splitter at (9.5, 42) serves no obligation: no source reaches it
  splitter at (13.5, 42) serves no obligation: no source reaches it
  splitter at (17, 40.5) serves no obligation: no source reaches it
  splitter at (21, 7.5) serves no obligation: no source reaches it
  splitter at (21, 12.5) serves no obligation: no source reaches it
  splitter at (21, 18.5) serves no obligation: no source reaches it
```

**Every one of the 13 complaints is about a splitter, and there are exactly 9 splitters in the blueprint.**

The cause is one line of prototype fact the tool never had. `tools/blueprint_audit.py:38-46`:

```python
#Tile footprints.  A blueprint carries no size, so the auditor needs the prototype fact to know which cells an
#entity occupies.  Anything absent here is one tile, which is correct for every transport entity and inserter.
SIZE = {
    "assembling-machine-1": 3, ... "big-electric-pole": 2, "substation": 2,
}
```

**`SIZE` has no splitter, and that comment is wrong.** A splitter is **two tiles**, side by side ACROSS its
own direction: north/south spans east-west, east/west spans north-south. `SPLITTERS` is already defined at
`tools/blueprint_audit.py:54`, so the tool knows the names and not the shape.

So `occupancy` at `tools/blueprint_audit.py:166-175` registers a splitter as ONE tile at its own centre —
and a two-tile splitter's centre has one WHOLE coordinate, so it lands on no tile centre at all:

```python
px, py = entity["position"]["x"], entity["position"]["y"]
```

Worked example from the delivered bytes: the splitter reported at `(4.5, 5)` faces east or west, so it is 1
wide and 2 tall and covers tiles `(4,4)` and `(4,5)`, whose centres are `(4.5,4.5)` and `(4.5,5.5)`. The
inserter at `(5.5,5.5)` facing east picks up from `(4.5,5.5)` — the splitter's own second tile — and the
tool calls that **empty ground**. Same defect, reported twice under two contract numbers.

**This is the same class of gap the pole story was**, and it went unseen for the same reason:
`tests/tools/test_blueprint_audit.py` has 18 tests and **not one of them puts a splitter in front of the
auditor**. The delivered bytes never reached the auditor before this round, because the `ok` gate at
`tools/blueprint_string.py:153-154` always refused first.

Measured baselines on this host 2026-09-22, green, none may regress:

```
python3 -m unittest tests.tools.test_blueprint_audit       Ran 18 tests   OK
python3 -m unittest tests.tools.test_real_sheet_census     Ran 17 tests   OK
```

## Traps, each measured

**Trap: this tool is THE ORACLE, and the spine will not relax it for its own work.** That is why this is a
lane. The frozen baseline in the module docstring — *"11 invalid inserters, 12 unpairable pipe-to-ground
endpoints, 89 untouched belt tiles, 3 redundant beacons"* against
`~/share/RRC/rrc-round13-mine.txt` — **must not move**, and the docstring says so itself: *"Any change to
those four numbers is a change to this tool, not a discovery."* If it moves, say so in the lane report with
the exact numbers and STOP; do not adjust the docstring to match.

**Trap: a splitter's two tiles and its position.** A tile centre is at `(n + 0.5, m + 0.5)`. A two-tile
splitter sits at the midpoint of its two tile centres, so **exactly one of its coordinates is a whole
number**. `(4.5, 5)` is east/west facing and covers `(4,4)`+`(4,5)`; `(21, 7.5)` is north/south facing and
covers `(20,7)`+`(21,7)`. Get this backwards and the fix moves every complaint to a different tile instead
of clearing it.

**Trap: `SIZE` is a SCALAR, and a splitter is not square.** `occupancy` reads
`size = SIZE.get(name, 1)` then `half = (size - 1) / 2.0` — one number for both axes. A splitter needs a
width AND a height that depend on `direction`. Decide how to carry that and say so in the lane report;
adding a rectangular footprint beside `SIZE` is fine, and so is a direction-aware helper. **Do not** make a
splitter `2` in `SIZE`, which would claim a 2x2 box and collide with its neighbours.

**Trap: a splitter has TWO inputs and TWO outputs, and no side output.** Items enter at the back of both
covered tiles and leave at the front of both. Every reader that walks the belt graph must be taught this,
not only `occupancy`: `audit_inserters` at `:190-210`, `audit_orphans` at `:275-402` and the bare
`entity["position"]` subscripts at `:203`, `:236`, `:293`, `:309`, `:421`.

**Trap: `VEC` is `{0:(0,-1), 4:(1,0), 8:(0,1), 12:(-1,0)}`** at `tools/blueprint_audit.py:66`, with NORTH
`0`, EAST `4`, SOUTH `8`, WEST `12`. The tile ACROSS the splitter is 90 degrees from its direction; the
tiles in FRONT are one step along its direction from each covered tile.

**Trap: judge the DELIVERED BYTES, never our tables.** Contract 26.7. The tool decodes a blueprint string
and re-derives geometry precisely so it cannot be fooled by `logic/`. Keep it that way: read nothing from
`logic/`, import nothing from the mod.

**Trap: the python tests are `unittest`, not `pytest`.** `python3 -m pytest` reports `No module named
pytest` on this host. Run `python3 -m unittest tests.tools.test_blueprint_audit`.

PRESERVE: `logic/**`, `tools/blueprint_string.py`, `tools/deliver.sh`, `tools/census_gate.py`,
`tools/red_list.sh`, `tests/**` except `tests/tools/test_blueprint_audit.py`,
`docs/round-16-census-baseline.json`, `docs/round-16-red-list.txt`,
`docs/round-16-delivery-target.json`, `docs/feature-contracts.md`, `info.json`, `mod-description.md`,
`.agent-lane.toml`.

## Files this lane owns

`tools/blueprint_audit.py`, `tests/tools/test_blueprint_audit.py`.

**Nothing else.** Lane 151 is editing `tools/blueprint_string.py` and `tools/deliver.sh` in parallel and the
spine is editing `logic/bp/route.lua`; touching either loses the merge.

## What to build

1. **Teach `tools/blueprint_audit.py` that a splitter covers two tiles**, chosen by its `direction`, and
   teach every reader that walks the belt graph that a splitter takes items in at the back of BOTH covered
   tiles and delivers them out the front of BOTH. There is **no side output**.
2. **`tests/tools/test_blueprint_audit.py` gains splitter cases, red at base.** At minimum:
   - a hand-built blueprint where a belt run enters a splitter and leaves by the **anchor** tile's output
   - the same leaving by the splitter's **second** tile's output
   - an **east/west** splitter and a **north/south** splitter, so the rotation is isolated
   - an inserter picking up from a splitter's **second** tile, which must be a valid endpoint and is
     reported as `picks up from empty ground` today
   - a negative control: a splitter genuinely reachable by nothing is still reported unused, so the tool can
     still fail
3. **Report what the delivered bytes say after the fix.** Run
   `python3 tools/blueprint_audit.py ~/share/RRC/player-red-science-1s-20260922.txt` and put the
   `invalid_inserters` and `unused_belt_tiles` numbers in the lane report. **They are 4 and 9 today.** If
   anything other than the splitter complaints survives, name it — that is a real finding and the spine
   needs it.

**Do not touch the round 13 frozen baseline.** Re-run it and report the four numbers unchanged.

## What done mean

Two checks. A check block takes one `gateslot` lease PER check and hands it back between them, so nine cheap
checks means nine trips to the back of a shared queue. Everything cheap is folded in with `&&`.

```checks
{"name": "audit-splitter", "command": "git diff --name-only round-18-audit-base HEAD | grep -v '^docs/tasks/153' | grep -Ev '^(tools/blueprint_audit\\.py|tests/tools/test_blueprint_audit\\.py)$' | ( ! grep . ) && python3 -m unittest tests.tools.test_blueprint_audit 2>&1 | tail -1 | grep -q '^OK' && python3 -m unittest tests.tools.test_real_sheet_census 2>&1 | tail -1 | grep -q '^OK' && python3 -m unittest tests.tools.test_deliver 2>&1 | tail -1 | grep -q '^OK' && python3 -c \"import re,pathlib; t=pathlib.Path('tests/tools/test_blueprint_audit.py').read_text(); assert t.lower().count('splitter') >= 8, 'splitter cases are missing'\" && echo audit-splitter-ok", "expect_exit": 0, "expect_regex": "audit-splitter-ok", "timeout_s": 1200}
{"name": "red-at-base", "command": "set -e; base=$(mktemp -d); git worktree add -q --detach \"$base\" round-18-audit-base; cp tests/tools/test_blueprint_audit.py \"$base/tests/tools/test_blueprint_audit.py\"; cd \"$base\"; fail=0; python3 -m unittest tests.tools.test_blueprint_audit 2>&1 | tail -1 | grep -q '^OK' && fail=1 || true; cd - >/dev/null; git worktree remove --force \"$base\"; [ \"$fail\" = 0 ] || { echo 'the new splitter cases are GREEN at round-18-audit-base; they prove nothing'; exit 1; }; echo red-at-base-ok", "expect_exit": 0, "expect_regex": "red-at-base-ok", "timeout_s": 900}
```

Re-cut because: none

# bound: 4000s

Reviewer ask: does the auditor now read a splitter's TWO tiles from its position and direction, and does the
round 13 frozen baseline in the module docstring still report 11 / 12 / 89 / 3 unchanged?
