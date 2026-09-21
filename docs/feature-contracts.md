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

Every terminal failure carries `reason_details` beside `reason_codes`: one entry per code, with the `detail` the
stage supplied and the `flow_id` when it had one. A code with no detail explains nothing, so the dialog prints
the detail too.

`BP_FAIL_INTERNAL_ERROR` is what a raised Lua error becomes. Its detail is the raised message, which names the
file and the line. Labelling such an error a budget or a layout limit hides the defect, so no other code is used
for it.

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
case: `case_id`, `branches`, `mods`, `outcome_kind`, `clauses`, `state = "draft" | "captured" | "accepted"`,
`prepared_input`. `captured` means the sheet was taken through the real preparation path and its engine
observation is still missing; it is reported as an open gap and never satisfies the release corpus.

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

## 22. Quality, recipe facts and receiver facts (2026-09-20, round 9, frozen before lanes 085-090)

A sheet of ordinary speed modules was refused as quality-changing production, and a chance-based product passed
as supported. Both came from the same habit: a stage guessing from data it never received.

### 22.1 The quality rule lives in `logic/bp/quality_policy.lua`

Three questions, never one:

```lua
QualityPolicy.effective_quality(step, catalog)        -> value, supported, reason
QualityPolicy.has_active_quality_module(step, catalog) -> boolean
QualityPolicy.speed_beacon_contribution(step, catalog) -> value
QualityPolicy.has_quality_capable_module(step, catalog) -> boolean
QualityPolicy.receiver(step, catalog)                  -> {status, reason, record}
```

- Quality changes from four sources: machine modules, beacon modules, the machine's `base_effect.quality`, and
  surface or local effects. An empty module list proves nothing about the other three, so **every active
  production machine needs a receiver decision**.
- `BP_REJ_QUALITY_CHANGING` fires when `effective_quality > 0`. A negative penalty is ordinary production.
- `has_active_quality_module` counts a **positive** quality effect only, and is a different question from the
  total: a positive module cancelled to zero still forbids speed beacons.
- `has_quality_capable_module` counts a **non-zero** effect, in either direction. It decides what must be
  verified, never what produces quality.
- `speed_beacon_contribution` counts a **positive** contribution only; a productivity beacon is no speed beacon.
- `BP_REJ_BEACON_SPEED_ON_QUALITY` needs `has_active_quality_module` **and** a positive beacon speed.
- Module and beacon effects count only when the receiver uses them. `recipe.allowed_effects.quality == false`
  zeroes the module and beacon share and **only** that share; a base effect is not a module effect.
- Beacon weight is `count` x distribution effectivity at the beacon's own quality x the profile sample for the
  number of beacons of that kind reaching the machine, matching the planner's model.

### 22.2 Receiver facts and their status

```lua
catalog.entity[name].effect_receiver = {
    status = "verified_default" | "verified_supported" | "unsupported" | "missing",
    source = "prototype" | "capture" | "default",
    branch = "2.0" | "2.1",
    base_effect, uses_module_effects, uses_beacon_effects, uses_surface_effects,
    uses_local_effects, quality_limits,   -- 2.1 only, by branch and never by omission
    reason,                               -- set whenever status is unsupported or missing
}
```

| Situation | Status | Rule |
|---|---|---|
| Field absent from our extract | - | Extractor bug. Fix `tools/extract_api.py` and regenerate. It says nothing about machine support. |
| Field absent from that engine branch (2.0 has no `quality_limits`) | `verified_default` / `verified_supported` | Verified legacy semantics. A 2.0 machine is **never** unsupported for lacking a 2.1 field. |
| Field present in 2.1 | `verified_supported` while the policy handles the values | `quality_limits` whose lower bound is `>= 0` cannot lower quality and changes nothing. A lower bound below zero, or a shape with no readable lower bound, is `unsupported` with that reason. |
| Nobody captured it | `missing` | Kept until enriched from a verified source. A record without a `status` is `missing`, never a default. |
| Behaviour outside the supported model | `unsupported` | Refused by name. |

