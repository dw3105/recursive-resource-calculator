# Round 14 baseline — what was true before any lane started

Host `legalcopilot-dev`, 2026-09-21. Branch `feat/round-8-blueprints`.
Pre-spine tree `498eff9`. Contract: `docs/feature-contracts.md` section 26.

Nothing in this file is a target. It records what was measured, so a later change that moves a number has to
say which number and why.

## 1. The delivered artifact, read from its bytes

`~/share/RRC/rrc-round13-mine.txt`, sha256 `9e075dddf2a16485cfa4d24e45b5fc62f2ba6cb04fbc23236ca6b8c78cb3d95a`.
It loads in Factorio; the player confirmed that. It is not a factory.

Measured by `tools/blueprint_audit.py`, which decodes the string and re-derives the geometry without ever
reading one of our own tables:

```
entities                    314
invalid_inserters            11      of 18
unpairable_pipe_to_ground    12      of 12
unpairable_underground_belt   4
unused_belt_tiles           224      of 224
unused_pipe_tiles            35
redundant_beacons             3      of 9
wires                         0      of 10 planned
inferred_terminals            3
```

The eleven inserters, in detail: five drop onto empty ground, two pick up from empty ground, one drops into
another inserter, one into a pipe-to-ground, one onto a medium electric pole, one into a beacon. The seven
that work are six belt-to-machine and one machine-to-machine.

All twelve pipe-to-ground endpoints face east or south. A pair needs opposite directions, so none of them can
pair with anything and every fluid route is cut.

The beacons: casting-iron is configured for 3 and is reached by 6; two of those six also serve the
copper-plate furnace; three of the nine are removable without dropping any machine below its configured count.

The same audit run against the preserved generator result `generator-int3.json` gives identical geometry
counts and `wires = 10`. So `tools/blueprint_string.py` converts the entities faithfully and loses only the
wires.

## 2. Why the generator said `ok=true`

One cause, four lines:

```
logic/bp/search.lua:777    make_candidate(state, grid, blocks, entities, ports, ...)  -- takes ports
logic/bp/search.lua:788    ... entities = {}, ports = {},                             -- throws them away
logic/bp/search.lua:1236   route_result = state.work.route.result or {}               -- route always non-nil
logic/bp/validate.lua:654  legacy_route_only = #root.ports == 0 and root.route ~= nil -- therefore ALWAYS true
logic/bp/validate.lua:1217 if work.legacy_route_only then return true end             -- physical checks skipped
```

The `ports` argument reached line 777 from the beginning and was never read. The comment at
`validate.lua:1213` states that every current candidate carries the top-level placed ports; it was false for
every candidate this function built. The same flag also disabled recipe identity at `validate.lua:1483` and
`:1493`.

A second, independent bypass: `tests/golden/generate.lua:414` returns `Validate.reconcile_artifact` **as** the
validation result, leaving `Validate.begin` / `Validate.step` at `:419-468` unreachable. Reconciliation
inspects machines, beacons and wires only (`validate.lua:1759-1902`); it never reads a belt, a pipe or an
inserter, and the code says so itself at `:1804-1806`.

## 3. Pre-spine suite, tree `498eff9`, both interpreters

`sh tests/run.sh` exits 1. Every failure below predates round 14.

| test | interpreter | failing cases | cause |
|---|---|---:|---|
| `test_corpus_setups` | lua5.2 | 2 | `shared-intermediate-multi-target` stops in phase `route` after 700 ticks |
| `test_corpus_setups` | lua5.4 | 2 | same |
| `test_search` | lua5.2 | 8 | BP-20, four cases under two shapes |
| `test_search` | lua5.4 | 8 | same |

Twenty failing Lua cases in total. Python: **167 of 167 pass**, which includes the 13 new cases of
`tests/tools/test_blueprint_audit.py`.

The BP-20 cases are: `a larger grid that needs fewer beacons wins`, `the better candidate found second wins`,
`the better first candidate survives a worse follow-up`, `equal beacon counts defer to footprint area`. All
four are about candidate comparison, which is lane 123's subject.

## 4. The auditor was qualified before it was trusted

`tests/tools/test_blueprint_audit.py`, 13 cases, the control asserted first. Two of its rules were wrong when
written and the suite caught both:

