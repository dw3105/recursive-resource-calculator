# player-inserter-10s

Player's inserter sheet, 10 inserters/s. Source: `~/share/RRC/inserter-10s-1.1.71.txt` (RRC 1.1.71 debug export,
Factorio 2.0.77, 2026-09-24). A real in-game capture (`generation.prepared_input`), converted with
`tools/prepared_from_export.py`; nothing copied from other cases. In game the generation never finished (stuck in
pack).

Recipe tree (solver): inserter 4× assembling-machine-3 (circuit + gear + iron-plate); casting-iron 2 foundries;
casting-iron-gear-wheel 1 foundry; electronic-circuit 1 electromagnetic-plant (copper-cable 15/s + iron-plate);
casting-copper-cable 1 foundry; molten-iron 1 foundry; molten-copper 1 foundry. Foundries: 4× productivity-3 + one
beacon with 2× speed-3; EM plant 5× productivity-3. External: iron-ore, copper-ore, calcite. Fast belt (30/s), fast
inserter, long-handed inserter, medium pole, roboport.

Captured offsets are in the game's prototype frame (pickup -y); the converter turns them 180 degrees into the
generator frame and stamps `offset_frame = "rrc"` (round 33; `logic/catalog.lua` now does the same in game).
`items_per_second` 4.62 is the catalog default (`logic/catalog.lua`), not a measurement.
No manifest: this case drives producers and measures (round 33), it never certifies.