The pinned concept proves the split: `concepts.EffectReceiver` carries four parameters on 2.0.77 and ten on
2.1.19, `quality_limits` and `uses_local_effects` among them. `tests/test_api_shapes.lua` checks the harness's
receiver table against that concept, per branch.

### 22.3 Recipe facts

```lua
catalog.recipe[name] = {
    name, category, energy,
    ingredients = {{type, name, amount, spoils}},
    products = {{type, name, full_name, amount, amount_min, amount_max,
                 probability, independent_probability, shared_probability,
                 extra_count_fraction, percent_spoiled, spoils}},
    allowed_effects, allowed_module_categories, maximum_productivity,
    facts = {missing = {<field names>}, known_empty = {<field names>}},
}
catalog.recipe_coverage = {state = "complete" | "partial", active = {<recipe names>},
                           missing = {<recipe name> = {<field names>}}}
```

**Completeness is structural.** A check needs only the fields it reads, and those fields must be there:

- `recipe` is a table; `products` is a table, and for an active producing column it holds at least one entry;
  each product carries `name`, `type` and one of `amount`, `amount_min`, `amount_max`.
- `ingredients` is a table. An explicitly empty list is valid; an absent list is not.
- Optional engine fields such as `probability` or `extra_count_fraction` may be absent and take their verified
  engine default. Absence of an optional field is never incompleteness.
- `facts.missing` is **additional** evidence, never the only detector, so a producer that drops a field and its
  declaration is still caught.
- A structurally complete inline `column.recipe` is complete for the product checks.

**Shadowing.** `logic/bp/plan.lua` prefers `catalog.recipe` over `prototypes.recipe`. A projected recipe is used
only when it is structurally complete for the fields that reader needs and declares nothing missing; otherwise
the reader falls back to the runtime prototype and records the gap. An incomplete projection never shadows a
complete runtime recipe. Replay with `prototypes` absent is a required test.

**Missing facts.** An **active** column whose recipe is absent, structurally incomplete for a needed check, or
declaring a needed field missing, is `BP_REJ_PROTOTYPE_FACTS_MISSING`, naming the recipe and the fields. The same
code covers a machine whose receiver status is `missing`. Inactive columns are untouched.

### 22.4 Lane verifier

`lane_config` accepts only `default`, `scaffold`, `ci_collect`, `perf` and `reference_dir` under `[verify]`, so a
per-tag key makes the whole configuration unloadable. `verify.default` therefore calls
`tools/verify_round9_lane.sh {worktree} {tag}`, which runs the whole suite for every tag except
`086_preflight_facts` and `087_planner_facts`. Those two cannot run `tests/test_blueprint_pipeline.lua` on their
own base, because it demands a successful generation that today succeeds only while recipe and receiver facts are
absent. The whole suite runs again, unchanged, once the producer and both consumers are integrated. Selecting no
check is a failure, never a green result.

## 23. Debug export completeness and attempt provenance (2026-09-20, round 10, frozen before lanes 091-093)

The player reported `BP_FAIL_SEARCH_BUDGET [search]` and sent a debug export. The export could not explain the
failure, because it carried no generation attempt, no recipe prototype facts and no calculated totals. Round 10
therefore repairs the export **before** anything else. Search, the golden runner, the release lifecycle and
evidence intake are all deferred until a complete fresh capture exists.

### 23.1 Export completeness

A debug export replays without a screenshot beside it. Per sheet row it carries:

- selected machine and recipe identity, with quality and the product-to-recipe binding;
- every module's name, quality and count;
- every beacon group's prototype, quality, count, sharing value and installed modules, with an explicitly empty
  selection preserved as empty rather than dropped;
- the recipe prototype facts for every selected recipe: ingredients, products, crafting time;
- targets, units, `round_up`, solved and external rates, calculated machine counts, effects, energy and
  pollution, at full precision;
- current against calculated settings with their sheet and revision identities, so stale or pending data is
  named and never blended into "current".

**A missing fact is an explicit diagnostic.** Never a default, never a silent gap, never another sheet's value.

