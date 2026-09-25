# player-red-science-10s

Player's red science sheet, 10 automation science packs/s. Source: `~/share/RRC/red-science-10s-1.1.81.txt` (RRC
1.1.81 debug export, Factorio 2.0.77, 2026-09-25), converted with `tools/prepared_from_export.py`. In game:
`BP_FAIL_NO_LAYOUT`.

Recipe tree (solver): automation-science-pack 10× assembling-machine-3, each 3 beacons (2× speed-3; player set
`sharing: 3`); casting-copper, casting-iron-gear-wheel, molten-copper, molten-iron 1 foundry each, 1 beacon each.
Fast belt, fast inserter, long-handed inserter, medium pole, roboport.

Blockers on round-35 code (round 36 contract): beaconed row layout in groups (bottom beacon row on the hand face;
top hands picking from the beacon row), fluid-port approach rule, second producer hand's path reported unused.
`items_per_second` 4.62 is the catalog default. No manifest: this case measures, it never certifies.
