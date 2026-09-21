# Round 15 ledger — what was measured, and what each measurement changed

Host `legalcopilot-dev`, 2026-09-21. Branch `feat/round-8-blueprints`. Spine `15d65ea`, tag `round-15-base`.
Contract: `docs/feature-contracts.md` section 27. Frozen census: `docs/round-15-census-baseline.json`.

Nothing here is a target. It records what was measured, so a later change that moves a number has to say
which number and why.

## 1. The defect, measured rather than argued

`logic/bp/validate.lua:1381-1382` decides every transfer: a belt carrying the right flow must sit **on the
inserter's own outward tile**. Routing terminates a belt at a block **port** (`logic/bp/route.lua:406-417`)
and reads no inserter at all (`route.lua:3`). Port and hand are placed by different code.

Driving `Groups.begin`/`Groups.step` on the player's sheet shape -- 4 assembling-machine-3 for science, 2
electric-furnace for copper, catalog offsets `pickup {0,1}`, `drop {0,-1}` -- one block came out `w=24 h=5`
with **18 inserters and 5 ports**, and **1** of those 18 had its outward cell on the block edge.

Driving `Pack` on a 24x4 block with one authored bottom port at `(21,4)`:

```
dir=N  ok  kept  21,4        dir=E  ok  MOVED 0,-1
dir=S  ok  MOVED 0,-1        dir=W  ok  MOVED -1,0
```

So even a correctly anchored port does not survive packing in three of four rotations.

## 2. The player's own two files

`~/share/RRC/red_science_1s.txt`, sha256 `482110b1cb94cf40f77163958e018aa6b3f6c525a46bd5818abe52160fd23c5e`.
Build 1.1.53, base 2.0.77, 54 active mods, 555 sheet rows. One target,
`item/automation-science-pack` at 1/s. Four steps: science on assembling-machine-3 x4, copper-plate on
electric-furnace x1.6, iron-gear-wheel on assembling-machine-3 x0.4, iron-plate on electric-furnace x3.2.
External inputs copper-ore 1/s and iron-ore 2/s. **No modules, no beacons, no fluids.** In game it failed
with `BP_FAIL_SEARCH_BUDGET`, phase `search`.

`~/share/RRC/red_science_1s_manual_bp.txt`, sha256
`934a0034af3069ef40ee1878582d53b26834d287fa4106c2b4480404f6123c30`. 131 entities: 84 transport-belt,
22 inserter, 10 medium-electric-pole, 6 electric-furnace, 5 assembling-machine-3, 4 roboport.

**Corrected claim.** The round 15 plan first said the science step needs 12 inserters. The player said there
are 8, and the player is right: `(210.5, 1076.5 / 1079.5 / 1082.5 / 1085.5)` feed and `(206.5, ...)` drain,
one each. **Every machine in that factory has exactly 2 hands**, 11 machines and 22 inserters. Our
`append_inserters` makes one inserter per **ingredient** (`groups.lua:432-436` loops `step.inputs`), so it
would place 26 where 22 do the job: the player feeds a science machine with ONE inserter reading both lanes
of one belt. That is a real quality gap. It is not this round's defect and is not fixed this round.

## 3. The export carries two PreparedInput objects, and they are the same input

`prepared_input` at the top level and `generation.prepared_input` differ in `catalog`, `snapshot`,
`solver_result` and `source_export`. Measured: after normalising the `rrc_empty_list` sentinel that
`logic/export_payload.lua:100` writes for an empty list, `catalog`, `snapshot` and `solver_result` are
**byte-identical**. One input in two encodings, not two inputs.

The generation copy is pinned, because it is the object the mod handed its own search and because
`tools/prepared_from_export.py` already decodes the sentinel.
`tests/golden/cases/player-red-science-1s/provenance.json` records the choice and
`tests/tools/test_real_sheet_census.py` pins it so nobody silently re-points the case.

## 4. Connector id 5

The player's own blueprint writes connector **5** on both ends of all 12 of its pole-to-pole copper wires.
`logic/bp/power.lua:255-263` returned 0, on the belief that `pole_copper` takes the first connector id --
a guess about field order, never an observation.