`reference_options` (`logic/export_payload.lua:262-270`) must forward `references.recipes`, which
`collect_recipe_names` (`:475-482`) already builds; without it `Catalog.build` leaves `prototypes.recipe` empty
(`logic/catalog.lua:349`). Forwarding that one field is necessary and **not** sufficient: dependency collection
is audited for a current selection with no result, a stale result, column-local setups, nested quality-loop
stages, and two distinct sheets.

### 23.2 Generation attempt record

For the sheet being exported, the export carries the appropriate attempt: its actual settings, prepared-input
identity, sheet and revision identities, terminal state, reason codes, and whatever diagnostics the current
search already produces. Information today's search does not produce is marked **absent by name**.

No future diagnostic schema is required here. `search.lua:80-89` already replaces the terminal error list, so the
exporter cannot recover stage history that was erased; richer search instrumentation is a later checkpoint and
never a precondition of this contract.

### 23.3 Durable attempt lookup

Transient discovery already works: `logic/jobs.lua:202` and `:257` write `data.blueprint_job` while a blueprint
job is queued or stored, and `logic/export_payload.lua:543-544` reads it. It is kept.

What is added is durability. `logic/jobs.lua:405-407` clears `data.blueprint_job` when the job is serviced, and
`:423-426` restores it only for a job that is **not** terminal, so an export taken after a failure — which is
exactly when a player exports — finds nothing. The generation service therefore owns a durable map from player
and sheet to the appropriate attempt, surviving terminal state, that cleanup, and reload.

Selection rule, stated and tested: the newest terminal or pending attempt **for that sheet**. Another sheet's
attempt is never a fallback. No attempt at all is an explicit absent record, never an omitted section.

`persist_handle` (`logic/bp/generation.lua:80-100`) keeps `reason_details`, which `terminal_failure` (`:724`)
sets and persistence currently drops.

### 23.4 Export semantic comparison

The release corpus runner cannot compare export payloads. `runner.py:1105-1114` skips draft and captured
comparison before the accept branch at `:1115`, and `runner.py:850-893` offers only rejection-code or blueprint
canonical comparison — `canonical()` (`:418-440`) keeps blueprint entities, so a full selection map and `{}` both
reduce to `{"entities": []}`.

Export comparison therefore lives in its own fixture and comparator with **hand-authored** expected values,
never generated from the repaired output. Ordering and timestamps may be normalized; no semantic field ever may.
Each required semantic field carries a negative control: removing or altering it alone must fail the comparison.
A passing round trip, or a canonical match, is never sufficient.

`tests/run.sh:6` globs only `tests/test_*.lua` and `:12` discovers Python only under `tests/tools`, so a
comparator placed anywhere else is never reached by the routine suite. One top-level Lua entry point invokes the
comparator and propagates its failure, so the focused lane command, the routine suite and the diagnostic archive
check all reach the same code. A missing comparator file, a missing fixture, or zero executed comparisons is a
failure, never a green run.

### 23.5 Two archive transitions

| Transition | Requires | Verdict | May be called fixed |
|---|---|---|---|
| diagnostic handoff | export-specific checks pass; exact build identity recorded; every current release blocker listed in the receipt | always `unverified_internal` | never |
| verified promotion | the mandatory golden run **and** `tools/release_gate.py` against an existing archive and bound evidence | `verified`, per branch | yes, for that branch |

A diagnostic archive is how engine evidence gets collected in the first place, so an incomplete release corpus
must never block it — while a failing **export** check must. A diagnostic verdict can never become `verified`
without the second transition. Branches are reported independently.

### 23.6 Lane verification

`tools/verify_round9_lane.sh` gains `--dispatch-only`, which resolves a tag and prints its selection without
executing, so the dispatcher can be gated before a lane has written its new test. It also gains a Python
dispatch, because the Lua loop would otherwise hand a `.py` file to `lua5.2`. A round-10 lane never runs the
whole suite; full suites and the full golden matrix belong to integration, so a sibling's unmerged work is never
charged to a lane. Selecting no check remains a failure.

