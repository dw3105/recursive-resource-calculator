# 244_groups_belt_split a step whose item flow needs more than one belt splits into belt-sized blocks

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-244`, branch `lane/244`,
base tag `round-44-base`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 30 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tests/golden/generate.lua`, `tools/game_test.sh`, `factorio`, or any
full suite, sheet run or headless run of any kind.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY; each runs in about 1 s). Never use `coroutine`. `require` only at file top
level. **No game item or entity name in `logic/`.** Every new test must FAIL on the base code (say so in its header
comment).

## Explain very simply

On the player's gray + magenta science sheet (2026-09-27) rail flows at 71.4/s, copper cable 60.5/s and stone into
bricks 63.5/s. One turbo belt carries 60/s. Each block has ONE belt port per item flow, so the router cannot move
those flows: `BP_R_CAPACITY` on rail. Two blocks of a step, each with its own port, split the flow over two belts:
measured on a synthetic route input (belt 10/s, flow 15/s, 2 producer blocks + 2 consumer blocks) route gives
`ok=true` in 0.28 s.

So a step with more than 1 machine whose item flow exceeds one belt splits into k = ceil(max item flow rate / belt
capacity) blocks of near-equal machine counts (capped at the machine count). Not one block per machine: 49 blocks
made the router restart for 15 minutes.

Machine ids come from `physical_ordinal = step._physical_ordinal or ordinal` (`build_block`, ~`groups.lua:1245`).
`_physical_ordinal` names ONE machine; a chunk of several machines with it would give them all one id. Chunks
therefore carry a new `_ordinal_offset`.

Measured with exactly these edits patched in memory (legalcopilot-dev, 2026-09-27): chunks copper cable 1+1,
production science 7+7, rail 2+1, stone brick 4+3.

## What to build

1. `tests/test_groups_belt_split.lua`, hand-built plans (shape of `tests/test_groups_hands_overflow.lua`), catalog
   with `belt = {belt = "belt", items_per_second = 10, lane_items_per_second = 5}`. Commit red first.
   - BS1 a step of 3 machines with one item output of 15/s (belt 10/s) → exactly 2 blocks hold that step, with 2
     and 1 machines; each block's output rate is at most 10/s (rate scales with machine share).
   - BS2 machine ids are unique across all blocks (`machine:<step>:1`, `:2`, `:3` each once).
   - BS3 total machines of the step across blocks equals 3.
   - BS4 a step of 3 machines with 9/s output (under the belt) stays ONE block (no split below capacity).
   - BS5 a step with an item flow above capacity but a single machine is not split (k capped at machine count).
   - BS6 synthetic route (shape of `tests/test_route.lua` R6 inputs, `Route.begin`/`Route.step`): belt 10/s, flow
     15/s from 2 producer blocks (7.5/s each) to 2 consumer blocks (7.5/s each) → `ok == true`.
2. `logic/bp/groups.lua`, three edits:
   a. `build_block`: `local physical_ordinal = step._physical_ordinal or ((step._ordinal_offset or 0) + ordinal)`.
   b. `make_candidates_once`, block id parts: a step with `_ordinal_offset` (and no `_physical_ordinal`) adds
      `"@" .. offset` to its id piece, so two chunks of one step never share a block id.
   c. `make_candidates_once`, the loop that builds `layout_steps`: after `row_possible` is known, compute
      `chunks` = max over the step's item inputs and outputs of `ceil(flow_entry_rate(entry) / belt_capacity - 1e-9)`,
      belt_capacity = `finite(catalog.belt.items_per_second)`, only when `step.machine_count > 1`; cap at
      `step.machine_count`. When `chunks > 1` and the step is NOT already split one per machine (the existing
      `needs_individual_blocks or (distinct > 2 and not row_possible)` case keeps priority), emit `chunks` fragments:
      size_i = floor(n / k) + (i <= n % k and 1 or 0), `machine_count = size_i`, `_ordinal_offset` = machines before
      it, `_rate_machine_count = step.machine_count`, `_force_block = true`. Comment: why (one belt port per flow per
      block; a flow above one belt needs several blocks).

## Files this lane owns

logic/bp/groups.lua (only the machine ordinal line in `build_block`, the block id parts and the `layout_steps` loop in
`make_candidates_once`; never the face plan and never the retry condition), tests/test_groups_belt_split.lua,
docs/tasks/244_groups_belt_split.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/244`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane244-tests", "command": "git diff --name-only round-44-base HEAD | grep -Ev '^(logic/bp/groups\\.lua|tests/test_groups_belt_split\\.lua|docs/tasks/244_groups_belt_split\\.md)$' | ( ! grep . ) && git diff --quiet round-44-base HEAD -- docs/tasks/244_groups_belt_split.md && ! git diff round-44-base HEAD -- logic | grep -q '^+.*coroutine' && for t in test_groups_belt_split test_groups test_groups_rows test_groups_one test_groups_hand_count test_groups_interior_port test_groups_fluid_row test_groups_long_hands test_groups_beacon_row test_groups_coverage_split test_groups_beacon_pad test_groups_hands_overflow test_beacon_coverage test_beacon_placement_incident test_route test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane244-tests-ok", "expect_exit": 0, "expect_regex": "lane244-tests-ok", "timeout_s": 1200}
{"name": "lane244-fast", "command": "out=$(lua5.2 tests/test_groups_belt_split.lua 2>&1); for n in BS1 BS2 BS3 BS4 BS5 BS6; do echo \"$out\" | grep -q \"$n\" || { echo MISSING $n; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane244-ok", "expect_exit": 0, "expect_regex": "lane244-ok", "timeout_s": 120}
```

# bound: 1800s
