# 145 probe: name the colliding pair in 18 seconds, never 414

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-145`, branch
`lane/145`, base tag `round-16-wave3` (resolve with `git rev-parse round-16-wave3`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract `docs/feature-contracts.md` section 28, rule 28.6. Ledger `docs/round-16-baseline.md`.
Frozen red list `docs/round-16-red-list.txt`. Frozen census `docs/round-16-census-baseline.json`.

The validator refuses two entities that overlap, `logic/bp/validate.lua:849-860`:

```lua
for other_index = index + 1, #work.infos do
    local other = work.infos[other_index]
    if masks_collide(info.mask, other.mask) and boxes_overlap(world, box_world(other)) then
        error_record(work.errors, "BP_V_COLLISION", {tostring(info.id), tostring(other.id)}, {box_a = world, box_b = box_world(other)})
    end
end
```

That record carries **both ids and both world boxes**, and carries **no name, no kind, no direction and no
tile**. So reading it means joining it back to the candidate by hand, every time.

Measured 2026-09-22 on this host: reading `BP_V_COLLISION` through
`python3 tools/census_gate.py --baseline docs/round-16-census-baseline.json --tier full --no-waivers` costs
**414 s** of wall time. Reading the first candidate through `sh tools/route_chain_probe.sh
player-red-science-1s` costs **17.6 s**. Same fault, 23x the price. The round's standing instruction is to
minimize probe wall time, and this lane is that instruction made permanent.

`tools/route_chain_probe.sh` already carries the whole harness and this lane copies its shape, never its
body. Its lines 38-41 cut `tests/golden/generate.lua` at the argument parser with `awk`, so the probe keeps
that file's `JSON`, `sha256`, `read_file` and `captured_plan` in scope without editing it:

```sh
awk '/^local input_path, output_path/{exit} {print}' \
    "$root/tests/golden/generate.lua" > "$work/probe.lua"