A red proof requires the **named** case to fail, nothing to error, and the run to have completed:
`tests/harness.lua:2075-2083` can emit `[assert]` and `[error]` in one run, and `tests/harness.lua:2164-2166`
prints the interpreter between the file name and the colon, as `test_x [Lua 5.2]: N cases, N passed, N failed`.

## 24. Supply geometry, roboport facts and honest search failure (2026-09-20, round 11, frozen before lanes 094-099)

Round 11 exists because a player's blueprint never got built and the mod could not say why. Replaying that
player's own capture offline named four defects. These are the rules the repair holds to. Each one is stated
once, here, so two lanes cannot implement two different versions of it.

### 24.1 Supply rule

**An entity is supplied when its collision box overlaps the supply area. Never when its centre sits inside.**

This was already written down at `logic/bp/validate.lua` and already applied to electric poles. Beacons used a
centre test instead, in both the planner and the validator. On the player's sheet that produced `covered=0` on
3744 of 3744 beacon placements: the beacon row sits above the machine row, and a 5x5 machine's centre is
further from the beacon centre than the reach, even with the beacon directly over it.

The same rule now governs beacons, poles and anything else that asks the question.

### 24.2 Geometry rule

**One conversion from a local prototype collision box to a world box, shared by everyone who needs it.**

`logic/bp/geometry.lua` owns it. The planner and the validator both call it and neither owns it, because they
disagreed for ten rounds while each stayed internally consistent. The validator resolved and rotated a
collision box; the planner used tile dimensions. Those are different shapes, and a machine could be grouped as
covered and then rejected as uncovered.

The module states its conventions rather than leaving them to be inferred:

- a tile rectangle is `{x, y, w, h}` with `x..x+w-1` occupied;
- a world box is `{left, top, right, bottom}` in absolute tiles, already rotated;
- rotation is by corners, so an asymmetric box survives a quarter turn - swapping width and height does not;
- a prototype with no collision box falls back to its tile footprint, and the fallback is **reported**, so a
  caller can tell a real box from a substituted one;
- a supply area is a **distance from the supplying entity's centre** on each axis, exactly as
  `get_supply_area_distance` reports it, never half of a width, and never expanded by the supplier's own
  footprint;
- there are **two** overlap rules, deliberately different at the boundary: collision overlap is strict, because
  Factorio places entities edge to edge; supply overlap is tolerant by one epsilon, because an entity sitting
  exactly on the boundary is supplied.

Substituting tile-rectangle overlap for collision-box overlap is not an implementation of this rule. A 3x3
machine at `3,4` overlaps a beacon supply area reaching `y 4.5` on its tile footprint and does not overlap it
with a `[-0.7, 0.7]` collision box, whose top edge is `4.8`.

### 24.3 Beacon requirement rule

**`count_per_machine` is a per-machine requirement. It is never reused as a block-wide physical count.**

The planner merged the two: it took the largest per-machine requirement in a block and placed exactly that many
beacons, in one centred row, then demanded every machine in the block be covered by all of them. With three
beacons of reach 3 spaced four tiles apart, their supply areas intersect in about one tile. On the player's
sheet `got` reached 2 at most and never 3, in 2280 coverage checks.

The physical beacon count is an **output** of placement. Blocks are laid out so that every machine genuinely
overlaps at least its configured count of beacon supply areas of that signature.

### 24.4 Roboport fact rule

Three layers, kept apart:

| layer | what it is | rule |
|---|---|---|
| engine fact | `logistic_radius`, `construction_radius`, `tile_w`, `tile_h` | read from the prototype; a genuine absence is recorded by name |
| compatibility input | a plain-data `connection_distance` in a hand-written fixture, golden case or caller option | still honoured, labelled an override, never called an engine fact |
| derived policy | `spacing = logistic_radius * 2` | labelled derived, with its source input named |

