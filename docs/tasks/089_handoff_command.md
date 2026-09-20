# 089 — One command stands between a built archive and the player

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-089`, branch `lane/089`, base tag `round-9-base` (resolve with `git rev-parse round-9-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own new `tools/handoff.sh`, new `docs/handoff.md` and new `tests/tools/test_handoff.py`.
- `tools/build_test_zip.sh`, `prepare_release.sh`, `tools/release_gate.py`, `tests/run.sh` and every test file are frozen.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- Never edit a file this lane does not own. If you need a change elsewhere, stop and report it.
- Never weaken an assertion, delete a case, or accept a new baseline. A changed expectation stops the lane.
- Never edit `info.json` or `mod-description.md`; both carry the player's own uncommitted work.
- Never add a "skip if the dependency is missing" branch to any test.

Measured on this base: `tools/build_test_zip.sh` archives a commit and writes two zips. It runs **no** test. The
acceptance command is separate and manual. So an archive can reach the player having proved nothing.

Two facts that decide the design:

- `tests/golden/lib/runner.py:1105-1114` counts every `draft` and `captured` case as a failure, and the branch requirement reports `branch 2.1 matches zero accepted required cases`. The corpus therefore **cannot** gate this command; it is recorded as informational.
- `tests/run.sh` changes directory relative to its own location, and several python tests resolve the repository from `Path(__file__)`. Staging tests from the live checkout would exercise the wrong tree.

## What to build

`sh tools/handoff.sh <sha> <2.0 version> <2.1 version>`:

1. Builds both archives through `tools/build_test_zip.sh` into a temporary workspace.
2. Extracts each archive, and stages tests and tools **from the same candidate sha** with `git archive`, never from the live checkout.
3. Asserts every loaded production module resolves under the extracted root.
4. Sanitizes `RRC_SHAPES` and `LUAS` so a narrowed environment cannot pass for a full run, and compares expected against executed case counts.
5. Runs the enumerated gating set: `sh tests/run.sh`, `sh tests/acceptance/run`, and `lua5.2 tests/test_quality_policy.lua`. Records `sh tests/golden/run --branch 2.0 --drafts report` as informational, with its exit code stored and never gating.
6. Writes `docs/handoff/<candidate sha>/<archive set sha256>.json` exactly as `docs/feature-contracts.md` §22 and the plan's handoff record state. Failed attempts are retained, never overwritten.
7. Refuses with exit `2` on any failing gating check, a missing archive, empty case discovery, or a count mismatch. There is no force mode.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; rm -f \"$S/tools/handoff.sh\"; if out=$(cd \"$S\" && python3 -m unittest tests.tools.test_handoff 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q 'FAILED (failures=' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "python3 -m unittest tests.tools.test_handoff 2>&1 | tail -3", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 900}
{"name": "usage-is-refused", "command": "sh tools/handoff.sh; echo \"exit=$?\"", "expect_exit": 0, "expect_regex": "exit=2", "timeout_s": 120}
{"name": "suite", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 089_handoff_command", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-9-base --manifest docs/tasks/089.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Your own tests must prove, with harmless doubles and no real agent or merge: a planted failing gating check
refuses; a narrowed `RRC_SHAPES` refuses instead of passing; two different archive sets keep two records; a
refused attempt is still written; the informational corpus line never turns a pass into a refusal.

## Files this lane owns

`tools/handoff.sh`, `docs/handoff.md`, `tests/tools/test_handoff.py`

# bound: 2700s
