# 088 — The player's exported sheet becomes a runnable 2.0 golden case

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-088`, branch `lane/088`, base tag `round-9-base` (resolve with `git rev-parse round-9-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `tests/golden/add_case`, the new case directory `tests/golden/cases/player-speed-module-chain/**`, `tests/golden/required-matrix.json`, `docs/golden-coverage.md`, and new `tests/tools/test_golden_capture.py`.
- `tests/golden/lib/runner.py`, `tests/golden/capture_case.lua` and every other golden file are frozen.
- `tests/tools/test_golden_matrix.py` is frozen and must keep passing: it already knows the three states `draft`, `captured`, `accepted`.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- Never edit a file this lane does not own. If you need a change elsewhere, stop and report it.
- Never weaken an assertion, delete a case, or accept a new baseline. A changed expectation stops the lane.
- Never edit `info.json` or `mod-description.md`; both carry the player's own uncommitted work.
- Never add a "skip if the dependency is missing" branch to any test.

The player's decoded export is on this host, read-only:

```text
~/codex-reviews/rrc-quality-rejection-evidence-2026-09-20/user-export.json
sha256 2d4de442dc13fc0872c01c7c1805d83c7498455a9d810aa637d0e6d865ec9c09
```

It is a 2.0.77 game with Space Age and Quality, one target of `assembling-machine-2` at 1/s, seven active steps,
and `speed-module-3` carrying `quality = -0.25`. It carries **no** prepared generation input, **no** recipe
projection and **no** receiver facts. Those absences are facts to record, never gaps to fill by guessing.

Measured on this base: `add_case` writes `factorio_branch: "2.0.77"` and `source_kind: "handwritten_fixture"`, and
`tests/golden/lib/runner.py` then reports the case `NOT_APPLICABLE` for `--branch 2.0`, because it compares that
field literally (`runner.py:680-690`).

## What to build

1. `add_case` writes the branch and the engine version as two separate facts: `factorio_branch` is `2.0` or `2.1`, and the exact engine version lives in `versions.base_game_version`. Never derive one by truncating the other silently; derive it and record both.
2. `add_case` records what the capture did **not** carry, as `facts_missing`, listing at least `prepared_input`, `catalog.recipe` and `effect_receiver` when they are absent, plus the observed failure stage and reason codes when the export carries them.
3. `source_kind` tells the truth: an export with no prepared input is not a generation capture.
4. Import the player's export as `tests/golden/cases/player-speed-module-chain/`, state `draft`, outcome `production`, branch `2.0` only. Add its row to `tests/golden/required-matrix.json` and `docs/golden-coverage.md` as an open gap.
5. Never invent 2.1 provenance for a 2.0 capture.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-9-base -- tests/golden/add_case || exit 1; if out=$(cd \"$S\" && python3 -m unittest tests.tools.test_golden_capture 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q 'FAILED (failures=' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "python3 -m unittest tests.tools.test_golden_capture 2>&1 | tail -3", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 600}
{"name": "matrix-still-honest", "command": "python3 -m unittest tests.tools.test_golden_matrix 2>&1 | tail -3", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 600}
{"name": "case-is-selected-for-2.0", "command": "sh tests/golden/run --branch 2.0 --drafts report 2>&1 | grep -E 'player-speed-module-chain'", "expect_exit": 0, "expect_regex": "DRAFT player-speed-module-chain", "timeout_s": 900}
{"name": "suite", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 088_case_importer", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-9-base --manifest docs/tasks/088.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

## Files this lane owns

`tests/golden/add_case`, `tests/golden/cases/player-speed-module-chain/**`, `tests/golden/required-matrix.json`, `docs/golden-coverage.md`, `tests/tools/test_golden_capture.py`

# bound: 2400s
