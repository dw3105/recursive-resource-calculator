# player-magenta-science-10s

Player's production (magenta) science 10/s. Source: `~/share/RRC/magenta-science-10s-1.1.103.txt` (RRC 1.1.103
runtime debug export, Factorio 2.0.77, 2026-09-29). 17 recipes: advanced oil processing + both crackings, plastic,
foundry steps (molten iron/copper, casting iron/steel/copper cable/iron stick), electromagnetic plants (electronic
and advanced circuits, productivity module), assembling-machine-3 (rail, electric furnace, production science),
electric furnace (stone brick); productivity modules and speed beacons. Turbo belts, bulk hands, legendary poles
and roboports. Input edge left, output edge top.

In game generation failed `BP_FAIL_NO_LAYOUT` at search after 22 attempts. Offline on 1.1.103 (legalcopilot-dev,
2026-09-29): attempts 1-5 `BP_P_NO_FIT`; attempt 6 (grid 6) routed, validate refused 114 errors (80 belt bleed:
plastic row end pours into furnace underground; 32 stone row never fed: trunk crosses stone-brick row head as an
underground exit; 1 side-load blocked; 1 loop made by tidy). Round 49 strict re-route: `ok=true`, 2155 entities,
34785 ticks, blueprint sha256 `efa2cf306dc84bfaa5014c38d83e3ea4c01c6cb35a29efebb4b478006fa5ae77`.
`export.txt` is the player's file; `prepared_input.json` is the export's `prepared_input` (source_kind runtime).
