# 045 — The corpus says what it covers, and a gap is machine-visible

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-045`, branch `lane/045`, base = `feat/round-8-blueprints`, tag `coverage-base` (resolve it with `git rev-parse coverage-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Stream E of the recovery plan. The corpus today holds one case and claims nothing about the rest.

## What is true

**PRESERVE:**
- You own `tests/golden/cases/`, `tests/golden/required-matrix.json`, `tests/golden/lib/runner.py`, new `docs/golden-coverage.md` and new `tests/tools/test_golden_matrix.py`. Everything else is frozen; if you need a change elsewhere, stop and report.
- Lane 039 owns `gui/blueprint_dialog.lua`, `logic/bp/generation.lua`, `logic/engine_test_api.lua`, `tests/test_blueprint_pipeline.lua`, `tests/test_engine_test_api.lua` and `tests/test_bp_settings.lua` right now. Never touch them.
- `tools/release_gate.py`, `prepare_release.sh`, `tests/golden/run`, `add_case`, `accept`, `generate.lua` and `tests/tools/test_golden_tools.py` are frozen. Your runner change is one added option, nothing else.
- Every existing case stays. `tests/golden/cases/basic-canonical/` keeps passing exactly as it does today.
- A prepared input is **captured from the real preparation path** (`docs/feature-contracts.md:301-309`). Never write a plan by hand and file it as a captured sheet. A case with no captured input stays `state: "draft"` and says so.
- A draft is never a skipped success. `tools/release_gate.py:430` fails a draft required case, and that behaviour never weakens.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- `tests/golden/required-matrix.json` holds 7 rows: `basic-canonical` accepted, and `assembler-chain-example`, `fluid-byproduct-chain`, `belt-inserter-bottleneck`, `multi-pole-connectivity`, `import-build-round-trip`, `export-decode` all draft with `prepared_input: null`.
- Only one case directory exists: `tests/golden/cases/basic-canonical/` with `manifest.json`, `candidate.json`, `expected_canonical.json`. The other six rows name no directory at all, so nothing checks that a matrix row and a case on disk agree.
- `tests/golden/lib/runner.py:1098` raises `draft case cannot satisfy the release corpus` for any case whose manifest says `state: "draft"`. So adding a draft directory today turns `sh tests/golden/run --branch 2.0` from green into an error with no list of what is missing.
- `tests/golden/lib/runner.py:1044-1048` counts a branch satisfied only by a non-draft case; `tests/golden/lib/runner.py:624` reads `independent_assertions`; `tests/golden/lib/runner.py:669` reads `expected_outcome` and `reason_codes`.
- A case manifest's frozen field set is visible in `tests/golden/cases/basic-canonical/manifest.json`: `schema_version`, `case_id`, `factorio_branch`, `versions`, `targets`, `setup`, `engine_scenario` (with `initial_state`, `supply`, `drain`, `warm_up_ticks`, `sampling_window_ticks`, `expected_rates`, `allowed_discrete_error`, `timeout_seconds`), `expected_outcome`, `expected`, `actual`, `independent_assertions`.
- `GOLD-09` lists the corpus categories: the provided assembler-chain example; base-only crafting and smelting; a shared-intermediate multi-target case; mixed fluids with deterministic byproducts; shared beacons and competing beacon loadouts; 2x2-to-larger grid growth with a larger-grid beacon improvement; quality of machines and infrastructure; a standard modded machine or interface; belt and inserter bottleneck handling; connected multi-pole coverage; repeatability; unsupported cycles, quality-changing, spoilage, probabilistic and custom behaviour; and a known-feasible case at the 100-machine and 30-step boundary.
- `COMP-01` needs both `2.0` and `2.1`. Every matrix row except `basic-canonical` already claims both branches, and no case directory declares `2.1` at all.

## What to build

1. `docs/golden-coverage.md`: one row per GOLD-09 category, naming the case that covers it, its branches, its outcome kind and its state today. A category with no case is written as an open gap with the reason, never left out.
2. Extend `tests/golden/required-matrix.json` so every GOLD-09 category has a row. Keep the 7 existing `case_id` values and their clauses unchanged; add the missing categories as new draft rows with `branches`, `mods`, `outcome_kind`, `clauses` and `prepared_input: null`.
3. Author a draft case directory for every matrix row that has none: `tests/golden/cases/<case_id>/manifest.json` carrying the field set above, `state: "draft"`, a real `engine_scenario` with supply, drain, expected rates and an allowed discrete error, `independent_assertions` naming the invariants that case is for (`conservation`, `simultaneous_demand`, `transport_capacity`, `beacon_coverage`, `power_connectivity`, `grid_containment`), and an explicit `"capture_pending"` note saying which real sheet must be captured. No invented `expected_canonical.json`, no invented `candidate.json`, no handwritten `prepared_input.json`.
4. A rejection row (for example `belt-inserter-bottleneck` and every unsupported-behaviour category) declares `expected_outcome: "rejection"`, its `reason_codes` from `docs/feature-contracts.md` §6, and no blueprint fields.
5. One added option in `tests/golden/lib/runner.py`: `--drafts report` prints `DRAFT <case>` per draft case and a closing count, and leaves the exit status non-zero unless every selected case is accepted and passes. Default behaviour without the option is unchanged, and a draft is never printed as `PASS` and never counted as accepted.
6. `tests/tools/test_golden_matrix.py`: for every matrix row, a case directory exists, its `manifest.json` agrees with the row on `case_id`, `outcome_kind` versus `expected_outcome` and `state`, and its `factorio_branch` is one of the row's `branches`; every branch the row claims has a directory; every GOLD-09 category in the coverage doc names a matrix row and every matrix row appears in the doc; a draft row is reported as a gap and never as coverage; a row naming a missing directory fails.
7. If a category cannot be expressed in the frozen manifest shape, stop and report which field is missing. Never widen the schema on your own.

## What done mean

```checks
{"name": "matrix-tests", "command": "python3 -m unittest discover -s tests/tools -p 'test_*.py' -t .", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 600}
{"name": "corpus-still-green", "command": "sh tests/golden/run --branch 2.0 --drafts report", "expect_exit": 1, "expect_regex": "PASS basic-canonical", "timeout_s": 900}
{"name": "draft-still-refused", "command": "sh tests/golden/run --branch 2.0; test $? -ne 0 && echo draft-refused", "expect_exit": 0, "expect_regex": "draft-refused", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base coverage-base --manifest docs/tasks/045.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste `tests/tools/test_golden_matrix.py` failing before the matrix and the directories exist, and passing after.
- Paste the `--drafts report` run showing `PASS basic-canonical` and one `DRAFT` line per draft case.
- `git diff --stat coverage-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `tests/golden/cases/`
- `tests/golden/required-matrix.json`
- `tests/golden/lib/runner.py`
- `docs/golden-coverage.md`
- `tests/tools/test_golden_matrix.py`

Touch nothing else.

# bound: 2400s

Reviewer ask: does one command now name every corpus gap, and does a draft still fail the release gate?
