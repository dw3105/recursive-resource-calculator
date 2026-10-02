---
name: rrc-code
description: "Working rule for RRC (recursive-resource-calculator, Factorio 2.0 + 2.1 blueprint generator mod): FAST CHECKS = SECONDS ladder (frozen stage input, ckpt save/resume, route snapshot replay, first-stage stop; whole sheet last), golden profiling, lanes run single lua5.2 tests only, headless Factorio only at integrator merge/release, plan format. Read before any diagnosis, measurement, plan or edit in ~/recursive-resource-calculator or ~/wt-rrc-*."
---

**v0.1 - 27 Sep 2026.** File caveman full. Change log in `references/ledger.md`, never here.

**Canonical copy `skills/rrc-code/` in RRC repo.** Live copy `~/.claude/skills/rrc-code` = copy from merged `main`.
Player said 7 times (2026-09-23..27): "did I not asked you to use fast checks whenever possible????". Fast = seconds.

## Fast-check ladder (RC-01) — climb only when step below cannot answer

| # | Question | Tool | Cost (legalcopilot-dev) |
|---|---|---|---|
| 1 | One stage on one frozen input | `lua5.2 tools/capture_stage_input.lua <prepared.json> <out.json> <groups|pack|route|power|validate>` once, then replay `Stage.begin/step` in a test or stdin probe | groups 0.5-1.7 s |
| 2 | Any step of a golden run, from any point | `lua5.2 tools/ckpt.lua list <case>` → `save <case> <at-spec> <out.lua.gz>` → `resume <file> [--until <spec> --save <out>] [--patch f.lua]` | save once, resume seconds |
| 3 | One failed route demand | `lua5.2 tools/route_fail_snapshot.lua <route_input.json> <N|0> <out>` then `tools/route_replay_one.lua <snap[.gz]>` (`PATCH=`, `MAP=1`) | replay 0.05-10 s |
| 3b | Profile one route checkpoint | `lua5.2 tools/route_prof.lua <checkpoint.lua.gz> [--until <at-spec>] [--set coarse|fine|all] [--patch f.lua]` | checkpoint resume time |
| 4 | Try a fix without editing code | in-memory patch: read module source, `gsub` (replacement as function: `%` breaks strings), `package.preload`; for tests `LUA_INIT=@patch.lua lua5.2 tests/<t>.lua` | seconds |
| 5 | First verdict of a stage on a whole sheet | `lua5.2 tools/first_stage.lua <case> <pack|route|validate>` (`DETAIL=1`, `FAST_TIDY=1`) | 7-170 s |
| 6 | Where time goes | `lua5.2 tools/golden_profile.lua <case> <out.json> [--cap S]` → `python3 tools/golden_report.py <dir> <out.html>` | = sheet time |
| 7 | Does sheet build end to end | `tests/golden/generate.lua` — LAST, one run, reason said to player before start | sheet time |
| 2a | Every golden examined (player rule 2026-09-28) | `RRC_SLOW=ckpt-save:<why> lua5.2 tools/ckpt.lua save-all <case> <dir> --output <r.json>`: snapshot per phase + `PROF phase=… worst=… at=<tick>` lines (DoD speed numbers, same run) | = sheet time, once |
| 2b | Validate verdict of one candidate | `VALEXIT=1 lua5.2 tools/ckpt.lua resume <dir>/NNN_…_validate.lua.gz --patch p_valdetail.lua` (REJ + every `E` code) | 20-60 s |
| 2c | Long stage in <120 s chunks | `ckpt.lua resume <snap> --at-tick N --save <out>`; chain chunks; save costs ~15 s CPU | per chunk |
| 2d | Which tidy step breaks flow X | tidy replay patch with only X's improve trials (`FLOWONLY`) + watch cell/binding per `tidy_step` / `Route.step` | 7-50 s |
| 2e | Cost of one stage call | load snapshot, call the module directly (`BeaconPrune.run`, exported `result_for`), `os.clock` | seconds |
| 2f | Layout rules (row flip, seat) | `fast_rundir.lua` 0.3 s; Seat replay on ckpt 0.11 s | < 1 s |

