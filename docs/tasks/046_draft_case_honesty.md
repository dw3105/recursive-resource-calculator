# 046 — A draft case says what it is, and never names a code the player cannot see

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-046`, branch `lane/046`, base = `feat/round-8-blueprints`, tag `draft-honesty-base` (resolve it with `git rev-parse draft-honesty-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair of two content defects merged with lane 045. The corpus machinery is right; the 19 draft manifests are not.

## What is true

**PRESERVE:**
- You own `tests/golden/cases/`, `tests/golden/required-matrix.json`, `docs/golden-coverage.md` and `tests/tools/test_golden_matrix.py`. Everything else is frozen; if you need a change elsewhere, stop and report.
- `tests/golden/lib/runner.py`, `tests/golden/run`, `add_case`, `accept`, `generate.lua`, `tools/release_gate.py` and `tests/tools/test_golden_tools.py` are frozen. `logic/bp/reason_codes.lua` is frozen; read it, never edit it.
- Lane 039 owns `gui/blueprint_dialog.lua`, `logic/bp/generation.lua`, `logic/engine_test_api.lua`, `tests/test_blueprint_pipeline.lua`, `tests/test_engine_test_api.lua` and `tests/test_bp_settings.lua` right now. Never touch them.
- `tests/golden/cases/basic-canonical/` is the one accepted case. Its three files never change, and it keeps passing.
- A draft never becomes an accepted expectation here. `--drafts report` keeps exiting non-zero and the default run keeps refusing a draft.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts, reproduced on this base:
- All 19 draft manifests copy the accepted baseline's content. `tests/golden/cases/unsupported-spoilage/manifest.json` declares `targets` `item/iron-gear-wheel` and `setup.selection` recipe `iron-gear-wheel`; so does `tests/golden/cases/fluid-byproduct-chain/manifest.json`, which is meant to carry mixed fluids and byproducts and names no fluid at all. Every one of the 19 declares the same `engine_scenario.supply` of `item/iron-plate` at 2 per second.
- `tests/golden/cases/belt-inserter-bottleneck/manifest.json` declares `reason_codes: ["BP_R_CAPACITY"]`. `logic/bp/reason_codes.lua:27-30` lists `BP_R_CAPACITY` under `ReasonCodes.INTERNAL`, and `logic/bp/reason_codes.lua:7` says a stage raises an internal code to tell the search to retry or grow and the player never sees one. `logic/bp/route.lua:744` raises it inside routing. A terminal rejection carries a `ReasonCodes.REJECT` code; a terminal search outcome carries a `ReasonCodes.FAIL` code.
- `tests/tools/test_golden_matrix.py:102-103` only asserts a rejection has some `reason_codes`; nothing checks which group the code belongs to, and nothing checks that a draft's declared content differs from the baseline's.

## What to build

1. Every draft manifest declares its own category honestly. A field whose value must come from a captured sheet is declared empty — `targets: []`, `setup.selection: []`, `engine_scenario.supply: []`, `engine_scenario.drain: []`, `engine_scenario.expected_rates: {}` — never filled with the baseline's iron-gear-wheel values. `capture_pending` keeps naming the sheet to capture.
2. Every declared `reason_codes` entry comes from `ReasonCodes.REJECT` or `ReasonCodes.FAIL` in `logic/bp/reason_codes.lua`. `belt-inserter-bottleneck` gets the terminal code its stage raises, not `BP_R_CAPACITY`. A rejection case names its stage the release gate expects.
3. `tests/tools/test_golden_matrix.py` gains three checks: a declared reason code outside `REJECT` and `FAIL` fails, naming the code and its group; a draft manifest whose `targets` or `setup.selection` equals the accepted baseline's fails; a draft manifest whose capture-dependent fields are non-empty without matching its own category fails. Read the code groups from `logic/bp/reason_codes.lua`, never from a list copied into the test.
4. `docs/golden-coverage.md` keeps one row per GOLD-09 category and states, per row, that its content arrives with the capture.
5. If a category genuinely needs a non-empty declared field before capture, say which and why in your report rather than inventing one.

## What done mean

```checks
{"name": "matrix-tests", "command": "python3 -m unittest discover -s tests/tools -p 'test_*.py' -t .", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 600}
{"name": "drafts-still-reported", "command": "sh tests/golden/run --branch 2.0 --drafts report; test $? -eq 1 && echo drafts-nonzero", "expect_exit": 0, "expect_regex": "drafts-nonzero", "timeout_s": 900}
{"name": "baseline-untouched", "command": "git diff --name-only draft-honesty-base HEAD -- tests/golden/cases/basic-canonical | wc -l", "expect_exit": 0, "expect_regex": "^0$", "timeout_s": 120}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base draft-honesty-base --manifest docs/tasks/046.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the new checks failing against this base's manifests, naming `BP_R_CAPACITY` and one copied-baseline case, then passing after.
- `git diff --stat draft-honesty-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `tests/golden/cases/`
- `tests/golden/required-matrix.json`
- `docs/golden-coverage.md`
- `tests/tools/test_golden_matrix.py`

Touch nothing else.

# bound: 1400s

Reviewer ask: can a draft still claim a code the player never sees, or borrow the baseline's sheet?
