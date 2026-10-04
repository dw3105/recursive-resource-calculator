# Operator rulings

Standing instructions from operator. One row each, dated. Agents read this file at session start and after compaction; a ruling here outranks skill text until skill text matches.

| Date | Id | Ruling |
|---|---|---|
| 2026-09-23 | lanes-suites | Lanes never run full test suites of any kind, only individual tests (`lua5.2 tests/<file>.lua`). Integrator runs `sh tests/run.sh` once after all lanes merge. |
| 2026-09-28 | RRC-04 | Fast checks by default: default check = affected test files only. Full suite and headless Factorio only before delivery. Operator typed "use fast checks" 7 times in one session; this row replaces retyping. |
| 2026-09-28 | HO-05 | Headless Factorio on host: `~/factorio-2.0/factorio/bin/x64`, `~/factorio-2.1/factorio/bin/x64`. Game load test runs at integrator merge and release, never in a lane. |
| 2026-09-29 | PUB | No push from VM. Publish = zips in `~/share/RRC` + operator box; player pushes `main` + tags and uploads portal. Re-read `git ls-remote origin` before re-issuing any push box. |
| 2026-09-29 | SIM-MINUTES | Player sheet starts delivering in minutes in game. Sim or search running longer than minutes = defect to find (research, fuel, power), never a longer window. Every background run > 5 min gets log-staleness watch. |
| 2026-09-30 | LUA52 | Lua 5.2 only, everywhere: Factorio runs Lua 5.2. No lua5.4 in suite, tools, lane checks or reports (player 2026-09-23, again 2026-09-29: "DROP Lua 5.4 TESTS - FACTORIO NOT USING IT"). tests/run.sh and tools are 5.2-only since round 50. |
| 2026-10-01 | BLOCKED-PORT | Turn or Flip is invalid only when a fluid input/output used by the recipe is blocked by another machine ("blocked by machine == unfixable"): refuse with `BP_FAIL_FLUID_PORT_BLOCKED`. Blocked by belt, pipe with different liquid, electric pole = fixable by rerouting or moving poles: generator owes the fix, never a refusal. |
| 2026-10-02 | GATE-MAIN | Gate row not SAME is never "known" until that sheet ran at `main` and at head back to back, same hour, same tool. Logic commit claiming "no behavior change" gets fast-case bytes in both pack modes before commit (rrc-code RC-11). |
| 2026-10-02 | CAP-120 | Per-check cap 120 s however spelled: no `TMO=` above 120, no `timeout N true`; timed-out row reruns alone under same cap (RC-12, hook refuses). |
| 2026-10-02 | LAB-SHAPE | Before full game run, one sheet per new shape (machine type, Turn/Flip pose, fluid ingredient or product, edge feed kind, far power, Factorio version) passes in lab (RC-13). |
| 2026-10-02 | REPORT-REVIEW | Delivery report figures checked by fresh agent against logs before push box (RC-14). |
| 2026-10-02 | KILL-OWN | Kill only own processes, found by `/proc/PID/cwd` == own worktree; never by command name (RC-15). |
| 2026-10-02 | BOX-VM | Push box says how to run it on VM: `!` prefix in Claude Code prompt on legalcopilot-dev (RC-16). |
| 2026-10-03 | TURN-TRIALS-OFF | Turn trials ship off by default (player Q11 a): on only with `RRC_TURN_TRIALS=1` (offline) or `settings.turn_trials = true`. A pass that spends generation time must not run by default unless it wins on most sheets (valid > fast > frugal). |
| 2026-10-03 | SUITE-FLOW | Lanes run single tests only. Integrator: all lanes merged -> full suite -> fix each red test singly -> full suite again -> repeat until green -> main + zips + push box. Plans: caveman full, very simple opening on why it works first try, Definition of done right after, maximum lane parallelism without needless lanes. |
| 2026-10-04 | GATE-MAIN amended | A gate row not SAME ships only as an Accepted DIFF (CONTEXT.md): speed row faster or Speed tie vs `main` back to back, proof per ticket 05 (lane: validate + `lane_sim.py` bleed=0; integrator, layered: Sheet sim 2.0 player profile >= 0.95 x rate + Parity row; magenta parity owed while in-game generation > 120 s cap; drawn: offline only), sha written by `tools/bytes_baseline.py`, which refuses a DIFF row with no proof line. Integrator cuts baseline once per round after all proofs. |
| 2026-10-04 | FAST-FIRST | Round 56: OPS_PER_TICK 4000, every spike sliced, worst tick <= 50 ms by Tick cost (ADR 0003); 16 ms per tick stays a later goal. |
| 2026-10-04 | LANES-ALL-AT-ONCE | Plan and every lane task carry a clear Definition of done. Maximum Codex lane parallelism without needless lanes: lanes with disjoint files and frozen seams launch at once (round 56: 8), over RC-09 cap of 3. Lanes run individual tests only, never a full suite of any kind. |
