# 143 audit: the delivered bytes report every family, and judge against the player's 127

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-143`, branch
`lane/143`, base tag `round-16-wave2` (resolve with `git rev-parse round-16-wave2`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 28, rule **28.6**, which says "Every count is reported".
Ledger: `docs/round-16-baseline.md`. Frozen red list: `docs/round-16-red-list.txt`.
Frozen census baseline: `docs/round-16-census-baseline.json`.

The player's own factory for this sheet is `~/share/RRC/red_science_1s_manual_bp.txt`, sha256
`934a0034af3069ef40ee1878582d53b26834d287fa4106c2b4480404f6123c30`. Decoded from those bytes 2026-09-22 on
this host: **84** `transport-belt`, **22** `inserter`, **10** `medium-electric-pole`, **6**
`electric-furnace`, **5** `assembling-machine-3`, **4** `roboport`, **12** wires, **131** entities, and
**0** underground, **0** splitter, **0** pipe, **0** beacon.

Roboport power is declined on the player's own instruction. So the delivery target is the other **127**, and
the roboport line is reported as **excluded**, never silently dropped.

`tools/blueprint_audit.py` already decodes those bytes correctly. Measured on this host 2026-09-22,
`python3 tools/blueprint_audit.py ~/share/RRC/red_science_1s_manual_bp.txt -q` prints:

```
  entities                 131
  inferred_terminals       11
  invalid_inserters        0
  redundant_beacons        0
  unpairable_pipe_to_ground 0
  unpairable_underground   0
  unpairable_underground_belt 0
  unused_belt_tiles        0
  unused_pipe_tiles        0
  wires                    12
