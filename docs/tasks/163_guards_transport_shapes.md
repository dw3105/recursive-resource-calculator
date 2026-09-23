# 163 guards: validator and byte auditor refuse a blocked side-load, a back-to-back pair and a belt ring

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-163`, branch
`lane/163`, base tag `round-21-base`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch. Everything you need is on
`round-21-base`.

## Attempt 2 — resume, do NOT stop early

Attempt 1 stopped after 180 s with the work half done and nothing committed: the auditor already reports
`5 1 1 1` on round 20's bytes and `0 0 0 0` on the player's factory, the codes are registered and
`tools/deliver.sh` carries the keys — **that work is still in your worktree; keep it.** Missing: the three
validator checks in `logic/bp/validate.lua`, `tests/test_validate_transport_shapes.lua`, the auditor rows in
`tests/tools/test_blueprint_audit.py`, the commit, and the checks.

You have about 35 minutes. **Do not end your turn until every item under "What to build" exists, is
committed, and both checks have run.** Stopping with uncommitted work is a failed lane. If one item is truly
blocked, commit everything else, then say which item and why.

## Explain very simply

The player placed round 20's blueprint in Factorio 2.0.77 on 2026-09-23 and found three transport defects
that **our validator passed and our byte auditor passed**. A check that cannot fail on what the player saw
is not a check. This lane makes both of them fail on exactly those shapes — and only those.

A belt has **two lanes**. An **underground belt entrance fed from the SIDE** (a side-load) blocks one of
the feeder's lanes. **The player's rule, verbatim, 2026-09-23:** "sideload of near lane is legitimate, but
need to be used only if there are no simpler solutions; sideload of far lane can be used to block far lane,
but only to be used if there are no simpler choices!" So a side-load is **legal**. It is a **defect only
when the items that must pass ride the lane the inlet blocks** — then nothing moves.

## The three shapes, frozen as a fixture

`tests/fixtures/blueprints/round20_delivered.txt` (sha256 `be22350b…27d17ff`) is round 20's delivered
bytes. `tools/transport_shape_probe.py` on it, this host, 2026-09-23:

```
SIDELOAD     (14,4) dir=12 -> (13,4) input dir=0     STALLED IN GAME — the player's screenshot
SIDELOAD     (6,9)  dir=4  -> (7,9)  input dir=0
SIDELOAD     (1,29) dir=4  -> (2,29) input dir=0
SIDELOAD     (11,9) dir=0  -> (11,8) input dir=12    a splitter's output tile
SIDELOAD     (9,21) dir=0  -> (9,20) input dir=4     a splitter's output tile
BACK_TO_BACK (14,1) -> (15,1) dir=4, one pair (12,1) -> (17,1) spans 5
CYCLE        len=14 first=(1,22)
sideload=5 back_to_back=1 cycles=1
```

`~/share/RRC/red_science_1s_manual_bp.txt` is the player's own working factory: `0 0 0`.

## The lane model — anchor it on the game, never on our code

Directions: NORTH `0`, EAST `4`, SOUTH `8`, WEST `12`. In the BYTES an inserter's `direction` names its
PICKUP tile; it drops on the opposite side. In the VALIDATOR's candidate an inserter's `dir` is the
opposite (the internal frame); `logic/bp/serialize.lua` `published_direction` flips it at the boundary.

Factorio lane rules to model:

1. An inserter drops on the **far** lane of the belt tile, seen from the inserter. When the belt runs
   directly away from or toward the inserter, it drops on the belt's **right** lane (relative to the belt's
   own direction).
2. A straight belt, a curve, a splitter and an underground pair all **keep** each item's lane (left stays
   left, right stays right, relative to direction of travel).
3. A side-load onto a plain belt puts every item onto the target's **near** lane (the lane on the feeder's
   side).
4. **A side-load into an underground INPUT blocks the feeder lane on the side the inlet FACES** (its hood,
   the front half of the tile). The feeder lane on the inlet's back side passes.

**Anchor, and the row that proves the model:** at `(14,4)` a WEST belt feeds the side of a NORTH-facing
input at `(13,4)`. The science pack arrives from an inserter at `(14,10)` placing onto `(14,9)`, a
NORTH belt running directly away from it — rule 1 puts it on that belt's right (east) lane; the curve at
`(14,4)` keeps it on the right lane of a WEST belt, which is its NORTH side; the inlet faces NORTH; rule 4
blocks it. **The game stalled there.** If your model does not mark `(14,4) -> (13,4)` blocked, your model
is wrong, not the game. Derive every lane from the bytes; print the trace in the test.

If any step above disagrees with what you can derive from the bytes, stop and report the first
disagreement with its coordinates — do not bend the rule to fit.

## What to build

**Validator**, `logic/bp/validate.lua` + `logic/bp/reason_codes.lua` (register every new code in the enum):

- `BP_V_UNDERGROUND_SIDELOAD_BLOCKED` — a side-load into an underground endpoint whose carried lane is the
  blocked one. A side-load whose items ride the passing lane is **legal and reports nothing**.
- `BP_V_UNDERGROUND_BACK_TO_BACK` — an underground OUTPUT whose next tile is an INPUT of the same
  direction, where one pair from the first input to the second output would be within reach
  (`underground-belt` 5, `fast-` 7, `express-` 9, `turbo-` 11).
- `BP_V_ROUTE_LOOP` — a directed cycle in the belt graph (belts, splitters, underground pairs as one hop).

Each record names its tiles in `detail`. Follow the existing `check_*` functions' shape and registration.

**Byte auditor**, `tools/blueprint_audit.py`: report `sideload`, `sideload_blocked`, `back_to_back`,
`cycles` in its text and `--json` output, and exit non-zero when `sideload_blocked`, `back_to_back` or
`cycles` is above zero — the same way `invalid_inserters` already fails it. Round 13's frozen baseline rows
in `tests/tools/test_blueprint_audit.py` must not move except to gain the four new keys.
**`tools/deliver.sh`**: add the four keys to `audit_keys` so the delivery line prints them.

**Tests**, each **red at `round-21-base`**:

- `tests/test_validate_transport_shapes.lua` (new), candidate fixtures written as literal tables:
  - **TS1** the anchor side-load with the item on the blocked lane → `BP_V_UNDERGROUND_SIDELOAD_BLOCKED`.
  - **TS2** the same geometry with the inserter on the OTHER side, so the item rides the passing lane →
    no record. A legal near-lane side-load passes.
  - **TS3** back-to-back pair within reach → `BP_V_UNDERGROUND_BACK_TO_BACK`; **TS3b** the same with the
    combined span beyond reach → no record.
  - **TS4** a 14-tile ring → `BP_V_ROUTE_LOOP`; **TS4b** a straight run → no record.
- `tests/tools/test_blueprint_audit.py`: `round20_delivered.txt` reports `sideload=5`,
  `sideload_blocked>=1` including `(14,4)->(13,4)`, `back_to_back=1`, `cycles=1`, and exits non-zero; the
  player's manual blueprint reports `0 0 0 0` and exits zero.

## Traps, each measured on this host

- **A splitter's `position` is the midpoint of its two tiles, across its own direction.** A NORTH splitter
  at `(12.0, 9.5)` covers `(11,9)` and `(12,9)`. Round 17 lost three rounds to a tool that never saw a
  splitter's second tile.
- **The validator runs on every search candidate.** Keep the new checks linear in entity count; the
  player's sheet validates dozens of candidates inside a 5-second-per-step budget.
- **This lane's new codes WILL refuse today's router output** on the player's sheet. That is expected and
  is why this lane merges LAST. `tests/test_census_codes_live.lua` and any test that counts codes on the
  live sheet may move; report which, never re-freeze them here.
- **Never touch** `logic/bp/route.lua`, `logic/bp/search.lua`, `logic/bp/groups.lua`,
  `logic/bp/serialize.lua`, `docs/**` except this task, `info.json`, `mod-description.md`,
  `.agent-lane.toml`, and every `tests/**` file except those listed below.

## Files this lane owns

`logic/bp/validate.lua`, `logic/bp/reason_codes.lua`, `tools/blueprint_audit.py`, `tools/deliver.sh`,
`tests/test_validate_transport_shapes.lua` (new), `tests/tools/test_blueprint_audit.py`.

## Commit, THEN check

Commit your work on `lane/163` with a message that says what changed and what was measured. **Run the two
checks below as the very LAST action, after the final commit.** A lane that ends with uncommitted work is a
failed lane whatever it built.

## What done mean

```checks
{"name": "guards-rows", "command": "git diff --name-only round-21-base HEAD | grep -v '^docs/tasks/163' | grep -Ev '^(logic/bp/validate\\.lua|logic/bp/reason_codes\\.lua|tools/blueprint_audit\\.py|tools/deliver\\.sh|tests/test_validate_transport_shapes\\.lua|tests/tools/test_blueprint_audit\\.py)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_validate_transport_shapes.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; $l tests/test_validate.lua 2>&1 | tail -1 | grep -q '44 passed, 0 failed' || exit 1; $l tests/test_validate_splitter.lua 2>&1 | tail -1 | grep -q '12 passed, 0 failed' || exit 1; $l tests/test_locale_keys.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && python3 -m pytest -q tests/tools/test_blueprint_audit.py 2>&1 | tail -1 | grep -Eq '^[0-9]+ passed' && echo guards-rows-ok", "expect_exit": 0, "expect_regex": "guards-rows-ok", "timeout_s": 1800}
{"name": "guards-bytes", "command": "python3 tools/blueprint_audit.py tests/fixtures/blueprints/round20_delivered.txt --json > /tmp/rrc163-a.json; a=$?; python3 tools/blueprint_audit.py ~/share/RRC/red_science_1s_manual_bp.txt --json > /tmp/rrc163-b.json; b=$?; python3 -c \"import json; a=json.load(open('/tmp/rrc163-a.json')); b=json.load(open('/tmp/rrc163-b.json')); g=lambda d,k: d.get(k, (d.get('counts') or {}).get(k)); print('ours', [g(a,k) for k in ('sideload','sideload_blocked','back_to_back','cycles')], 'player', [g(b,k) for k in ('sideload','sideload_blocked','back_to_back','cycles')]); assert g(a,'sideload')==5 and g(a,'sideload_blocked')>=1 and g(a,'back_to_back')==1 and g(a,'cycles')==1; assert [g(b,k) for k in ('sideload','sideload_blocked','back_to_back','cycles')]==[0,0,0,0]\" && [ $a -ne 0 ] && [ $b -eq 0 ] && echo guards-bytes-ok", "expect_exit": 0, "expect_regex": "guards-bytes-ok", "timeout_s": 600}
```

# bound: 2400s

Reviewer ask: does the model mark the in-game stall `(14,4) -> (13,4)` blocked from a lane trace printed in
the test, does a passing-lane side-load report nothing, and does the player's factory read `0 0 0 0`?