`LuaEntityPrototype::connection_distance` is `subclasses: ["RollingStock"]` in the pinned 2.0.77 and 2.1.19
runtime API. A roboport can never answer it. Reading it anyway raised on the real engine and yielded nil in
every capture, and the planner then fell back to a **one-tile** roboport gap, making its largest grid 11x11
tiles against a block needing 387. It is therefore not a missing roboport fact to record; it is a wrong field
to stop reading.

Resolution order is: explicit caller override, then derived from `logistic_radius`. Never a literal 1, never a
literal 0.

The derived value is measured, not assumed. A player blueprint of four unmodded roboports at maximum connection
distance, 2.0.77, places adjacent centres exactly 50 tiles apart, and the vanilla roboport's `logistic_radius`
is 25. That blueprint is kept at `tests/fixtures/engine/roboport-cell.json` with a written statement of what it
proves and what it does not: it fixes positions and names, it bounds **one cell** with four roboports, and it
establishes no rejection boundary, no network state and no diagonal rule.

**Applicability is checked, not assumed.** The pinned API extracts record which subclass may answer each
member, because a flattened list of member names cannot: changing a member's owning subclass leaves such a list
identical. The mock is checked against those extracts, so a fabricated member cannot hide a production defect
again.

### 24.5 Mock fidelity rule

**A mock that answers a member the engine refuses is a defect, not a convenience.**

The roboport mock fabricated `connection_distance` unconditionally, on the default path every fixture uses. The
whole suite therefore ran on a branch the engine never takes, and no test could see the one-tile gap. Engine
applicability gates apply on the default path, not only in an opt-in case.

### 24.6 Failure rule

**One stop, one cause, and the reasons are kept.**

`BP_FAIL_SEARCH_BUDGET` stood for three unrelated things: an operation cap, an exhausted grid ladder, and a
power bound. The player saw it for a grid ladder that had run out while no operation cap had ever been derived.
Each cause gets its own code. The operation cap keeps `BP_FAIL_SEARCH_BUDGET`, because that is what it is.

Rejections are recorded, not discarded. Pack, route-input, route and power rejections reach the failure record
the same way validator rejections already do, a candidate refused for not fitting the grid says so instead of
being skipped in silence, and the terminal failure stops erasing the stage list it was handed.

### 24.7 Evidence rule

An offline replay is offline replay evidence. It is never reported as an in-game fix.

A fitting candidate is an intermediate milestone. A passing offline test, a diagnostic archive and a delivered
blueprint are three different things, and only the third is what the player asked for.

Configured inputs are never weakened to make a regression pass. Reducing a beacon count or injecting a
connection distance is a diagnostic counterfactual, recorded as such, and never a fixture.

No case is marked accepted without validated, case-specific engine evidence bound to the candidate and archive;
states and expected results are never changed merely to make a gate green.

## 25. A blueprint that physically produces (2026-09-21, round 13, frozen before lanes 110-115)

Round 12 delivered a blueprint the generator called valid. The player pasted it and every machine was blank.

Measured on that exact candidate, against the real seven-step plan, 2026-09-21:

| mutation | entities left | validator |
|---|---:|---|
| unmodified | 316 | `ok=true` |
| every belt and underground belt removed | 76 | `ok=true` |
| every pipe and pipe-to-ground removed | 286 | `ok=true` |
| every inserter removed | 296 | `ok=true` |
| every machine quality set to legendary, plan unchanged | 316 | `ok=true` |

A 76-entity arrangement with no transport at all passes. So the validator is not a validator of production: it
reads declarations. `logic/bp/validate.lua` contains no occurrence of the word `recipe`, and
`logic/bp/groups.lua` never copies `step.recipe` onto the machine member it builds, so the field the serializer
would have written is never present.

These are the rules the repair holds to. Each is stated once, here, so two lanes cannot implement two versions.

### 25.1 Recipe and machine identity rule

**The selected machine prototype, machine quality, recipe, recipe quality, module multiset and module inventory
placement travel from plan to block member to serialized entity, unchanged.**

Comparison is by a bound identity map. A `step_id` tag is a label, never proof, and a planner flag is not an
observation of the artifact.

