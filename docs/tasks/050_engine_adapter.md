# 050 — The engine adapter is tested, not replaced by a fake

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-050`, branch `lane/050`, base = `feat/round-8-blueprints`, tag `unblock-base` (resolve it with `git rev-parse unblock-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `tests/golden/engine/mod/`, `tests/test_engine_scenario.lua`, new `tests/test_engine_runtime_adapter.lua` and `docs/engine-evidence/runner.md`. Everything else is frozen.
- Lane 048 owns `logic/engine_test_api.lua` and `logic/bp/generation.lua`. Lane 051 owns `tools/release_gate.py`. Lane 052 owns `tests/golden/add_case` and `tests/golden/lib/common.py`. Never touch any of them.
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
- `tests/golden/engine/mod/scenario.lua:224` takes `dependencies.adapter or Scenario.runtime_adapter()`, and today's cases always inject a fake adapter, a fake blueprint build and fake supply and drain. So `Scenario.runtime_adapter()` at `tests/golden/engine/mod/scenario.lua:615` is shipped untested.
- `Scenario.runtime_adapter().generation_context` copies the prepared input's fields **flat** into the context (`tests/golden/engine/mod/scenario.lua:656-660`), while lane 039's service reads `input.prepared_input`. One of the two shapes must go; §17.1 and §20 of `docs/feature-contracts.md` decide it, and the nested `prepared_input` is the frozen one.
- `docs/feature-contracts.md` §21 freezes the observation shape the companion already writes: `outcome_kind` plus one block of that name, `warm_up.ticks` and `window.ticks` in engine ticks, `timings.wall_clock_seconds` only when something measured it. `docs/engine-evidence/examples/` holds one synthetic example per outcome kind.

## What to build

1. `tests/test_engine_runtime_adapter.lua` drives `Scenario.runtime_adapter()` itself against the strict harness mocks — never a fake adapter.
2. The adapter hands the service a context carrying `prepared_input` nested, per §17.1 and §20.
3. Cases prove: building yields real machines carrying their recipe, modules, quality and wires, never a nonempty array alone; a source and a sink attach at each of the four perimeter edges; declared supply and drain exceed the factory's own demand, so the measurement never measures the feed; power reaches the network the poles form.
4. Every engine member the adapter calls is checked against `docs/api/2.0.77.members.json` and `docs/api/2.1.19.members.json` before it is called. Never infer a member exists from a permissive `pcall` and never from the mock alone.
5. The observation the controller emits matches `docs/engine-evidence/examples/production.json` field for field for a production run, and the rejection and export examples for those outcomes.
6. `docs/engine-evidence/runner.md` states the exact implemented capture and run command, and states plainly that a cheap adapter test is never physical throughput evidence.

## What done mean

```checks
{"name": "adapter-tests", "command": "lua5.2 tests/test_engine_runtime_adapter.lua && lua5.4 tests/test_engine_runtime_adapter.lua && lua5.2 tests/test_engine_scenario.lua && lua5.4 tests/test_engine_scenario.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "api-shapes", "command": "lua5.2 tests/test_api_shapes.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 300}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base unblock-base --manifest docs/tasks/050.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste one adapter case failing against today's flat context and passing after.
- `git diff --stat unblock-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `tests/golden/engine/mod/`
- `tests/test_engine_scenario.lua`
- `tests/test_engine_runtime_adapter.lua`
- `docs/engine-evidence/runner.md`

Touch nothing else.

# bound: 2000s

Reviewer ask: does a test ever drive the adapter the game would actually run?
