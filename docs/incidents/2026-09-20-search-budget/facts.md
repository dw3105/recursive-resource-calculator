# Incident facts — 2026-09-20 search budget

Every fact below carries one label: **supplied**, **inferred**, or **absent**. Nothing here is authoritative.
The incident fixture is the fresh capture of checkpoint 2. This directory is historical evidence only.

Source: `export.txt`, decoded to `payload.json`. Hashes in `provenance.json`.

## supplied — serialized in the export

Environment: mod `1.1.51`, base game `2.0.77`, 54 active mods.
Sheet state `current`, calculation status `ok`.

Target: `item/assembling-machine-2` at `1` /s, quality `normal`,
`round_up = false`, `start_leftovers = "byproduct"`.

Seven active columns, with their selected machines and setups:

| recipe               | product                   | machine               | modules                                                                                                           | beacons                                    |
|----------------------|---------------------------|-----------------------|-------------------------------------------------------------------------------------------------------------------|--------------------------------------------|
| assembling-machine-2 | item/assembling-machine-2 | assembling-machine-3  | speed-module-3, speed-module-3, speed-module-3, speed-module-3                                                    | (none)                                     |
| casting-steel        | item/steel-plate          | foundry               | productivity-module-3, productivity-module-3, productivity-module-3, productivity-module-3                        | beacon x1 [speed-module-3, speed-module-3] |
| electronic-circuit   | item/electronic-circuit   | electromagnetic-plant | productivity-module-3, productivity-module-3, productivity-module-3, productivity-module-3, productivity-module-3 | beacon x1 [speed-module-3, speed-module-3] |
| assembling-machine-1 | item/assembling-machine-1 | assembling-machine-3  | speed-module-3, speed-module-3, speed-module-3, speed-module-3                                                    | (none)                                     |
| casting-iron         | item/iron-plate           | foundry               | productivity-module-3, productivity-module-3, productivity-module-3, productivity-module-3                        | beacon x3 [speed-module-3, speed-module-3] |
| copper-cable         | item/copper-cable         | electromagnetic-plant | productivity-module-3, productivity-module-3, productivity-module-3, productivity-module-3, productivity-module-3 | beacon x1 [speed-module-3, speed-module-3] |
| copper-plate         | item/copper-plate         | electric-furnace      | productivity-module-3, productivity-module-3                                                                      | beacon x3 [speed-module-3, speed-module-3] |

Solved rates, per second:

```text
item/assembling-machine-1          1
item/assembling-machine-2          1
item/copper-cable                  8.999999966472387
item/copper-plate                  2.2499999832361937
item/electronic-circuit            6
item/iron-plate                    11.999999988824129
item/steel-plate                   1.9999999999999998
```

External (unsolved) rates, per second — these are the edge inputs:

```text
fluid/molten-iron                  82.51273285464012
item/copper-ore                    1.8749999813735485
item/iron-gear-wheel               10
```

Entity prototypes with collision boxes, fluid boxes and energy: assembling-machine-3, beacon, electric-furnace, electromagnetic-plant, foundry.
Module prototypes: productivity-module-3, speed-module-3.
Beacon prototypes: beacon.

## inferred — read from `dialog-screenshot.png`, never serialized

The export carries no blueprint settings at all. These come from the Generate blueprint dialog:

```text
roboport          roboport
pole              small-electric-pole      read from icon: wooden, cross beam
belt              transport-belt           read from icon: yellow
inserter          inserter                 read from icon: yellow arm
pipe              pipe
underground_pipe  pipe-to-ground
input_edge        "left"
output_edge       "top"
```

`small-electric-pole` is the one that changes layout difficulty: supply 5x5 against `medium-electric-pole`'s
7x7, wire reach 7.5 against 9. More poles, more occupied tiles, tighter corridors. The harness default is
`medium-electric-pole`, so a reconstruction that ignored this screenshot would solve a different problem.

Icons are evidence. They are never serialized prototype names. Checkpoint 2 replaces every line above.

## absent — not in the export, and not inferable

```text
prototypes.recipe            {} — reference_options (logic/export_payload.lua:262-270) never forwards
                             references.recipes, which collect_recipe_names (:475-482) already built
recipe_coverage.active       {}
calculated machine counts    absent; the reported per-row values 0.133, 0.272, 0.429, 0.133, 0.843, 0.321,
                             0.910 are readable only from the calculation screenshots
aggregate energy, pollution  absent; the reported 34.172 MW and 110.637/m cannot be checked offline
generation section           absent entirely: no settings, no terminal state, no reason codes, no diagnostics
```

The generation section is absent because discovery is transient, never durable: `logic/jobs.lua:202` and `:257`
write `data.blueprint_job`, `logic/export_payload.lua:543-544` reads it, and `logic/jobs.lua:405-407` clears it
when the job is serviced — `:423-426` restores it only for a job that is **not** terminal. An export taken after
a failure therefore finds nothing.
