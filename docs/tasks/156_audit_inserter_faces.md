# 156 audit: a blueprint inserter takes from the tile it FACES

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-156`, branch
`lane/156`, base tag `round-19-base` (resolve with `git rev-parse round-19-base`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**Round 18's delivered blueprint had every one of its 26 inserters 180 degrees wrong**, and this tool said
`invalid_inserters=0`, because the tool holds the same wrong rule as the code it judges.

`tools/blueprint_audit.py:211-213`:

```python
        #Base inserter geometry: it reaches BEHIND itself to pick up and drops in the direction it faces.
        vx, vy = VEC[direction]
        pickup = endpoint_kind(cells.get((px - vx, py - vy)))
```

**That is backwards for a blueprint.** In a blueprint an inserter's `direction` names its **pickup**: the
game takes from the tile the inserter faces and drops behind it. `docs/feature-contracts.md:172-173` has
said so since it was written — *"An inserter's `dir` points at its pickup, and `drop_position` decides, not
the other way round."*

**The proof is the player's own working factory**, `~/share/RRC/red_science_1s_manual_bp.txt`, which the
game runs. Measured on this host 2026-09-22:

```
belt columns present: 186.5 187.5 ... 205.5, then 211.5      <- 211.5 is ISOLATED
science machines    : x = 208.5, spanning tiles 207.5 208.5 209.5
its two hands       : (206.5, 1076.5) dir=12 W   and   (210.5, 1076.5) dir=12 W
```

Nothing inside that factory can feed the isolated column at `211.5`: copper plate and gears are made at
`x <= 204.5` and travel on belts that stop at `205.5`. So **ingredients must reach the science machines
from `205.5`**, which makes the hand at `(206.5, 1076.5)` the INPUT. A WEST-facing hand at `206.5` whose
pickup is `205.5` is only possible when `direction` names the pickup. The isolated `211.5` column is the
science pack leaving the factory.

Measured the other way round on round 18's delivery, with the correct rule applied to its published bytes:

```
(16.5, 2.5) dir=N  game picks transport-belt       drops assembling-machine-3
(15.5, 3.5) dir=E  game picks assembling-machine-3 drops transport-belt
(19.5, 3.5) dir=W  game picks assembling-machine-3 drops transport-belt
```

The first is the science machine's OUTPUT hand feeding the machine from a belt; the next two are its INPUT
hands emptying it onto the ingredient belts. **All 26 are inverted.**

The spine fixes the publish boundary in `logic/bp/serialize.lua`. **This lane fixes the judge**, and it must
not be the same hand that wrote the thing it judges.

Measured baselines, green, none may regress:

```
python3 -m unittest tests.tools.test_blueprint_audit     Ran 22 tests   OK
python3 -m unittest tests.tools.test_real_sheet_census   Ran 21 tests   OK
python3 -m unittest tests.tools.test_deliver             Ran  8 tests   OK
```

## Traps, each measured

**Trap: this tool is THE ORACLE for delivered bytes.** Contract 26.7. It decodes the string and re-derives
geometry precisely so `logic/` cannot fool it. Keep it that way: read nothing from `logic/`, import nothing
from the mod.

**Trap: the round 13 frozen baseline must NOT move.** `~/share/RRC/rrc-round13-mine.txt`, sha256
`9e075dddf2a16485cfa4d24e45b5fc62f2ba6cb04fbc23236ca6b8c78cb3d95a`, measures `invalid_inserters 11` and
`unused_belt_tiles 51` today. **`invalid_inserters` on that artifact WILL change when the rule flips**, and
that is expected, not a regression — report the new number in the lane report with both values side by side
and say plainly which rule produced each. Do **not** silently rewrite the docstring's numbers.

**Trap: `VEC` is `{0:(0,-1), 4:(1,0), 8:(0,1), 12:(-1,0)}`** at `tools/blueprint_audit.py:66`, NORTH `0`,
EAST `4`, SOUTH `8`, WEST `12`. With the correct rule, pickup is at `+VEC[direction]` and drop at
`-VEC[direction]` — the exact opposite of the two lines quoted above.

**Trap: `audit_orphans` uses the same convention** at `tools/blueprint_audit.py:302-330`, where inserter
drops seed the forward walk and pickups seed the backward walk. **Flip those too**, or the waste check will
report every belt in a correct blueprint as unused.

**Trap: the splitter footprint landed last session.** `occupied_tiles` reads a splitter's two tiles from its
direction. Leave it alone; it is right.

**Trap: the python tests are `unittest`, not `pytest`.** `python3 -m pytest` reports `No module named
pytest`. Run `python3 -m unittest tests.tools.test_blueprint_audit`.

PRESERVE: `logic/**`, `tools/blueprint_string.py`, `tools/deliver.sh`, `tools/census_gate.py`,
`tools/real_sheet_census.py`, `tools/red_list.sh`, `tests/**` except
`tests/tools/test_blueprint_audit.py`, `docs/round-18-census-baseline.json`, `docs/round-16-red-list.txt`,
`docs/feature-contracts.md`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

## Files this lane owns

`tools/blueprint_audit.py`, `tests/tools/test_blueprint_audit.py`. **Nothing else.** The spine is editing
`logic/bp/serialize.lua` and lanes 157, 158, 159 own other files; touching any of them loses the merge.

## What to build

1. **Correct the rule**: an inserter picks up from the tile at `+VEC[direction]` and drops at
   `-VEC[direction]`, in `audit_inserters` and in `audit_orphans`. Correct the comment at `:211` too — a
   stale comment is how this survived.
2. **Anchor it on the player's factory**, which is the only thing here the code cannot fake. A case that
   decodes `~/share/RRC/red_science_1s_manual_bp.txt` and asserts:
   - the hand at `(206.5, 1076.5)` facing WEST picks from the belt at `205.5` and drops into the machine;
   - the hand at `(210.5, 1076.5)` facing WEST picks from the machine and drops onto the isolated belt at
     `211.5`;
   - that file audits with **`invalid_inserters == 0`** under the corrected rule.
   **Red at base**: under today's rule those assertions fail.
3. **A negative control** that still fails: a hand-built inserter with a belt on one side and empty ground
   on the other is still reported, so the tool can still say no.
4. Report the round 13 artifact's `invalid_inserters` before and after.

## What done mean

Two checks. A check block takes one `gateslot` lease PER check and hands it back between them.

```checks
{"name": "audit-inserter-faces", "command": "git diff --name-only round-19-base HEAD | grep -v '^docs/tasks/156' | grep -Ev '^(tools/blueprint_audit\\.py|tests/tools/test_blueprint_audit\\.py)$' | ( ! grep . ) && python3 -m unittest tests.tools.test_blueprint_audit 2>&1 | tail -1 | grep -q '^OK' && python3 -m unittest tests.tools.test_real_sheet_census 2>&1 | tail -1 | grep -q '^OK' && python3 -m unittest tests.tools.test_deliver 2>&1 | tail -1 | grep -q '^OK' && python3 tools/blueprint_audit.py \"$HOME/share/RRC/red_science_1s_manual_bp.txt\" 2>&1 | grep -q 'invalid_inserters *0' && echo audit-faces-ok", "expect_exit": 0, "expect_regex": "audit-faces-ok", "timeout_s": 1200}
{"name": "red-at-base", "command": "set -e; base=$(mktemp -d); git worktree add -q --detach \"$base\" round-19-base; cp tests/tools/test_blueprint_audit.py \"$base/tests/tools/test_blueprint_audit.py\"; cd \"$base\"; fail=0; python3 -m unittest tests.tools.test_blueprint_audit 2>&1 | tail -1 | grep -q '^OK' && fail=1 || true; cd - >/dev/null; git worktree remove --force \"$base\"; [ \"$fail\" = 0 ] || { echo 'the new cases are GREEN at round-19-base, where the rule is still backwards; they prove nothing'; exit 1; }; echo red-at-base-ok", "expect_exit": 0, "expect_regex": "red-at-base-ok", "timeout_s": 900}
```

Re-cut because: none

# bound: 4000s

Reviewer ask: does the auditor now read the player's own working factory as having zero invalid inserters,
and does it still refuse a hand pointing at empty ground?
