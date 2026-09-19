# Round 8 feature contracts

What every lane codes against. The plan says why; this file says exactly what. A lane never negotiates a shape
here: if one is wrong, the lane stops and reports, and the integrator amends this file between waves.

Baseline: `main` 3670e8e. Branch `feat/round-8-blueprints`. Nothing reaches `main` without the user's word.

## 1. File ownership

One file has one owner for the whole round. A lane's diff is checked against its manifest with
`python3 tools/lane_ownership.py --base <lane base> --manifest docs/tasks/<n>.manifest`.

| Owner | Files |
| --- | --- |
| integrator (frozen) | `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/api/*`, `docs/feature-contracts.md`, `tools/*`, `tests/run.sh`, `tests/__init__.py`, `tests/tools/*`, `tests/test_api_shapes.lua`, `tests/test_harness_api.lua`, `tests/test_locale_keys.lua`, `tests/test_round8_spine.lua`, `info.json`, `changelog.txt`, `generate_release.sh`, `prepare_release.sh`, every existing `tests/test_*.lua` |
| W1-snapshot | `logic/snapshot.lua`, `tests/test_snapshot.lua` |
| W1-jobs | `logic/jobs.lua`, `tests/test_jobs.lua` |
| W1-catalog | `logic/catalog.lua`, `tests/test_catalog.lua` |
| W1-grid | `logic/bp/grid.lua`, `tests/test_grid.lua` |
| W1-exportui | `gui/export_dialog.lua`, `tests/test_export_dialog.lua` |
| W1-progress | `gui/progress_panel.lua`, `tests/test_progress_panel.lua` |
| W2-payload | `logic/export_payload.lua`, `tests/test_export_payload.lua` |
| W2-solver | `logic/solver_steps.lua`, `logic/solver.lua`, `tests/test_solver_steps.lua` |
| W2-reset | `logic/reset.lua`, `logic/player_data.lua`, `tests/test_reset.lua` |
| W2-report | `logic/report_steps.lua`, `gui/report.lua`, `logic/compute_power_and_pollution.lua`, `tests/test_report_steps.lua` |
| W2-plan | `logic/bp/plan.lua`, `tests/test_bp_plan.lua` |
| W2-preflight | `logic/bp/preflight.lua`, `logic/bp/reason_codes.lua`, `tests/test_bp_preflight.lua` |
| W3-calc | `logic/calc_pipeline.lua`, `tests/test_calc_pipeline.lua` |
| W3-infra | `logic/bp/settings.lua`, `gui/blueprint_dialog.lua`, `tests/test_bp_settings.lua` |
| W3-pack | `logic/bp/pack.lua`, `tests/test_pack.lua` |
| W3-groups | `logic/bp/groups.lua`, `tests/test_groups.lua` |
| W3-route | `logic/bp/route.lua`, `tests/test_route.lua` |
| W3-power | `logic/bp/power.lua`, `tests/test_power.lua` |
| W3-validate | `logic/bp/validate.lua`, `tests/test_validate.lua` |
| W3-serial | `logic/bp/serialize.lua`, `tests/test_serialize.lua` |
| W4-search | `logic/bp/search.lua`, `tests/test_search.lua` |
| W4-deliver | `gui/blueprint_delivery.lua`, `tests/test_blueprint_delivery.lua` |
| W4-golden | `tests/golden/**`, `logic/engine_test_api.lua`, `tools/evidence_receipt.py`, `docs/export-format.md`, `docs/golden-workflow.md`, `docs/engine-evidence/README.md` |

A lane that believes an existing test is wrong stops and reports. It never edits one.

## 2. Stubs and the red proof

Every module in §1 exists already, with its signatures and a stub that returns **the shape, empty**, not nil. That
is deliberate: a lane's test must fail against the stub as an assertion (`FAIL <case> [assert]`), and a stub
returning nil would make it crash instead (`[error]`), which the gates refuse as proof.

Red proof, run in a throwaway worktree so nothing of yours is touched:

