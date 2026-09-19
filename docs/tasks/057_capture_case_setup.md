# 057 — One command captures one case, layout or no layout

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-057`, branch `lane/057`, base = `feat/round-8-blueprints`, tag `queue-base` (resolve it with `git rev-parse queue-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own new `tests/golden/capture_case.lua`, new directory `tests/golden/setup/`, new `tests/test_case_capture.lua` and new `docs/golden-case-authoring.md`. Everything else is frozen.
- `tests/golden/required-matrix.json`, `tests/golden/cases/`, `tests/golden/lib/`, `tests/golden/add_case`, `tests/golden/run`, `logic/export_payload.lua` and `logic/bp/generation.lua` are **not** yours. Reuse them; never edit them. Lane 056 owns `logic/bp/generation.lua`, lane 053 owns `logic/bp/search.lua`, lane 055 owns `docs/api/*.json`.
- Every existing case stays. You add; you never weaken, skip or delete one.
- The branch carries one **known red** case: `tests/test_blueprint_pipeline.lua` holds the mandatory real-sheet case, which fails with `BP_FAIL_NO_LAYOUT_GRID_LIMIT` while lane 053 repairs the defect under it. Never edit that file, never change its expected outcome, and never treat its failure as yours. Report `component checks: PASS; feature integration: BLOCKED by tests/test_blueprint_pipeline.lua (lane 053)` when your own work is done.
- `require` runs only while `control.lua` is parsed. Never call it inside a function; `tests/test_no_runtime_require.lua` fails the suite on an indented `require`. Use `logic/registry.lua` for a late edge.
- `prototypes`, `game`, `settings` and prototype lists are **userdata**; ask `rawget(_G, "prototypes")`.
- Nothing in `storage` may be a function, a metatable or a LuaObject.
- The coordinator owns `tests/harness.lua`, `tests/run.sh`, `control.lua`, `gui/sheet.lua`, locale files, `docs/feature-contracts.md`, `tests/golden/required-matrix.json`, the board and every merge. Need one changed? Send the exact small patch and carry on with your other work.
- `info.json` carries the user's own uncommitted edit and `mod-description.md` is the user's untracked file. Never touch either.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**When something outside your files breaks:** record the first failing stage, the immutable input and a bounded
reproducer, and say so at once. Never edit an unowned file and never weaken an assertion. Continue every owned
piece that does not need that fix. Checkpoint before you end.

Current facts:
- `Generation.capture(player_index, generation_id)` (contracts §20) returns the prepared input of a job that reached preparation, including one whose search later failed. `logic/export_payload.lua` carries that capture through the envelope, and `tests/golden/add_case` files a draft from it, marking `source_kind` from the capture itself.
- `source_kind` is `runtime` only for a capture taken inside the game. A capture taken in the offline harness is `harness` and is never engine evidence.
- 20 matrix rows exist: one accepted, 19 draft with no setup. Another empty directory is never progress.
- The mandatory real-sheet case in `tests/test_blueprint_pipeline.lua` is red while lane 053 works, so your capture must not need a finished layout.

## What to build

1. A small versioned **setup description**: the prototype facts the fixture needs, the target rows, the chosen recipe, machine, modules and beacons, the infrastructure choice, and the engine scenario assumptions. It records which facts are mocked.
2. `tests/golden/setup/` holds those descriptions and the helper that builds a sheet from one using existing harness facilities. No second preparation implementation.
3. `tests/golden/capture_case.lua`: one command takes one named setup, runs the real sliced calculation and the real preparation, takes the capture, and writes it through the existing export encoding. It bounds its ticks and names the phase it stopped in.
4. A search that fails afterwards leaves the capture intact, and the resulting draft keeps the supported outcome and the observed outcome apart.
5. `tests/test_case_capture.lua`: one tiny fixture end to end — setup, calculation, preparation, capture, encode, decode, `add_case` draft; `source_kind` is `harness`; a failed search still yields a draft; nothing is ever accepted as a baseline.
6. `docs/golden-case-authoring.md`: the exact command, what a setup description carries, what a runtime capture needs instead (mods, research, player setup), and the four facts kept apart — setup exists, capture exists, result meets independent assertions, engine evidence exists.
7. Never run the full corpus in your checks, and never accept a baseline.

## What done mean

```checks
{"name": "capture-tests", "command": "lua5.2 tests/test_case_capture.lua && lua5.4 tests/test_case_capture.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "decoder-and-tools", "command": "python3 -m unittest discover -s tests/tools -p 'test_*.py' -t . && lua5.2 tests/test_export_payload.lua", "expect_exit": 0, "expect_regex": "(?s).*OK.*", "timeout_s": 900}
{"name": "baselines-untouched", "command": "git diff --name-only queue-base HEAD -- tests/golden/cases tests/golden/required-matrix.json | wc -l", "expect_exit": 0, "expect_regex": "^0$", "timeout_s": 120}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base queue-base --manifest docs/tasks/057.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the one command and its output for a capture whose search failed, showing the preserved prepared input.
- `git diff --stat queue-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `tests/golden/capture_case.lua`
- `tests/golden/setup/`
- `tests/test_case_capture.lua`
- `docs/golden-case-authoring.md`

Touch nothing else.

# bound: 1800s

Reviewer ask: does one command produce a labelled capture when the layout never appears?
