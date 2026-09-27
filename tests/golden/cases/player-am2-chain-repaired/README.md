# player-am2-chain-repaired

Same player export as `player-am2-chain` (tests/golden/cases/player-am2-chain/export.txt, captured 2026-09-21 by an
older mod version). That capture delivered EMPTY inserter geometry (`catalog.inserter.pickup_offset`, `drop_offset`,
`drop_position`), so it stays a historical negative case (`BP_CAP_INCOMPLETE`, tests/tools/test_incident_capture.py).

This case is the same export re-prepared by today's converter, which repairs those three fields:
`python3 tools/prepared_from_export.py tests/golden/cases/player-am2-chain/export.txt -o prepared_input.json`
(`source_kind = runtime-repaired`, `certifiable = False`), round 45, 2026-09-27, legalcopilot-dev.

Measured 2026-09-27 on int/r44 (lanes 254 + pipe leaf prune): generates ok=true, 287 entities, 29.7 s CPU.