```sh
S=$(mktemp -d); git worktree add --detach "$S" HEAD >/dev/null
git -C "$S" checkout <LANE_BASE> -- <owned module files>
out=$(cd "$S" && lua5.2 tests/test_<name>.lua 2>&1); rc=$?
git worktree remove --force "$S"
printf '%s\n' "$out" | grep -q '^FAIL <case> \[assert\]' && [ "$rc" -ne 0 ] && echo red-proof-ok
```

Every check runs under POSIX `sh`: the lane verifier executes checks with `shell=True`, which is `/bin/sh`. No
process substitution, and no fixed `/tmp` path, because six lanes run at once.

## 2b. A test that crashes proves less than a test that asserts

A stub returns an empty shape, so `catalog.entity["assembler"].tile_w` is a nil index, not a failed assertion. A
test written that way fails against the stub with `[error]`, which the gates do not count, and its failure message
names a nil value rather than the fact that broke. Assert that a thing exists, then read it:

```lua
local machine = catalog.entity["assembler"]
H.equal(machine ~= nil, true, "the assembler is in the catalog")
H.equal(machine.tile_w, 3, "its footprint is three tiles wide")
```

Lane 003's red proof came back 2 assertions and 18 crashes, which is why this is written down.

## 2c. An engine global is never a table

`prototypes` is a `LuaPrototypes` object, `game` a `LuaGameScript`, `settings` a `LuaSettings`, and a prototype
list such as `prototypes.entity` a `LuaCustomTable`. In the game `type()` reports `userdata` for every one of
them. A guard written `type(prototypes) == "table"` is therefore false in every real factory and true in every
offline test: the code takes its absent branch, finds nothing, and the suite still passes. That shape shipped
broken in 1.1.27.

Ask about presence instead:

```lua
if not rawget(_G, "prototypes") then return nil end
local machine = prototypes.entity[name]
```

The harness reports these globals as userdata, and `tests/test_guards_userdata.lua` refuses the pattern in every
shipped file. Registering `prototypes` alone turned twelve merged cases red and led to nine such guards across
five modules.

**Purity.** The geometry core — `grid.lua`, `pack.lua`, `groups.lua`, `route.lua`, `power.lua`, `validate.lua`,
`serialize.lua` — reads no engine global at all: plain data in, plain data out. The boundary modules `plan.lua`,
`preflight.lua` and `settings.lua` do read the game, because they resolve what the player picked and what the
force unlocked before any catalog exists.

## 3. Units, identities, determinism

Rates per second. Power watts. Pollution per minute. Lengths in tiles. Budgets in ops.
`full_name` is `"item/<name>"` or `"fluid/<name>"`; above-normal quality uses `logic/quality_id.lua`.
Quality is always an explicit string; `"normal"` is never nil except where stored data already uses nil for it.
Tolerance: `EPS(x) = math.max(1e-9, math.abs(x) * 1e-9)`.

Anything that decides output order is an array with a stated sort key. `pairs()` never decides an order that
reaches a result: two players on two machines must build the same layout from the same sheet.

## 4. Storage keys

```
storage[player_index].calc_jobs              = {[sheet_id] = job}
storage[player_index].blueprint_job          = job | nil
storage[player_index].config_revision        = int      -- bumped by the reset and by a configuration change
storage[player_index].sheet_revision         = {[sheet_id] = int}
storage[player_index].blueprint_settings     = {[sheet_id] = settings}
storage[player_index].last_snapshot          = {[sheet_id] = snapshot}
storage.next_sheet_id                        = int      -- assigned by gui/sheet.lua
storage.job_cursor                           = {player_index = int}
```

Everything reachable from `storage` is a number, string, boolean or table. No functions, no metatables, no
LuaObjects, and nothing is written during `on_load`.

## 5. Sheet identity

`sheet_flow.tags.hxrrc_sheet_id`, assigned in `Sheet.new` and backfilled by `Sheet.add_missing_controls`. Tags read
back as a copy, so the whole table is assigned, never one field. `Sheet.id_of(sheet_flow)` reads it.

## 6. The job shape