- **Component membership is not the contract.** Joining components across legal underground pairs is
  physically right -- a tunnel is a connection -- and it moved the round 13 artifact's unused belt count from
  89 to 0, because one inserter blessed the whole network. Directed reachability replaced it: a belt counts as
  used only when a real source reaches it and it reaches a real sink. That is where 224 comes from.
- **The bounding box was taken from entity centres.** Every cell of a one-row layout then sat on the
  perimeter, and a stray belt extended the box and inferred itself as both supply and drain terminal, so it
  satisfied its own obligation. The reversed-inserter mutant and the added-waste-belt mutant both survived.
  Extents, plus a terminal only where the belt's own flow crosses the boundary, killed both.

## 5. Timing, before round 14

Player's sheet, lua5.2, default configuration:

```
TOTAL 29.41s ok=true
  plan     0.00s   0.0%  calls=2
  groups   0.47s   1.6%  calls=2
  pack     1.72s   5.8%  calls=28
  route   25.07s  85.2%  calls=884
  power    1.31s   4.5%  calls=509
  validate 0.18s   0.6%  calls=2
```

Fourteen candidates tried; candidate 14 succeeded in 1.07s; the first thirteen burned about 26s.

## 6. Measured and refuted — do not retry

| tried | result |
|---|---|
| order the route frontier by remaining distance | never finished one candidate in 110s, against 6.8s |
| disable the four direction-order retries | saved 13% and removed a real fallback |
| grant a restart only while it buys progress | 66.72s over 60 candidates |
| order candidates by block count descending | 74.10s over 59 candidates, against 27.60s over 14 |

The lever for round 14 is different and larger: lane 123 removes the port-copy multiplication at
`search.lua:582-587`, and lane 122 makes same-flow sharing sought rather than tolerated. Fewer demands and
fewer independent runs, not a faster inner loop.

## 7. Post-spine, and what spine changed

Spine is one commit. It closes the bypass, publishes contract section 26, registers the codes the round needs,
maps the five lane tags, and adds the oracle rows that name each new rule.

### 7.1 The flip, and what it actually proved

`search.lua:788` now publishes the `ports` argument the function has always received. Consequence on the
suite, both interpreters:

| test | pre-spine failing | post-spine failing | delta |
|---|---:|---:|---:|
| `test_blueprint_pipeline` | 0 | 2 per interpreter | +4 |
| `test_corpus_setups` | 2 per interpreter | 12 per interpreter | +20 |
| `test_search` | 8 per interpreter | 8 per interpreter | 0 |
| python | 167 pass | 167 pass | 0 |

The new failures are **not** physical rejections. They read `BP_FAIL_GRID_LIMIT` and `capture stopped in
phase power after 600 ticks: tick bound reached`. Plainly: with the exception closed, no candidate the
generator currently builds survives the strict validator, so the search exhausts every grid and dies. All
four corpus cases are red, not only the one that was red before.

That agrees with the byte audit exactly. There was never a passing candidate; there was a validator that
never looked.

### 7.2 One defect spine had to fix in `logic/bp/validate.lua`

`validate.lua:1506-1514` compared an inserter's `pickup_position`, which is in world coordinates, against
`rotated(spec.pickup_offset)`, which is an offset from the entity centre. Different units. It had never fired
because `groups.lua` publishes no position and the oracle's catalog carried no offset, so both sides were
always nil. The moment either side was populated the whole positive control failed with two
`BP_V_INSERTER_GEOMETRY` records, and with it `TR3`, `BE1`, `BE3` and `MT1`.

Spine converts the published position to an offset before comparing. That file belongs to lane 120, and spine
lands before lane 120 branches, so there is no conflict.

`TR3` moved the inserter entity without moving its published cells, which after the fix is an inconsistency
the geometry check catches first. The mutation now moves the cells with the entity, so the row still tests
what it was written to test: both cells land on empty ground and the input transfer breaks.

### 7.3 Oracle at spine: 88 cases, 76 pass, 12 red

The twelve are six rows under two shapes, and every one is a lane 120 target:

| row | requires | why it cannot pass yet |
|---|---|---|
| `EP4` | `BP_V_INSERTER_GEOMETRY` | occupant resolution: a pole stands where the product must land, geometry consistent |
| `EP5` | `BP_V_INSERTER_GEOMETRY` | occupant resolution: a pipe is offered as an item pickup endpoint |
| `WA1` | `BP_V_TRANSPORT_UNUSED` | rule 26.2 is not implemented |
| `WA2` | `BP_V_TRANSPORT_UNUSED` | rule 26.2 is not implemented |
| `BR1` | `BP_V_BEACON_REDUNDANT` | rule 26.6 is not implemented |
| `FC1` | acceptance | `validate.lua:1196` reads `position`, the capture writes `positions` |

`EP1`, `EP2` and `EP3` pass already, because the unit fix in 7.2 made the geometry check live. They pass on
**geometry consistency**, never on occupant type. `EP4` and `EP5` exist because of that difference: written
loosely, `EP4` passed on `BP_V_TRANSFER_BROKEN`, since deleting the belt also broke the route. A row that
passes for a neighbouring reason is not a row.

`WA3`, an orphan underground endpoint, passes already through `BP_V_UNDERGROUND_UNPAIRED`.

### 7.4 Expected red at spine, by name

Any failure outside this list blocks the `round-14-base` tag.

```
test_blueprint_physical_contract   EP4 EP5 WA1 WA2 BR1 FC1        x2 shapes x2 interpreters = 24 cases
test_blueprint_pipeline            2 cases x2 interpreters        =  4 cases
test_corpus_setups                 12 cases x2 interpreters       = 24 cases
test_search                        8 cases x2 interpreters        = 16 cases
python                             0
```

## 8. Integration findings, landed while the lanes ran

### 8.1 Wires: the loss was silent, and silence was the defect

All ten edges in the round 13 result are pole-to-pole copper carrying connector id `0`, the offline stand-in
`logic/bp/power.lua:255-263` writes. `tools/blueprint_string.py` dropped them deliberately, reasoning that an
invented id is worse than none. The reasoning is sound; the silence is not. Contract 26.7 requires a named
refusal.

`factorio-draftsman` 4.0.0 reports `WireConnectorID.POLE_COPPER = 5`, so `0` is wrong. Draftsman is **not** an
oracle for this question: measured 2026-09-21, it accepted connector `99` and round-tripped `wires` as
`None`, discarding wires exactly as it discards every `recipe`. Proving one value wrong never proves another
right, so nothing here writes `5` on that evidence alone.

Electric poles auto-connect to poles in range when a blueprint is built, so omitting pole-to-pole copper costs
nothing physically. `--allow-pole-autoconnect` therefore omits it and prints every edge omitted; without the
flag the converter refuses and names what the capture must supply. A non-pole wire refuses even with the flag.
`tests/tools/test_blueprint_string.py`, 8 cases, control first.

Also recorded, because it cost time: `draftsman.blueprintable.Blueprint(dict)` takes the **inner** blueprint
object. Handed the `{"blueprint": ...}` wrapper it raises `'label' must be an instance of str`, naming a field
that is not the problem.

### 8.2 The release gate discarded an argument it had been given

`tools/release_gate.py:635` replaced `args.archive` with `None` whenever `--release` was set. The intent is
right: a release covers both branches, so one archive cannot be the exact package for either. The execution
then failed with `mismatched archive: no archive supplied for branch 2.0`, a complaint about a missing
argument the caller had supplied.

It now refuses by name and points at `--archive-dir`, which holds `2.0.zip` and `2.1.zip`. A single branch
still accepts its own `--archive`. The new case was run against the code before the change and failed with
exactly the old message, so it is a real test. `tests/tools/test_release_gate.py`, 33 cases.

### 8.3 Both new suites are already in the offline gate

`tests/run.sh:12` discovers `tests/tools/test_*.py`, so `test_blueprint_audit.py` and
`test_blueprint_string.py` run with the suite without any further wiring.

## 9. Merge 120, and the one thing it broke

Lane 120 verified independently before merging: oracle 88 of 88 on both interpreters, up from 76, closing
`EP4`, `EP5`, `WA1`, `WA2`, `BR1` and `FC1`. Ownership clean.

The suite after the merge carried one failure outside section 7.4's list:
`tests/test_route_layout_contract.lua` `L1` and `L4`, 4 cases per interpreter. Both are POSITIVE controls --
"cardinal crossing is accepted", "same-flow approach belt remains legal" -- and both rejected with
`BP_V_TRANSPORT_UNUSED`, three records on `L1`.