`recipe` is written **only** where the catalog `etype` is `assembling-machine`. A `furnace` never receives a
`recipe` field: its product follows its input item. So for a furnace the absence of the field is not by itself
sufficient, and its input path is what must be proven. The catalog already carries the fact —
`assembling-machine-3`, `foundry` and `electromagnetic-plant` are `assembling-machine`; `electric-furnace` is
`furnace`.

### 25.2 Physical transfer rule

**A declared flow is an allocation, never a proof.** Every required transfer is reconstructed from placed
entities and catalog facts alone:

- **input chain** — a source structure, an inserter whose pickup cell touches it, a drop cell touching the
  target machine. A disconnected belt stub is not a source structure.
- **output chain** — an inserter whose pickup cell touches the machine, a drop cell touching an output
  structure that reaches a consumer or a declared external drain.
- **continuity** — each required path continuous from a declared external supply port, through every intended
  operation, to a declared external drain, with correct belt direction, legal splits and merges, and matched
  underground pairs.
- **fluid** — a pipe network reaching a real oriented fluid-box connection with correct input, output and
  filter semantics. Incompatible fluids never share a network, and a fluid-only connection never receives an
  item inserter.
- **capacity** — every required transfer carries its demanded rate, derived from the immutable production
  demand and the per-instance allocation. A branch is never assigned more load than its physical path supports.
- **multi-instance** — a step needing two machines gives both machines an input chain and an output chain.

### 25.3 Beacon rule

**Influence above the configured count is legal.** Configured counts are minima, never maxima, and they are
never raised to match placement nor lowered to make a check pass.

**One exception: a machine carrying a quality module may never be reached by a beacon carrying a speed
module.** Checked on real geometry across the whole placed factory, including a neighbouring block's beacon.
The producer splits blocks until it stops. Stripping the coverage record while the beacon still stands there,
which is what `logic/bp/groups.lua` did, fixes the bookkeeping and not the factory.

**Recording an effect is not accounting for it.** Per-instance effects feed available production capacity,
power reporting and transport sizing. Extra speed may leave unused capacity; that is acceptable, and it never
changes the user's machine count or demands extra input. Computing effects and then ignoring them is not.

Effects and influence are keyed by machine **instance**. Keyed by step, two machines of one step overwrite each
other's evidence.

### 25.4 Metric rule

Two measurements, never summed into one number.

| key | unit | includes | excludes |
|---|---|---|---|
| `production_area` | tiles squared | bounding area of machines, beacons, inserters, poles, belts, pipes | the roboport corner envelope |
| `cell_envelope_area` | tiles squared | the requested roboport cell | reported only, never optimized against |
| `transport_cost` | tiles | belt tiles, underground belt span, pipe tiles, underground pipe span, each physical segment counted once, fluid detours included | — |
| `transport_entities` | count | belt, underground, splitter, pipe, pipe-to-ground | — |
| `beacon_count` | count | physical beacons | — |
| `pole_count` | count | electric poles | — |
| `coord_key` | string | deterministic tiebreak, unchanged | — |

**A metric that cannot be measured is a reported missing fact, and it rejects.** It is never defaulted to zero.
That default is how `route_length` read 0 while 270 transport entities stood on the grid.

Comparator, first difference wins: `beacon_count`, then `production_area`, then `transport_cost`, then
`pole_count`, then `transport_entities`, then `coord_key`. `cell_envelope_area` never ranks.

**Frozen reference ceilings are filters, not score components.** A candidate over a ceiling is unacceptable
however well it ranks on an earlier component. Score chooses among candidates that already pass.

### 25.5 Serialized artifact rule

**The exported artifact is decoded and reconciled against the real plan**, by a bound identity map: machine
prototype and quality, recipe and recipe quality where supported, module multiset and inventory placement,
beacon prototype, quality and loadout, entity directions, wires and connectivity. A mutation applied only at
serialization is detected even when the internal candidate stays valid. A recomputed digest identifies output;
it never proves output preserves the plan.