```lua
job = {kind = "calculation" | "blueprint", player_index, sheet_id,
       revisions = {sheet = int, config = int},
       phase = string, cursor = table, state = table,
       progress = {phase = string, done_units = int, total_units = int | nil},
       done = boolean, ok = boolean | nil, result = table | nil, errors = table | nil, ops_used = int}
```

Every module that does long work exposes the same pair:

```lua
M.begin(input) -> state
M.step(state, budget) -> state     -- budget = {ops = int}, mutated in place; return once ops <= 0
```

Yielding happens inside the long loops — the free-region scan, route expansion, report rows — not only between
blocks or columns. Calculations are served before blueprint work; one budget covers every player.

Before publishing, a job compares its revisions with the sheet's and the player's. A mismatch drops the result.

## 7. Geometry

Two models, on purpose:

* **Packing model** — integers. `TileRect = {x, y, w, h}` covers tiles `x .. x+w-1`. Occupancy cells, reserved
  owners from `Grid.RESERVED`. A conservative bound.
* **Physical model** — floats. `collision_box` and `collision_mask` from the catalog, beacon reception by the
  engine's own rule. The validator uses this and never `Grid.can_place`, so it can catch a packer mistake.

Centres are derived, never stored: `x + w/2`.

Rotation lives only in `logic/bp/grid.lua`, as four different operations (east, `dir = 4`, clockwise, y down):

| Operation | East |
| --- | --- |
| `rotate_cell(dx, dy, w, h)` | `(h - 1 - dy, dx)` |
| `rotate_rect(dx, dy, a, b, w, h)` | `(h - dy - b, dx, b, a)` |
| `rotate_point(px, py, w, h)` | `(h - py, px)` |
| `rotate_vector(vx, vy)` | `(-vy, vx)` |

Directions are `0, 4, 8, 12` only. Belt direction is travel. An underground endpoint also carries
`ug_role = "input"|"output"`. An inserter's `dir` points at its pickup, and `drop_position` decides, not the other
way round. Fluid connections come from the catalog's rotated runtime connections: a pipe-to-ground pairs when its
own `connection_type == "underground"` connection faces its partner, within that connection's own
`max_underground_distance`. Vanilla's exposed connection faces **away** from the partner.

## 8. Entity identity

Producers name their entities with a string id: `m:` block members, `r:` routing, `p:` power, `k:` roboports.
`entity_number` is assigned only by `Serialize.entity_order`, sorting `(y, x, id)`; cross references
(`ug_pair_id`, `port_id`, wire endpoints) are remapped in one pass there.

## 9. Flows, capacity, wires

```lua
Flow    = {flow_id, full_name, item_name, quality, is_fluid, rate_per_second,
           producers = {{step_id, share_per_second}}, consumers = {{step_id, share_per_second}}}
Segment = {segment_id, kind = "belt"|"lane"|"pipe"|"inserter", capacity_per_second,
           allocations = {{flow_id, sink = "step:<id>"|"port:<id>", rate_per_second}}}
```

`step_id = "$external"` is the world outside. Checked by the validator: per flow, produced plus supplied equals
consumed plus removed within `EPS` (`BP_V_FLOW_IMBALANCE`); per segment, allocations fit capacity; every consumer's
share is reachable **at the same time** as every other's (`BP_V_TARGET_SHORTFALL`).

Power returns poles **and** wire edges `{a_id, a_connector, b_id, b_connector}`, serialized into
`BlueprintEntity.wires` after renumbering. An edge is legal only between copper connectors
(`defines.wire_connector_id.pole_copper`, and the `power_switch_*_copper` pair where one is placed) and within
`min(get_max_wire_distance(q_a), get_max_wire_distance(q_b))`. Illegal edges are `BP_V_WIRE_ILLEGAL` and are
excluded before connectivity is judged.

## 10. Block ports

```lua
BlockPort = {port_id, role = "in"|"out", kind = "item"|"fluid", flow_id, rate_per_second,
             attach_dx, attach_dy, normal_dir, travel_dir, member_id}
```