The cause is a gap in rule 26.2, not a defect in lane 120. Those fixtures are pure geometry: an underground
pair and one middle belt, with no machine and no plan step. Waste is measured **against obligations**, so a
candidate carrying none cannot be judged for it -- every entity is trivially unused when there is nothing to
serve. The rule now applies only where the plan has at least one step. A candidate whose plan has no steps is
already refused by plan completeness long before this check, so nothing escapes through the guard, and the
oracle's `WA1` and `WA2` still reject a spare belt and a spare inserter.

## 10. What the integrated tree actually does on the player's sheet

All five lanes merged and were verified here, never on their verdicts. The oracle is 88 of 88 on both
interpreters and the python suite is green. On `player-am2-chain` the pipeline still delivers nothing.

One candidate reached validation in 240s and failed with 449 errors:

| count | code | reason as reported |
|---:|---|---|
| 403 | `BP_V_TRANSPORT_UNUSED` | consequence of the rows below |
| 18 | `BP_V_INSERTER_GEOMETRY` | **captured inserter offsets are missing** |
| 18 | `BP_V_TRANSFER_BROKEN` | consequence |
| 6 | `BP_V_PORT_EDGE_WRONG` | `binding source has role in`, `binding sink has role out` |
| 2 | `BP_V_FLUID_DISCONNECTED` | consequence |
| 1 | `BP_V_UNDERGROUND_UNPAIRED` | `endpoints do not carry transport direction` |
| 1 | `BP_V_COLLISION` | `m:inserter:assembling-machine-2:1:input:3` against `:input:4` |

### 10.1 The dominant cause is the INPUT, and it was already declared incomplete

```
catalog.inserter: {"drop_offset": {}, "drop_position": {}, "pickup_offset": {}, "items_per_second": 4.62}
```

Every inserter offset in the stored capture is an **empty table**. Lane 121 reads the captured offsets exactly
as rule 26.3 requires; there are none to read. Lane 120 rejects exactly as rule 26.3 requires. The 403 unused
transport records follow from that single fact, because an inserter that cannot be placed serves no
obligation and every belt that would have fed it serves nothing either.

Contract section 25.8, written in round 13, already names `player-am2-chain` a **historical negative** that
must reject with `BP_CAP_INCOMPLETE`, precisely because of these empty offsets. Driving it as the acceptance
input, and timing it against the five second ceiling, was an error in this round's integration, not a defect
in any lane.

### 10.2 Two genuine code defects survive that reading

- `BP_V_COLLISION`: `m:inserter:assembling-machine-2:1:input:3` and `:input:4` occupy the same cell. Lane 121
  places two input inserters of one machine on top of each other.
- `BP_V_PORT_EDGE_WRONG`, 6 records: `binding source has role in` and `binding sink has role out`. The route
  bindings and the validator disagree about which role a binding endpoint carries.

### 10.3 Why five passing lanes left a product that does not work

Every lane gate ran that lane's own hand-built fixtures. **No lane gate drove the player's sheet**, and no
lane gate could have: of the whole golden corpus, only `player-am2-chain` gets past preflight at all -- every
other case rejects with `BP_REJ_PROTOTYPE_FACTS_MISSING`. So the offline corpus cannot exercise generation,
and the single input that can is the one already declared incomplete.

That is the structural finding of round 14, and it outranks every individual defect above: a lane cannot be
gated on the only input that matters, so lane verdicts can never stand in for integration.

### 10.4 What round 14 did deliver

The validator now catches all seven classes above. Round 13 reported `ok=true` on an artifact whose 224 belt
entities served nothing, whose 11 of 18 inserters moved nothing and whose 12 pipe-to-ground endpoints could
not pair. The pipeline now tells the truth about itself, in detail, for the first time.

## 11. The player's own two files, and what they settled

Two files arrived after the merges, and each overturned something this round had written down.

### 11.1 `red_science_1s.txt` — the fresh capture

`~/share/RRC/red_science_1s.txt`, build 1.1.53, base 2.0.77, **54 active mods**, 555 sheet rows, target
`item/automation-science-pack` at 1/s. Solved: science 4 machines, iron-plate 3.2, copper-plate 1.6,
iron-gear-wheel 0.4.

