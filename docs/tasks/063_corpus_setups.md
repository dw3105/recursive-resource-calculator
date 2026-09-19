# 063 — Five corpus cases contain the production chain they claim

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-063`, branch `lane/063`, base tag `routing-recovery-base` (resolve with `git rev-parse routing-recovery-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own new files under `tests/golden/setup/`, the five case directories listed below, new `tests/test_corpus_setups.lua` and new `docs/golden-case-authoring.md`. Everything under `tests/golden/` that is not listed is frozen, including `tests/golden/engine/`, which another lane owns.
- Your five case directories are `tests/golden/cases/base-only-crafting-smelting/`, `tests/golden/cases/shared-intermediate-multi-target/`, `tests/golden/cases/fluid-byproduct-chain/`, `tests/golden/cases/assembler-chain-example/` and `tests/golden/cases/repeatability/`. No other case directory.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- `tests/test_companion_api_shapes.lua` is red on this base, by design. Ignore it. Never run the whole suite as your gate.

`tests/golden/capture_case.lua` and `tests/golden/setup/init.lua` already exist and work. The only setup present,
`tests/golden/setup/tiny-chain.lua`, deliberately uses a zero search budget: it is a failure-capture demo, never a
production-chain success case.

A measured trap from the routing fixture, host `legalcopilot-dev`, 2026-09-19: `docs/tasks/058_reproducer.lua`
defines a foundry and `molten-iron`, yet the routing input it produces carries **no fluid flow at all** — five
flows, three steps, `cable`, `circuit`, `machine`, with plate and gear arriving from outside. A case named for a
fluid chain can silently become a plate-import case. Your tests exist to stop exactly that.

## What to build

For each of the five cases: an executable setup giving targets, recipe and machine selection, modules, beacons,
infrastructure, and the mod, branch and research the case needs; plus the supply and drain the engine scenario
would use.

Before any layout call, the setup asserts the **calculated step names and the flow list**, fluids and byproducts
included. A case whose graph does not match its name fails there, with the names it found.

Produce captures with truthful provenance: `source_kind = "harness"` for anything captured here. A harness capture
unblocks replay today; physical observations come from packaged Factorio runs later, and are not yours to write.
Keep the expected supported outcome separate from whatever the current pipeline does: a positive case whose layout
fails today stays a positive case with a recorded failure, never a rejection case.

## What done mean

```checks
{"name": "setups", "command": "lua5.2 tests/test_corpus_setups.lua && lua5.4 tests/test_corpus_setups.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "existing-capture-test", "command": "lua5.2 tests/test_case_capture.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base routing-recovery-base --manifest docs/tasks/063.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_corpus_setups.lua` must assert, per case: the setup loads, the calculated step names match the case's
declared chain, the flow list contains the declared fluids and byproducts, and the capture it writes carries its
source kind and source SHA.

## Files this lane owns

`tests/golden/setup/`, `tests/golden/cases/base-only-crafting-smelting/`, `tests/golden/cases/shared-intermediate-multi-target/`, `tests/golden/cases/fluid-byproduct-chain/`, `tests/golden/cases/assembler-chain-example/`, `tests/golden/cases/repeatability/`, `tests/test_corpus_setups.lua`, `docs/golden-case-authoring.md`.

# bound: 1918s