`attach_dx/attach_dy` is the tile **outside** the envelope. Both coordinates are bounded:
`(attach_dx == -1 or attach_dx == w) and 0 <= attach_dy < h`, or the same with the axes swapped. `normal_dir`
points from that tile into the block. `travel_dir` is transport travel: into the block for an input, out of it for
an output. They are separate fields because they are separate things.

## 11. Reason codes

`logic/bp/reason_codes.lua` is the list. A rejection and a search failure carry a locale key and are shown; an
internal retry signal and a validator violation are diagnostics the export carries by code. Goldens compare codes,
never message text.

## 12. Export envelope

`format = "rrc-sheet-debug"`, `schema_version = 1`, `encoding = "zlib+base64"`, produced with
`helpers.encode_string(helpers.table_to_json(payload))`, no blueprint prefix. It decodes with
`base64.b64decode` then `zlib.decompress`. Current settings and the result's own settings are carried separately;
state is one of `not_computed`, `current`, `pending`, `stale`, `failed`.

## 13. Canonical blueprint form

`Serialize.canonical` with `Serialize.CANONICAL_VERSION`. Keys sorted, arrays in their defined order, entity
numbers remapped by `(y, x, id)`, MapPositions as `{x = , y = }` objects, numbers `%.17g` with integers written
whole, volatile metadata dropped, everything affecting layout, connectivity or throughput kept. Goldens and engine
evidence compare this, never the compressed string: equal factories can compress to different bytes.

## 14. Engine evidence

The candidate carries `logic/build_id.lua` (written into the packaged copy by `generate_release.sh`, with
`packaged = true`) and the remote interface `rrc-engine-test`. In a source checkout the module is absent,
`build_id()` reports `packaged = false`, and the companion refuses to write evidence.

Generation is a job over `start_generation` / `generation_status` / `cancel_generation`, because `remote.call`
returns within its own tick. The companion polls, so what it measures is the path a player takes.

An observation carries `candidate_sha` from `build_id()` and one outcome block: production (canonical digest,
string, rates, warm-up, window, timings), rejection (reason codes and the stage), or export (envelope and digest).
The host receipt adds `zip_sha256` of the tested archive. Release readiness needs both branches, the whole fixture
matrix and the performance cases.

## 15. Locale

Keys live in `locale/en|cs|ro/locale.cfg` and only the integrator edits them; cs and ro carry English text for the
round 8 keys until translated. A lane names an existing key. `tests/test_locale_keys.lua` scans `gui/`, `logic/`,
`logic/bp/` and the root files, and walks the reason-code enum for the keys that are built by concatenation.

## 16. Wave bases

A lane is given its base as a SHA in its task file. The table names the tag that SHA comes from; a tag is
written down here rather than a commit id, because a commit id moves whenever the commit it names is amended.

| Wave | Base tag | SHA |
| --- | --- | --- |
| 1 | `wave-0-spine` | resolve with `git rev-parse wave-0-spine` |
| 2 | `wave-1-green` | `git rev-parse wave-1-green` |
| 3 | `wave-2-green` | `git rev-parse wave-2-green` |
| 3 repair, plus lanes 022 and 023 | `wave-3-repair-base` | `git rev-parse wave-3-repair-base` |
| 4 | `wave-3-green` | `git rev-parse wave-3-green` |

## 17. Generation service, prepared input, terminal result (recovery amendment, 2026-09-19)

Two callers want a blueprint: the player's Generate click and the `rrc-engine-test` interface. Today the dialog
validates settings and stops (`gui/blueprint_dialog.lua`, the Generate handler returns `true, settings`), while the
engine interface registers the shared `blueprint` job kind on its own (`logic/engine_test_api.lua`). Two owners of
one job kind means whichever registers last decides how every job publishes. One service owns it.

### 17.1 `logic/bp/generation.lua`

```lua
Generation.register()                       -- registers the "blueprint" job kind exactly once; idempotent
Generation.start(input) -> job_id, nil      -- or nil, reason_code
Generation.status(player_index, job_id) -> TerminalResult
Generation.cancel(player_index, job_id) -> boolean
```