Sent twice. The first, sha256 `92d162d8…`, was capture-only: `generation.status = "absent"`, so no
PreparedInput existed and `tests/golden/add_case` wrote none. The second, sha256 `482110b1…`, followed a real
Generate press and carries `generation.prepared_input` — the exact object the mod handed its own search.

**In game it failed**: `reason_codes: ["BP_FAIL_SEARCH_BUDGET"]`, phase `search`, progress 184 of 49 units.
That is the same wall measured offline, reported by the mod itself.

**A live capture defect.** The real captured catalog carries
`inserter: {"pickup_offset": {}, "drop_offset": {}, "drop_position": {}}` while
`options.catalog_diagnostics` is `{}`. Belt, pipe, pole and robo all survive intact. So the vectors are
emptied after `logic/catalog.lua` builds them and before the JSON is written, and capture never notices. This
is shipping in 1.1.53; it is not an artefact of the historical `player-am2-chain` case.

**A sentinel nothing ever read back.** `logic/export_payload.lua:100` writes `rrc_empty_list = true` for an
empty list, so a JSON round trip keeps "empty LIST" distinct from "empty map". No reader undid it, and the
generator died with `preflight.lua:422: attempt to index local 'group' (a boolean value)` -- the boolean
being the sentinel's own `true`.

`tools/prepared_from_export.py` now handles both: it prefers the captured PreparedInput, repairs only the
empty inserter vectors, names each repair, and marks the result `certifiable: false`.

**On the real captured input the search is fast.** First candidate at **3 seconds**, then one every one to two
seconds. The five second ceiling is reachable on this sheet; the seven-step `player-am2-chain` was never
representative of it.

Every candidate fails the same way, and the cause is one handshake:

```
17265  BP_V_TRANSPORT_UNUSED
 2706  BP_V_TRANSFER_BROKEN
 1114  BP_V_INSERTER_GEOMETRY   "cell has invalid occupant: empty ground"
  180  BP_V_ROUTE_DISCONTINUOUS
```

`groups.lua:1148` `step_ports` builds block ports carrying **no position**; placement comes later from
`Grid.place_port` on the block edge. `candidate_inserter` separately places inserters at catalog-derived
cells. Route connects to the **port**. The inserter's cell is elsewhere. Everything above follows from that.

### 11.2 `red_science_1s_manual_bp.txt` — the hand-built reference, and the auditor it broke

`~/share/RRC/red_science_1s_manual_bp.txt`, sha256
`934a0034af3069ef40ee1878582d53b26834d287fa4106c2b4480404f6123c30`. A factory a person built and the game
runs: **131 entities**, 84 belts, 22 inserters, 10 medium poles, 6 electric furnaces, 5 assembling-machine-3,
4 roboports, **12 wires**, for this exact sheet.

`tools/blueprint_audit.py` **rejected it** and called all 84 belts unused.

The terminal rule was wrong twice. It inferred a terminal only where a belt's own flow crossed the artifact's
bounding box, and roboports and poles push that box far from the belt ends: 3 terminals found where the
factory has 11. And it missed the structure -- supply runs feed inserter **pickups** while output runs carry
inserter **drops** away, so the two never touch. Forward-reachable-from-a-drop and reaches-a-pickup were
disjoint sets of 25 belts each, **intersecting in 0**.

The physical reading needs no bounding box. A belt run that begins nowhere is where the player feeds it; one
that ends nowhere is where it leaves; a cell that is both would satisfy its own obligation, which is the
stray-belt case, so it is excluded from both. The reference now passes outright and runs as control `ACC14`.

Two frozen claims were corrected rather than defended:

- the round 13 delivery's unused belt count is **51 of 224**, not 224; the old rule inflated it for the same
  reason it condemned the hand-built factory;
- `ACC4` claimed a reversed output inserter strands its belt. It does not. The machine then drains nowhere,
  which is a broken **obligation**, but the belt becomes an externally fed run passing an inserter that takes
  from it, and that is legal. From bytes alone the two are indistinguishable. The case is kept, inverted.

### 11.3 Reference budgets for this sheet, from a factory that works

| metric | hand-built reference |
|---|---:|
| entities | 131 |
| belts | 84 |
| inserters | 22 |
| electric poles | 10 |
| wires | 12 |

These are the first acceptance ceilings in this project taken from a working factory rather than from the
generator's own output.
