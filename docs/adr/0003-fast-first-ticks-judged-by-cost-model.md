# Fast first: 4000 ops per tick, worst tick judged by an offline cost model

Generation inside the game is budgeted in ops, not milliseconds: Factorio gives mod Lua no clock it can read. At
2000 ops per tick a sheet's game time is total ops / 2000, so code that is faster per op only makes ticks cheaper and
never shortens game time. Ticket 06 measured that bytes do not change at 2000, 3000, 4000 or 6000 ops per tick (16 of
16 runs) and that tick count falls as 1 / ops. Decided in the round 56 grill (player, 2026-10-04): fast first. Ops per
tick goes from 2000 to 4000, every spike is sliced, and no tick may cost more than 50 ms. The 50 ms is judged offline
by a load-independent cost model, engine ms ~= 20.28 x M Lua VM instructions + 1.58 x thousand `tostring` calls +
0.51 (r^2 0.86, legalcopilot-dev 2026-10-04), and checked against real engine ticks at release on red-science-1s,
blue-science-10s and the first 2500 ticks of magenta-science-10s.

## Considered Options

- Smooth first, no tick > 16 ms (the player's goal): rejected for round 56. Normal ticks already sit at median 5-9 ms,
  but the tail needs op charging by real work in every hot loop. Kept as a later-round goal.
- 6000 ops per tick with a 100 ms worst tick: magenta ~93 s instead of ~140 s, but twice the stutter while a sheet
  builds.
- Judging ticks by engine ms in every gate: real, but noisy at load 5-25 on the shared host, and a whole magenta run
  is far over the 120 s per-check cap. Instruction count alone was too weak (51% error on slow ticks); the `tostring`
  term carries the string-key code.

## Consequences

- A lane that adds a deep copy or a `tostring`-heavy loop can break the 50 ms row even when ticks and bytes stay the
  same: deep copies are charged no ops.
- Raising ops per tick again is safe for bytes, but magenta route ticks reach 50 ms near ~4900-5000 ops
  (extrapolated from a 4000-op window).
- Magenta stays over the 60 s game-time goal (~140 s). Getting it lower needs route restart robustness on layered
  grid 6, not ops per tick.
