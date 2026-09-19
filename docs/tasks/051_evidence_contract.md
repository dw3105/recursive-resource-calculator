# 051 — The release gate reads what the companion writes, and surplus is never a failure

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-051`, branch `lane/051`, base = `feat/round-8-blueprints`, tag `unblock-base` (resolve it with `git rev-parse unblock-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `tools/release_gate.py`, `tests/tools/test_release_gate.py`, new `tests/tools/test_evidence_contract.py` and `docs/release-preparation.md`. Everything else is frozen.
- Lane 050 owns `tests/golden/engine/mod/`. Read it; never edit it. Lane 052 owns `tests/golden/add_case` and `tests/golden/lib/common.py`. Never touch them.
- Every existing case stays. You add; you never weaken, skip or delete one. An asynchronous path gains bounded ticks, never fewer assertions.
- `require` runs only while `control.lua` is parsed. Never call it inside a function; `tests/test_no_runtime_require.lua` fails the suite on an indented `require`. Use `logic/registry.lua` for a late edge.
- `prototypes`, `game`, `settings` and prototype lists are **userdata**; ask `rawget(_G, "prototypes")`.
- Nothing in `storage` may be a function, a metatable or a LuaObject.
- The coordinator owns `tests/harness.lua`, `tests/run.sh`, `control.lua`, `gui/sheet.lua`, locale files, `docs/feature-contracts.md`, `docs/engine-evidence/examples/`, task files, the corpus matrix and every merge. Need one of them changed? Send the exact small request and carry on with your other work.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**When something outside your files breaks:** record the first failing stage, the immutable input and a bounded
reproducer, and say so in your report at once. Never edit an unowned file and never weaken the positive
assertion. Continue every owned implementation and focused test that does not need that fix. Checkpoint your work
before you end. Report component completion and integration blockage as two separate things: a blocked
integration gate is never an overall PASS.

Current facts, reproduced on this base:
- The companion writes `observation.outcome_kind = "production"` and puts the outcome in `observation.production` (`tests/golden/engine/mod/scenario.lua:324-326`). `tools/release_gate.py:152-156` reads `observation.outcome`, else the whole observation, so it never finds `rates` and raises `rates below target: ... has no measured rates`.
- `tools/release_gate.py:329-332` raises `rates mismatch` when a measured rate is above target plus tolerance. A factory that makes more than asked is correct, and this check refuses it.
- `tools/release_gate.py:358` demands flat `warm_up_ticks` and `sampling_window_ticks`; the companion writes `warm_up = {ticks, start_tick, end_tick}` and `window = {ticks, start_tick, end_tick}` (`tests/golden/engine/mod/scenario.lua:318-320`) and repeats `warm_up_ticks` and `sampling_ticks` inside `timings`.
- Today's `tests/tools/test_release_gate.py` builds the gate's preferred shape by hand, and the scenario tests use a fake adapter, so no test drives the real producer's bytes into the real consumer.
- `docs/feature-contracts.md` §21 freezes the producer's shape as the contract, and `docs/engine-evidence/examples/` holds one synthetic example per outcome kind.

## What to build

1. Add the failing tests first, built from `docs/engine-evidence/examples/*.json`, then change the gate.
2. The gate reads `observation[observation.outcome_kind]`, keeps `observation.outcome` as a synonym, and reads windows as `warm_up.ticks` and `window.ticks`, with the flat names kept as synonyms.
3. Rates become a lower bound: every expected rate must be met within the declared discrete error, and surplus passes. A shortfall fails with the rate and the target in the message.
4. Engine ticks are simulation time. A wall-clock target is checked only against `timings.wall_clock_seconds`; a missing measurement fails rather than counting as met.
5. `tests/tools/test_evidence_contract.py` drives the real scenario controller with a synthetic adapter, writes its emitted JSON to a temporary directory, and passes it through the real receipt and gate path. Its output is labelled synthetic and is never filed as engine evidence.
6. Required cases: surplus passes; a shortfall fails; every simultaneous target must meet its own lower bound; missing or empty rate data fails; a missing or invalid window fails; missing 2.1 evidence blocks release readiness; a canonical digest or archive mismatch fails; a draft required case still fails.
7. `docs/release-preparation.md` states the frozen observation shape, the lower-bound rule and the tick-versus-wall-clock rule.

## What done mean

```checks
{"name": "gate-tests", "command": "python3 -m unittest discover -s tests/tools -p 'test_*.py' -t .", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 900}
{"name": "corpus-unchanged", "command": "sh tests/golden/run --branch 2.0 --drafts report; test $? -eq 1 && echo drafts-nonzero", "expect_exit": 0, "expect_regex": "drafts-nonzero", "timeout_s": 900}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base unblock-base --manifest docs/tasks/051.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the producer-shaped observation refused before your change, with the exact message, and accepted after.
- `git diff --stat unblock-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `tools/release_gate.py`
- `tests/tools/test_release_gate.py`
- `tests/tools/test_evidence_contract.py`
- `docs/release-preparation.md`

Touch nothing else.

# bound: 1800s

Reviewer ask: does one test carry the companion's own bytes into the gate?