Changing power alone made things worse: `logic/bp/validate.lua:342` kept its own hardcoded
`pole_copper = 0`, so `connector_role` classified every delivered wire as non-copper and the census on the
player's sheet gained **55 `BP_V_WIRE_ILLEGAL`** and **8 `BP_V_WIRE_DISCONNECTED`** records that were not
there before. The constant moved in `logic/bp/power.lua`, `logic/bp/validate.lua` and `tests/harness.lua`
together, and three test files carried the same guess: `tests/test_power.lua`, `tests/test_validate.lua`,
`tests/test_power_wires.lua`. With all six aligned the wire codes are gone from the baseline.

## 5. The census needed a denominator that did not exist

`record_rejection` flattened every candidate's errors into one list, so "how many candidates were judged"
was unanswerable and any count of a code was unreadable: a change that tries fewer candidates reports fewer
errors and looks like an improvement. `logic/bp/search.lua:112` now stamps each record with its attempt
ordinal and refusing stage.

Measured consequence, and it was not expected: on the player's sheet **every** rejection record comes from
`validate`. Pack, route and power never refuse a candidate.

## 6. The frozen baseline

Bounded by `search_budget`, injected into a private copy at measurement time and never written into the
committed case.

| tier | ops | candidates | `TRANSPORT_UNUSED` | `TRANSFER_BROKEN` | `INSERTER_GEOMETRY` | `ROUTE_DISCONTINUOUS` | `TARGET_SHORTFALL` |
|---|---:|---:|---:|---:|---:|---:|---:|
| fast | 5,000,000 | 8 | 1122 | 192 | 86 | 16 | 8 |
| full | 40,000,000 | 47 | 6984 | 1138 | 485 | 69 | 47 |

Rates per candidate hold steady across budgets -- 2M gave 148.0 / 23.7 / 10.0 / 2.3 and 40M gives
148.6 / 24.2 / 10.3 / 1.5 -- which is what makes a rate gate meaningful at all. The round 14 figures
(17265 / 2706 / 1114 / 180) came from an unbounded run and are not comparable to a bounded one.

## 7. The gate was proved red before any lane started

| proof | result |
|---|---|
| unchanged tree, nothing required down | `CENSUS-GATE ok`, exit 0 |
| unchanged tree, `--require-down BP_V_TRANSFER_BROKEN` | `rate 24.0 did not fall below the baseline 24.0`, exit 1 |
| `connector-zero` mutation | `BP_V_WIRE_ILLEGAL rate 0.0 -> 6.875 (increase, no waiver)`, exit 1 |
| `census-code-unused` mutation | `tests/test_census_codes_live.lua` CL3 red |

## 8. Expected red at `round-15-base`, all pre-existing

| test | interpreter | failing cases |
|---|---|---:|
| `test_blueprint_pipeline` | lua5.2 and lua5.4 | 2 each |
| `test_corpus_setups` | lua5.2 and lua5.4 | 12 each |
| `test_search` | lua5.2 and lua5.4 | 6 each |

`test_blueprint_pipeline` was verified red at the round 14 HEAD `e87b1eb` before any spine change.

## 9. Two errors in my own task files, found by running the gates

**Lane 132's prose and its check contradicted each other.** The prose said the lane is gated with
`--require-new`, requiring a code the validator could not see before. The check line omits it, and the check
line is the consistent one: the same task requires the four census codes keep their spelling so the census
stays comparable, so a better *reason* cannot move a *count*. Measured after the lane finished: the census is
byte-identical to its baseline, which is the correct outcome and not a no-op.

**Lane 133's golden re-capture item was vacuous.** The task claimed accepted case exports carry block port
ids that spine's step-qualified ids would move. Measured across every `tests/golden/cases/*/export.txt`:
**zero** carry a flow-only block port id. The lane was right to skip it; the claim was asserted without
checking.

## 10. After the anchor merge, measured

Merged `130` (checkpoint), `132`, `133`. Tag `round-15-anchor` = `573c8d4`.

`sh tests/run.sh` on the merged tree reports exactly the section 8 list and nothing else -- 
`test_blueprint_pipeline` 2, `test_corpus_setups` 12, `test_search` 6, each per interpreter -- and the python
tier is **OK, 217 tests**. Three merges added **no** new red.

Census on the player's sheet at `--ops 5000000`, against the frozen fast tier:

| code | baseline rate | after the anchor | |
|---|---:|---:|---|
| `BP_V_TRANSPORT_UNUSED` | 140.25 | 92.0 | fell 34% |
| `BP_V_TRANSFER_BROKEN` | 24.00 | 17.0 | fell 29% |
| `BP_V_INSERTER_GEOMETRY` | 10.75 | 17.0 | rose |
| `BP_V_ROUTE_DISCONTINUOUS` | 2.00 | 7.0 | rose |
| `BP_V_PORT_UNREACHABLE` | 0 | 5.0 | new |
| `BP_R_NO_PATH` | 0 | 1.0 | new, stage `route` |
| `BP_PW_DISCONNECTED` | 0 | 1.5 | new, stage `power` |
| candidates reaching `validate` | 8 | 2 | fell |

Port ids are now per hand, for example
`copper-plate:in:item/copper-ore:inserter:copper-plate:2:input:1`, so contract 27.1 and 27.4 hold.

**The rises are one cause and it is named by the records themselves.** Every `BP_V_PORT_UNREACHABLE` carries
`reason = "no binding uses this port as a sink"`; every new `BP_V_INSERTER_GEOMETRY` carries
`found = "empty ground"` at a pickup cell. `logic/bp/route.lua:612` `build_demands` makes one demand per
**plan** entry and `demand_endpoint_candidates` hands it the flow's ports as interchangeable alternatives, of
which `candidates[1]` is used. Where a step published one port per flow the candidate list had one entry; it
now publishes one per hand, and all but one are never bound. Lane 131 divides the demand per hand.

The denominator fell because a pinned port whose tile is unusable now rejects the **placement** rather than
moving the port, which is what contract 27.3 asks for.

**This merge was waived, not passed.** Lane 130 exhausted its bound and the harness committed WIP. Its owned
suites and the frozen oracle are green on both interpreters, so the tree is sound; the census gate is not
satisfied and the round does not end here. `docs/tasks/131.census-waiver.json` names the two risen codes,
their ceilings, the cause and the task that repays them. Integration runs `--no-waivers`.

## 11. Why lane 130's rises were guaranteed, not accidental

Reading the merged diff rather than the verdict: `logic/bp/groups.lua:565-568` keeps **one route-visible
endpoint per (step, flow, role)** and comments that "the other anchored hands remain physical witnesses with
zero independent demand, so the unchanged router does not report them as unreachable aliases".

That is a workaround for the frozen router, and it cannot satisfy the contract. Rule 27.1 gives every hand a
port; `logic/bp/validate.lua:1381-1382` then demands a belt on every hand's own outward tile. A port carrying
zero demand is never bound, so its hand's tile stays bare, which produces exactly the two codes that rose and
the `BP_V_PORT_UNREACHABLE` records that say `no binding uses this port as a sink`.

Lane 130's own gates could not catch this: `tests/test_transport_handshake.lua` asserts that the ports exist,
are anchored and are distinct. It never asserts that anything routes to them. A test can be green and the
factory still starve.

**Integration owes one deletion.** Once lane 131 divides demand per hand in `logic/bp/route.lua`, the
`route_live` aggregation in `logic/bp/groups.lua` has no purpose and must go, or the router will still see
one endpoint per step. `logic/bp/groups.lua` is PRESERVE-listed for lane 131, so this deletion belongs to
integration and is not the lane's to make.

### 11.1 The probe that settles it

Measured in a throwaway worktree at `round-15-anchor`, changing one line -- `logic/bp/groups.lua:678`
`rate_per_second = selected_port.route_live == false and 0 or source.rate_per_second` becomes
`rate_per_second = source.rate_per_second`, so every anchored hand carries its step rate:

| code | with `route_live` | every hand live |
|---|---:|---:|
| `BP_V_PORT_UNREACHABLE` | 5.0 | **17.0** |
| `BP_V_TRANSPORT_UNUSED` | 92.0 | 92.0 |
| `BP_V_TRANSFER_BROKEN` | 17.0 | 17.0 |
| `BP_V_INSERTER_GEOMETRY` | 17.0 | 17.0 |

Giving the hands a rate makes the count of unreachable ports **rise**, from 10 records to 34. Nothing else
moves. So `route_live` was not routing more product anywhere; it was zeroing rates so the unbound ports
stopped being counted. The router binds one port per (step, flow, role) whatever the ports carry.

Two consequences. Lane 131's change to `build_demands` is the necessary fix and not merely a tidy one: until
a demand exists per port, a port's rate changes nothing. And `route_live` must be deleted **with** that
change, because a router that asks for one endpoint per step will still get one even after demands are split.
