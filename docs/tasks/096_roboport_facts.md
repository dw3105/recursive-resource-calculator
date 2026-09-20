# 096 roboport facts, and the spacing record the export must carry

## What is true

Base tag `round-11-base`. Contract: `docs/feature-contracts.md` section 24, rules 24.4 and 24.7.

The invalid read is already gone. `logic/catalog.lua` `build_robo` no longer touches
`entity.connection_distance`, `tests/harness.lua` no longer fabricates it, and
`tests/test_catalog.lua` case `C3b` fails if either returns. **This lane never re-proves that.**

Two things remain.

**One. `build_robo` is the only infrastructure builder with no missing-fact record.** It writes
`name, quality, tile_w, tile_h, logistic_radius, construction_radius` and says nothing when a field is nil, so
an absence is indistinguishable from "never asked". The repo already has the pattern:
`logic/catalog.lua` `project_recipe` builds `facts.missing` and `facts.known_empty` with local `required`,
`required_table` and `optional` helpers, and returns the missing list. `logic/bp/preflight.lua:442-447` maps a
missing-fact status to `BP_REJ_PROTOTYPE_FACTS_MISSING`, already registered in `logic/bp/reason_codes.lua:15`.
There is no `BP_PF_` prefix anywhere in this repo.

**Two. The export must carry the spacing record lane 097 produces, and must never invent one.** The real
lookup chain, verified on this tree:

```
logic/export_payload.lua:878  service_attempt picks generation.lookup (then its aliases)
logic/bp/generation.lua:1309  Generation.lookup calls public_attempt
logic/bp/generation.lua:1263  public_attempt BUILDS ITS OWN RECORD; it never calls public_status
logic/export_payload.lua      the attempt is copied into the export
```

`public_status` (`logic/bp/generation.lua:1247`) is NOT on that path. The record's shape is fixed by the
contract:

```
grid_spacing = {resolved, kind = "override" | "derived",
                source = "caller" | "logistic_radius", source_value, generation_job_id}
```

**Trap.** `connection_distance` is `subclasses: ["RollingStock"]`. It is NOT a missing roboport fact and must
never appear in `robo.facts.missing`. A plain-data `connection_distance` in a hand-written fixture or caller
option is a compatibility input, labelled an override, never an engine fact.

**Trap.** Writing a `grid_spacing` into the export from anything other than the attempt makes the export a
fiction. If the attempt carries none, the export names the absence.

PRESERVE: `logic/bp/search.lua`, `logic/bp/generation.lua`, `logic/bp/groups.lua`, `logic/bp/validate.lua`,
`logic/bp/geometry.lua`, `tests/harness.lua`, `tests/golden/**`, `info.json`, `mod-description.md`.

Files this lane owns: `logic/catalog.lua`, `logic/export_payload.lua`, `tests/test_catalog.lua`,
`tests/test_export_payload.lua`, `tests/test_export_completeness.lua`.

Lane 097 produces the record. On this lane's base no producer exists, so this lane tests transport with an
attempt record it supplies to the reader it owns. The end-to-end "remove the producer and the export check
fails" check belongs to integration, on the merged tree.

## What to build

1. `build_robo` records `facts.missing` and `facts.known_empty` over its real engine fields only, reusing the
   `project_recipe` helpers rather than new ones.
2. `logic/export_payload.lua` carries `grid_spacing` from the attempt through `service_attempt` to the encoded
   export, unchanged, and names its absence when the attempt has none.

## What done mean

Every Lua check runs on both interpreters.

```
red-proof   git checkout round-11-base -- logic/catalog.lua; lua5.2 tests/test_catalog.lua
            emits FAIL <your named case> ... [assert], zero [error], and a summary line matching
            ^test_catalog \[Lua 5\.[24]\]: [1-9][0-9]* cases,
            C3b stays green throughout
facts       a default-infrastructure world yields logistic_radius 25, construction_radius 55, and an empty
            facts.missing; a roboport whose logistic_radius is genuinely absent names it in facts.missing
applicable  connection_distance never appears in robo.facts.missing, on either shape
transport   given an attempt carrying grid_spacing {resolved 50, kind derived, source logistic_radius,
            generation_job_id}, the export encoded through the real path and decoded through
            tests/harness.lua H.decode_export carries all four fields unchanged
absence     given an attempt with no grid_spacing, the export names the absence and invents nothing;
            asserting a default value here is the failure this check exists to catch
focused     sh tools/verify_round9_lane.sh "$PWD" 096_roboport_facts
```
