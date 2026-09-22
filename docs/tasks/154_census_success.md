# 154 census: the gate counts discarded alternatives, and success discards fewer

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-154`, branch
`lane/154`, base tag `round-18-census-base` (resolve with `git rev-parse round-18-census-base`), merge
target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**The generator now delivers a blueprint**, and the census gate fails BECAUSE it does. Measured 2026-09-22
on this host at `round-18-census-base`:

```
$ python3 tools/census_gate.py --baseline docs/round-16-census-baseline.json --tier full --no-waivers
CENSUS-GATE fail: denominator floor: 1 candidates reached validate, the baseline reached 11; fewer candidates judged is not an improvement
CENSUS-GATE fail: BP_PW_DISCONNECTED rate 0.0909 -> 1.0 (increase, no waiver)
CENSUS-GATE fail: BP_V_INSERTER_GEOMETRY rate 0.4545 -> 26.0 (increase, no waiver)
CENSUS-GATE fail: BP_V_PORT_UNREACHABLE rate 0.4545 -> 30.0 (increase, no waiver)
CENSUS-GATE fail: BP_V_ROUTE_MISSING rate 0.0 -> 4.0 (increase, no waiver)
CENSUS-GATE fail: BP_V_TARGET_SHORTFALL rate 1.0 -> 8.0 (increase, no waiver)
CENSUS-GATE fail: BP_V_TRANSFER_BROKEN rate 0.4545 -> 26.0 (increase, no waiver)
CENSUS-GATE fail tier=full validate_attempts=1 total=121
```

**Total records fell 2862 to 121, and every single rate rose.** That is arithmetic, not a regression.

Why. `tools/real_sheet_census.py:records_of` reads records two ways. A FAILING run reports them under
`errors[].reason_details`. A SUCCEEDING run reports them under `result.discarded_alternatives`, one record
per `reason_codes` entry, keyed by `candidate_id`. `census_of` then counts **distinct `attempt` values** as
`validate_attempts`, so the denominator is **the number of candidates the search THREW AWAY**, never the
number it judged.

The frozen baseline carries `entities_delivered: 0` and `validate_attempts: 11`: eleven candidates, all
rejected, nothing delivered. Today the search discards **1** and keeps the next, so:

- rule 3, the **denominator floor** at `tools/census_gate.py:84-89`, reads 1 < 11 and calls delivery a dodge
- rule 5, **nothing rises** at `tools/census_gate.py:103-116`, divides by 1 instead of 11 and every rate
  jumps by about 11x while the absolute counts collapsed

Both rules were written for a product that always failed. Both are right about that product. **Neither can
tell a delivered artifact apart from "judge fewer candidates", and that is the whole defect.**

Same run, reproduced directly, this host 2026-09-22:

```
$ lua5.2 tests/golden/generate.lua --input <prepared_input with search_budget=40000000> --output result.json
ok=True stage=done ticks=274        validation errors: 0
```

Measured baselines, green, none may regress:

```
python3 -m unittest tests.tools.test_real_sheet_census   Ran 17 tests   OK
python3 -m unittest tests.tools.test_blueprint_audit     Ran 18 tests   OK
sh tools/red_list.sh docs/round-16-red-list.txt          RED-LIST ok 223 identities
```

## Traps, each measured

**Trap: this gate exists to stop exactly the dodge it is now mis-firing on.** Its own docstring says it is
"the gate every round 15 lane shares". Do NOT delete rule 3 and do NOT delete rule 5. A lane that reports
fewer records by judging fewer candidates must still fail, and there must be a test proving it still does.

**Trap: the distinction is DELIVERY, never a count.** A run that delivers an artifact discards fewer
alternatives on purpose; a run that delivers nothing and judges fewer is hiding. The envelope already
carries both facts: `counters.entities_delivered` and the envelope's `ok`/`stage`
(`tools/real_sheet_census.py` writes them, `tools/census_gate.py:78-82` already reads `envelope.stage`).
Use them. **State in the lane report which field you keyed the rule on and why it cannot be faked.**

**Trap: rates are per DISCARDED alternative, so they are not comparable across a delivery boundary at all.**
A baseline measured with `entities_delivered: 0` and a report with `entities_delivered > 0` are two
different denominators. Decide and say plainly whether rule 5 compares absolute counts in that case, or is
skipped with the total-records fall reported instead. **Whichever you choose, a RISE in absolute records
must still fail.** 2862 to 121 must pass; 2862 to 3000 must fail.

**Trap: `--no-waivers` is how the round runs it.** Do not solve this with a waiver; a waiver is an
admission, and this is not one.

**Trap: do NOT re-freeze `docs/round-16-census-baseline.json`.** The spine re-freezes it at the close of
the round, with a note saying what it blesses and what it does not. This lane changes the GATE, never the
baseline. If the gate cannot pass without a new baseline, say exactly that in the lane report and stop.

**Trap: the python tests are `unittest`, not `pytest`.** `python3 -m pytest` reports `No module named
pytest` on this host. Run `python3 -m unittest tests.tools.test_real_sheet_census`. That file drives
`census_gate.judge` with **hand-built reports** rather than by running the generator, so every rule is
exercised alone and a new rule is cheap to test. Keep it that way: do not make it run the generator.

PRESERVE: `logic/**`, `tools/real_sheet_census.py`, `tools/blueprint_audit.py`,
`tools/blueprint_string.py`, `tools/deliver.sh`, `tools/red_list.sh`, `tests/**` except
`tests/tools/test_real_sheet_census.py`, `docs/round-16-census-baseline.json`,
`docs/round-16-red-list.txt`, `docs/feature-contracts.md`, `info.json`, `mod-description.md`,
`.agent-lane.toml`.

## Files this lane owns

`tools/census_gate.py`, `tests/tools/test_real_sheet_census.py`.

**Nothing else.** Lane 151 owns `tools/blueprint_string.py` and `tools/deliver.sh`, lane 153 owns
`tools/blueprint_audit.py`, and the spine owns `logic/bp/route.lua`. Touching any of them loses the merge.

## What to build

1. **Teach `judge` that a delivering run is not a dodging run.** Rules 3 and 5 keep their teeth for a run
   that delivers nothing, and stop punishing a run that delivers something.
2. **Report the fall, never hide it.** When the gate passes a delivering run, the `CENSUS-GATE ok` line
   names the absolute record totals on both sides, so the number that actually moved is on screen. Today
   the failing line already prints `total=121`; the passing line at `tools/census_gate.py:186` does not.
3. **`tests/tools/test_real_sheet_census.py` gains cases, red at base.** At minimum:
   - a delivering report with FEWER discarded alternatives and far fewer absolute records **passes**
   - a report that delivers NOTHING and judges fewer candidates **still fails** the denominator floor
   - a delivering report whose absolute records **rose** still fails
   - a delivering report where a named `require_down` code did not fall still fails

**State plainly in the lane report which rows are red at base**, with each one's exact failure text.

## What done mean

Two checks. A check block takes one `gateslot` lease PER check and hands it back between them, so nine cheap
checks means nine trips to the back of a shared queue. Everything cheap is folded in with `&&`.

```checks
{"name": "census-success", "command": "git diff --name-only round-18-census-base HEAD | grep -v '^docs/tasks/154' | grep -Ev '^(tools/census_gate\\.py|tests/tools/test_real_sheet_census\\.py)$' | ( ! grep . ) && python3 -m unittest tests.tools.test_real_sheet_census 2>&1 | tail -1 | grep -q '^OK' && python3 -m unittest tests.tools.test_blueprint_audit 2>&1 | tail -1 | grep -q '^OK' && git diff round-18-census-base HEAD -- docs/round-16-census-baseline.json | ( ! grep . ) && echo census-success-ok", "expect_exit": 0, "expect_regex": "census-success-ok", "timeout_s": 1200}
{"name": "red-at-base", "command": "set -e; base=$(mktemp -d); git worktree add -q --detach \"$base\" round-18-census-base; cp tests/tools/test_real_sheet_census.py \"$base/tests/tools/test_real_sheet_census.py\"; cd \"$base\"; fail=0; python3 -m unittest tests.tools.test_real_sheet_census 2>&1 | tail -1 | grep -q '^OK' && fail=1 || true; cd - >/dev/null; git worktree remove --force \"$base\"; [ \"$fail\" = 0 ] || { echo 'the new cases are GREEN at round-18-census-base; they prove nothing'; exit 1; }; echo red-at-base-ok", "expect_exit": 0, "expect_regex": "red-at-base-ok", "timeout_s": 900}
```

Re-cut because: none

# bound: 4000s

Reviewer ask: can a lane still pass this gate by judging fewer candidates while delivering nothing, and does
a delivering run whose absolute record count ROSE still fail?