Round 47 probe patches (`p_valdetail`, `p_trunk`, `p_bindwatch`, `p_parts`, `p_vphase`, `walk.lua`, `gate13.sh`,
`bisect_sheet.sh`): `~/.claude/plans/rrc-round-47-probes/`.

- **RC-02** Before any command expected > 60 s: say why no rung below answers; build that rung next. One slow run per
  question, never a second.
- **RC-02b** Enforced since round 47: slow tools refuse without `RRC_SLOW=<slot>:<reason>` (tools/lib/slow_guard.lua,
  budget per wave in tools/slow_budget.json, ledger ~/.cache/rrc/slow_ledger.tsv); Claude hook caps RRC commands at
  `timeout 120`. Goldens in `fast_cases` need no slot. Bisect byte diffs over commits in spare worktrees, one slot.
- **RC-02c** Every run expected > 5 min: say ETA before start, run in background with log-staleness watch (Monitor:
  log mtime older than 5 min = stalled, report at once); never say "running" without log mtime read this turn.
  Player sheet delivers in minutes (RULINGS SIM-MINUTES): long sim = defect to find, never longer window.
- **RC-03** Never pipe progress through `cut`/`sort` (buffers to exit). Log to file, `tail`.
- **RC-04** Stage inputs can lie: diff a capture's catalog against a live one before diagnosing layout
  (am2-chain 2026-09-27: empty inserter offsets → rebuild via `tools/prepared_from_export.py`).
- **RC-05** Never `require "tests.harness"` in tools that run whole sheets (resets `logic.*`, sets game globals).
- **RC-05b** `tools/golden_profile.lua` preloads its own `logic.bp.search`/`logic.bp.route`: `LUA_INIT` patches of those
  modules are ignored under it. Prove a patch is live (marker line) before any run over 60 s.

## Talking to player

- **RC-06** Never ask whether slow is acceptable; speed is part of "works". Never repeat an unanswered ask as a
  standing line; decide small things, state once.
- **RC-07** Every figure carries host or date. Close-out ends `Your move` then `Mine`.

## Plans and lanes

- **RC-08** Plan: caveman full, simple opening + why first try, definition of done, ASCII lanes diagram, blocker
  table with file:line + in-memory proof; whole blocker chain found before lanes.
- **RC-09** Lanes: max 3 at once; single `lua5.2 tests/<file>.lua` only; never suite, never headless, never whole
  sheet except one named delivers test at end. Integrator: merge `git merge --no-ff` with own review, full suite
  once after all merges, fix red singly, suite again, then main + zips + boxes.
- **RC-10** Gentle rule changes: a new ban fires only where build fails today (after restart refused), so passing
  sheets keep bytes; bytes of gated sheets checked vs `tests/fixtures/bytes_round*.txt`.

## Gates and delivery (round 54, player "adopt all" 2026-10-02)

- **RC-11** Gate row not SAME: run that sheet at `main` and at head back to back, same hour, same tool, before calling
  it "known". A commit on `logic/` that claims "no behavior change" gets bytes of fast cases in both pack modes before
  commit. Drawn bytes of `main` kept as baseline file beside layered `tests/fixtures/bytes_round*.txt`.
- **RC-12** Per-check cap is 120 s however spelled: no `TMO=` above 120, no `timeout N true`. Row that times out
  under host load: rerun alone under same cap. Hook `tools/claude_slow_hook.py` refuses both spellings.
- **RC-13** Before any full game run: one sheet per new shape passes in lab first. New shape = any of these not yet
  in a passing lab test: machine type, Turn or Flip pose, fluid ingredient, fluid product, edge feed kind (belt,
  underground, pipe), power reach beyond one pole, Factorio version.
- **RC-14** Delivery report: fresh agent checks every figure against logs (read-only) before push box; its wrong
  and cannot-verify rows fixed or named in report.
- **RC-15** Kill only own processes: PIDs whose `/proc/PID/cwd` is own worktree. Never by command name.
- **RC-16** Push box for player says how to run it on VM: `!` prefix in Claude Code prompt on legalcopilot-dev.

| Reference | Read when |
|---|---|
| `references/ledger.md` | changing this skill |
