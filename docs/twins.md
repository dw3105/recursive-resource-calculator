# Twins

A **twin** is one tiny factory written once as data and judged twice: offline by our validator (or preflight),
headless by real Factorio. Both judges must agree. Glossary: `CONTEXT.md`. Why: `docs/adr/0001-engine-judges-sheets.md`.

## File

One twin per file under `tests/twins/<area>/`. `tests/twins/lib/` is code, `tests/twins/required.lua` is the
coverage list.

```lua
return {
  id = "T-BLEED-1",                 -- unique
  rule = "BP_V_BELT_BLEED",         -- the code (or "audit:<tool>:<key>") this twin is about
  class = "engine",                 -- engine | waste   (player and contract rules have no twin)
  from = "tests/test_validate_bleed.lua VB1",   -- where the case came from
  stage = "validate",               -- validate (default) | preflight | artifact
  grid = {w = 20, h = 20},
  entities = {                      -- validate stage: validator-native
    {id = "a0", kind = "belt", name = "transport-belt", x = 5, y = 0, dir = "south", flows = {"iron-plate"}},
  },
  validator = {},                   -- extra Validate.begin fields copied as-is: catalog, plan, ports, bindings, wires
  preflight = nil,                  -- preflight stage: {snapshot, solver_result, catalog, options} for Preflight.check
  artifact = nil,                   -- artifact stage: {artifact, plan, catalog} for Validate.reconcile_artifact
  feeds = {{tile = {5, 0}, item = "iron-plate"}},  -- flow heads; MUST sit on the grid edge
  sinks = {{tile = {8, 3}, items = {"copper-plate"}}},
  check = "flow_purity",            -- what the engine looks at, see below
  truth = "defect",                 -- ok | defect | waste
  codes = {"BP_V_BELT_BLEED"},      -- EXACT code set the offline judge must return ({} when clean)
  audit = {lane_sim = {bleed = 1}, blueprint_audit = {cycles = 0}},  -- pinned auditor counts, listed keys only
}
```

Rules:
- **Entities**: `x, y` top-left tile, `w, h` default 1, `dir` one of `north|east|south|west`, `kind` as the
  validator reads it (`belt`, `underground-belt`, `splitter`, `inserter`, `pipe`, `pipe-to-ground`, `machine`,
  `beacon`, `pole`, `roboport`, ...). `flows` = real item or fluid names (`fluid/water` for fluids); the engine
  needs real names. An inserter's `dir` is the internal frame (drops toward `dir`); publishing flips it to the
  blueprint's pickup direction (`logic/bp/serialize.lua:406`).
- **Feeds on the grid edge**: the validator treats an unfed belt head inside the grid as `BP_V_BELT_NO_SOURCE`
  (`logic/bp/validate.lua:1655`). Put every flow head on row/column 0 or `w-1`/`h-1`.
- **Exact codes (G2)**: a breach caught under the wrong code is a wrong rule. Build the twin so only the rule under
  test fires; list every code the judge returns.
- **Truth (G3)**: `defect` = the engine shows failure (wrong item at a sink, no power, short rate). `waste` = the
  factory still delivers but the entity does nothing (belt carries 0 items, beacon removal keeps speed). `ok` = clean.
- **Audit**: pin only counts inside the auditor's scope. `lane_sim` bleed/mixed/starved count only at inserter
  pickups that feed a machine (`tools/lane_sim.py:13`); `blueprint_audit` sideload counts only underground inlets.
  A twin with no layout (preflight, artifact) pins nothing.

## Checks (engine side, `tests/game/test_twins.lua`)

| check | engine looks at |
|---|---|
| `flow_purity` | every belt/lane carries only its declared flows; every sink gets only declared items |
| `rate` | items/s at the sinks over the window vs twin `rate` |
| `pickup_drop` | `inserter.pickup_position` / `drop_position` vs validator transfer tiles |
| `placeable` | `surface.can_place_entity` / `create_entity` result |
| `powered` | each consumer's electric network and status |
| `network` | electric network ids of poles; logistic network of roboports |
| `beacon_effect` | machine `effects` / beacons affecting it |
| `underground_pair` | `neighbours` of each underground / pipe-to-ground |
| `fluid_system` | fluid system ids and contents per pipe |
| `prototype` | live prototype facts named by the twin (preflight twins) |
| `artifact` | blueprint imported in the engine, read back, compared to the plan |

## Running

- Offline verdicts: `lua5.2 tests/test_twins.lua`
- Coverage: `lua5.2 tests/test_twins_coverage.lua` (one lane: `TWIN_OWNER=L279 ...`)
- Auditors: `python3 -m unittest tests.tools.test_twins_audit`
- One twin's blueprint: `lua5.2 tools/twin_bp.lua <twin.lua>`; its pinned counts: `lua5.2 tools/twin_bp.lua --audit <twin.lua>`
- Headless (integrator only): `tests/game/test_twins.lua` through `tools/game_test.sh`.
