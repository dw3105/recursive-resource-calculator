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

- **RC-02** Before any command expected > 60 s: say why no rung below answers; build that rung next. One slow run per
  question, never a second.
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

| Reference | Read when |
|---|---|
| `references/ledger.md` | changing this skill |
