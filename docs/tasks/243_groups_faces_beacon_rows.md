# 243_groups_faces_beacon_rows a belt hand never takes a machine face that a beacon row covers

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-243`, branch `lane/243`,
base tag `round-44-base`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 30 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tests/golden/generate.lua`, `tools/game_test.sh`, `factorio`, or any
full suite, sheet run or headless run of any kind.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY; every groups test runs under 1 s). Never use `coroutine`. `require` only at
file top level. **No game item or entity name in `logic/`.** Every new test must FAIL on the base code (say so in
its header comment).

## Explain very simply

The player's gray + magenta science sheet (`tests/golden/cases/player-gray-magenta-science-10s`, 2026-09-27) gets no
blueprint. The frozen groups input `tests/fixtures/groups_gray_magenta.json` shows why in 1.4 s: four blocks fail
because a beacon row sits on a machine face that a belt hand was sent to.

- A. Strip of several machines (not face layout, not row layout), branch `elseif not face_layout then` in
  `build_block` (~`logic/bp/groups.lua:1483-1504`): flow 1 always gets `top`, flow 2 `bottom`. With a top beacon
  row the top face has 0 capacity (`new_face_allocator`), so casting-iron and casting-steel fail
  `no free machine face for item/iron-plate` / `item/steel-plate`.
- B. molten-iron strip has 2 item inputs and a top beacon row: only 1 free face for 2 flows. No layout of that
  strip fits; its machines fit alone.
- C. A lone machine (face layout) with 4 item flows (3 in, 1 out) and a top beacon row: left, right, bottom hold 3,
  the 4th has no face (`no free machine face is on the block perimeter for output:item/electric-furnace`, the
  single-machine branch near `:1546-1556`).

Measured with exactly the edits below patched in memory (legalcopilot-dev, 2026-09-27): the fixture groups
`ok=true` with 0 failures in 2.4 s.

## What to build

1. `tests/test_groups_faces_beacon_rows.lua` (shape of `tests/test_groups_coverage_split.lua` for the fixture, shape
   of `tests/test_groups_hands_overflow.lua` for hand-built plans). Commit red first.
   - GF1 fixture: `state.ok == true`, 0 failures.
   - GF2 fixture: in every block, no inserter sits on a machine face that a beacon of the same block covers (a hand
     directly above a machine when a beacon row is above it, or directly below when one is below).
   - GF3 fixture: every physical machine gets its configured beacon count by signature (same check as the coverage
     split test).
   - GF4 fixture: every block holding step `molten-iron` has exactly 1 machine.
   - GF5 fixture: the block of step `electric-furnace` has 4 port-bound hands on its one machine, and two of them
     are on the same long side (left or right).
   - GF6 hand-built: a 3-machine strip (3x3 machines, 1 item output, 1 fluid input so it is not a row) with a top
     beacon row (1 beacon per machine) → groups ok, the output hand is below its machine.
2. `logic/bp/groups.lua`, three edits:
   A. In the strip branch: build `strip_sides`: `"top"` when `#top_rows == 0`, then `"bottom"` when
      `#bottom_rows == 0`. Refuse (same failure record as today) only when `#flow_ids > #strip_sides`; flow i gets
      `strip_sides[i]` (replaces `index == 1 and "top" or "bottom"` and the `#bottom_rows > 0` refusal).
   B. In `make_candidates_once`, the retry condition `if block.invalid_coverage and machine_total > 1 then` becomes
      `if (block.invalid_coverage or (block.failure and block.failure.name == "inserter-face")) and machine_total > 1
      then` — a strip that cannot give every flow a free face is retried as single-machine blocks. Update its comment.
   C. In the single-machine branch where `side` is picked (`top_available` / `bottom_available`): when neither is
      free, use `"left"` if no vertical flow took left yet and at least 1 horizontal flow exists, else `"right"` if
      no vertical flow took right yet and 2 horizontal flows exist. Record it in `vertical_sides` so a 3rd extra flow
      still fails. Comment: a long machine face has room for more than one hand; the beacon row took the short face.
   Keep every existing failure message text.

## Files this lane owns

logic/bp/groups.lua (only `build_block` face plan and the retry condition in `make_candidates_once`; never the
pre-bucket loop that builds `layout_steps`, never machine ordinals), tests/test_groups_faces_beacon_rows.lua,
docs/tasks/243_groups_faces_beacon_rows.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/243`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane243-tests", "command": "git diff --name-only round-44-base HEAD | grep -Ev '^(logic/bp/groups\\.lua|tests/test_groups_faces_beacon_rows\\.lua|docs/tasks/243_groups_faces_beacon_rows\\.md)$' | ( ! grep . ) && git diff --quiet round-44-base HEAD -- docs/tasks/243_groups_faces_beacon_rows.md && ! git diff round-44-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_groups_faces_beacon_rows test_groups test_groups_rows test_groups_one test_groups_hand_count test_groups_interior_port test_groups_fluid_row test_groups_long_hands test_groups_beacon_row test_groups_coverage_split test_groups_beacon_pad test_groups_hands_overflow test_beacon_coverage test_beacon_placement_incident test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane243-tests-ok", "expect_exit": 0, "expect_regex": "lane243-tests-ok", "timeout_s": 1200}
{"name": "lane243-fast", "command": "out=$(lua5.2 tests/test_groups_faces_beacon_rows.lua 2>&1); for n in GF1 GF2 GF3 GF4 GF5 GF6; do echo \"$out\" | grep -q \"$n\" || { echo MISSING $n; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane243-ok", "expect_exit": 0, "expect_regex": "lane243-ok", "timeout_s": 120}
```

# bound: 1800s
