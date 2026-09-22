# 144 flag: one switch in one place, so the three-halves flip cannot go half-way

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-144`, branch
`lane/144`, base tag `round-16-wave2` (resolve with `git rev-parse round-16-wave2`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 28, rules **28.1**, **28.2**, **28.3**, **28.4**.
Ledger: `docs/round-16-baseline.md`. Frozen red list: `docs/round-16-red-list.txt`.
Frozen census baseline: `docs/round-16-census-baseline.json`.

One feature, `multi_flow_hands`, is built in three halves in three modules. Each module carries its **own
literal copy** of the switch, re-derived against this tree 2026-09-22:

```
logic/bp/groups.lua:511     local multi_flow_hands = false
logic/bp/route.lua:617      local multi_flow_hands = false
logic/bp/validate.lua:468   local multi_flow_hands = false
```

Each of the three sites carries the same five-line comment saying integration "flips all three together,
because that is the only point where the halves meet". Nothing in the tree makes that true. Three literals
can disagree, and the tree would still load, still pass every test at the default, and deliver a factory
whose layout pairs hands while its validator refuses to witness them. The round-16 handoff names this step
as "the one point where three halves meet and the round can break".

This lane removes the possibility. It does **not** flip the switch. The switch stays `false` at the tip of
this branch.

Two test-only seams already exist and both must keep working unchanged:

- `logic/bp/groups.lua:502-509` `forced_multi_flow_hands(input)` returns `true` when
  `input._force_multi_flow_hands` is set, and `logic/bp/groups.lua:1822-1824` in `make_candidates` swaps the
  module local for the duration of one call and restores `previous_multi_flow_hands`. `tools/lane_mutate.sh`
  turns the `true` at `:506` off, and `tests/test_hand_economy.lua:50` depends on that seam.
- `logic/bp/validate.lua:473-475` `multi_flow_hands_enabled(work)` returns
  `multi_flow_hands or work.input._force_multi_flow_hands == true`, read at `:1445` and `:1512`.
  `tests/test_physical_witness.lua:114-116` depends on it.

**`logic/bp/route.lua` is owned by another lane running right now and this lane must NEVER edit it.** Route's
own copy is wired to the shared module by integration, by hand, at merge. Your test must therefore state
route's requirement without editing route: see S3.

PRESERVE: `logic/bp/route.lua`, `logic/bp/search.lua`, `logic/bp/grid.lua`, `logic/bp/geometry.lua`,
`logic/bp/plan.lua`, `logic/bp/power.lua`, `logic/bp/serialize.lua`, `logic/catalog.lua`,
`tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`, `tests/test_census_codes_live.lua`,
`tests/golden/cases/player-red-science-1s/`, `docs/round-16-census-baseline.json`,
`docs/round-16-red-list.txt`, `docs/feature-contracts.md`, `tools/**`, `info.json`, `mod-description.md`,
`.agent-lane.toml`.

Files this lane owns: `logic/bp/flags.lua` (new), `logic/bp/groups.lua`, `logic/bp/validate.lua`,
`tests/test_feature_flags.lua` (new).

## What to build

**S1. `logic/bp/flags.lua`, the one place.** A tiny module that returns a table carrying the production
default `multi_flow_hands = false` and nothing else it does not need. It requires no other module in
`logic/bp/`, so it can never introduce a cycle. Document in it, in one sentence, that flipping the value here
flips every half at once, and that is the point.

**S2. `groups.lua` and `validate.lua` read it.** Replace the literal at `logic/bp/groups.lua:511` and at
`logic/bp/validate.lua:468` with a read of `logic/bp/flags.lua`'s value. Both keep their module local so the
existing seams keep working: `groups.lua:1822-1824` still swaps and restores, and
`validate.lua:473-475` still ORs the per-run input. Behaviour at default configuration is **byte-identical**;
this is a refactor and it must measure as one.

**S3. `tests/test_feature_flags.lua`, the guard that goes red.** Two assertions, both by reading the source
files as text, so the guard covers a module the test does not load:

1. **No module carries its own default.** For each of `logic/bp/groups.lua`, `logic/bp/route.lua`,
   `logic/bp/validate.lua`, assert the file contains **no** line matching `^local multi_flow_hands = false$`
   and **no** line matching `^local multi_flow_hands = true$`. Each of the three must instead contain a read
   of `flags`. `route.lua` is expected to FAIL this until integration wires it; write the assertion so its
   failure message says exactly that, names `logic/bp/route.lua`, and says integration wires it at merge.
   Record in `docs/tasks/144_flag.md`'s own result, not in the test, that route is the known red one.
2. **The default is off.** `require "logic.bp.flags"` returns `multi_flow_hands == false`. A lane that leaks
   the feature into the default breaks every other lane's base.

Additionally assert, by loading the modules, that with the flag at its default the grouping seam still plans
the measured **26** hands over **11** machines on the player's sheet shape, exactly as
`tests/test_hand_economy.lua`'s HE1 case does today. A refactor that changes a number is not a refactor.

Ship the test with `route.lua`'s row **skipped by name** rather than failing, using an explicit,
commented allowance naming the integration step, so this lane's own suite is green while the requirement is
still written down. Never delete the row.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; lua5.2 tests/test_feature_flags.lua >/dev/null 2>&1 || rc=1; sed -i 's/^local multi_flow_hands = .*$/local multi_flow_hands = false/' $S/logic/bp/validate.lua || rc=1; (cd $S && lua5.2 tests/test_feature_flags.lua 2>&1 | grep -q FAIL) || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "flags-cases", "command": "sh tools/lane_rows.sh tests/test_feature_flags.lua --min-cases 4", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "flags-green", "command": "for l in lua5.2 lua5.4; do $l tests/test_feature_flags.lua 2>&1 | tail -1 | grep -q '0 failed' || exit 1; done; echo flags-green", "expect_exit": 0, "expect_regex": "flags-green", "timeout_s": 900}
{"name": "switch-off-by-default", "command": "lua5.2 -e 'package.path=\"./?.lua;\"..package.path; local f=require \"logic.bp.flags\"; if f.multi_flow_hands ~= false then os.exit(1) end; print(\"switch-off\")'", "expect_exit": 0, "expect_regex": "switch-off", "timeout_s": 120}
{"name": "route-untouched", "command": "git diff --quiet round-16-wave2 HEAD -- logic/bp/route.lua && echo route-untouched || { echo 'another lane owns logic/bp/route.lua right now'; exit 1; }", "expect_exit": 0, "expect_regex": "route-untouched", "timeout_s": 120}
{"name": "economy-and-witness", "command": "for l in lua5.2 lua5.4; do $l tests/test_hand_economy.lua 2>&1 | tail -1 | grep -q '0 failed' || exit 1; $l tests/test_physical_witness.lua 2>&1 | tail -1 | grep -q '0 failed' || exit 1; $l tests/test_groups.lua 2>&1 | tail -1 | grep -q '0 failed' || exit 1; $l tests/test_validate.lua 2>&1 | tail -1 | grep -q '0 failed' || exit 1; done; echo seams-ok", "expect_exit": 0, "expect_regex": "seams-ok", "timeout_s": 1800}
{"name": "oracle-whole", "command": "for l in lua5.2 lua5.4; do $l tests/test_blueprint_physical_contract.lua 2>&1 | tail -1 | grep -q '88 passed, 0 failed' || exit 1; done; echo oracle-whole", "expect_exit": 0, "expect_regex": "oracle-whole", "timeout_s": 900}
{"name": "codes-live", "command": "for l in lua5.2 lua5.4; do $l tests/test_census_codes_live.lua 2>&1 | tail -1 | grep -q '7 passed, 0 failed' || exit 1; done; echo codes-live-ok", "expect_exit": 0, "expect_regex": "codes-live-ok", "timeout_s": 900}
{"name": "frozen", "command": "git diff --quiet round-16-wave2 HEAD -- tests/golden/cases/player-red-science-1s tools docs/round-16-census-baseline.json docs/round-16-red-list.txt docs/feature-contracts.md && echo frozen || { echo 'this lane changed the pinned sheet, the tooling, the red list or the contract'; exit 1; }", "expect_exit": 0, "expect_regex": "frozen", "timeout_s": 120}
{"name": "no-new-red", "command": "sh tools/red_list.sh docs/round-16-red-list.txt", "expect_exit": 0, "expect_regex": "RED-LIST ok", "timeout_s": 3600}
{"name": "census-still", "command": "python3 tools/census_gate.py --baseline docs/round-16-census-baseline.json --tier fast --no-waivers", "expect_exit": 0, "expect_regex": "CENSUS-GATE ok", "timeout_s": 1800}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-16-wave2 --manifest docs/tasks/144.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
