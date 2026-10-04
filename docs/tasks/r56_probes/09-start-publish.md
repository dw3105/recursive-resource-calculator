# Ticket 09: where in-game start and publish ticks spend their time

Measured 2026-10-03 21:49-21:54 UTC, legalcopilot-dev, headless Factorio 2.0.77 (3 runs) + 2.1.20 (2 runs),
code = origin/main f3d2268 in ~/wt-rrc-speed01 plus per-call LuaProfiler timers (inert unless armed).
Host load 1.5-9.9 during runs (other sessions), so ranges are wide; shares are stable across runs.

Probe: `09-probe/patch_generation.py` (38 timer sites in logic/bp/generation.lua, diff `generation_timers.diff`),
`09-probe/test_t09_probe.lua` (engine test), `09-probe/hl.sh` (one headless run, RRC_SLOW headless slot, wave
r56-speed02), `09-probe/compare.py` (tables), logs `09-probe/logs/`. Worktree reverted after runs.

Three probe paths:
- **t09fix**: ticket 01 path. Fixture prepared_input passed to `Generation.start`, real search, deliver=true.
- **t09gui**: player's own path. Sheet row, calculate, Generate button `BlueprintDialog.on_generate_clicked`.
  No prepared_input, so Snapshot.of_sheet, calculation and Catalog.build run in the job's prepare ticks.
