# 028 — fixtures, canonical comparison, and evidence from the game

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-028`, branch `lane/028`, base = `feat/round-8-blueprints`, tag `wave-4-golden-base` (resolve it with `git rev-parse wave-4-golden-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `tests/golden/**`, `logic/engine_test_api.lua`, `tools/evidence_receipt.py`, `docs/export-format.md`, `docs/golden-workflow.md` and `docs/engine-evidence/README.md`.
- `tests/run.sh` discovers `tests/test_*.lua` and `tests/tools/*.py` only. Nothing you add may make the fast suite start a golden run or a game.
- A captured candidate is a draft expectation until it is reviewed. The generator producing it is never proof that it is right.
- A development checkout can never pass as a release candidate.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/engine_test_api.lua` carries the interface sketch and `EngineTestApi.build_id()`, which reads `logic/build_id.lua` through a guarded `pcall` and reports `{candidate_sha = "dev", packaged = false}` when it is absent. `control.lua` already calls `EngineTestApi.register()`; `control.lua` is frozen.
- `generate_release.sh` is frozen and **does** write `logic/build_id.lua` into the packaged copy, taking the commit from `RRC_CANDIDATE_SHA` when the builder sets it, else `git rev-parse HEAD`, else `unknown`. The working tree never holds that file, so a source checkout reports `packaged = false`.
- `remote.call` returns inside its own tick, so generation is a job: `start_generation(context)`, `generation_status(job_id)`, `cancel_generation(job_id)`, beside `build_id()`, `preflight(case)`, `export(sheet_id)` and `canonical(blueprint_string)` (`docs/feature-contracts.md` §14).
- `logic/bp/serialize.lua` owns `Serialize.canonical` and `CANONICAL_VERSION`; compare canonical structure, never the compressed string, because equal factories can compress to different bytes.
- `logic/export_payload.lua` produces the debug envelope a fixture is authored from, and `H.decode_export` reads one back.
- The supplied reference case is `/home/dev_zaigraev_gmail_com/codex-reviews/rrc-feature-requirements-2026-09-18/`: a blueprint string, its decoded JSON, a summary of its 104 entities, and the sheet screenshots it came from.

## What attempt 1 left undone

Attempt 1 wrote `tests/golden/run`, `logic/engine_test_api.lua` and `tools/evidence_receipt.py`, and its ownership
audit and the whole suite passed. It failed on two checks that were wrong in this task, both now corrected:

- The check ran `lua5.2 tests/test_golden.lua`, a file this task never asks for. The tooling tests live in
  `tests/tools/test_golden_tools.py`, and the corpus runs through `tests/golden/run`. Both are checked now.
- The red proof restored `tools/evidence_receipt.py` from the base, where that file does not exist, so git refused
  with `error: pathspec 'tools/evidence_receipt.py' did not match any file(s) known to git`. There is no red proof
  for a file that is born in this lane; paste the red-then-green transcript in your report instead.

Still missing from attempt 1, and required: `tests/golden/add_case`, `tests/golden/accept`, at least one case
under `tests/golden/cases/`, the shared code under `tests/golden/lib/`, the companion mod under
`tests/golden/engine/mod/`, `tests/tools/test_golden_tools.py`, and the three documents. Keep what attempt 1 built
and add the rest. `logic/engine_test_api.lua` changed under you in the meantime: the packaged build id is now read
at load, because Factorio refuses `require` inside a handler. Never move it back into a function. Your own
`logic/engine_test_api.lua:282` still holds `local Serialize = require "logic.bp.serialize"` inside a function;
`tests/test_no_runtime_require.lua` fails the suite on it. Move that require, and every other one you wrote, to
the top of the file.

## What to build

1. `tests/golden/run` walks the case directories, compares canonical structure, checks the independent invariants, and writes failure artifacts: expected and actual canonical JSON, a readable diff, the blueprint string when valid, the inputs, and timings. It never rewrites an expectation.
2. `tests/golden/add_case` builds a case directory from a debug export plus generation options, filling versions, targets and setup from the snapshot, and leaving only the few human fields.
3. `tests/golden/accept <case>` is the separate, explicit action that replaces an expectation, with a reviewable diff.
4. A case manifest carries what `docs/feature-contracts.md` §14 and the requirements ask for, including the engine scenario: initial state, supply and drain, warm-up, sampling window, expected rates, allowed discrete error and timeout.
5. `logic/engine_test_api.lua` implements the interface against the real generation path, refusing every call when `packaged` is false.
6. `tools/evidence_receipt.py` files one in-game observation against the tested archive, computing `zip_sha256` here rather than trusting the observation for it, and refuses a mismatch of case, candidate or environment.
7. Documentation: the export format with a working offline decoder, the golden workflow, and what an evidence record must contain.
8. Red-first cases in `tests/tools/test_golden_tools.py` (your own new file under the directory you own): a case that matches passes; a renumbered blueprint still matches; a changed belt direction or module quality fails; a rejection case compares reason codes rather than message text; `accept` changes one expectation and leaves the rest; a normal run never rewrites anything; a receipt with the wrong zip hash, wrong candidate or wrong case is refused; a `packaged = false` build id yields no evidence.

## What done mean

```checks
{"name": "golden-tooling-tests", "command": "python3 -m unittest discover -s tests/tools -p 'test_golden*.py' -t .", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 900}
{"name": "golden-corpus", "command": "sh tests/golden/run --branch 2.0", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 1800}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-4-golden-base --manifest docs/tasks/028.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-4-golden-base HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree the
proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green every
check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/engine_test_api.lua`
- `tools/evidence_receipt.py`
- `tests/golden/run`

Touch nothing else.

# bound: 8800s

Reviewer ask: can a normal run ever rewrite an expectation, and can evidence from a development checkout ever be filed?