```

**No line in that output names a family.** The `counts` dict is built at
`tools/blueprint_audit.py:381-392` and carries only totals and violations. A reader cannot tell 84 belts from
84 inserters, and cannot tell that this factory carries **0 splitter**. Round 16 decided its geometry on the
zero-splitter fact, and today no tool prints it.

Existing pieces this lane reuses rather than rebuilds:

- `load_entities` at `tools/blueprint_audit.py` reads both a blueprint string file and generator JSON, and
  returns `(entities, wires, label)`. Already correct. Call it.
- `BELTS`, `UG_BELTS` at `:51`, `SPLITTERS` at `:52`, `UG_PIPES`, and the machine size map at `:41` already
  name the families. Use these sets; never hardcode a new list beside them.
- `main` at `:359-418` parses `--json`, `-q/--quiet`, `--expect-wires` and `--beacon-config`, prints
  `counts` sorted, then the violation groups, and returns `1` when any group is non-empty. Keep that shape.
- Python tests for this tool live at `tests/tools/test_blueprint_audit.py` and run under
  `python3 -m unittest discover -s tests/tools -p 'test_*.py' -t .`, which `tests/run.sh:12` invokes.

Trap: `--expect-wires` at `:415-417` increments `failed` **after** printing, and returns `1`. A new judge
must follow that same shape: print every count first, then fail. A judge that exits before printing makes the
delivery unreadable exactly when it is wrong.

Trap: `counts` is printed sorted by key at `:402-403` and also dumped as JSON at `:399`. Anything added to
`counts` lands in both. A separate ad-hoc `print` that bypasses `counts` will be invisible to `--json` and to
every caller that parses it.

PRESERVE: `logic/**`, `tests/test_*.lua`, `tests/harness.lua`, `tests/golden/cases/player-red-science-1s/`,
`tools/census_gate.py`, `tools/real_sheet_census.py`, `tools/red_list.sh`, `tools/route_chain_probe.sh`,
`tools/route_chain_report.py`, `tools/ceiling.sh`, `docs/round-16-census-baseline.json`,
`docs/round-16-red-list.txt`, `docs/feature-contracts.md`, `info.json`, `mod-description.md`,
`.agent-lane.toml`.

Files this lane owns: `tools/blueprint_audit.py`, `tests/tools/test_blueprint_audit.py`.

## What to build

**S1. A per-family census in `counts`.** Add one key per delivered family, from the sets already at
`tools/blueprint_audit.py:41-59`: `belts`, `undergrounds`, `splitters`, `inserters`, `machines`, `poles`,
`pipes`, `beacons`, `roboports`, and `entities_excluding_roboports`. Every key appears **always**, including
when its value is `0`, because a zero that is never printed is a zero nobody can cite. Family membership is
decided by the existing sets; a name in none of them is counted under a new `other` key rather than dropped.

Prove it on the player's bytes: `belts` 84, `inserters` 22, `poles` 10, `machines` 11, `roboports` 4,
`splitters` 0, `undergrounds` 0, `pipes` 0, `beacons` 0, `entities` 131,
`entities_excluding_roboports` 127.

**S2. A target judge, `--expect-target`.** New flag taking a JSON file that pins expected counts, for example
`{"entities_excluding_roboports": 127, "inserters": 22, "machines": 11, "splitters": 0, "undergrounds": 0,
"belts": {"min": 84, "max": 126}}`. A scalar pins exactly; an object with `min` and `max` pins a window.
Every mismatch prints one line naming the key, the delivered value and the expectation, and then the tool
returns `1`, following `--expect-wires`'s shape at `:415-417`: **print all counts first, fail after**.

Ship the player's own target as a file this lane owns, `docs/round-16-delivery-target.json`, carrying the
window `belts` 84 to 126 and the exact `inserters` 22, `machines` 11, `splitters` 0, `undergrounds` 0,
`entities_excluding_roboports` 127. Its note says roboports are excluded on the player's instruction.

**S3. The excluded line is reported, never dropped.** The human output prints one explicit line, in words,
that roboport entities are excluded from `entities_excluding_roboports` and how many were excluded. 28.6
says every count is reported; an exclusion is a count.

## What done mean

```checks
{"name": "red-proof", "command": "git stash list >/dev/null; python3 - <<'PY'\nimport json,subprocess,sys,tempfile,pathlib\nt=pathlib.Path(tempfile.mkdtemp())/'target.json'\nt.write_text(json.dumps({'splitters': 99}))\nr=subprocess.run([sys.executable,'tools/blueprint_audit.py','/home/dev_zaigraev_gmail_com/share/RRC/red_science_1s_manual_bp.txt','--expect-target',str(t),'-q'],capture_output=True,text=True)\nassert r.returncode==1, 'a wrong target must fail: '+r.stdout+r.stderr\nassert 'splitters' in (r.stdout+r.stderr), 'the failure must name the key'\nassert 'entities' in r.stdout, 'every count must print BEFORE the judge fails'\nprint('red-proof-ok')\nPY", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "player-census", "command": "python3 tools/blueprint_audit.py /home/dev_zaigraev_gmail_com/share/RRC/red_science_1s_manual_bp.txt --json | python3 -c \"import json,sys; c=json.load(sys.stdin); exp={'entities':131,'belts':84,'inserters':22,'poles':10,'machines':11,'roboports':4,'splitters':0,'undergrounds':0,'pipes':0,'beacons':0,'entities_excluding_roboports':127,'wires':12}; bad=[(k,c.get(k),v) for k,v in exp.items() if c.get(k)!=v]; print('MISMATCH',bad) or sys.exit(1) if bad else print('player-census-ok')\"", "expect_exit": 0, "expect_regex": "player-census-ok", "timeout_s": 600}
{"name": "player-passes-target", "command": "python3 tools/blueprint_audit.py /home/dev_zaigraev_gmail_com/share/RRC/red_science_1s_manual_bp.txt --expect-target docs/round-16-delivery-target.json -q && echo player-passes-target", "expect_exit": 0, "expect_regex": "player-passes-target", "timeout_s": 600}
{"name": "roboport-line", "command": "python3 tools/blueprint_audit.py /home/dev_zaigraev_gmail_com/share/RRC/red_science_1s_manual_bp.txt | grep -qi 'roboport' && python3 tools/blueprint_audit.py /home/dev_zaigraev_gmail_com/share/RRC/red_science_1s_manual_bp.txt | grep -qi 'exclud' && echo roboport-line-ok", "expect_exit": 0, "expect_regex": "roboport-line-ok", "timeout_s": 600}
{"name": "tool-tests", "command": "python3 -m unittest discover -s tests/tools -p 'test_*.py' -t . 2>&1 | tail -3 | grep -q OK && echo tool-tests-ok", "expect_exit": 0, "expect_regex": "tool-tests-ok", "timeout_s": 1800}
{"name": "suite-untouched", "command": "git diff --quiet round-16-wave2 HEAD -- logic tests/test_route.lua tests/harness.lua tools/census_gate.py tools/red_list.sh docs/round-16-census-baseline.json docs/round-16-red-list.txt docs/feature-contracts.md && echo suite-untouched || { echo 'this lane changed logic, the census tooling, the red list or the contract'; exit 1; }", "expect_exit": 0, "expect_regex": "suite-untouched", "timeout_s": 120}
{"name": "no-new-red", "command": "sh tools/red_list.sh docs/round-16-red-list.txt", "expect_exit": 0, "expect_regex": "RED-LIST ok", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-16-wave2 --manifest docs/tasks/143.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
