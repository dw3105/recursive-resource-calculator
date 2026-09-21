# 133 goldens: an acceptance case shaped like the player's own sheet

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-133`, branch `lane/133`, base tag `round-15-base` (resolve with `git rev-parse round-15-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 27, rules 27.4, 27.5.
Frozen census baseline: `docs/round-15-census-baseline.json`.

`tests/acceptance/run` is the delivery gate and has been red since it was written; `tests/run.sh` never
discovers it, which is why the fast tier stayed green through three rounds of a product that did not work.
`tests/acceptance/README.md` states the rules: terminal `state == "success"`, entities and a blueprint
string present, the accepted candidate passed the independent validator and is the one serialized, no stage
stubbed.

Its only item case is `ACC-ITEM`, built by `tests/acceptance/lib/chains.lua:25` `M.item_chain`, whose own
header calls it "the shape of the player's own sheet". It is not. It carries productivity modules in the
machines and speed beacons around them (`chains.lua:23-24`, `:62-68`), and the player's captured sheet
carries **no modules and no beacons** at all: `calculation.columns[*].setup.modules` and `.beacons` are each
the empty-list sentinel and all five effect values are zero. So the delivery gate is strictly harder than the
thing the player asked for, and nothing offline exercises the easy case at all.

The player's sheet: four steps, one target `item/automation-science-pack` at 1/s, solved as
`automation-science-pack` on assembling-machine-3 x4, `copper-plate` on electric-furnace x1.6,
`iron-gear-wheel` on assembling-machine-3 x0.4, `iron-plate` on electric-furnace x3.2; external inputs
`item/copper-ore` 1/s and `item/iron-ore` 2/s. No fluids anywhere.

The factory the player built by hand for that sheet, which the game runs, is
`tests/golden/cases/player-red-science-1s/reference_manual_blueprint.txt`, sha256
`934a0034af3069ef40ee1878582d53b26834d287fa4106c2b4480404f6123c30`: **131 entities** -- 84 transport-belt,
22 inserter, 10 medium-electric-pole, 6 electric-furnace, 5 assembling-machine-3, 4 roboport. Zero
underground belts, zero splitters, zero pipes, zero beacons. Every inserter is belt-to-machine; each of its
11 machines carries exactly 2 inserters, one feeding and one draining, because one inserter reads both lanes
of one belt. `tools/blueprint_audit.py` passes it clean and it runs as control `ACC14` in
`tests/tools/test_blueprint_audit.py`.

`tests/golden/lib/runner.py:605-613` `run_lua_generator` calls `subprocess.run` with **no timeout**, so one
generation that does not terminate hangs the whole corpus run with no diagnosis.

`tests/golden/cases/player-red-science-1s/` is registered in `tests/golden/required-matrix.json` with
`state: "captured"`. `runner.py:1374-1383` refuses a captured case for the release corpus, so it can never
be a pass; `runner.py:1032-1033` refuses `source_kind: "runtime-repaired"`; and the export's own
`provenance.packaged = false` is refused at `runner.py:1034-1039`. Six cases were already `captured` before
this one, so `tests/golden/run` exiting 1 is not new.

Block port ids inside each accepted case's compressed `export.txt` change with spine's step-qualified ids,
even though no external description does. `tests/run.sh` does not run the goldens, so that is churn in the
corpus, never a fast-tier failure.

`tests/tools/test_real_sheet_census.py` exists and drives `census_gate.judge` with hand-built reports, 14
cases. It does not yet drive `tools/real_sheet_census.py` against a real envelope.

PRESERVE: `logic/**`, `tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`,
`tests/test_census_codes_live.lua`, `tests/golden/cases/player-red-science-1s/`,
`docs/round-15-census-baseline.json`, `docs/feature-contracts.md`, `tools/real_sheet_census.py`,
`tools/census_gate.py`, `tools/blueprint_audit.py`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `tests/acceptance/red_science_case.lua` (new), `tests/acceptance/lib/chains.lua`,
`tests/golden/lib/runner.py`, `tests/golden/required-matrix.json`,
`tests/tools/test_real_sheet_census.py`, `tests/golden/cases/` except `player-red-science-1s`.

