# 278_audit_head_on_ends two belts facing each other are not a belt cycle

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-278`, branch `lane/278`,
base tag `round-49-base`, merge target `int/r49`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 30 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/first_stage.lua`, `tools/ckpt.lua`, `factorio`, or any full suite, whole sheet or headless run of any kind.
No command may take more than 60 s.** Run only
`timeout 90 python3 -m pytest tests/tools/test_blueprint_audit.py -q` (and single-case `-k` runs of it). Every new
test must FAIL on the base code where this task says "red on base" (say so in a comment); commit it red first.

## Explain very simply

`tools/blueprint_audit.py` `audit_transport_shapes` (~:494-518) builds a directed tile graph: every plain belt gets
an edge to the tile in front of it. On the player's magenta 10/s blueprint (legalcopilot-dev 2026-09-29) it reports
`cycles 1`. The "cycle" is two belt ENDS facing each other: (1.5,12.5) facing south (direction 8, calcite) and
(1.5,13.5) facing north (direction 0, copper ore); foundry inserters at (2.5,12.5)/(2.5,13.5) pick from each tile.
In Factorio a belt never moves items onto a belt that faces straight back at it, so nothing flows between them; the
lane simulator agrees (`LANE-SIM mixed=0 starved=0 bleed=0`). The audit must not count this.

## What to build

1. `tools/blueprint_audit.py`, graph build in `audit_transport_shapes`: for a plain belt at `cell` with vector `v`,
   drop the edge `cell -> q` when `transport[q]` is a plain belt (name in `BELTS`) whose direction vector is exactly
   `-v`. Underground-input jumps and splitter edges unchanged. Comment with the measured fact + date.
2. `tests/tools/test_blueprint_audit.py` (use the existing `audit(entities)` helper and entity dict shapes in that
   file):
   - `test_AUC1_head_on_belt_ends_are_not_a_cycle` (red on base): transport-belt (1.5,12.5) direction 8 and
     transport-belt (1.5,13.5) direction 0 -> `cycles == 0`.
   - `test_AUC2_real_ring_still_counts`: 4 belts in a closed square ring ((0.5,0.5) E, (1.5,0.5) S, (1.5,1.5) W,
     (0.5,1.5) N) -> `cycles == 1`.
   - `test_AUC3_belt_into_opposite_underground_output_unchanged`: count for a belt facing an underground output
     that faces back equals base count (record base value in the test).
   - Existing `test_round20_transport_shape_rows_and_manual_control` must stay green (its cycle is a real 14-tile
     ring; `cycles == 1` stays).

## Files this lane owns

tools/blueprint_audit.py, tests/tools/test_blueprint_audit.py, docs/tasks/278_audit_head_on_ends.md. Never touch
anything else.

## Commit, THEN check

Commit on `lane/278`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane278-tests", "command": "git diff --name-only round-49-base HEAD | grep -Ev '^(tools/blueprint_audit\\.py|tests/tools/test_blueprint_audit\\.py|docs/tasks/278_audit_head_on_ends\\.md)$' | ( ! grep . ) && timeout 600 python3 -m pytest tests/tools/test_blueprint_audit.py -q 2>&1 | tail -1 | grep -Eq '^[0-9]+ passed' && echo lane278-tests-ok", "expect_exit": 0, "expect_regex": "lane278-tests-ok", "timeout_s": 900}
{"name": "lane278-fast", "command": "out=$(timeout 300 python3 -m pytest tests/tools/test_blueprint_audit.py -q -k 'AUC1 or AUC2 or AUC3 or round20' 2>&1); echo \"$out\" | tail -1 | grep -Eq '^4 passed' && echo lane278-ok", "expect_exit": 0, "expect_regex": "lane278-ok", "timeout_s": 600}
```

# bound: 1800s
