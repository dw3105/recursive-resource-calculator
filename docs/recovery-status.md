# Round 8 board — one list, replaces every older "next step"

Updated 2026-09-19 by the integrator on host `legalcopilot-dev`. Branch `feat/round-8-blueprints`, never pushed,
never merged to `main`. This board supersedes the "next three steps" of `~/.claude/plans/rrc-round-8-handoff.md`.

## Streams

| Stream | Lane | Owns | State |
|---|---|---|---|
| Calculation activation | 037 | `control.lua`, `gui/sheet.lua`, `logic/calc_pipeline.lua`, six older test files | running |
| A blueprint generation service | 039 | `gui/blueprint_dialog.lua`, `logic/bp/generation.lua`, `logic/engine_test_api.lua`, two new test files, `tests/test_bp_settings.lua` | dispatched |
| B engine scenario runner | 040 | `tests/golden/engine/mod/`, `tests/test_engine_scenario.lua`, `docs/engine-evidence/runner.md` | dispatched |
| C release gate | 041 | `prepare_release.sh`, `tools/release_gate.py`, its tests, `tools/evidence_receipt.py`, `generate_release.sh`, `tools/build_test_zip.sh`, `docs/release-preparation.md` | dispatched |
| D golden generates from this candidate | 042 | `tests/golden/run`, `add_case`, `accept`, `lib/`, `generate.lua`, `tests/tools/test_golden_tools.py`, `docs/golden-workflow.md` | dispatched |
| E coverage and scenarios | — | `tests/golden/cases/`, `tests/golden/required-matrix.json`, `docs/golden-coverage.md`, `tests/tools/test_golden_matrix.py` | waits for a slot |
| Integrator | — | `tests/harness.lua`, `tests/run.sh`, locale files, `docs/feature-contracts.md`, `logic/registry.lua`, `tools/lane_ownership.py`, `tools/mutate.py`, task files, merges | active |

## What is done

Waves 1 to 4 merged and sealed: snapshot, jobs, catalog, grid, export dialog, progress panel, payload, solver
steps, reset, report steps, plan, preflight, calc pipeline, settings, pack, groups, route, power, validate,
serialize, search, delivery, golden skeleton. Suite 2544 case runs, 0 failed, both interpreters, plus 27 Python
tooling tests and the golden corpus. Mutation batches: W1 8 of 9 with one recorded equivalent, W2 7 of 7,
W3 12 of 12, W3b 6 of 6, W4 6 of 6.

In game, on 2.0.77: no crash since 1.1.41, export decodes offline, reset works, blueprint dialog and its pickers
accepted by the user.

## What is not done

- Generate validates and stops; no blueprint reaches the player yet (lane 039).
- Compute still solves in one call; the bar and Cancel are dead (lane 037).
- The companion forwards calls; it measures nothing (lane 040).
- No `prepare_release.sh`; release readiness is unenforced (lane 041).
- The corpus compares two stored files (lane 042).
- One case in the matrix is accepted; six are drafts (stream E).
- Engine evidence: none, on either branch. 2.1 has no runtime here at all.

## Rules that still bind

One file has one owner. A lane never edits a locale file, `tests/harness.lua`, `tests/run.sh` or
`docs/feature-contracts.md`. The integrator merges with `git merge --no-ff` and runs the suite; `lane merge` is
not used, so its reviewer and verifier requirements do not apply. Nothing reaches `main` without the user's word.
