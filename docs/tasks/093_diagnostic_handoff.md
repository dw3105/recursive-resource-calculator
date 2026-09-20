# 093 — A diagnostic build reaches the player honestly, with its blockers named

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-093`, branch `lane/093`, base tag `round-10-base` (resolve with `git rev-parse round-10-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `tools/handoff.sh`, `docs/handoff.md` and `tests/tools/test_handoff.py`.
- `tools/release_gate.py`, `prepare_release.sh`, `tests/golden/lib/runner.py`, `tests/golden/required-matrix.json`, `tests/golden/add_case`, `tests/golden/accept` and every `logic/` file are frozen.
- `docs/feature-contracts.md` §23 is a frozen contract. Read §23.5 first.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- Never edit a file this lane does not own. If you need a change elsewhere, stop and report it.
- Never weaken an assertion, delete a case, or accept a new baseline. A changed expectation stops the lane.
- Never edit `info.json` or `mod-description.md`; both carry the player's own uncommitted work.
- **This lane does not fix corpus gating.** `tools/handoff.sh:307` passes `false` to `run_check`, and `tests/tools/test_handoff.py:238` pins that. Both stay for the ordinary path. A later checkpoint replaces them, and doing it here would block the diagnostic build this lane exists to deliver.

**Write the new python cases first, before changing the script.**

A zip reached the player while the golden corpus was failing. The receipt
`docs/handoff/f66881c02d5c7b72dbc563582000db217505c285/8ab2dcc90b2fbee3cf9f3831f2700529c80779ef970fccee6fae4c08203ed93d.json`
records `"result": "pass"` beside two corpus exits of `1`. That is the ambiguity this lane removes — not by making
the corpus gate today, but by making the **kind** of archive explicit.

A diagnostic archive is how engine evidence gets collected in the first place. Verified on this base, host
`legalcopilot-dev`, 2026-09-20: `tools/release_gate.py:467-471` refuses a draft or non-accepted case, and the
matrix holds 15 draft and 5 captured rows, so requiring the release gate before **any** archive copy would stop
the diagnostic build from ever reaching the player. An incomplete release corpus must therefore never block a
diagnostic handoff — while a failing **export** check must.

## What to build

A `--diagnostic` mode for `tools/handoff.sh`, and nothing else:

1. It runs the export-specific checks. `tests/test_export_completeness.lua` is the entry point; it exists on the integrated branch, and on this base you drive the mode with a harmless double, the way `HandoffFixture` already doubles `tests/run.sh` and `tests/acceptance/run`.
2. It records the exact build identity: candidate sha, and the sha256 of each archive handed over.
3. It lists **every** current release blocker in the receipt — each failing or unfinished gate, named, with its exit status. A blocker is recorded, never hidden and never fatal.
4. It always writes `verdict: "unverified_internal"` per archive. It can never write `verified`, whatever else passes.
5. A failing export check **refuses** the diagnostic build. An incomplete release corpus alone does not.
6. `docs/handoff.md` states plainly that neither mode means the blueprint generator works.

The ordinary path keeps today's behaviour exactly. Changing it is a later checkpoint's job.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-10-base -- tools/handoff.sh || exit 1; if out=$(cd \"$S\" && python3 -m unittest -v tests.tools.test_handoff 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL: test_a_diagnostic_run_is_always_unverified_internal' || { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE '^ERROR:' && { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE '^FAILED \\(failures=[1-9]' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "python3 -m unittest -v tests.tools.test_handoff", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 900}
{"name": "ordinary-path-unchanged", "command": "grep -q 'test_informational_corpus_failure_does_not_refuse' tests/tools/test_handoff.py || { echo 'the ordinary path lost its pinned behaviour'; exit 1; }; echo ordinary-path-kept", "expect_exit": 0, "expect_regex": "ordinary-path-kept", "timeout_s": 60}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 093_diagnostic_handoff", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 1800}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-10-base --manifest docs/tasks/093.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Your own tests must include, by these exact case names:

- `test_a_diagnostic_run_is_always_unverified_internal` — whatever passes, every archive carries that verdict.
- `test_a_diagnostic_run_can_never_write_verified` — no input, planted or otherwise, produces `verified`.
- `test_a_diagnostic_run_records_every_release_blocker` — each failing or unfinished gate appears in the receipt by name with its exit status.
- `test_an_incomplete_corpus_does_not_block_a_diagnostic_build` — the archive is still copied, and the blocker is recorded.
- `test_a_failing_export_check_refuses_the_diagnostic_build` — exit non-zero, no archive copied.
- `test_a_diagnostic_receipt_carries_the_exact_candidate_and_archive_identity` — candidate sha and each archive sha256 match the bytes handed over.
- `test_the_ordinary_path_is_unchanged_by_the_diagnostic_mode` — an ordinary run behaves exactly as it does today.

## Files this lane owns

`tools/handoff.sh`, `docs/handoff.md`, `tests/tools/test_handoff.py`

# bound: 2700s
