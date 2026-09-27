# player-red-science-1s-foundry

Player's red science 1/s sheet on foundries with beacons. Source: `~/share/RRC/red-science-1s-1.1.95.txt` (RRC 1.1.95
debug export, Factorio 2.0.77, 2026-09-27). Four foundries (molten iron, molten copper, casting copper, casting gear),
each with 4 productivity-module-3 and 1 beacon of 2 speed-module-3; one assembling-machine-3 for red science with 4
productivity-module-3 and 3 such beacons. Turbo belts, bulk hands, legendary substations.

In game generation failed `BP_FAIL_NO_LAYOUT` at search (98 attempts, every one refused in groups:
`BP_P_NO_FIT configured beacon coverage cannot be split`): the single red-science machine stood at the left edge of
its block, so its beacon row reached it with 2 beacons, never 3. `export.txt` is the player's file. No manifest: this
case measures.
