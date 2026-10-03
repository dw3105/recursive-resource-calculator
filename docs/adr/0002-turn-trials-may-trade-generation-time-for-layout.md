# Turn trials may trade generation time for layout

The player's order is valid, then fast (wall time and worst tick), then frugal (Material cost). Round 55 adds a
keep-if-cheaper pass of Turn trials after the Drawn pack routes a sheet; each trial packs and routes the sheet again,
so the pass always costs time. Decided in the round 55 grill (player, 2026-10-03): on a sheet whose delivered bytes
change, the pass may make generation slower than a Speed tie with the layout before it; a sheet whose bytes do not
change must still be a Speed tie. The extra time stops at 100% of the sheet's own drawn time or when every Block has
tried all its options, whichever comes first, and the worst tick stays within 10%. A trial wins on lower whole-blueprint
Material cost, then smaller Footprint inside a Material tie.

## Considered Options

- Pass inside the Speed tie window (at most max(1 s, 10%) extra): rejected, the window is too small for a re-route
  on most sheets, so the pass could rarely change anything.
- Pass off by default behind a flag: rejected, round 55 must show at least one golden delivering a turned or flipped
  Block.

## Consequences

- Speed comparisons against an older drawn run are judged only on sheets whose bytes stayed the same.
- An unbounded trial count is never allowed: EM x4 already showed a long in-game pack loop reads as a freeze.

## Status (round 55 close, player 2026-10-03)

Shipped OFF by default (`RRC_TURN_TRIALS=1` or `settings.turn_trials = true` switches it on). Measured at game rate
(2000 ops per tick, legalcopilot-dev): every try costs about one full pack+route+power, tidy most of all; the 100%
cap held at most 2-3 screens and no final. With the cap raised in memory: red-1s no cheaper Turn than the rule's
pick; red-1s-foundry one screen cheaper, final lost; green-1s one win (Material tie, area 1836 -> 1785) as the 17th
screen, past 5x the search time. A no-win sheet still paid the time, against the Speed tie this ADR keeps for
unchanged bytes. Round 56 decides from a 14-sheet study with the pass on.
