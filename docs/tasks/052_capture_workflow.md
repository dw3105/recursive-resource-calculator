# 052 — A capture becomes a case, even when the layout failed

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-052`, branch `lane/052`, base = `feat/round-8-blueprints`, tag `unblock-base` (resolve it with `git rev-parse unblock-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/export_payload.lua`, `tests/test_export_payload.lua`, `tests/golden/add_case`, `tests/golden/lib/common.py`, new `tests/tools/test_capture_workflow.py` and `docs/golden-workflow.md`. Everything else is frozen.
- `tests/golden/lib/runner.py`, `tests/golden/run`, `tests/golden/accept`, `tests/golden/cases/`, `tests/golden/required-matrix.json` and `tests/tools/test_golden_matrix.py` are frozen. Lane 048 owns `logic/bp/generation.lua`; read `Generation.capture` through `logic/registry.lua` and stub it in your own tests. Lane 050 owns `tests/golden/engine/mod/`. Lane 051 owns `tools/release_gate.py`.
- Every existing case stays. You add; you never weaken, skip or delete one. An asynchronous path gains bounded ticks, never fewer assertions.
- `require` runs only while `control.lua` is parsed. Never call it inside a function; `tests/test_no_runtime_require.lua` fails the suite on an indented `require`. Use `logic/registry.lua` for a late edge.
- `prototypes`, `game`, `settings` and prototype lists are **userdata**; ask `rawget(_G, "prototypes")`.
- Nothing in `storage` may be a function, a metatable or a LuaObject.
- The coordinator owns `tests/harness.lua`, `tests/run.sh`, `control.lua`, `gui/sheet.lua`, locale files, `docs/feature-contracts.md`, `docs/engine-evidence/examples/`, task files, the corpus matrix and every merge. Need one of them changed? Send the exact small request and carry on with your other work.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**When something outside your files breaks:** record the first failing stage, the immutable input and a bounded
reproducer, and say so in your report at once. Never edit an unowned file and never weaken the positive
assertion. Continue every owned implementation and focused test that does not need that fix. Checkpoint your work
before you end. Report component completion and integration blockage as two separate things: a blocked
integration gate is never an overall PASS.

Current facts:
- `tests/golden/add_case:60` looks for `prepared_input` or `prepared` inside the decoded debug export. `logic/export_payload.lua` writes no such field, so every capture becomes `source_kind = "handwritten_fixture"` and no captured case can exist.
- `docs/feature-contracts.md` §20 freezes `Generation.capture`, `source_kind` (`runtime`, `harness`, `handwritten_fixture`), `provenance` and the rule that `source_export` names the export and never carries its text, so a capture never nests inside itself.
- A capture is taken once preparation finished, so a routing failure later never removes it. `docs/feature-contracts.md` §17.2 fixes `PreparedInput` itself.
- 19 draft case directories already exist. Creating more empty folders is never progress.

## What to build

1. `logic/export_payload.lua` carries the prepared capture of §20 when one exists: `prepared_input`, `source_kind`, `provenance`, and `source_export` as a name only. The dialog's work stays bounded; a big capture never becomes one long synchronous copy when the window opens.
2. The capture survives the envelope: table to JSON, deflate, Base64, and back, with every number intact.
3. `tests/golden/add_case` files a truthful draft from such an export: `source_kind` copied from the capture, never guessed; the supported outcome and the observed outcome as two separate fields; a failed generation still producing a reproducible draft.
4. An accepted baseline stays protected: `add_case --force` still refuses one, and nothing here ever accepts a baseline.
5. `tests/tools/test_capture_workflow.py`: a runtime capture round-trips through encode, decode and `add_case`; a capture whose generation failed at search yields a draft whose observed outcome names that stage and whose supported outcome stays production; a harness capture is labelled `harness` and never `runtime`; a capture naming its own export text is refused.
6. `tests/test_export_payload.lua` gains the encode and decode cases for the capture fields.
7. `docs/golden-workflow.md` states the whole path from a real sheet to a draft case, with the exact commands.

## What done mean

```checks
{"name": "capture-tests", "command": "python3 -m unittest discover -s tests/tools -p 'test_*.py' -t . && lua5.2 tests/test_export_payload.lua && lua5.4 tests/test_export_payload.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "corpus-unchanged", "command": "sh tests/golden/run --branch 2.0 --drafts report; test $? -eq 1 && echo drafts-nonzero", "expect_exit": 0, "expect_regex": "drafts-nonzero", "timeout_s": 900}
{"name": "export-dialog-unchanged", "command": "lua5.2 tests/test_export_dialog.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base unblock-base --manifest docs/tasks/052.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the failed-generation capture becoming a draft case, and the draft's two outcome fields.
- `git diff --stat unblock-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `logic/export_payload.lua`
- `tests/test_export_payload.lua`
- `tests/golden/add_case`
- `tests/golden/lib/common.py`
- `tests/tools/test_capture_workflow.py`
- `docs/golden-workflow.md`

Touch nothing else.

# bound: 2000s

Reviewer ask: does a failed generation still leave a reproducible draft case?
