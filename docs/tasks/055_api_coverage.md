# 055 — The pinned API covers what the companion actually calls

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-055`, branch `lane/055`, base = `feat/round-8-blueprints`, tag `queue-base` (resolve it with `git rev-parse queue-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `tools/extract_api.py`, `docs/api/2.0.77.members.json`, `docs/api/2.1.19.members.json`, `tests/test_api_shapes.lua` and new `tests/test_companion_api_shapes.lua`. Everything else is frozen.
- `tests/golden/engine/mod/` is **not** yours: you report a wrong companion call, you never fix it here. Lane 053 owns `logic/bp/search.lua`. Lane 056 owns `logic/bp/generation.lua` and `logic/engine_test_api.lua`. Lane 057 owns new files under `tests/golden/`.
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
- `tools/extract_api.py:5` lists 21 classes. Both extracts carry those 21 and no others: `LuaEntity` is absent and `LuaFluidBox` is absent, checked today on this base.
- `tests/golden/engine/mod/scenario.lua` builds entities, reads fluid boxes, inserts items, sets qualities, connects wires and writes files, so nothing checks the members it calls on those classes.
- Absence from the current extract is **never** proof the engine lacks a member. The pinned sources are `https://lua-api.factorio.com/2.0.77/runtime-api.json` and `https://lua-api.factorio.com/2.1.19/runtime-api.json`.
- `tests/test_api_shapes.lua` already checks that every member the harness mocks exists with the right kind, and case `A7` checks every style name the mod uses against `docs/api/2.0.77.styles.json`.

## What to build

1. `tools/extract_api.py` records, per extract, the source URL, the API version and a digest of the downloaded description, and regenerates both extracts deterministically.
2. The class list grows to cover every class the companion and the mod actually call, `LuaEntity` and `LuaFluidBox` included, with `parent` chains resolved and attributes kept apart from methods.
3. `tests/test_companion_api_shapes.lua` reads `tests/golden/engine/mod/**` and checks every engine member it names against the pinned extract for both branches, keeping the attribute-versus-method distinction.
4. A member the companion calls that the engine has not got is a failure naming the file, the member and the class. Plant one wrong member yourself and paste the red run, then the green run.
5. A call whose shape the strict adapter depends on is checked where the extract describes it. Never widen a pin to match a guess, and never edit the companion.
6. If the companion genuinely calls something the engine lacks, write the minimal failing case, name the exact correction, and report it for the companion's owner.

## What done mean

```checks
{"name": "api-tests", "command": "lua5.2 tests/test_api_shapes.lua && lua5.4 tests/test_api_shapes.lua && lua5.2 tests/test_companion_api_shapes.lua && lua5.4 tests/test_companion_api_shapes.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "extracts-regenerate", "command": "python3 tools/extract_api.py --check", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 600}
{"name": "harness-still-green", "command": "lua5.2 tests/test_engine_runtime_adapter.lua && lua5.2 tests/test_engine_scenario.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base queue-base --manifest docs/tasks/055.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the planted wrong member failing, then the green run.
- `git diff --stat queue-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `tools/extract_api.py`
- `docs/api/2.0.77.members.json`
- `docs/api/2.1.19.members.json`
- `tests/test_api_shapes.lua`
- `tests/test_companion_api_shapes.lua`

Touch nothing else.

# bound: 1700s

Reviewer ask: does one test now cover every engine member the companion names?
