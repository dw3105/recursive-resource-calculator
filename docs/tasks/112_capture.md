# 112 capture: export carries every selection, and empty geometry refuses

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-112`, branch `lane/112`, base tag `round-13-base` (resolve with `git rev-parse round-13-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 25, rule 25.7. Baseline: `docs/round-13-baseline.md`.

`logic/catalog.lua:60` copies only `position.x` and `position.y`. An array-shaped vector becomes an empty
table with no diagnostic, in both API-shaped mocks. A keyed vector survives.

`tests/golden/cases/player-am2-chain/prepared_input.json` already carries **empty inserter offsets**. Their
origin is not established. They may come from that array path, from the export boundary, or from the engine.
Naming the origin is part of this lane; inferring it from a screenshot is not.

`tests/test_export_completeness.lua` has no `grid_spacing` coverage. `tests/test_export_payload.lua` `E25`
and `E26` cover an injected record only, never a real attempt.

An empty table is NEVER valid geometry. Missing required data is an explicit incomplete-capture result, never
a default filled in at replay.

PRESERVE: every `logic/bp/**` file, `tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`,
`docs/feature-contracts.md`, `tools/**`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/catalog.lua`, `logic/export_payload.lua`, `tests/test_catalog.lua`,
`tests/test_catalog_recipe_facts.lua`, `tests/test_export_payload.lua`, `tests/test_export_completeness.lua`.

This lane is **Milestone A**. Nothing asks the user for a fresh export until its gate is green, so it is the
first lane to merge.

## What to build

**Every required vector component is checked.** A vector that arrives keyed, and a vector that arrives as an
array, both normalize where the boundary supports that shape. A shape the boundary does not support is
REJECTED with a diagnostic naming the entity and the field. An empty table is never published as geometry.

**Trap.** Do not fix only the fixture. Trace the stored capture's empty inserter offsets through
normalization, JSON export and replay, and record which boundary drops them. A repair that makes this one
file look complete, while the boundary still publishes empty vectors, is not the repair.

**The export round trip proves exact selections**, compared by stable row identity and never by recipe name
alone: alternate machine, non-default recipe, machine quality, nonuniform module counts and qualities,
different beacon count and sharing, a selected row beside an unselected row, two rows using one recipe with
different configuration, explicit empty modules and beacons, a change made immediately before export, and
save then reload. Absence, an explicit zero and an empty selection are three different results.

**Revisions travel too**: sheet, config and solver revisions, surface, force research, mod versions and the
export schema.

## Case names this lane must use

Integration gates named cases, never a count.

In `tests/test_catalog.lua`:

- `CG1` an empty vector is REFUSED, never published as geometry;
- `CG2` an unsupported representation is REFUSED with a diagnostic naming the entity and the field;
- `CG3` a keyed vector and an array vector both normalize where the boundary supports them;
- `CG4` a complete capture still round-trips unchanged.

In `tests/test_export_completeness.lua`:

- `CX1` every selected machine, recipe, module and beacon survives export and decoding, compared by stable
  row identity;
- `CX2` absence, an explicit zero and an empty selection are three different results;
- `CX3` sheet, config and solver revisions, surface, force research, mod versions and export schema travel.

Use the refusal code `BP_CAP_INCOMPLETE` from contract 25.7; the red proof mutates exactly that string.

Record the origin of the stored capture's empty inserter offsets in `docs/tasks/112_findings.md`. That file is
a required new deliverable.

## What done mean

```checks
{"name": "red-proof", "command": "sh tools/lane_rows.sh tests/test_catalog.lua --min-cases 4 --pass CG1,CG2 || exit 1; S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; sh tools/lane_mutate.sh $S capture-code >/dev/null 2>&1 || rc=1; (cd $S && sh tools/lane_rows.sh tests/test_catalog.lua --min-cases 4 --fail CG1) >/dev/null 2>&1 || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "rows", "command": "sh tools/lane_rows.sh tests/test_catalog.lua --min-cases 4 --pass CG1,CG2,CG3,CG4", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "export-rows", "command": "sh tools/lane_rows.sh tests/test_export_completeness.lua --min-cases 4 --pass CX1,CX2,CX3", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "offsets-origin-named", "command": "test -f docs/tasks/112_findings.md || { echo 'no findings file exists'; exit 1; }; grep -qiE 'pickup_offset|drop_offset|inserter offset' docs/tasks/112_findings.md || { echo 'the empty inserter offsets have no recorded origin'; exit 1; }; echo origin-named", "expect_exit": 0, "expect_regex": "origin-named", "timeout_s": 120}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 112_capture", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-13-base --manifest docs/tasks/112.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 3600s