```

`state.work.validate_candidate` is set at `logic/bp/search.lua:1477`, immediately before `Validate.begin`, so
that object is byte for byte what the validator judges.

Trap, measured 2026-09-22 and costing two probe runs: `Validate.begin(candidate)` alone **crashes** with
`./logic/bp/validate.lua:1997: attempt to perform arithmetic on local 'capacity' (a nil value)`. The bare
candidate is not enough input. Drive the validator the way `logic/bp/search.lua` drives it, or compute the
footprints in the report instead.

Trap: not every candidate entity carries `position`. A block member carries `x`, `y`, `w`, `h`. Indexing
`e.position.x` blind fails with `attempt to index local 'p' (a nil value)`. `Geometry.center`
(`logic/bp/geometry.lua:70-79`) is the rule: position first, then `x + w/2`.

Trap: a `splitter` covers **two** tiles and a belt covers one. `tests/test_route_footprints.lua:20-33`
already carries the box rule for both, including the quarter turn. Read it before writing a third copy.

PRESERVE: `logic/**`, `tests/test_*.lua`, `tests/harness.lua`, `tests/golden/cases/player-red-science-1s/`,
`tools/census_gate.py`, `tools/real_sheet_census.py`, `tools/red_list.sh`, `tools/route_chain_probe.sh`,
`tools/route_chain_report.py`, `tools/ceiling.sh`, `tools/blueprint_audit.py`,
`docs/round-16-census-baseline.json`, `docs/round-16-red-list.txt`, `docs/feature-contracts.md`,
`docs/round-16-delivery-target.json`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `tools/collision_probe.sh` (new), `tools/collision_report.py` (new),
`tests/tools/test_collision_report.py` (new).

## What to build

**S1. `tools/collision_probe.sh`.** Same shape as `tools/route_chain_probe.sh`: `usage: collision_probe.sh
[case] [ops] [interpreter]`, defaults `player-red-science-1s`, `5000000`, `lua5.2`. It drives `Search` to the
first candidate reaching `validate`, writes that candidate as JSON, and hands it to
`tools/collision_report.py`. It edits no file in the tree and it never modifies `tests/golden/generate.lua`.

**S2. `tools/collision_report.py`.** One line per overlapping pair, and each line answers the question a
reader actually has:

```
COLLIDE r:825 splitter   tile=(12,8) pos=(12.5,9.0) dir=E span=2  ||  r:856 transport-belt tile=(13,8) pos=(13.5,8.5) dir=E span=1  overlap=0.4x0.9
```

Both ids, both names, both anchor tiles, both published positions, both directions, each entity's tile span,
and the size of the overlap. Mark a `splitter` and an underground endpoint (`ug_role`) by name, because those
are the two shapes whose footprint is not one tile. Then a summary line: pair count, entity count, splitter
count, underground count.

It **reports**. It exits 0 whatever it finds, because producing a diagnosis is never a pass — the same rule
`tools/route_chain_report.py` states in its own docstring. `tools/census_gate.py` judges.

**S3. `tests/tools/test_collision_report.py`.** Python tests under `tests/tools/`, discovered by
`python3 -m unittest discover -s tests/tools -p 'test_*.py' -t .`, which `tests/run.sh:12` runs. Feed the
report hand-built candidates, never the generator:

- two belts one tile apart: **0** pairs
- two belts on one tile: **1** pair, and the line names both ids
- a correctly centred 2-tile `splitter` beside a belt on the next tile: **0** pairs
- that same `splitter` shifted half a tile along its span: **1** pair, and the line says `splitter`
- an entity carrying `x`/`y`/`w`/`h` and no `position`: centred by `x + w/2`, never a crash

The fourth case is the one that matters: it is the real defect this lane was cut for, reduced to nine lines.

**S4. Wall time is the deliverable.** Record in the script's own header comment the measured wall seconds of
one `sh tools/collision_probe.sh player-red-science-1s` run on this host, next to the 414 s the full census
costs. A probe that is not faster than the gate has no reason to exist.

## What done mean

```checks
{"name": "red-proof", "command": "python3 - <<'PY'\nimport subprocess,sys,json,tempfile,pathlib\nsys.path.insert(0,'tools')\nimport collision_report as R\nshifted=[{'id':'a','name':'splitter','position':{'x':12.5,'y':9.0},'direction':4,'splitter':True},{'id':'b','name':'transport-belt','position':{'x':13.5,'y':8.5},'direction':4}]\nok=R.overlapping_pairs(shifted)\nassert len(ok)==0, 'a correctly centred splitter must not collide: %r' % (ok,)\nbad=[dict(shifted[0],position={'x':13.0,'y':9.0}),shifted[1]]\nhit=R.overlapping_pairs(bad)\nassert len(hit)==1, 'a splitter shifted half a tile MUST collide: %r' % (hit,)\nprint('red-proof-ok')\nPY", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "probe-runs", "command": "sh tools/collision_probe.sh player-red-science-1s 2>&1 | tail -3 | grep -Eq 'pairs|COLLIDE' && echo probe-runs-ok", "expect_exit": 0, "expect_regex": "probe-runs-ok", "timeout_s": 900}
{"name": "probe-is-fast", "command": "start=$(date +%s); sh tools/collision_probe.sh player-red-science-1s >/dev/null 2>&1; end=$(date +%s); took=$((end-start)); echo \"probe seconds $took\"; [ $took -lt 120 ] || { echo 'the probe must beat the 414s census by an order of magnitude'; exit 1; }", "expect_exit": 0, "expect_regex": "probe seconds", "timeout_s": 900}
{"name": "report-never-judges", "command": "sh tools/collision_probe.sh player-red-science-1s >/dev/null 2>&1; echo \"exit $?\"; sh tools/collision_probe.sh player-red-science-1s >/dev/null 2>&1 && echo report-never-judges", "expect_exit": 0, "expect_regex": "report-never-judges", "timeout_s": 900}
{"name": "tool-tests", "command": "python3 -m unittest discover -s tests/tools -p 'test_*.py' -t . 2>&1 | tail -3 | grep -q OK && echo tool-tests-ok", "expect_exit": 0, "expect_regex": "tool-tests-ok", "timeout_s": 1800}
{"name": "report-cases", "command": "python3 -m unittest discover -s tests/tools -p 'test_collision_report.py' -t . -v 2>&1 | grep -c '\\.\\.\\. ok' | awk '{ if ($1 >= 5) print \"report-cases-ok\"; else { print \"fewer than five cases: \" $1; exit 1 } }'", "expect_exit": 0, "expect_regex": "report-cases-ok", "timeout_s": 1800}
{"name": "generate-untouched", "command": "git diff --quiet round-16-wave3 HEAD -- tests/golden logic tools/route_chain_probe.sh tools/route_chain_report.py tools/census_gate.py tools/red_list.sh docs && echo generate-untouched || { echo 'this lane changed the generator, the logic, the existing tooling or the docs'; exit 1; }", "expect_exit": 0, "expect_regex": "generate-untouched", "timeout_s": 120}
{"name": "no-new-red", "command": "sh tools/red_list.sh docs/round-16-red-list.txt", "expect_exit": 0, "expect_regex": "RED-LIST ok", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-16-wave3 --manifest docs/tasks/145.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