## What to build

Add `M.red_science_chain(shape)` to `tests/acceptance/lib/chains.lua`: four steps, one target at 1/s, two
external item inputs, **no modules and no beacons**, no fluids. It is the player's sheet shape and nothing
more. Leave `M.item_chain` exactly as it is; it is a harder case and stays.

Add `tests/acceptance/red_science_case.lua` driving it through `Gate.demand_success`, case name
`ACC-RED-SCIENCE`. It is red until the product works, like every other case in that directory, and deleting
its assertion is never the fix.

Give `run_lua_generator` a timeout, with the elapsed seconds and the interpreter named in the `GoldenError`.
A hang must be diagnosable from the message alone.

Extend `tests/tools/test_real_sheet_census.py` to drive `tools/real_sheet_census.py` end to end on a small
case whose census is hand-countable, and on a deliberately broken candidate, so the instrument is qualified
against something whose answer is known before any lane's number is trusted. Add a case asserting that the
export's two PreparedInput copies differ, so nobody silently re-points the case at the top-level copy: after
normalising the `rrc_empty_list` sentinel the two are byte-identical, and the pinned one is
`generation.prepared_input`, which `tests/golden/cases/player-red-science-1s/provenance.json` records.

Re-capture the accepted golden cases whose `export.txt` carries block port ids, and say in the commit which
cases moved and that only the ids moved.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; python3 -m unittest -q tests.tools.test_real_sheet_census >/dev/null 2>&1 || rc=1; sh tools/lane_mutate.sh $S census-code-unused >/dev/null 2>&1 || rc=1; (cd $S && lua5.2 tests/test_census_codes_live.lua 2>&1 | grep -q FAIL) || rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "acceptance-case-exists", "command": "test -f tests/acceptance/red_science_case.lua || { echo 'no acceptance case for the player sheet shape'; exit 1; }; grep -q 'ACC-RED-SCIENCE' tests/acceptance/red_science_case.lua || { echo 'the case does not name itself ACC-RED-SCIENCE'; exit 1; }; grep -q 'demand_success' tests/acceptance/red_science_case.lua || { echo 'the case does not demand a delivered blueprint'; exit 1; }; echo acceptance-case", "expect_exit": 0, "expect_regex": "acceptance-case", "timeout_s": 120}
{"name": "no-beacons-no-modules", "command": "python3 - <<'PY'\nimport re,sys\ns=open('tests/acceptance/lib/chains.lua').read()\nm=re.search(r'function M\\.red_science_chain.*?\\nend\\n', s, re.S)\nif not m: print('red_science_chain is missing'); sys.exit(1)\nbody=m.group(0)\nfor word in ('beacon','module_setups','add_beacon'):\n    if word in body: print('the player sheet shape carries a '+word); sys.exit(1)\nprint('sheet-shape-ok')\nPY", "expect_exit": 0, "expect_regex": "sheet-shape-ok", "timeout_s": 120}
{"name": "generator-timeout", "command": "grep -q 'timeout' tests/golden/lib/runner.py && python3 - <<'PY'\nimport re,sys\ns=open('tests/golden/lib/runner.py').read()\nm=re.search(r'def run_lua_generator.*?\\n\\n', s, re.S)\nif not m or 'timeout' not in m.group(0): print('run_lua_generator still has no timeout'); sys.exit(1)\nprint('generator-timeout-ok')\nPY", "expect_exit": 0, "expect_regex": "generator-timeout-ok", "timeout_s": 120}
{"name": "census-tests", "command": "python3 -m unittest -q tests.tools.test_real_sheet_census 2>&1 | tail -3", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 900}
{"name": "case-frozen", "command": "git diff --quiet round-15-base HEAD -- tests/golden/cases/player-red-science-1s tools/real_sheet_census.py tools/census_gate.py tests/test_census_codes_live.lua docs/round-15-census-baseline.json && echo case-frozen || { echo 'this lane changed the pinned sheet, the census tooling or the baseline'; exit 1; }", "expect_exit": 0, "expect_regex": "case-frozen", "timeout_s": 120}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 133_goldens", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-15-base --manifest docs/tasks/133.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 5400s
