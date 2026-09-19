# 062 — The engine companion calls members the engine actually has

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-062`, branch `lane/062`, base tag `routing-recovery-base` (resolve with `git rev-parse routing-recovery-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `tests/golden/engine/mod/`, `tests/test_engine_runtime_adapter.lua`, `tests/test_engine_scenario.lua`, `tests/test_companion_api_shapes.lua` and `docs/engine-evidence/runner.md`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `docs/api/2.0.77.members.json` and `docs/api/2.1.19.members.json` are pinned extracts of the official `runtime-api.json`. They are frozen. Never edit a pin to make a call legal.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

`tests/test_companion_api_shapes.lua` is **red on this base** and names exactly what you repair, host
`legalcopilot-dev`, 2026-09-19:

```text
FAIL 2.0 C1 every companion engine member is pinned with its source kind [assert]
  tests/golden/engine/mod/scenario.lua: LuaEntity.connect_neighbour is a pinned method: expected true, got false
  tests/golden/engine/mod/scenario.lua: LuaGameScript.write_file is a pinned method: expected true, got false
FAIL 2.1 C1 every companion engine member is pinned with its source kind [assert]
  tests/golden/engine/mod/scenario.lua: LuaEntity.fluidbox is a pinned attribute: expected true, got false
```

So the companion calls three members the pinned engine does not have. `game.write_file` moved to
`helpers.write_file`; wire connections are made through the wire connector API, not `connect_neighbour`; fluid
box access differs between the two branches. Confirm each replacement against the pins in `docs/api/`, never
against memory.

## What to build

1. Replace each unpinned call with the pinned member for that branch. Keep the branch difference explicit in the
   code; never hide an unsupported call behind `pcall`.
2. Make `tests/test_companion_api_shapes.lua` green for both shapes, with no pin edited.
3. Extend `tests/test_engine_runtime_adapter.lua` so the adapter is exercised, not only its member names:
   building and reviving an entity, modules and qualities, electrical connection between two poles,
   perimeter-only supply and drain, and writing an observation file.
4. `docs/engine-evidence/runner.md` must describe commands that the shipped companion actually implements. A
   command that does not exist is a defect, not documentation.

## What done mean

```checks
{"name": "companion-api", "command": "lua5.2 tests/test_companion_api_shapes.lua && lua5.4 tests/test_companion_api_shapes.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 600}
{"name": "adapter-and-scenario", "command": "lua5.2 tests/test_engine_runtime_adapter.lua && lua5.4 tests/test_engine_runtime_adapter.lua && lua5.2 tests/test_engine_scenario.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "api-shapes-unchanged", "command": "lua5.2 tests/test_api_shapes.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 300}
{"name": "pins-untouched", "command": "git diff --name-only routing-recovery-base HEAD | grep -q '^docs/api/' && exit 1; echo pins-untouched", "expect_exit": 0, "expect_regex": "pins-untouched", "timeout_s": 120}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base routing-recovery-base --manifest docs/tasks/062.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

## Files this lane owns

`tests/golden/engine/mod/`, `tests/test_engine_runtime_adapter.lua`, `tests/test_engine_scenario.lua`, `tests/test_companion_api_shapes.lua`, `docs/engine-evidence/runner.md`.

# bound: 1918s
