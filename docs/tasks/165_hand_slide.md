# 165 slide: a hand moves along its machine face so its belt ends straight

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-165`, branch
`lane/165`, base tag `round-22-base`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 35 minutes — do NOT stop early

Do not end your turn until every item under "What to build" exists, is committed, and both checks have run.
Stopping with uncommitted work is a failed lane. If one item is truly blocked, commit everything else, then
say which item and why.

## Explain very simply

An inserter (a "hand") sits on one tile of its machine's face and picks from, or drops onto, the belt tile
beyond it. Grouping fixes that tile BEFORE any belt is routed. So the belt must bend to reach it.

The player placed our blueprint in Factorio 2.0.77 on 2026-09-23 and boxed it: "This can and should be
straight". The gear branch runs west along `y=6`, then jogs `(11,6) N -> (11,5) W -> (10,5)` because the
science machine's input hand sits at `(9,5)` picking from `(10,5)`. The machine's east face is `x=9`,
`y=5..7`, and `(9,6)` is free. With the hand at `(9,6)` picking from `(10,6)`, the run along `y=6` ends
straight at `(10,6)` and two belts disappear.

## What to build

A new pass, `logic/bp/hand_slide.lua`, run once per candidate **after routing and before power**. In
`logic/bp/search.lua`, the `state.phase == "route"` branch builds `power_entities` from
`state.work.materialized.entities` and `state.work.route.result.entities` and calls `Power.begin`. Call the
slide right before that, on `state.work.materialized` and `state.work.route.result`.

For every inserter whose belt tile `T` (its pickup tile for an input hand, its drop tile for an output
hand) ends a run with a TURN on the tile before it: look at the other free tiles `F` of the same machine
face (a tile that holds no entity and is not reserved). Moving the hand to `F` moves its belt tile to
`T' = F + (T - hand)`. Slide when ALL hold:

1. `T'` is free now, or already holds a belt of this flow on the same run.
2. The run can end at `T'` with fewer belts: the tile BEFORE the turn continues straight into `T'`
   (input hand) or the output leaves `T'` straight into the run (output hand).
3. The belts no longer needed (from the turn tile to `T`) carry no other flow and feed no other hand.
4. Nothing else moves: the hand keeps its direction and its machine; only its position and its
   pickup/drop positions shift by one face step.

Then update, consistently: the inserter entity (`x`, `y`, `position`, `pickup_position`,
`drop_position`), the materialized port it belongs to (`x`, `y`), every route entity and segment you
remove or add (`segments`, `entities`, `bindings` keep pointing at live segments), so that
`logic/bp/validate.lua` passes the candidate exactly as before.

Deterministic order: sort hands by `(y, x)`. Slide at most one step per hand per pass.

## Tests

`tests/test_hand_slide.lua` (new), each **red at `round-22-base`**:

- **HS1** a machine with an input hand at the face's top tile, a belt run arriving along the face's
  middle row and jogging up: after the pass the hand sits on the middle tile, the run is straight, and it
  is two belts shorter.
- **HS2** negative control: the face's middle tile holds another hand, so no slide happens.
- **HS3** the candidate still validates: run `Validate` on the slid candidate, `ok=true`.

And report on the player's sheet, measured with `sh tools/round21_product.sh`: entity count (spine
`round-22-base` measures 248), and whether `(9,5)` moved to `(9,6)`.

## Traps

- **The product must not grow** and must stay `product-ok` with `sideload=0 back_to_back=0 cycles=0`.
- **Determinism**: `tests/test_route_budget.lua` and `coord_key` need the same input to give the same
  layout.
- **Never touch** `logic/bp/route.lua`, `logic/bp/validate.lua`, `logic/bp/groups.lua`,
  `logic/bp/serialize.lua`, `tools/**`, `docs/**` except this task, `info.json`, `mod-description.md`,
  `.agent-lane.toml`, any `tests/**` file except `tests/test_hand_slide.lua`.

## Files this lane owns

`logic/bp/hand_slide.lua` (new), `logic/bp/search.lua` (the one call site only), `tests/test_hand_slide.lua`
(new).

## Commit, THEN check

Commit on `lane/165` with a message saying what changed and what was measured. **Run the two checks below as
the very LAST action, after the final commit.**

## What done mean

```checks
{"name": "slide-regress", "command": "git diff --name-only round-22-base HEAD | grep -v '^docs/tasks/165' | grep -Ev '^(logic/bp/hand_slide\\.lua|logic/bp/search\\.lua|tests/test_hand_slide\\.lua)$' | ( ! grep . ) && for l in lua5.2 lua5.4; do $l tests/test_hand_slide.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; done && sh tools/round21_regress.sh | tail -1 | grep -q '^regress-ok$' && echo slide-regress-ok", "expect_exit": 0, "expect_regex": "slide-regress-ok", "timeout_s": 1800}
{"name": "slide-product", "command": "sh tools/round21_product.sh > /tmp/rrc165-product.txt 2>&1; cat /tmp/rrc165-product.txt; grep -q '^product-ok$' /tmp/rrc165-product.txt && grep -q 'sideload=0 back_to_back=0 cycles=0' /tmp/rrc165-product.txt && echo slide-product-ok", "expect_exit": 0, "expect_regex": "slide-product-ok", "timeout_s": 1200}
```

# bound: 2400s

Reviewer ask: on the player's sheet, did the science hand move from `(9,5)` to `(9,6)`, did the entity count
fall below 248, and does the slid candidate validate with no new record?
