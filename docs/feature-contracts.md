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