**This runs on the production path, not only in tests.** `logic/bp/search.lua` sets `state.ok = true` as soon
as serialization succeeds, and `logic/bp/generation.lua` then encodes, marks success and may deliver. So
serialization and reconciliation form **one reserved, bounded finalization sequence**: exploration exhaustion
never resets either phase, both yield within the tick allowance, cancellation and a revision change invalidate
the pending result throughout, and success is impossible until reconciliation completes. On mismatch: a named
failure, no delivered artifact, no success.

The engine's own blueprint preview is not interceptable by the mod. Any artifact edited there and then
re-imported or re-exported is revalidated before certification; no hook into the preview is promised.

### 25.6 Roboport rule

Roboports stay outside power coverage, as `logic/bp/search.lua` and `logic/bp/validate.lua` already have them.
Recorded as declined on the user's instruction, never as done.

### 25.7 Capture rule

**Missing required data is an explicit incomplete-capture result, never a default filled in at replay.** Every
required vector component is checked; an empty table is never valid geometry. Representation shapes that the
boundary supports are normalized; a shape it does not support is rejected with a diagnostic naming the entity
and the field.

A capture that fails this is immutable history and a negative case. It is never enriched with inferred
geometry, and it is never the acceptance input.

## 26. A blueprint that is a factory, not a picture of one (2026-09-21, round 14, frozen before lanes 120-124)

Round 13 delivered a blueprint that **loads**. The player pasted it. It is not a factory.

Measured from the delivered bytes, `~/share/RRC/rrc-round13-mine.txt`, sha256
`9e075dddf2a16485cfa4d24e45b5fc62f2ba6cb04fbc23236ca6b8c78cb3d95a`, by `tools/blueprint_audit.py`:

| contract | measured |
|---|---:|
| inserters whose pickup or drop cell holds no belt and no machine | **11 of 18** |
| pipe-to-ground endpoints with no partner they can pair with | **12 of 12** |
| underground belt endpoints with no partner they can pair with | **4** |
| belt entities that serve no obligation | **224 of 224** |
| pipe tiles touching no machine | **35** |
| beacons whose removal leaves every machine at its configured count | **3 of 9** |
| wire edges delivered, against 10 planned | **0** |

The generator reported `ok=true`. One cause, verified line by line at `0b6b607`:

```
logic/bp/search.lua:777    make_candidate(state, grid, blocks, entities, ports, ...)  -- takes ports
logic/bp/search.lua:788    ... entities = {}, ports = {},                             -- throws them away
logic/bp/search.lua:1236   route_result = state.work.route.result or {}               -- route always non-nil
logic/bp/validate.lua:654  legacy_route_only = #root.ports == 0 and root.route ~= nil -- therefore ALWAYS true
logic/bp/validate.lua:1217 if work.legacy_route_only then return true end             -- physical checks skipped
```

The `ports` argument arrives at line 777 and is never read, so every production candidate takes an exception
written for one old fixture. The comment at `validate.lua:1213` states the opposite and is false. The same
flag also disables recipe identity at `validate.lua:1483` and `:1493`.

A second, independent bypass: `tests/golden/generate.lua:414` returns `Validate.reconcile_artifact` **as** the
validation result, leaving `Validate.begin`/`Validate.step` at `:419-468` unreachable. Reconciliation reads
machines, beacons and wires only (`validate.lua:1759-1902`).

These are the rules the repair holds to. Each is stated once, here, so two lanes cannot build two versions.

### 26.1 Obligation rule

**Every committed transfer keeps an obligation:** material, quality, positive required rate, exact physical
source entity, exact physical destination entity.

A `flow_id`, a claimed target, a `ug_pair_id`, a segment allocation and `ok = true` are labels. None of them
is an obligation, and none may stand in for one.

### 26.2 Zero-waste rule

**Every placed transport entity and every placed inserter must serve at least one obligation in the final
graph**, with legal direction and adequate capacity.

Orphan fragments, unpaired underground endpoints, dead branches, abandoned alternatives and loops that merely
circulate product each **reject**. An external terminal is a legal end only where it participates in a
required transfer; it never excuses a loose end. The budget is exactly **zero**, independent of every
compactness budget.

