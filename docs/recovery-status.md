# Round 8 board — one list, replaces every older "next step"

Updated 2026-09-19, HEAD 05fab31, by the integrator on host `legalcopilot-dev`. Branch `feat/round-8-blueprints`, never pushed,
never merged to `main`. This board supersedes the "next three steps" of `~/.claude/plans/rrc-round-8-handoff.md`.

## Streams

| Stream | Lane | Owns | State |
|---|---|---|---|
| Calculation activation | 037 | `control.lua`, `gui/sheet.lua`, `logic/calc_pipeline.lua`, six older test files | **merged** |
| A blueprint generation service | 039 | `gui/blueprint_dialog.lua`, `logic/bp/generation.lua`, `logic/engine_test_api.lua`, two new test files, `tests/test_bp_settings.lua` | attempt 2 stopped at a real defect; work uncommitted in `~/wt-rrc-039`; run again after lane 044 |
| B engine scenario runner | 040 | `tests/golden/engine/mod/`, `tests/test_engine_scenario.lua`, `docs/engine-evidence/runner.md` | **merged** |
| C release gate | 041 | `prepare_release.sh`, `tools/release_gate.py`, its tests, `tools/evidence_receipt.py`, `generate_release.sh`, `tools/build_test_zip.sh`, `docs/release-preparation.md` | **merged** |
| D golden generates from this candidate | 042 | `tests/golden/run`, `add_case`, `accept`, `lib/`, `generate.lua`, `tests/tools/test_golden_tools.py`, `docs/golden-workflow.md` | **merged** |
| Repair: obstacle shape | 043 | `logic/bp/search.lua`, `tests/test_search.lua` | **merged** |
| Repair: perimeter ports | 044 | `logic/bp/search.lua`, `logic/bp/route.lua`, `tests/test_search.lua`, `tests/test_route.lua` | running, base `perimeter-base` |
| E coverage and scenarios | — | `tests/golden/cases/`, `tests/golden/required-matrix.json`, `docs/golden-coverage.md`, `tests/tools/test_golden_matrix.py` | waits for a slot |
| Integrator | — | `tests/harness.lua`, `tests/run.sh`, locale files, `docs/feature-contracts.md`, `logic/registry.lua`, `control.lua` since 037 merged, `gui/export_dialog.lua`, task files, merges | active |

## What is done

Waves 1 to 4 merged and sealed: snapshot, jobs, catalog, grid, export dialog, progress panel, payload, solver
steps, reset, report steps, plan, preflight, calc pipeline, settings, pack, groups, route, power, validate,
serialize, search, delivery, golden skeleton. Suite 2544 case runs, 0 failed, both interpreters, plus 27 Python
tooling tests and the golden corpus. Mutation batches: W1 8 of 9 with one recorded equivalent, W2 7 of 7,
W3 12 of 12, W3b 6 of 6, W4 6 of 6.

In game, on 2.0.77: no crash since 1.1.41, export decodes offline, reset works, blueprint dialog and its pickers
accepted by the user.

## Two real defects found by running a real sheet

Both came from lane 039's end-to-end case, never from a unit test.

1. **Obstacle shape** (fixed, lane 043): `search.lua` gave `Pack.begin` the `{rect, owner}` records the power
   stage wants; the packer reads bare rectangles, so `Grid.free_regions` raised
   `logic/bp/grid.lua:73: attempt to compare number with nil`.
2. **Perimeter ports** (lane 044, running): `search.lua:314` asks `Grid.edge_slots` for slots on the grid's own
   envelope, and §5.8 puts an attach tile outside the envelope, which for the grid is outside the world.
   `route.lua:260` maps every outside cell to `"__outside__"` and routing treats it as blocked, so a real sheet
   ends `BP_R_PORT_BLOCKED`, then `BP_FAIL_NO_LAYOUT_GRID_LIMIT`. Contract §18 decides the rule.

Expect more of these. A unit-green module set says nothing about the path a player takes.

## What is not done

- Generate queues a real job and reaches routing, then fails; no blueprint reaches the player yet (lanes 044 then 039).
- One case in the matrix is accepted; six are drafts (stream E, never dispatched).
- One case in the matrix is accepted; six are drafts (stream E).
- Engine evidence: none, on either branch. 2.1 has no runtime here at all.

## Tag rule, learned the hard way

A lane's base tag is frozen the moment a worktree forks it. Repointing `recovery-base` after lanes 039 to 042
had forked it made `tools/lane_ownership.py` report `HEAD does not descend from the lane base`, and lane 042 took
a FAIL for work that was entirely inside its own five files. Every new dispatch gets its **own** tag, named for
that dispatch, and no tag is ever moved.

## Rules that still bind

One file has one owner. A lane never edits a locale file, `tests/harness.lua`, `tests/run.sh` or
`docs/feature-contracts.md`. The integrator merges with `git merge --no-ff` and runs the suite; `lane merge` is
not used, so its reviewer and verifier requirements do not apply. Nothing reaches `main` without the user's word.
