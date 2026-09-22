# 151 position: every delivered entity carries its own position, and the encoder refuses one that does not

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-151`, branch
`lane/151`, base tag `round-18-base` (resolve with `git rev-parse round-18-base`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Round 17 reported 13 `medium-electric-pole` entities delivered with **no `position`**, and
`tools/blueprint_audit.py:171` dying `KeyError: 'position'`. **That report was wrong about delivery.**
Re-measured on this host 2026-09-22: `logic/bp/serialize.lua:394-396` sets
`result.position = entity_position(entity)`, and `entity_position` at `logic/bp/serialize.lua:84-95` falls
back to `x + w/2, y + h/2`. Delivered bytes carry a position.

```
$ lua5.2 -e 'package.path="./?.lua;"..package.path; local S=require "logic.bp.serialize"
  local c={entities={{id="p:1",name="medium-electric-pole",quality="normal",x=10,y=20,w=1,h=1}},wires={}}
  for _,e in ipairs((S.canonical(c)).blueprint.entities) do print(e.name, e.position.x..","..e.position.y) end'
medium-electric-pole	7,16
```

The dump that produced the false report came from the **internal** candidate, which never passes the
serializer. Decisive tell: those poles carried `"quality": "normal"`, and `logic/bp/serialize.lua:400-401`
**omits** quality when it is normal.

**Two real gaps remain, and this lane closes them.**

1. **`logic/bp/power.lua:1056-1062` is the only entity producer in the tree that publishes no `position`.**
   Every other family sets it beside `x/y/w/h`: roboports at `logic/bp/search.lua:286`, machines at
   `logic/bp/groups.lua:1966`, belts and splitters at `logic/bp/route.lua:1365` and `:1383`. Poles are the
   odd one out, and the serializer's fallback is what has been hiding it.
2. **`tools/blueprint_string.py:54-60` drops a missing location SILENTLY.** `KEEP` has no `x`/`y` and there
   is no required-field check, so an entity with neither encodes as
   `{"entity_number": 345, "name": "medium-electric-pole", "quality": "normal"}` — bytes Factorio cannot
   place. Contract 26.7 says **named refusal, never a silent drop**. `resolve_wires` at
   `tools/blueprint_string.py:85-86` already refuses by name; positions do not. **That asymmetry is the
   whole defect.**

Third, separate, and needed for this round's agreed bar: **`tools/deliver.sh` always audits against 127.**
It hard-codes `target_path="$ROOT/docs/round-16-delivery-target.json"` at `tools/deliver.sh:14` and always
passes `--expect-target "$target_path"` at `tools/deliver.sh:287-288`. The player's bar this round is **a
blueprint that loads**, judged **without** `--expect-target`; the 127-entity target is deferred, never
dropped. So even a perfect loading blueprint reports `verdict=refused reason=audit_refused` today, against
`splitters 0`, `undergrounds 0`, `entities_excluding_roboports 127`.

Measured baselines on this host 2026-09-22, all green, none may regress:

```
lua5.2 tests/test_power.lua                        16 cases, 16 passed, 0 failed
python3 -m unittest tests.tools.test_blueprint_string   Ran 8 tests   OK
python3 -m unittest tests.tools.test_deliver            Ran 6 tests   OK
```

## Traps, each measured

**Trap: the serializer's fallback makes a pole fix invisible end to end.** Adding `position` to
`logic/bp/power.lua` changes **nothing** in the delivered bytes, because `entity_position` already computes
the identical value. So a test asserting the delivered blueprint proves nothing. **Assert `power.lua`'s own
`state.result.entities`**, which is what `tests/test_power.lua` already drives.

**Trap: a pole's `rect` is tile coordinates, its `position` is the entity centre.** `logic/bp/power.lua:283`
builds `{x = x, y = y, w = spec.tile_w, h = spec.tile_h}` from a tile origin. `logic/bp/search.lua:286` is
the exact shape to copy: `{x = port.x + port.w / 2, y = port.y + port.h / 2}`. A `medium-electric-pole` is
1x1, so tile `(10,20)` becomes `(10.5, 20.5)`. Get this wrong and the pole moves half a tile.

**Trap: the local named `position` in that block is an ORDINAL, never a coordinate.**
`logic/bp/power.lua:1051` reads `local position, candidate_index = publish.entity_index, ...`. That shadowing
is almost certainly why the omission survived review. Do not reuse the name for the new field's value.

**Trap: `tools/blueprint_string.py` must still accept every entity the real pipeline produces.** The refusal
is for an entity with **neither** `position` **nor** usable finite `x` and `y`. An entity carrying `x`/`y`
without `position` is what the internal candidate looks like; decide and state in the lane report whether
the tool derives the position or refuses it, and make the test say which. **Refusing is the safer answer**
and matches `resolve_wires`, but whichever is chosen must be named in the error text, never silent.

**Trap: do NOT teach the encoder dict-shaped wires.** Candidate wires are
`{a_id, a_connector, b_id, b_connector}` while `resolve_wires` demands a 4-element list and refuses anything
else at `tools/blueprint_string.py:85-86`. **That refusal is correct** — the delivery path converts in
`tests/golden/generate.lua`. Loosening it would let a raw candidate encode and hand the next round another
false blocker.

**Trap: `tools/deliver.sh` is `#!/bin/sh` with `set -u` and NO `set -e`.** Every abort funnels through
`finish()` at `tools/deliver.sh:139-147`, which always prints the one-line summary. A new flag must keep that
property: `--no-target` still prints `verdict=` and every `key=value` count, and still exits nonzero when the
physical audit refuses. `--no-target` and `--target` together are a named usage refusal, exit 2, never a
traceback.

