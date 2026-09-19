# Round 8 board — one list, replaces every older "next step"

Updated 2026-09-19 10:45 UTC, HEAD 5d5f9c8, by the integrator on host `legalcopilot-dev`. Branch
`feat/round-8-blueprints`, never pushed, never merged to `main`. Dispatch follows
`~/codex-reviews/rrc-parallel-execution-unblock-plan-2026-09-19-1014.md`: five disjoint lanes run beside every
physical repair, and no lane waits on the blueprint pipeline for work it can finish alone.

## Streams

| Stream | Lane | Owner live? | Base SHA | Owns | State and next command |
|---|---|---|---|---|---|
| Repair: block port binding | 047 | no | binding-base 835a66e | `logic/bp/groups.lua`, `logic/bp/route.lua`, `tests/test_groups.lua`, `tests/test_route.lua` | **merged** 93fcfe3 |
| S service lifecycle and capture | 048 | **yes** | unblock-base 93fcfe3 | `gui/blueprint_dialog.lua`, `logic/bp/generation.lua`, `logic/engine_test_api.lua`, two new test files, `tests/test_bp_settings.lua` | running; carries lane 039's checkpoint 17ca320 as its first commit |
| C calculation result record | 049 | **yes** | unblock-base 93fcfe3 | `logic/calc_pipeline.lua`, new `logic/calculation_result.lua`, their two test files | running; §19 frozen |
| E real engine adapter | 050 | **yes** | unblock-base 93fcfe3 | `tests/golden/engine/mod/`, `tests/test_engine_scenario.lua`, new `tests/test_engine_runtime_adapter.lua`, `docs/engine-evidence/runner.md` | running; §21 frozen |
| R evidence contract and release gate | 051 | no | unblock-base 93fcfe3 | `tools/release_gate.py`, its tests, new `tests/tools/test_evidence_contract.py`, `docs/release-preparation.md` | **merged**; verdict FAIL was my broken manifest, verified by hand |
| G capture to case workflow | 052 | **yes** | unblock-base 93fcfe3 | `logic/export_payload.lua`, its test, `tests/golden/add_case`, `tests/golden/lib/common.py`, new `tests/tools/test_capture_workflow.py`, `docs/golden-workflow.md` | running; §20 frozen |
| Lane 039 (superseded) | 039 | no | recovery-base-039c 7e4a5c2 | — | attempt 3 terminal; work preserved as checkpoint 3698214, now lane 048's first commit |
| Merged earlier | 037, 038, 040–046 | no | — | calculation activation, export shape, engine runner, release gate, golden workflow, coverage, two repairs | **merged** |
| Integrator | — | yes | — | `tests/harness.lua`, `tests/run.sh`, `control.lua`, `gui/sheet.lua`, `gui/export_dialog.lua`, locale, `docs/feature-contracts.md`, `docs/engine-evidence/examples/`, task files, corpus matrix, merges | active |

## Frozen interfaces (2026-09-19)

`docs/feature-contracts.md` §19 calculation result record, §20 prepared capture, §21 observation v1 with the
producer's own spelling. `docs/engine-evidence/examples/` holds one synthetic example per outcome kind.

## What is done

Waves 1 to 4 merged and sealed: snapshot, jobs, catalog, grid, export dialog, progress panel, payload, solver
steps, reset, report steps, plan, preflight, calc pipeline, settings, pack, groups, route, power, validate,
serialize, search, delivery, golden skeleton. Suite 2596 case runs, 0 failed, both interpreters, plus 27 Python
tooling tests and the golden corpus. Mutation batches: W1 8 of 9 with one recorded equivalent, W2 7 of 7,
W3 12 of 12, W3b 6 of 6, W4 6 of 6.

In game, on 2.0.77: the user confirms the debug export window works at 1.1.47 — selectable text that refuses
typing, Esc and the close key shut it, the title bar's X shuts it. Reset works, the blueprint dialog and its
per-category pickers are accepted. Two window defects reached the game first: `add{}` silently dropped
`read_only`, and an invented style name (`draggable_space_with_no_left_margin`) crashed on open. Both classes now
fail offline — `docs/api/2.0.77.styles.json` pins 582 core style names.

## Two real defects found by running a real sheet

Both came from lane 039's end-to-end case, never from a unit test.

1. **Obstacle shape** (fixed, lane 043): `search.lua` gave `Pack.begin` the `{rect, owner}` records the power
   stage wants; the packer reads bare rectangles, so `Grid.free_regions` raised
   `logic/bp/grid.lua:73: attempt to compare number with nil`.
2. **Perimeter ports** (fixed, lane 044): `search.lua:314` asked `Grid.edge_slots` for slots on the grid's own
   envelope, and §5.8 puts an attach tile outside the envelope, which for the grid is outside the world.
   `route.lua:260` maps every outside cell to `"__outside__"` and routing treats it as blocked, so a real sheet
   ended `BP_R_PORT_BLOCKED`, then `BP_FAIL_NO_LAYOUT_GRID_LIMIT`. Contract §18 decided the rule; the search now
   builds perimeter slots on the grid's own edge cell, and a small real plan reaches `state.ok == true` with a
   serialized result.

Expect more of these. A unit-green module set says nothing about the path a player takes.

## What is not done

- Generate queues a real job and reaches routing. Three real defects are fixed (obstacle shape 043, perimeter
  ports 044, block port binding 047). No blueprint has reached a player yet; lane 048 owns that gate.
- One case in the matrix is accepted; 19 are drafts, every GOLD-09 category has a row, and `sh tests/golden/run
  --branch 2.0 --drafts report` names every gap and exits 1. `--branch 2.1` matches zero accepted cases.
- Every draft's capture-dependent fields are empty and its reason codes are terminal, checked by
  `tests/tools/test_golden_matrix.py` against the groups in `logic/bp/reason_codes.lua` (54 Python tests).
  Nothing is captured yet: a capture needs the real preparation path, which is lane 039's deliverable.
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
