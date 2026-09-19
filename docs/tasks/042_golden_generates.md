# 042 — the corpus runs this candidate, not a file it was handed

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-042`, branch `lane/042`, base = `feat/round-8-blueprints`, tag `recovery-base` (resolve it with `git rev-parse recovery-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Stream D of the recovery plan.

## What is true

**PRESERVE:**
- You own `tests/golden/run`, `tests/golden/add_case`, `tests/golden/accept`, `tests/golden/lib/`, new `tests/golden/generate.lua`, `tests/tools/test_golden_tools.py`, `docs/golden-workflow.md`. Everything else is frozen; if you need a change elsewhere, stop and report.
- `tests/golden/cases/` and `tests/golden/required-matrix.json` belong to stream E. Read them; never edit them.
- `tests/golden/engine/mod/` belongs to stream B. Never touch it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- `tests/golden/lib/runner.py`, in `compare_case`, refuses when no `actual.json` and no `--candidate` is given, so today a case compares two checked-in files. A stored file cannot notice that the generator changed.
- The only case, `tests/golden/cases/basic-canonical/`, points its actual at `candidate.json`.
- `logic/bp/serialize.lua` owns `Serialize.canonical` and `CANONICAL_VERSION`. Comparison is canonical structure at equal canonical version, never the compressed string: equal factories compress to different bytes (GOLD-04).
- `logic/bp/validate.lua` is the independent checker: collisions from collision boxes, beacon reception, flow conservation, simultaneous demand, capacities, wire legality then connectivity, port edges, machine counts.
- `docs/feature-contracts.md` §17.2 fixes `PreparedInput`, and says a captured input and a handwritten fixture are different things that must be labelled differently.

## What to build

1. `tests/golden/generate.lua`: run the **real** Lua generator over a recorded `PreparedInput` and emit the canonical result. No second generator in Python.
2. `tests/golden/run` generates the actual result from this candidate by default, and compares canonically at equal canonical version. A stale or foreign actual file is refused, naming why.
3. Cross-language conformance: a case proving the Python comparison and the Lua canonical digest agree on one structure.
4. Reuse `logic/bp/validate.lua` for the independent assertions rather than counting entities: conservation, simultaneous demand, transport capacity, beacon coverage, power connectivity, grid containment, whichever the case declares. A stored `ok = true` is never proof.
5. `add_case` keeps the original export, the prepared input, the options and the provenance, and marks the case `draft`. Neither `add_case` nor any force flag may overwrite an accepted baseline. A case with an unfilled placeholder is refused.
6. `accept` stays the only path that changes an expectation, and writes a reviewable diff plus provenance. A normal run never rewrites anything.
7. A branch selection that matches zero required cases fails. A case that does not apply to a branch is reported, and can never satisfy another branch's requirement.
8. Failure artifacts: expected and actual canonical JSON, a readable diff, the inputs and provenance, stage diagnostics, timings, and the layout overlay for a production failure.

## What done mean

```checks
{"name": "golden-tooling-tests", "command": "python3 -m unittest discover -s tests/tools -p 'test_golden_tools.py' -t .", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 900}
{"name": "golden-corpus", "command": "sh tests/golden/run --branch 2.0", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 1800}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base recovery-base --manifest docs/tasks/042.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste a tiny-fixture case proving a generator change turns the corpus red.
- `git diff --stat recovery-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `tests/golden/run`
- `tests/golden/add_case`
- `tests/golden/accept`
- `tests/golden/lib/`
- `tests/golden/generate.lua`
- `tests/tools/test_golden_tools.py`
- `docs/golden-workflow.md`

Touch nothing else.

# bound: 2400s

Reviewer ask: after a deliberate change inside the generator, does the corpus go red on its own?
