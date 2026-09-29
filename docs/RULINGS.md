# Operator rulings

Standing instructions from operator. One row each, dated. Agents read this file at session start and after compaction; a ruling here outranks skill text until skill text matches.

| Date | Id | Ruling |
|---|---|---|
| 2026-09-23 | lanes-suites | Lanes never run full test suites of any kind, only individual tests (`lua5.2 tests/<file>.lua`). Integrator runs `sh tests/run.sh` once after all lanes merge. |
| 2026-09-28 | RRC-04 | Fast checks by default: default check = affected test files only. Full suite and headless Factorio only before delivery. Operator typed "use fast checks" 7 times in one session; this row replaces retyping. |
| 2026-09-28 | HO-05 | Headless Factorio on host: `~/factorio-2.0/factorio/bin/x64`, `~/factorio-2.1/factorio/bin/x64`. Game load test runs at integrator merge and release, never in a lane. |
| 2026-09-29 | PUB | No push from VM. Publish = zips in `~/share/RRC` + operator box; player pushes `main` + tags and uploads portal. Re-read `git ls-remote origin` before re-issuing any push box. |
| 2026-09-29 | SIM-MINUTES | Player sheet starts delivering in minutes in game. Sim or search running longer than minutes = defect to find (research, fuel, power), never a longer window. Every background run > 5 min gets log-staleness watch. |
