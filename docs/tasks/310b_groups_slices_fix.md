# 310b_groups_slices_fix: Groups cache owned by the caller, cheap key, real per-hand slices (groups.lua)

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-310`, branch `lane/310`,
base tag `round-56-310b-base` (the commit that holds this task file, on top of lane 310's own work), merge target
`int/r56`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

# bound: 5400s

## You have about 90 minutes — do NOT stop early

Do not stop until the check below passes. Commit early, commit again, run the check LAST.
**Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`, `tools/bytes_hash.sh`,
`tools/sheet_verdict.sh`, `tools/golden_profile.lua` on a sheet, `tools/game_test.sh`, `tools/turn_flip_census.sh`,
`tools/ckpt.lua save`, `tests/golden/generate.lua`, `factorio`, `tests/test_turn_flip_census.lua`,
`tests/test_drawn_e2e.lua`, `tests/test_collector_trial.lua`, any `*_delivers.lua`, or any full suite, census, whole
golden sheet or headless run of any kind.** Single test files only: `timeout 100 lua5.2 tests/<file>.lua` (lua5.2
ONLY), each under 60 s. Never `coroutine` or `math.random`. `require` only at file top level. No game item or entity
name in `logic/`. Deterministic. Every new test case must FAIL on the base commit (header comment says so, date
2026-10-04); commit it red first, then the code. Each case prints its marker at the end of its passing run.

Read `CONTEXT.md` (**Block**, **Tick cost**), `docs/adr/0003-fast-first-ticks-judged-by-cost-model.md`,
`docs/tasks/r56_probes/18-groups-per-grid.md` (cache key facts), `docs/tasks/r56_probes/06-tail-ticks.md`.

## What is true (explain very simply)

Lane 310's first pass (commits f84f13d..2ec39b5 on this branch) passed its check, but the integrator review found
three defects. Measured on legalcopilot-dev 2026-10-04 with `tests/fixtures/r56/blue_bound_groups.json`:

1. **Cache in module state.** `groups_cache` / `groups_cache_order` are module locals in `logic/bp/groups.lua`. Mod
   state outside the job's saved state differs after save/load and on a joining multiplayer peer: same tick, different
   ops charged -> desync risk. All cached data must live in a table the CALLER owns and keeps in its own state.
2. **Key costs one 420 ms tick.** `groups_cache_key` serializes the whole Groups input with a `tostring` per scalar,
   uncharged, inside `Groups.begin`: 210 ms CPU, 4.55 M instructions, 207 185 `tostring` calls (Tick cost 420 ms) on
   blue. Base `Groups.begin` costs 0 ms. Ticket 18: the only per-search inputs Groups reads are `split_steps`
   (groups.lua `make_candidates_once`) and `ring_bump`; key = `split_steps` (as given) + `ring_bump`.
3. **No real slices.** A bucket is billed by machine count but still built in one call (blue chemistry bucket with
   beacons ~250 ms). `if pending_cost > ops and ops > 1 then return` never runs a bucket whose cost exceeds a whole
   tick's budget (stall).

## What to build (in `logic/bp/groups.lua` only)

1. Remove the module-level cache. New API: `Groups.begin(input, cache)`; `cache` is a plain table owned by the caller
   (or nil = no caching). Store only plain data in it (no functions, no metatables, no shared mutable state handed
   back: a hit returns a state whose `result` the caller may read but Groups never mutates later). Keep at most 8
   entries, oldest dropped, order deterministic.
2. Key = canonical text of `input.split_steps` (sorted keys, numbers `%.17g`) + `"|" .. tostring(input.ring_bump or 0)`.
   Build cost charged to the first step, and at most 200 `tostring` calls on the blue fixture.
3. Real slices per the Slice rule: the hand loop in block building (`for index, hand in ipairs(groups)`, ~:1007) and
   beacon row placement / redundancy (`place_row`, `redundant`) resume across `Groups.step` calls at one hand / one
   beacon candidate per unit; `Groups.step` stops when `budget.ops <= 0` and the next call continues. A bucket whose
   cost exceeds the whole budget still makes progress every call (no stall).
4. Keep lane 310's BOX/ROT hoists and every result byte-identical to base (GS2 digest unchanged).

## Tests (`tests/test_groups_slices.lua`; update GS1/GS3 to the new API, never weaken an assertion)

- GS1 `Groups.begin(input, cache)` twice with the same cache -> second is a hit, result digest equal to a fresh run.
- GS2 unchanged (base digest e1d66712...).
- GS3 budgeted work resumes and finishes with the base digest.
- GS4 unchanged.
- GS5 no module cache: two `Groups.begin(input)` calls with no cache arg -> neither is a hit; `groups.lua` source has
  no module-level table used as cache (grep `groups_cache` at top level -> none).
- GS6 key cost: `Groups.begin(blue, cache)` + the first `Groups.step` make <= 200 `tostring` calls (wrap `_G.tostring`).
- GS7 cache table is plain data: walk it, no function/userdata/metatable; it survives a JSON round trip and still hits.
- GS8 Tick cost: on the blue fixture at 4000 ops per step, every `Groups.step` call costs <= 2.44 M weighted
  instructions (instr + 78 x tostring; count instr with `debug.sethook(f, "", 1000)`, 1000 per fire).
- GS9 a bucket whose cost exceeds the whole budget (budget 50 ops) still finishes, same digest.

## Files this lane owns

`logic/bp/groups.lua`, `tests/test_groups_slices.lua`, `tests/fixtures/r56/310/`.

## Integrator-proven (not yours; do not try)

Search passing its cache table (search.lua, integrator); Groups phase worst tick on blue and magenta whole sheets.

## Commit, THEN check

Commit on `lane/310`. **Run the check as the very LAST action.**

## What done mean

- GS1-GS9 pass and print markers; GS5-GS9 red on base commit `round-56-310b-base`.
- Every groups test listed in `tools/lane_check_r56.sh` (R310) green.
- Diff only inside owned files (vs `round-56-310b-base`); guards green.

```checks
{"name": "lane310b-check", "command": "sh tools/lane_check_r56.sh 310b", "expect_exit": 0, "expect_regex": "lane310b-ok", "timeout_s": 3000}
```
