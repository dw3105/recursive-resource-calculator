# player-green-science-1s

Player's green (logistic) science sheet, 1/s. Source: `~/share/RRC/debug-green-science-1s.txt` (RRC 1.1.63 debug
export, 2026-09-24). Converted with `tools/prepared_from_export.py`.

The export carries no `catalog.inserter` facts. `inserter.items_per_second` is 4.62, captured live on the same save
(red science export); the vanilla fallback 0.83 gives capacity errors that the player's game does not have.
No manifest: this case drives producers and measures (round 30), it never certifies.

The export is `reconstructed` and its `catalog.entity` lists machines only. The infrastructure entity specs
(`beacon`, `inserter`, `medium-electric-pole`, `pipe`, `pipe-to-ground`, `roboport`, `splitter`, `transport-belt`,
`underground-belt`) are copied from `player-red-science-1s` (`runtime-repaired`, same save, same prototypes). The
in-game catalog carries them live; without them the artifact check cannot tell a pole is a pole.

Also copied from the red capture: `catalog.robo` (live: logistic_radius 25, 4x4; the converter wrote
`catalog.roboport` with logistic_radius 50 and no size, which doubled the grid to 101x101), `catalog.pole` (live:
supply 3.5, 1x1; converter wrote 7), `catalog.quality_level`, `catalog.schema_version`.
Open: `tools/prepared_from_export.py` reconstructs these facts wrong for an export without a runtime capture.
