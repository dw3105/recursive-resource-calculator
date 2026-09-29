# player-gray-magenta-science-10s

Player's military (gray) + production (magenta) science 10/s each. Source: `~/share/RRC/gray-magenta-science-10s-1.1.97.txt`
(RRC 1.1.97 debug export, Factorio 2.0.77, 2026-09-27). 23 recipes: advanced oil processing + both crackings, 7 foundry
steps (molten iron/copper, casting iron/steel/copper/cable/stick), electromagnetic plants (circuits, productivity
module), machining assembler (electric furnace), modded smelting-plant (stone brick), assembling-machine-3; productivity
modules and speed beacons on every machine. Turbo belts, bulk hands, legendary substations.

In game generation failed `BP_FAIL_NO_LAYOUT` at search. Offline (2026-09-27) every attempt was refused in groups:
beacon rows took the machine faces the belt hands needed. Past groups: rail 71.4/s, copper cable 60.5/s and stone
63.5/s into bricks need more than one turbo belt (60/s), and route then failed on the oil pipes. `export.txt` is the
player's file. No manifest: this case measures.

## Round 48 re-export (2026-09-29)

Replaced by the player's re-export `~/share/RRC/gray-magenta-science-10s-2.txt` (converted with
`tools/prepared_from_export.py`, certifiable). Why: headless player-profile sim showed `smelting-plant` is a burner
machine (fuel category `chloric-fuel`); the delivered 1.1.103 sheet left all 7 at `no_fuel`, so military and
production science made 0/s. Player moved `stone-brick` to `electric-furnace` (speed module 3 rare x2, 1 beacon with
speed module 3 rare x2) and chose medium electric poles.
