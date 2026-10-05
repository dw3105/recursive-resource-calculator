# Player run round close (2026-10-05)

Plan: `~/.claude/plans/rrc-player-run-plan-2026-10-05.md` (approved rev 1, Q1-Q16). Host legalcopilot-dev,
headless Factorio 2.0.77 (player mods incl. bobinserters) and 2.1.20 vanilla.

## What shipped

- `tests/game/test_player_run.lua`: every golden but magenta driven end to end: calculation sheet through GUI
  handlers, generation dialog, blueprint in cursor, `build_from_cursor`, revive + module insert (bots stand-in),
  poles wired as bots wire them, ports found on the built factory (`tests/game/lib/ports.lua`), Port feed + Pre-fill,
  output judged against the calculation. Round gate + release only (`RRC_PLAYER_RUN=1`).
- Verdict: R >= 0.98 per output, no upper cap (player 2026-10-05). Settled when the last 3 windows agree
  (1.5% + 4 units per window) or each is >= 0.98 of calc (floor pass); a draining inner stock never settles; a
  growing stock with R < 0.98 keeps measuring.
- Feed: Port feed on every input for the whole run + Pre-fill of single-item inner lanes at half density (player
  "maximize input filling"); Metered feed kept as `RRC_FEED=metered`.
- **Player-facing fix** (f2b6a18, 10ad86f): hand `drop_position` written exactly as the game writes it. The in-game
  path wrote absolute drop tiles; with bobinserters' custom vectors the engine adds the field to the hand's position,
  so every hand dropped onto empty ground (red-1s, first Player run: offsets +4.5 to +16.5 tiles; that log was overwritten). Engine probe: a game blueprint of a default-drop hand has no
  `drop_position`; a custom drop is the world-axis offset floored to 1/256 (probe values {0, 1.296875}, {-0.80078125, 0}, {1, -1.203125},
  {0, 1.19921875} recorded in session; engine log not kept; the last is pinned in test_serialize S5c; probe file
  `~/.claude/plans/rrc-playerrun-probes/test_drop_probe.lua` reruns it). Every Player run now asserts each hand's
  `drop_position` equals the game's own blueprint of the built factory (`DROP_NOT_AS_GAME`).
- Sheet sim uses the same feed and verdict rules (Q11).

## Final Player run (7ba8e43 code; blue rerun alone on 05e051c, RC-12)

| Case | R | Hands as game | Wall |
|---|---|---|---|
| red-1s | 1.000 | 22/22 | 61 s |
| red-1s-bulk | 1.000 | 14/14 | 54 s |
| red-1s-foundry | 1.050 | 9/9 | 57 s |
| red-10s | 1.050 | 26/26 | 48 s |
| red-10s-bulk | 1.050 | 26/26 | 49 s |
| red-10s-stack1 | 1.050 | 26/26 | 46 s |
| green-1s | 1.042 | 44/44 | 65 s |
| inserter-10s | 1.000 | 23/23 | 50 s |
| inserter-10s-bulk | 1.000 | 23/23 | 50 s |
| inserter-10s-stack1 | 1.000 | 23/23 | 50 s |
| red-green | 1.050 / 1.049 | 64/64 | 62 s |
| am2 | 1.219 | 18/18 | 83 s |
| blue | 1.583 | 145/145 | 89 s (alone, see note) |
| vanilla red 2.1 | 1.000 | 23/23 | 37 s |
| vanilla green 2.1 | 1.000 | 43/43 | 68 s |
| magenta | skipped (player) | | |

R above 1.0 = the built factory's top speed with unlimited input (whole machines, beacons); no upper cap.

Blue note: R 1.583 and 145/145 come from the 7ba8e43 run, which reached its verdict as the 120 s cap hit under suite-2
load (exit 124). The solo rerun on 05e051c (RC-12) passed in 89.46 s; its factorio log was overwritten by suite 3, so its
own R and hand lines are not kept (runner log `~/.cache/rrc/pr/blue-solo.log`). Earlier blue runs on the same rules
read 1.583 with flat stock (drain-only settle, 2026-10-05).

## Suite

Suite 3 on 05e051c: exit 0, no RUN-FAIL, 24/24 headless shards ok (16 on 2.0 incl. player mods, 8 on 2.1). Suites 1-2
reds and fixes: fixture INDEX rows, IG8 + route digests (drop format), PD5 offline-only, Sheet sim feed parity,
offline.lua passed=0 on test_player_run.

## Defects found by the end-to-end test

1. Hand `drop_position` (above) - player-facing.
2. Test harness: drive waited on `#storage.calc_jobs` (a map); calc record read without `.result`; lab surface takes
   no blueprint ghosts (build on nauvis); script revive leaves poles unwired; setting qualities not unlocked.
3. Measuring: metered feed misread low-rate and deep-buffer sheets (green-1s, vanilla green, am2, blue); full-density
   pre-fill drained for minutes; fixed by half-density Pre-fill + drain guard + floor pass.

## Unmet / deferred

- Magenta untested (player rule MAGENTA-SKIPPED).
- Player run runs only in the round gate and at release (Q10); not per commit.

## Done-when (plan DoD) at close

1. Player run PASS 15 Cases - met; bar changed by ruling PLAYER-RUN-BAR (>= 0.98, no upper cap) in place of 0.98-1.1.
2. Sheet sim PASS 15 Cases - met; feed changed by ruling MAX-FILL (Port feed + Pre-fill) in place of Metered feed.
3. Each Player run <= 120 s wall - met (37-89 s alone; blue 96 s alone on the tag).
4. Player run out of per-commit suite - met (suite 3: 16 SKIP lines, only the Case-list check runs).
5. Short Case owed a fix - none short; the defect found was the hand drop_position (logic/, fixed, zips built).
6. Full suite green, main moved, push box - met (suite 3 exit 0; origin main 7764d99 pushed by player).
Unmet: none. Magenta stays untested by ruling MAGENTA-SKIPPED.

## Reflection

| Issue | Bucket | Root cause | Proposed rule change |
|---|---|---|---|
| First drop fix removed the field; player: "THIS IS WRONG!!!!" | oracle | fixed from my reading of the symptom, not from what the game writes | rrc-code: a blueprint field change first probes the game's own blueprint of the same entity and matches it exactly |
| Lab sims never saw the drop bug | coverage | lab builds via create_entity skip blueprint fields | covered by Player run in round gate (Q10); no new rule |
| Metered feed chosen (Q2) then reworked for hours (settle, buffers, lumps) | probe-first | method fixed at grill without a probe on the slowest golden | rrc-code: before a grill fixes a measuring method, probe it on the slowest and lowest-rate golden |
| Tree edited while a background run read it (twice) | discipline | rule existed (memory) and was skipped under time pressure | none; side-worktree pattern worked once used |
| Suite 2 exit 1 with no failure text | tooling | run.sh hid which step failed | fixed: run.sh prints RUN-FAIL <step> |
