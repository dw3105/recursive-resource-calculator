# 091 — The debug export carries every fact a replay needs, or names it missing

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-091`, branch `lane/091`, base tag `round-10-base` (resolve with `git rev-parse round-10-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/export_payload.lua`, `tests/test_export_payload.lua`, new `tests/test_export_completeness.lua`, and the new directory `tests/export_golden/`.
- `logic/bp/generation.lua` and `gui/blueprint_dialog.lua` are frozen. Lane 092 owns them.
- `logic/bp/search.lua`, `logic/bp/route.lua`, `tests/golden/lib/runner.py`, `tools/release_gate.py`, `prepare_release.sh`, `tests/golden/add_case`, `tests/golden/capture_case.lua` and `tools/handoff.sh` are frozen.
- `docs/feature-contracts.md` §23 is a frozen contract. Read §23.1, §23.2 and §23.4 first.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- Never edit a file this lane does not own. If you need a change elsewhere, stop and report it.
- Never weaken an assertion, delete a case, or accept a new baseline. A changed expectation stops the lane.
- Never edit `info.json` or `mod-description.md`; both carry the player's own uncommitted work.
- Never add a "skip if the dependency is missing" branch to any test.
- Never inject a generation id into player storage, and never stub `Generation.capture`. A test that injects what the game never writes proves nothing. `tests/golden/capture_case.lua:90-92` does exactly that today, which is why this defect survived.

**Write `tests/test_export_completeness.lua` and the comparator first, before changing the module.**

A player reported `BP_FAIL_SEARCH_BUDGET [search]` and sent a debug export. The export explained nothing.
Frozen at `docs/incidents/2026-09-20-search-budget/`, decoded payload sha256
`57cad769cd3b826596c6e1d45142b7909f7dcd53425d3a81bfd2774581af7b38`, 1 858 798 bytes, mod `1.1.51`, base `2.0.77`.

Measured on that payload, host `legalcopilot-dev`, 2026-09-20:

```text
prototypes.recipe            {}          empty, on a sheet with 7 active recipes
prototypes.recipe_coverage   {"state": "complete", "active": {}, "missing": {}}
calculated machine counts    absent
aggregate energy, pollution  absent
generation section           absent entirely
```

Named causes in this lane's file:

- `logic/export_payload.lua:262-270` — `reference_options` returns `{entities, items, fluids, modules, qualities}` and never forwards `references.recipes`, which `collect_recipe_names` (`:475-482`) already fills and `force.research` (`:450-453`) already uses. `Catalog.build` projects recipes only when the options carry them (`logic/catalog.lua:349`), so `prototypes.recipe` is always the empty template. The runtime generation path does forward them (`logic/bp/generation.lua:318-339`); the exporter does not.
- `logic/export_payload.lua:510`, `:623` — `diagnostics.last_blueprint_attempt` is read and written into the payload, and no production code anywhere writes `player_data.last_blueprint_attempt`. The field is always absent.

Forwarding one field is necessary and **not** sufficient. `docs/feature-contracts.md` §23.1 lists what a replay needs.

## What to build

1. `reference_options` forwards `references.recipes`.
2. The payload carries every §23.1 fact: selections with qualities and bindings, module names/qualities/counts, beacon prototypes/qualities/counts/sharing/modules with explicitly empty selections preserved, recipe prototype facts, targets and units and `round_up`, solved and external rates, calculated machine counts, effects, energy and pollution at full precision, and current against calculated settings with sheet and revision identities.
3. A fact the runtime could not supply is an **explicit diagnostic**, named. Never a default, never a silent gap, never another sheet's value.
4. The attempt section follows §23.2: whatever diagnostics the current search already produces, and everything else marked absent by name. Do **not** invent a diagnostic schema; `logic/bp/search.lua:80-89` already erased the stage history and this lane never touches search.
5. On this base the durable lookup does not exist yet (lane 092). Where an attempt is genuinely unavailable, your tests assert the **explicit absent marker**. They never fabricate a section and never inject an id to manufacture one.
6. Resolve `diagnostics.last_blueprint_attempt`: write it from real data or delete it. A field nothing writes is not a diagnostic.
7. Audit dependency collection for: a current selection with no result; a stale result; column-local setups; nested quality-loop stages; two distinct sheets.

### The export comparator, `tests/export_golden/`

The release corpus runner cannot do this job, for two independently verified reasons (§23.4): `runner.py:1105-1114` skips draft and captured comparison before the accept branch at `:1115`, and `canonical()` (`:418-440`) keeps blueprint entities only, so a full selection map and `{}` both reduce to `{"entities": []}`.

Build a small semantic comparator over the existing decoder, `tests/golden/lib/common.py:37-61`, with **hand-authored** expected values. Never generate an expectation from the repaired output. Ordering and timestamps may be normalized; no semantic field ever may.

`tests/run.sh:6` globs only `tests/test_*.lua` and `:12` discovers Python only under `tests/tools`, so nothing under `tests/export_golden/` is reached by the routine suite. Therefore `tests/test_export_completeness.lua` **invokes the comparator and propagates its failure**. A missing comparator file, a missing fixture, or zero executed comparisons is a failure, never a green run.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-10-base -- logic/export_payload.lua || exit 1; if out=$(cd \"$S\" && lua5.2 tests/test_export_completeness.lua 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL EC1 .*\\[assert\\]' || { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -q '\\[error\\]' && { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE '^test_export_completeness \\[Lua 5\\.[24]\\]: [1-9][0-9]* cases, ' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_export_completeness.lua && lua5.4 tests/test_export_completeness.lua && lua5.2 tests/test_export_payload.lua && lua5.4 tests/test_export_payload.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "comparator-is-reached-by-the-entry-point", "command": "grep -q 'export_golden' tests/test_export_completeness.lua || { echo 'the entry point never reaches the comparator'; exit 1; }; echo entry-point-ok", "expect_exit": 0, "expect_regex": "entry-point-ok", "timeout_s": 60}
{"name": "no-injected-attempt-id", "command": "if grep -nE 'generation_id|last_blueprint_attempt|blueprint_attempt' tests/test_export_completeness.lua | grep -v 'absent\\|missing\\|nil'; then echo 'a test injects an attempt id'; exit 1; fi; echo no-injection", "expect_exit": 0, "expect_regex": "no-injection", "timeout_s": 60}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 091_export_payload", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-10-base --manifest docs/tasks/091.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Your own tests must include, by these exact case names:

- `EC1` every selected recipe's prototype facts reach the payload: ingredients, products, crafting time.
- `EC2` deleting the recipe forwarding makes `EC1` fail. The recipe map is never silently empty.
- `EC3` selections survive: machine and recipe identity, quality, and the product-to-recipe binding, per row.
- `EC4` module names, qualities and counts survive, including two rows with different setups.
- `EC5` beacon prototype, quality, count, sharing and installed modules survive.
- `EC6` an explicitly empty module or beacon selection stays explicitly empty, never dropped and never absent.
- `EC7` calculated machine counts, effects, energy and pollution reach the payload at full precision.
- `EC8` current against calculated settings carry their sheet and revision identities, and a stale result is named stale rather than blended into current.
- `EC9` a fact the runtime could not supply is an explicit named diagnostic.
- `EC10` no-result, current, stale and failed states each export honestly.
- `EC11` two distinct sheets never borrow each other's selections or results.
- `EC12` with no attempt available, the payload carries the explicit absent marker, never a fabricated section.
- `NEG1`..`NEGn` one case per required semantic field: removing or altering that field alone fails the comparison. A passing round trip, or a canonical match, is never sufficient.

## Files this lane owns

`logic/export_payload.lua`, `tests/test_export_payload.lua`, `tests/test_export_completeness.lua`, `tests/export_golden/`

# bound: 2700s