`Generation.start` never blocks: it enqueues, and the shared tick budget advances it (`logic/jobs.lua`,
CALC-06). Preparation that can be large — snapshot, catalog projection, plan — runs inside the job, never inside
the click, because a click that blocks on preparation still freezes the game.

```lua
GenerationInput = {
    schema_version = 1,
    player_index, sheet_id, revisions = {sheet, config},
    settings,              -- logic/bp/settings.lua shape, already validated by the caller
    options,               -- sheet options that reach the plan
    surface, force,        -- names, never LuaObjects
    deliver = true|false,  -- true: hand the result to BlueprintDelivery; false: return it only
}
```

`deliver = false` is what the engine interface uses: it wants the result, never the player's cursor.

### 17.2 Prepared input, captured not invented

```lua
PreparedInput = {schema_version = 1, snapshot, solver_result, catalog, settings, options, revisions,
                 surface, force, source_export}   -- source_export: the debug export the capture came from
```

A prepared input is **captured from the real preparation path**. A handwritten plan is a fixture and must never be
filed as a captured sheet; `tests/golden/add_case` records which one it holds.

### 17.3 Terminal result

```lua
TerminalResult = {
    job_id, state = "pending" | "success" | "failure" | "cancelled",
    phase, progress = {done_units, total_units},
    blueprint_string?, canonical_sha256?, canonical_version?,   -- success only
    reason_codes?, stage?,                                      -- failure only: "preflight" | "search" | "validate"
}
```

Rules: one terminal result per job; a second `start` on one sheet supersedes the first and the superseded job
publishes nothing; publication rechecks revisions and fails `BP_FAIL_REVISION_CHANGED`; a cancelled job leaves the
previous report and the cursor exactly as they were; a deleted sheet ends the job without publishing.

### 17.4 Required-case matrix

`tests/golden/required-matrix.json` is machine-readable and is what release verification reads. A case may be
listed as unfinished; release verification then **fails**, and never counts it as a skipped success. Fields per
case: `case_id`, `branches`, `mods`, `outcome_kind`, `clauses`, `state = "draft" | "accepted"`, `prepared_input`.

## 18. Perimeter ports (2026-09-19, decided after a second real-sheet failure)

§5.8 defines a block port's attach tile as the tile **outside that block's envelope**, which is still a tile inside
the grid. The factory perimeter is not a block, and applying the same rule to the grid envelope puts the attach
tile outside the world: `logic/bp/search.lua` asks `Grid.edge_slots` for slots on `{x = 0, y = 0, w, h}`, so a
left-edge slot lands at `x = -1`, and `logic/bp/route.lua` maps every cell outside the grid to `"__outside__"`,
which routing treats as blocked. A real sheet therefore ends `BP_R_PORT_BLOCKED`, then
`BP_FAIL_NO_LAYOUT_GRID_LIMIT`, and no blueprint is ever produced.

The rule, from here on:

- A **perimeter port** sits on the grid's own edge cell, inside the grid: `x == 0`, `x == w - 1`, `y == 0` or
  `y == h - 1`. Its `travel_dir` points out of the grid for an output and into the grid for an input.
- Routing reaches a perimeter port like any other cell. Nothing outside the grid is ever a routing endpoint, and
  `"__outside__"` keeps meaning blocked.
- A block port keeps §5.8 unchanged: its attach tile is outside its block and inside the grid.
- The belt or pipe standing on a perimeter cell is what the player connects to; the blueprint carries it.

## 19. Calculation result record (2026-09-19, frozen for lanes S and C)

The sliced calculation publishes its solver result where preparation can read it. Nothing downstream ever solves
again to fill a gap: a synchronous `Solver.solve_for` inside a job step is a stall, not a fallback.

```lua
CalculationResult = {
    schema_version = 1,
    player_index, sheet_id,
    sheet_revision, config_revision,       -- the revisions the calculation ran against
    input_fingerprint,                     -- the snapshot's input half
    result,                                -- plain solver result: numbers, strings, booleans, tables only
    published_tick,
}
```

