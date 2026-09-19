# Round 8 board — one list, replaces every older "next step"

Updated 2026-09-19, HEAD c171fcf, by the integrator on host `legalcopilot-dev`. Branch `feat/round-8-blueprints`, never pushed,
never merged to `main`. This board supersedes the "next three steps" of `~/.claude/plans/rrc-round-8-handoff.md`.

## Streams

| Stream | Lane | Owns | State |
|---|---|---|---|
| Calculation activation | 037 | `control.lua`, `gui/sheet.lua`, `logic/calc_pipeline.lua`, six older test files | **merged** |
| A blueprint generation service | 039 | `gui/blueprint_dialog.lua`, `logic/bp/generation.lua`, `logic/engine_test_api.lua`, two new test files, `tests/test_bp_settings.lua` | **attempt 3 running**, base `recovery-base-039c` = 7e4a5c2, work from attempt 2 rebuilt on it |
| B engine scenario runner | 040 | `tests/golden/engine/mod/`, `tests/test_engine_scenario.lua`, `docs/engine-evidence/runner.md` | **merged** |
| C release gate | 041 | `prepare_release.sh`, `tools/release_gate.py`, its tests, `tools/evidence_receipt.py`, `generate_release.sh`, `tools/build_test_zip.sh`, `docs/release-preparation.md` | **merged** |
| D golden generates from this candidate | 042 | `tests/golden/run`, `add_case`, `accept`, `lib/`, `generate.lua`, `tests/tools/test_golden_tools.py`, `docs/golden-workflow.md` | **merged** |
| Repair: obstacle shape | 043 | `logic/bp/search.lua`, `tests/test_search.lua` | **merged** |
| Repair: perimeter ports | 044 | `logic/bp/search.lua`, `logic/bp/route.lua`, `tests/test_search.lua`, `tests/test_route.lua` | **merged** aba5d15 |
| E coverage and scenarios | 045 | `tests/golden/cases/`, `tests/golden/required-matrix.json`, `tests/golden/lib/runner.py`, `docs/golden-coverage.md`, `tests/tools/test_golden_matrix.py` | **merged**; 17 GOLD-09 rows, 19 draft cases, `--drafts report` |
| Repair: draft case honesty | 046 | `tests/golden/cases/`, `required-matrix.json`, `docs/golden-coverage.md`, `tests/tools/test_golden_matrix.py` | **running**, base `draft-honesty-base` = c171fcf |
| Integrator | — | `tests/harness.lua`, `tests/run.sh`, locale files, `docs/feature-contracts.md`, `logic/registry.lua`, `control.lua` since 037 merged, `gui/export_dialog.lua`, task files, merges | active |

## What is done

Waves 1 to 4 merged and sealed: snapshot, jobs, catalog, grid, export dialog, progress panel, payload, solver
steps, reset, report steps, plan, preflight, calc pipeline, settings, pack, groups, route, power, validate,
serialize, search, delivery, golden skeleton. Suite 2580 case runs, 0 failed, both interpreters, plus 27 Python
tooling tests and the golden corpus. Mutation batches: W1 8 of 9 with one recorded equivalent, W2 7 of 7,
W3 12 of 12, W3b 6 of 6, W4 6 of 6.

In game, on 2.0.77: no crash since 1.1.41, export decodes offline, reset works, blueprint dialog and its pickers
accepted by the user.

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

- Generate queues a real job and reached routing; lane 044 cleared that stop, and lane 039 attempt 3 is proving
  whether a click now ends with a blueprint in the player's hand. Nothing delivered yet.
- One case in the matrix is accepted; 19 are drafts, every GOLD-09 category has a row, and `sh tests/golden/run
  --branch 2.0 --drafts report` names every gap and exits 1. `--branch 2.1` matches zero accepted cases.
- Lane 045's 19 draft manifests copy the baseline's iron-gear-wheel sheet, and `belt-inserter-bottleneck` declares
  `BP_R_CAPACITY`, which `logic/bp/reason_codes.lua:7` says the player never sees. Lane 046 repairs both and adds
  the checks that keep them out.
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