Membership of a connected component is **not** this test. Measured: joining components across legal
underground pairs -- which is physically right, a tunnel is a connection -- moved the round 13 artifact's
unused belt count from 89 to 0, because a single inserter blessed the whole network. The test is directed:
product must reach the entity from a real source, and leave it toward a real sink.

### 26.3 Inserter endpoint rule

**An inserter's pickup and drop cells come from the catalog's captured `pickup_offset` and `drop_offset`,
rotated into the entity's frame** -- never from a direction vector, never from a placement convention.

The catalog already carries them (`logic/catalog.lua:402-412`, `:750-757`). `logic/bp/groups.lua:309-320`
invents a fixed left-input, bottom-output convention instead, and because it emits no position
`logic/bp/validate.lua:1100-1106` guesses from the direction vector. Both stop.

Each cell must hold a real belt or a real machine. Permitted: belt to machine, machine to belt, belt to belt,
machine to machine. Empty ground, a pipe, a pipe-to-ground, a pole, a beacon, a roboport, another inserter and
a chest are each **invalid** endpoints. A fluid connection never receives an inserter.

### 26.4 Connection witness rule

**For every required transfer the validator emits an ordered witness:** the entities the product passes
through, from physical source to physical destination, each consecutive pair legal for that transport kind.

Coordinate proximity, a drawn route line and a shared pair id are each insufficient. Belt turns, splitters,
merges and underground spans are each a witness step carrying its own legality check. A rejection names the
**first** illegal step, never only the obligation.

### 26.5 Underground pairing rule

**Both endpoints exist, prototypes compatible, collinear, facing each other, within the captured
`max_underground_distance`.**

Belts pair in the **same** direction with `type` `input` at the entrance and `output` at the exit; the
entrance looks downstream and the exit looks upstream. Pipes pair in **opposite** directions and carry **no**
`type` field at all -- a pipe-to-ground is oriented by `direction` alone. `logic/bp/route.lua:798-803` and
`:907-912` write one direction to both ends of both families, which is why all twelve delivered pipe-to-ground
endpoints faced east or south and none could pair. The emission must agree with `underground_candidate`
(`route.lua:744-770`), which already demands facing ends.

Surface transport feeds the entrance; the exit feeds surface transport or the physical destination. The
**observed** partner under engine pairing rules must equal the **intended** partner: an intervening endpoint
that steals the pairing **rejects**.

### 26.6 Beacon redundancy rule

**Influence above the configured count is legal. A redundant beacon is not.**

A beacon is redundant when removing it leaves **every** machine at or above its configured count. That
rejects as `BP_V_BEACON_REDUNDANT`, alongside the existing one-sided `BP_V_BEACON_COVERAGE_SHORT`
(`validate.lua:789-795`). Configured counts stay minima and stay immutable.

This is the player's rule, in the player's words on 2026-09-21: "more beacons per machine is fine, but that
foundry is affected by 6! it is overkill!". Measured on the delivery: casting-iron is configured for 3 and is
reached by 6; two of those six are also the copper-plate furnace's; three of nine beacons are removable.

### 26.7 Delivered-bytes rule

**Certification reads the delivered blueprint string, decoded** -- never an internal table, never the
serializer's intermediate.

Identity reconciliation and physical validation are **both** required and neither substitutes for the other.
Wires survive conversion with a correct old-to-new entity-number mapping; where a runtime connector id is
genuinely unavailable offline that is a **named refusal**, never a silent drop.

### 26.8 Search honesty rule

**"A feasible layout was found" is not an optimization certificate.**

`logic/bp/search.lua:602-613` stops the search after the first feasible candidate whenever generated ports
outnumber planned ports or the beacon count is zero, and `:1262-1266` fast-forwards every cursor to the end,
so `Validate.compare` never sees the rest. The search must instead prove its bound, compare its documented
alternatives, or report a bounded heuristic result **naming what it discarded**.