Rules:

- One record per `(player_index, sheet_id)`, stored under `storage[player_index].calc_results[sheet_id]`.
- A record is written **only** on a successful publication, in the same step that commits the staged report. A
  failed, cancelled or superseded calculation never overwrites the previous record.
- A reader treats a record as current only when `sheet_revision`, `config_revision` **and** `input_fingerprint`
  all match what it holds now. Any mismatch is `stale`, and the reader reports `BP_REJ_SNAPSHOT_STALE` instead of
  recalculating.
- Reset, configuration change and sheet deletion drop that sheet's record. A player leaving drops theirs.
- `Calculation.get(player_index, sheet_id)` returns a copy or nil; `Calculation.publish(record)` writes one;
  `Calculation.forget(player_index, sheet_id)` drops one. Copying is bounded work and respects the job budget.

## 20. Prepared capture, kept whether or not generation succeeds (2026-09-19, frozen for lanes S and G)

`PreparedInput` (§17.2) is built before Search starts. The capture of it therefore never waits for a layout.

- `Generation.capture(player_index, generation_id)` returns the prepared input of a job that reached preparation,
  including one that later failed in search, was cancelled, or is still running.
- A capture carries `source_kind`: `"runtime"` when it came from the real preparation path inside the game,
  `"harness"` when it came from the offline test harness, `"handwritten_fixture"` when a person wrote it. Only
  `"runtime"` is engine evidence. The field is written by the producer and never edited afterwards.
- A capture carries `provenance`: `candidate_sha`, `mod_version`, `factorio_branch`, `packaged`, the sheet and
  config revisions, and the terminal outcome known at capture time (`pending`, `success`, `failure`, `cancelled`)
  with its reason codes and stage when it has them.
- `source_export` names the debug export the capture came from and never contains that export's own text, so a
  capture can never nest inside itself.
- A capture of a failed generation makes a **draft** golden case whose supported outcome and observed outcome are
  separate fields. A failure is never filed as an accepted rejection.

## 21. Observation v1: one spelling, producer first (2026-09-19, frozen for lanes E and R)

The companion in `tests/golden/engine/mod/scenario.lua` is the producer; `tools/release_gate.py` is the consumer.
Today they disagree, and no test drives one into the other:

- The companion writes `observation.outcome_kind` plus a block named for that kind — `observation.production`
  (`tests/golden/engine/mod/scenario.lua:324-326`). The gate reads `observation.outcome`, else the whole
  observation (`tools/release_gate.py:152-156`), so it finds no rates and reports
  `rates below target: ... has no measured rates`.
- The companion writes `warm_up = {ticks, start_tick, end_tick}` and `window = {ticks, start_tick, end_tick}`
  (`tests/golden/engine/mod/scenario.lua:318-320`); the gate wants flat `warm_up_ticks` and
  `sampling_window_ticks` (`tools/release_gate.py:358`).

The frozen shape is the producer's, because it is what the game can actually write:

- `observation.outcome_kind` is `"production"`, `"rejection"` or `"export"`, and exactly one block of that name
  carries the outcome. The gate reads `observation[observation.outcome_kind]` and accepts the older
  `observation.outcome` only as a synonym.
- Windows keep the producer's spelling: `warm_up.ticks`, `window.ticks`, both counted in engine ticks. Engine
  ticks are simulation time and are never read as wall-clock seconds; a wall-clock measurement lives under
  `timings.wall_clock_seconds` and is absent when nothing measured it. A missing wall-clock measurement never
  counts as meeting a time target.
- Measured rates satisfy a **lower bound**: a case passes when every expected rate is met within the declared
  discrete error, and surplus production is never a failure. Conservation, capacity and simultaneity assertions
  stay exactly as they are; surplus is never permission for impossible arithmetic.
- `docs/engine-evidence/examples/` carries one synthetic example per outcome kind, in the producer's shape. They
  are examples, never engine evidence, and every file in that directory says so in its own `note` field.
