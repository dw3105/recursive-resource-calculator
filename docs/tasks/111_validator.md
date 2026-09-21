# 111 validator: reject a factory that cannot produce

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-111`, branch `lane/111`, base tag `round-13-base` (resolve with `git rev-parse round-13-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 25, rules 25.1, 25.2, 25.3, 25.4, 25.5.
Frozen oracle: `tests/test_blueprint_physical_contract.lua`. Baseline: `docs/round-13-baseline.md`.

Measured on the real round-12 candidate against its real seven-step plan, host legalcopilot-dev 2026-09-21:

```
unmodified                                316 entities  ok=true
every belt and underground belt removed    76 entities  ok=true
every pipe and pipe-to-ground removed     286 entities  ok=true
every inserter removed                    296 entities  ok=true
every machine quality set to legendary    316 entities  ok=true
```

A 76-entity arrangement with no transport at all passes. `logic/bp/validate.lua` contains **no occurrence of
the word `recipe`**. `validate.lua:706` reasons over declared segment allocations, and `validate.lua:1033`
takes an undeclared inserter load as zero, so removing the entities leaves every declaration intact and the
factory still validates.

`validate.lua:1019` `check_machines` compares counts and some module properties. It never compares machine
prototype or machine quality with the requested step.

`validate.lua:646` rejects only `got + tolerance(got) < required`, so extra beacon influence passes. That is
the behaviour the user asked to KEEP. `validate.lua:635-638` already rejects a speed beacon over a quality
machine, from real geometry via `box_in_area`. `validate.lua:658` writes
`work.metrics.beacon_effects_by_step_id[step_id]`, so two machines of one step overwrite each other.

`validate.lua:1062` sums `finite(segment.length, 0)`, and `logic/bp/route.lua` never sets `segment.length`, so
`route_length` read 0 while 270 transport entities stood on the grid. `validate.lua:1056-1064` scores the
bounding box of ALL entities, so the four mandatory roboport corners fix the area at 2916 whatever the
production arrangement is.

`validate.lua:1108` ranks `beacon_count, footprint_area, pole_count, route_length, entity_count` and defaults a
missing value to zero.

PRESERVE: `logic/bp/groups.lua`, `logic/bp/serialize.lua`, `logic/bp/route.lua`, `logic/bp/pack.lua`,
`logic/bp/search.lua`, `logic/bp/geometry.lua`, `logic/bp/power.lua`, `logic/bp/grid.lua`,
`tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`, `docs/feature-contracts.md`, `tools/**`,
`info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `logic/bp/validate.lua`, `logic/bp/plan.lua` (**additive interface only**),
`tests/test_validate.lua`, `tests/test_validated_candidate.lua`, `tests/test_blueprint_delivery.lua`.

## What to build

**Every negative starts from an independently valid positive control that PASSES first.** A base that rejects
everything proves nothing. `tests/test_blueprint_physical_contract.lua` `PC1` is such a control and it passes
today; use it or build another, never a candidate the generator produced.

**Machine identity.** Recipe missing, recipe replaced, a recipe written onto a `furnace`, machine prototype
changed, machine quality changed, a module removed or misplaced: each REJECTS with a named code and the
offending entity. Key the recipe rule on catalog `etype`, never on entity name.

**Physical graph.** Reconstruct connectivity from placed entities and catalog facts. Removing all belts, all
pipes, all inserters, one output inserter, reversing a middle belt, or changing an underground partner: each
REJECTS, although flow allocations and bindings stay intact. A disconnected stub at a pickup cell is never a
source structure. Prove each required path continuous from a declared external supply port to a declared
external drain. A branch loaded past what its physical path supports REJECTS.

**Beacons.** Influence above the configured count does NOT reject. A speed beacon reaching a quality machine
rejects, including from a neighbouring block. Key influence and effects per machine **instance**. Per-instance
effects must be CONSUMED by available capacity, power reporting and transport sizing; a recorded effect that
nothing consumes fails this lane's own check.

**Metrics.** Emit `production_area`, `cell_envelope_area`, `transport_cost`, `transport_entities`,
`beacon_count`, `pole_count`, `coord_key` with the units in rule 25.4. A metric that cannot be measured
REJECTS and is never zero. Implement the comparator of rule 25.5 and REMOVE `footprint_area` and
`route_length` in the same change, so no consumer can read a stale key.

**Trap.** `logic/bp/search.lua:1256` and `logic/bp/validate.lua:1108` both touch score keys, and `search.lua`
belongs to lane 113. Change only the keys inside `validate.lua`, publish them, and report the consumer change
to integration.

**Artifact reconciliation.** Expose `Validate.reconcile_artifact{artifact, plan, catalog}`. It decodes the
exported artifact and compares prototype, quality, recipe and recipe quality where supported, module multiset
and placement, beacon prototype, quality and loadout, directions and wires, by a bound identity map. A
mutation applied ONLY at serialization is detected even when the internal candidate stays valid.

**Keep the requested plan immutable.** Never lower a configured count, never raise one to match placement.

## Case names this lane must use

Integration gates the frozen oracle by case id. Every one of these must pass, and `PC1`, `FL1`, `ID6`, `BE1`
and `BE2` must STAY passing:

```
PC1 FL1 ID1 ID2 ID3 ID4 ID5 ID6 TR1 TR2 TR3 TR4 TR5 TR6 TR7 TR8 TR9 TR10
BE1 BE2 BE3 MT1 MT2 MT3 FL2 FL3 FL4 FL5 FL6 SR4
```

`SR4` is yours: `Validate.reconcile_artifact` must exist and must reject a serializer-only mutation while
accepting an unmodified artifact. Lane 113 calls it on the production path; a helper test alone never proves
that path.

`FL2` `FL3` `FL4` `FL6` are the fluid rows: an item inserter on a fluid connection, a pipe removed from the
middle, every pipe removed, and a pipe run that reaches no fluid box. `FL1` and `FL5` already pass and must
stay passing.

## What done mean

```checks
{"name": "red-proof", "command": "sh tools/lane_rows.sh tests/test_blueprint_physical_contract.lua --min-cases 68 --pass ID1 || exit 1; S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; sh tools/lane_mutate.sh $S identity-code >/dev/null 2>&1 || rc=1; (cd $S && sh tools/lane_rows.sh tests/test_blueprint_physical_contract.lua --min-cases 68 --fail ID1) >/dev/null 2>&1 || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "rows", "command": "sh tools/lane_rows.sh tests/test_blueprint_physical_contract.lua --min-cases 68 --pass PC1,FL1,ID1,ID2,ID3,ID4,ID5,ID6,TR1,TR2,TR3,TR4,TR5,TR6,TR7,TR8,TR9,TR10,BE1,BE2,BE3,MT1,MT2,MT3,FL2,FL3,FL4,FL5,FL6,SR4", "expect_exit": 0, "expect_regex": "lane-rows-ok", "timeout_s": 1800}
{"name": "reconcile-entry", "command": "grep -q reconcile_artifact logic/bp/validate.lua || { echo 'Validate.reconcile_artifact is absent'; exit 1; }; echo reconcile-entry", "expect_exit": 0, "expect_regex": "reconcile-entry", "timeout_s": 120}
{"name": "no-stale-score-key", "command": "grep -qE 'footprint_area|route_length' logic/bp/validate.lua && { echo 'a stale score key survives'; exit 1; }; grep -q production_area logic/bp/validate.lua || { echo 'production_area is absent'; exit 1; }; echo score-keys-published", "expect_exit": 0, "expect_regex": "score-keys-published", "timeout_s": 120}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 111_validator", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-13-base --manifest docs/tasks/111.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 3600s