- **t09pub**: publish tick at real size. The prepare ticks and publish code are real. Search is stubbed to finish on
  its first step with a decoded delivered blueprint from ~/share/RRC: magenta 1.1.105 (2155 entities, the same
  count as today's offline layered run), blue 20260926 (1436), stack1 1.1.99 (841) and gray-magenta 1.1.103 (3402).
  - Proxy check: red1s real engine result (148 entities) against a decoded red1s string (169) under the same code.
    sha256 0.38 vs 0.28 ms/entity. Decoded proxies read up to ~25% low per entity.
  - Proxy blue publish 913-1354 ms is above ticket 01's real blue publish tick of 741 ms (load 0.7-2.6). The absolute
    numbers are load- and GC-noisy; the shares below hold in every run.

## Fact 1: player's click is cheap; "start 173-319 ms" was the test path

| path | click/start tick ms, 2.0 (2.1) | what costs |
|---|---|---|
| player GUI, red 1/s | 27-48 (37-46) | dialog + enqueue; no prepared input |
| player GUI, red+green 1/s | 16-37 (17-31) | same |
| fixture prepared_input (red1s, bulk, foundry) | 143-323 (152-424) | `Jobs.request_sheet` 103-290 ms + `Generation.start` copy 15-36 ms |
| fixture, big sheets (stack1/blue/magenta prepared) | 242-663 (180-560) | same copies, larger input |

- Fixture path deep-copies the whole prepared input 7 times on the click tick: generation.lua:1363, then
  jobs.lua:248 (request_sheet), :142 (make_job), :147 (copy of begin's copy), generation `begin` copy, :259
  (`data.blueprint_job`), :265 (returned copy). Only engine_test_api / tests pass prepared_input; player never does.
- Player path pays the same work later instead, in prepare ticks (bounded per call, not per op):

| player GUI prepare tick (2.0, 3 runs) | ms |
|---|---|
| tick 1: `Snapshot.of_sheet` (generation.lua:624) + `calculation_for` | 18-31 + 19-28 (tick 40-48) |
| tick 2: `Catalog.build` (generation.lua:694) | 30-51 |
| other prepare ticks (copy cursors, budgeted) | 5-18 |

## Fact 2: publish tick = copies + Lua sha256, not search

Search work on the real publish tick is 1-3 ms. Everything else is publish (2.0, median of 3 runs, ms):

| call | gui_red1 (144 ent) | red1s fixture (148) | stack1 proxy (841) | blue proxy (1436) | magenta proxy (2155) | gray-magenta proxy (3402) |
|---|---|---|---|---|---|---|
| `sha256` pure Lua of canonical JSON (generation.lua:1004, called :1292) | 56 | 44 | 265 | 503 | **710** | **1144** |
| `persist_handle` x3: done (:1256) + update_capture (:1293 -> :806) + final (:1330) | 82 | 164 | 251 | 343 | **417** | 525 |
| `Serialize.canonical` (:1283) | 8 | 6 | 47 | 94 | 135 | 244 |
| `helpers.table_to_json` for digest | 5 | 5 | 24 | 43 | 76 | 98 |
| `BlueprintString.build` encode (:1282) | 5 | 5 | 33 | 57 | 87 | 135 |
| result copies (job.result + publish copy) | 3 | 2 | 13 | 28 | 39 | 59 |
| deliver to cursor (:1309) | 3 | 2 | 13 | 41 | 38 | 34 |
| **publish all** | **162** | **229** | **666** | **1089** | **1529** | **2208** |

2.1.20 (2 runs, load 7-10 on run 2): same shape. Magenta publish 973-1771, blue 913-1672, sha256 magenta 477-829.

- sha256 is the largest single cost from ~800 entities up (40-52% of publish). Below that, persist copies are the largest (51-72%).
- Only engine_test_api.lua:307 (parity / engine tests) and offline tools read `canonical_sha256`. The player never sees it.
- `persist_handle` (generation.lua:115-145) copies `handle.capture` (the whole prepared input, :137). It then copies the
  whole record again (:139), and the record already holds the capture, the result and the interim result. Each call
  therefore copies the prepared input twice: 35-100 ms per call on fixture captures and 13-33 ms on the GUI red
  sheet. The publish tick makes 3 such calls.

## Fact 3: capture tick (prepare -> search) pays copies on top of plan + groups

Same tick as ticket 01's worst tick (plan + all groups). Overhead outside the search step, 2.0 medians:

| call | gui_red1 | red1s fixtures | big-sheet fixtures |
|---|---|---|---|
| `handle.capture = copy_plain(prepared)` (:1168) | 10 | 30-39 | 31-40 |
| `persist_handle` (:1175) + bridge after capture | 21 | 55-72 | 60-75 |
| `Search.begin` | 10 | 29-38 | n/a (stubbed) |
| `BoxBinding.fill` (scratch surface probes) | 20 | 22-29 | n/a |
| sum | ~61 | ~140-180 | — |

## Not measured

- **Interim offers** (generation.lua:1233-1243): each interim pays a result copy, a blueprint encode and a
  `persist_handle` that copies the capture and the interim result. Estimated from the magenta proxy at
  ~300 ms per interim (an estimate, not a measurement). No t09 run produced an interim: the small sheets did not, and
  the stub search gives none. The number of interims per big sheet is unknown, as is whether ticket 01's blue worst
  tick (1027 ms @678) is an interim tick.
- Player-mod profile: the runs used the vanilla profile, same as ticket 01 Table C.

## Addendum: prepared_input total, player mod profile (2026-10-03 21:57-21:59 UTC, load 13.3-17.4)

`prepared_input` summed over all prepare ticks (ms, median (range)): 2.0 vanilla red1s fixture 205 (171-213), GUI red
160 (109-167), blue 173, magenta 173; 2.1 red1s 205 (158-252), GUI red 147 (119-176), blue 155, magenta 158.

Player mods (`RRC_PROFILE=player`, 2.0 only, 1 run, `logs/cmp-2.0-player.md`, heavy host load = upper-biased):
- GUI red 1/s: click 55; prepare total 498; of_sheet 81 + calculation_for 102 in one tick (183); Catalog.build 134
  in one tick. 3-4x vanilla: catalog and snapshot scale with mod prototypes.
- Publish: magenta 1675 (sha256 896, persist x3 393, canonical 149, encode 88, deliver 40); blue 1260 (sha256 489,
  persist x3 524, canonical 89, encode 62, deliver 27). Same shape as vanilla.
- 2.1 per-call publish breakdown for magenta/blue: `logs/cmp-2.1.md` (sha256 653 / 562, persist x3 317 / 462).