**Trap: the python tests are `unittest`, not `pytest`.** `python3 -m pytest` reports
`No module named pytest` on this host. Run `python3 -m unittest tests.tools.test_blueprint_string`.

**Trap: `tests/harness.lua`'s `H.shapes()` yields two shapes**, so an `H.test` inside that loop counts twice
per interpreter. Both `lua5.2` and `lua5.4` must be green.

PRESERVE: `logic/bp/route.lua`, `logic/bp/validate.lua`, `logic/bp/serialize.lua`, `logic/bp/search.lua`,
`logic/bp/groups.lua`, `tools/blueprint_audit.py`, `tools/census_gate.py`, `tests/harness.lua`,
`tests/test_validate.lua`, `tests/test_validate_splitter.lua`, `tests/test_blueprint_physical_contract.lua`,
`tests/test_census_codes_live.lua`, `docs/round-16-census-baseline.json`, `docs/round-16-red-list.txt`,
`docs/round-16-delivery-target.json`, `docs/feature-contracts.md`, `info.json`, `mod-description.md`,
`.agent-lane.toml`.

## Files this lane owns

`logic/bp/power.lua`, `tools/blueprint_string.py`, `tools/deliver.sh`, `tests/test_power.lua`,
`tests/tools/test_blueprint_string.py`, `tests/tools/test_deliver.py`.

**Nothing else.** The spine is editing `logic/bp/route.lua` in parallel; touching it loses the merge.

## What to build

1. **`logic/bp/power.lua:1056-1062` publishes `position`**, matching `logic/bp/search.lua:286`:
   `position = {x = rect.x + rect.w / 2, y = rect.y + rect.h / 2}`. Keep `x`, `y`, `w`, `h` and `rect` exactly
   as they are — `logic/bp/validate.lua` and `tools/` both read them.
   One row in `tests/test_power.lua`, **red at base**, asserting the published pole's `position` against its
   `rect`, and printing both so the geometry is readable from test output.

2. **`tools/blueprint_string.py` refuses a location-less entity BY NAME.** No entity may encode without a
   position. The message names the entity's index and its `name`, the way
   `tools/blueprint_string.py:86` and `:100` already do. One row in `tests/tools/test_blueprint_string.py`,
   **red at base**: today that file has **no** case mentioning `position` at all, which is exactly why the
   drop went unseen.

3. **`tools/deliver.sh --no-target`** runs `tools/blueprint_audit.py` **without** `--expect-target`, so the
   physical checks (contract 26.2, 26.3, 26.5, 26.6) still judge the bytes and the count contract does not.
   The summary line keeps every field, and the family counts still load, because `load_counts` reads the
   auditor's `--json` and does not depend on the target. One row in `tests/tools/test_deliver.py`, **red at
   base**, proving `--no-target` accepts bytes that `--expect-target docs/round-16-delivery-target.json`
   refuses, and one asserting `--no-target --target X` is a named usage refusal.

**State plainly in the lane report which rows are red at base**, with each one's exact failure text. That
list is the lane's deliverable as much as the code is.

## What done mean

Two checks. A check block takes one `gateslot` lease PER check and hands it back between them, so nine cheap
checks means nine trips to the back of a shared queue. Everything cheap is folded in with `&&`.

```checks
{"name": "position-and-refusal", "command": "git diff --name-only round-18-base HEAD | grep -v '^docs/tasks/151' | grep -Ev '^(logic/bp/power\\.lua|tools/blueprint_string\\.py|tools/deliver\\.sh|tests/test_power\\.lua|tests/tools/test_blueprint_string\\.py|tests/tools/test_deliver\\.py)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_power.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; $l tests/test_validate.lua 2>&1 | tail -1 | grep -q '44 passed, 0 failed' || exit 1; done && python3 -m unittest tests.tools.test_blueprint_string 2>&1 | tail -1 | grep -q '^OK' && python3 -m unittest tests.tools.test_deliver 2>&1 | tail -1 | grep -q '^OK' && echo position-ok", "expect_exit": 0, "expect_regex": "position-ok", "timeout_s": 1800}
{"name": "red-at-base", "command": "set -e; base=$(mktemp -d); git worktree add -q --detach \"$base\" round-18-base; for f in tests/test_power.lua tests/tools/test_blueprint_string.py tests/tools/test_deliver.py; do cp \"$f\" \"$base/$f\"; done; fail=0; cd \"$base\"; lua5.2 tests/test_power.lua 2>&1 | tail -1 | grep -q \" 0 failed\" && fail=1 || true; python3 -m unittest tests.tools.test_blueprint_string 2>&1 | tail -1 | grep -q \"^OK\" && fail=1 || true; python3 -m unittest tests.tools.test_deliver 2>&1 | tail -1 | grep -q \"^OK\" && fail=1 || true; cd - >/dev/null; git worktree remove --force \"$base\"; [ \"$fail\" = 0 ] || { echo \"new rows are GREEN at round-18-base; they prove nothing\"; exit 1; }; echo red-at-base-ok", "expect_exit": 0, "expect_regex": "red-at-base-ok", "timeout_s": 1200}
```

Re-cut because: none

# bound: 4000s

Reviewer ask: does the encoder now REFUSE a location-less entity by name rather than emitting bytes Factorio
cannot place, and does `--no-target` keep every physical check while dropping only the 127-entity count
contract?
