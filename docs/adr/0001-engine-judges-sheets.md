# Real Factorio judges sheets; the bytes baseline only detects change

Our validator, auditors, mock and fixtures all encode our own reading of game rules, and the engine proved that
reading wrong three times in round 42. From round 48 a delivered sheet passes only when a headless sheet sim in
the player profile builds it, feeds every port full on both lanes at max stack, and measures output
>= 0.95 x target; every validator rule has twins the engine must agree with. When a catalog fixture is corrected to
the engine's value the golden bytes move, so a new bytes baseline is cut and the changed sheet is judged by its
sim, not by equality with the old hash. When the engine shows a rule too loose, the rule is tightened and routing
repaired in the same round so no gated sheet stops building.

## Considered Options

- Keep bytes equality as the gate and only record engine differences: rejected, it keeps testing against facts
  the engine already refuted.
- Ship a tightened rule even if a sheet goes NO_LAYOUT: rejected, a sheet that stops building is a regression.
