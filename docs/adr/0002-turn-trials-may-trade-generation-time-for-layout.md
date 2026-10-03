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
