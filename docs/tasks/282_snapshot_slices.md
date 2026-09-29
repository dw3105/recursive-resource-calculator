# 282_snapshot_slices: sheet snapshot built and fingerprinted in slices, same bytes as today

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-282`, branch `lane/282`,
base tag `round-50-base`, merge target `int/r50`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet or headless run of any
kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No
game item or entity name in `logic/`.** Every new test must FAIL on the base code where this task says "red on
base" (say so in its header comment); commit it red first.

## Explain very simply

Player save (legalcopilot-dev 2026-09-29, Factorio 2.0.77, 55 mods): pressing Compute, loading the save, a
productivity research or a module change recalculates a sheet. `Snapshot.of_sheet` (`logic/snapshot.lua:254`)
builds `selection` from ALL 529 recipe setups of the player (`selection_of` :114) and `Snapshot.fingerprint`
(:327) encodes it into a 210 696-byte string: 86-95 ms in ONE game tick, plus 10-35 ms selection build. Game
stutters. Fix: same result, built in slices over several ticks. Fingerprint bytes MUST NOT change (stored
results and blueprint staleness checks compare them).

Proof already in hand (offline, real player data):
- `docs/tasks/r50_probes/enc_new.lua`: faster encoder, byte-identical on player data (32.3 -> 20.8 ms).
- `docs/tasks/r50_probes/sliced.lua`: encode each selection entry alone, then assemble -> byte-identical to the
  engine string (sha256 `a1e319902c0252d2343fb89c8ce445d53eb0344a170de41c6525071bedad8466`).
- Fixture `tests/fixtures/r50_player_selection.lua` returns `{targets=…, options=…, selection=…}` (529 entries,
  `selection.burners = {}`, `selection.quality_loops = {}`).

## What to build

1. `logic/snapshot.lua`:
   - Replace `encode_value` with the faster byte-identical form of `enc_new.lua` (memo of string codes in a
     module-local table is fine: pure function of the string). Keep the cyclic-table error and the
     unsupported-type error. Factor out `assemble(key_codes, code_by_key)` (sort key codes, emit `t` + count +
     pairs) and use it inside `encode_value` too, so sliced and whole encodings share one code path.
   - Split `selection_of` so one product's entry is built by a local function `entry_for(player_storage,
     product_full_name)` (same fields as today), and burners / quality loops by `selection_tail(player_storage)`.
     `selection_of` keeps its output exactly.
   - `Snapshot.ENTRY_OPS = 40`.
   - `Snapshot.begin_sheet(sheet_flow)`: same work as `of_sheet` except selection: returns a snapshot with every
     `of_sheet` field, `selection = nil`, `fingerprint = {input = nil, result = nil}`, and `build = {names =
     <sorted product names, same sort as selection_of>, index = 1, entries = {}, key_codes = {}, code_by_key = {}}`
     (plain strings / numbers / tables only: it is saved in storage between ticks).
   - `Snapshot.step(snapshot, budget)`: while `budget.ops > 0` and products remain: build the entry for
     `build.names[build.index]` from CURRENT storage (skip a name whose recipe is gone, as `selection_of` does),
     append to `build.entries`, encode key `#entries` and the entry into `key_codes` / `code_by_key`,
     `budget.ops = budget.ops - Snapshot.ENTRY_OPS`, `build.index = build.index + 1`. At least one product per call
     when `budget.ops > 0`. When products are done (same call if ops remain, else next call): build the tail
     (burners, quality_loops), encode them under keys `"burners"` / `"quality_loops"`, assemble the selection code,
     assemble the top code from `targets`, `options`, `selection` exactly like `Snapshot.fingerprint`, set
     `snapshot.selection` (entries array + `.burners` + `.quality_loops`), `snapshot.fingerprint.input`,
     `snapshot.build = nil`, return true. Returns false while not done. On a done snapshot: returns true, changes
     nothing, takes no ops.
   - `Snapshot.progress(snapshot)` -> `done_units, total_units` (products done, product count + 1); done snapshot
     -> `1, 1`.
   - `Snapshot.of_sheet` and `Snapshot.fingerprint` outputs unchanged.
   - Short comments with the measured numbers above + date 2026-09-29.
2. New `tests/test_snapshot_slices.lua` (header: SL1 SL2 SL4 SL5 SL6 SL7 red on round-50-base: `begin_sheet` /
   `step` / `progress` missing; SL3 green on base, it pins the bytes):
   - SL1: harness world (pattern: `tests/test_snapshot.lua` `world_with` + `configured_setup`; add 3 more recipes
     with setups so there are > 3 products), `begin_sheet` then `step` with `{ops = 1}` repeatedly -> done;
     `selection` deep-equal and `fingerprint.input` equal to `Snapshot.of_sheet` on the same sheet.
   - SL2: same with `{ops = 2000}` -> done in one call; equal again. With `{ops = 80}` -> exactly 2 products per
     call (ENTRY_OPS 40).
   - SL3: `Snapshot.fingerprint(dofile("tests/fixtures/r50_player_selection.lua"))` has length 210696 and sha256
     above (write to `os.tmpname()`, read `sha256sum` via `io.popen`, remove the temp file).
   - SL4: the player fixture rebuilt by the sliced path (per-entry `encode_value` + `assemble`, like `sliced.lua`)
     equals `Snapshot.fingerprint` of the fixture. Expose `Snapshot._test = {encode_value = …, assemble = …}`.
   - SL5: `build` holds only plain data (walk: no function, no userdata, no metatable) after 1 step.
   - SL6: `step` on a done snapshot returns true, `budget.ops` unchanged.
   - SL7: `Snapshot.progress` counts up per product, then `1, 1` when done.
3. Keep green (one at a time, `timeout 90`): `test_snapshot`, `test_calculation_result`, `test_export_payload`,
   `test_export_completeness`, `test_export_settings`, `test_generation_attempt_lookup`,
   `test_generation_record_handoff`, `test_generation_reload`, `test_job_flow`, `test_calc_pipeline`,
   `test_fixture_index`, `test_no_item_names`, `test_no_runtime_require`, `test_locale_keys`.

## Files this lane owns

logic/snapshot.lua, tests/test_snapshot_slices.lua, docs/tasks/282_snapshot_slices.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/282`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane282-tests", "command": "git diff --name-only round-50-base HEAD | grep -Ev '^(logic/snapshot\\.lua|tests/test_snapshot_slices\\.lua|docs/tasks/282_snapshot_slices\\.md)$' | ( ! grep . ) && for t in test_snapshot_slices test_snapshot test_calculation_result test_export_payload test_export_completeness test_export_settings test_generation_attempt_lookup test_generation_record_handoff test_generation_reload test_job_flow test_calc_pipeline test_fixture_index test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 300 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane282-tests-ok", "expect_exit": 0, "expect_regex": "lane282-tests-ok", "timeout_s": 2400}
{"name": "lane282-fast", "command": "out=$(timeout 120 lua5.2 tests/test_snapshot_slices.lua 2>&1); for c in SL1 SL2 SL3 SL4 SL5 SL6 SL7; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane282-ok", "expect_exit": 0, "expect_regex": "lane282-ok", "timeout_s": 300}
```

# bound: 3600s
