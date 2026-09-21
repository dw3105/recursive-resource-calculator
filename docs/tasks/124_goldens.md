# 124 goldens: report the validation that was actually run

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-124`, branch `lane/124`, base tag `round-14-base` (resolve with `git rev-parse round-14-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 26, rules 26.1, 26.7.
Frozen oracle: `tests/test_blueprint_physical_contract.lua`. Baseline: `docs/round-14-baseline.md`.

`tests/golden/generate.lua:414` short-circuits: whenever `Validate.reconcile_artifact` exists, and it does
(`logic/bp/validate.lua:1741`), `artifact_validation` returns the reconciliation result and the
`Validate.begin` / `Validate.step` path at `generate.lua:419-468` is dead code. That value is reported as
`validation` at `generate.lua:513-518`, and in the `--validate` branch `ok = validation.ok == true`
(`generate.lua:491`).

`Validate.reconcile_artifact` (`validate.lua:1741-1903`) inspects entity directions, machine count, machine
name, quality, recipe, recipe quality and modules, beacon identity and module slots, and wires. It never
inspects a belt, an underground belt, a pipe, a pipe-to-ground, an inserter, a port binding or a segment.
Deleting every belt, pipe and inserter leaves all of those untouched, so it still returns `ok = true`. The
code says so itself at `validate.lua:1804-1806`.

`tools/blueprint_audit.py` decodes a delivered string and re-derives the geometry independently. Measured on
the round 13 delivery, sha256 `9e075dddf2a16485cfa4d24e45b5fc62f2ba6cb04fbc23236ca6b8c78cb3d95a`: 11 invalid
inserters, 12 unpairable pipe-to-ground endpoints, 4 unpairable underground belt endpoints, 224 unused belt
entities, 35 pipe tiles touching no machine, 0 wires against 10 planned.
`tests/tools/test_blueprint_audit.py` qualifies it: 13 cases, control first.

`tests/test_beacon_placement_incident.lua` parses `tests/golden/generate.lua` keyed on the literal
`local input_path,`. That line and the success envelope are frozen text.

PRESERVE: everything under `logic/`, `tests/harness.lua`,
`tests/test_blueprint_physical_contract.lua`, `tests/test_beacon_placement_incident.lua`,
`docs/feature-contracts.md`, `tools/**`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `tests/golden/generate.lua`, `tests/golden/lib/runner.py`, `tests/incident/replay.py`,
`tests/tools/test_golden_tools.py`, `tests/tools/test_incident_capture.py`.

## What to build

Stop returning reconciliation as validation. Run BOTH: drive `Validate.begin` / `Validate.step` to completion,
so the code at `generate.lua:419-468` becomes live again, AND call `reconcile_artifact`. Report both results
under distinct keys, and make `ok` require BOTH. Put the physical result in a local named `physical`; the name
is mandated, because the red proof `validation-reconciliation` binds to it.

Validate the DECODED EXPORTED string per rule 26.7. The serializer's intermediate table is never the certified
object.

Register the round 13 delivery as a known-bad regression that must keep failing, carrying its six measured
counts above. A canonical hash of a broken factory is never accepted as proof.

Keep the case selector in `replay.py`. `--require-success` targets only a fresh complete case; the historical
case keeps its required `BP_CAP_INCOMPLETE` rejection.

Keep structural regression, canonical golden and engine golden as separate layers.

Keep `generate.lua`'s `local input_path,` line and the success envelope in their exact line shape.

## What done means

```
red-proof   sh tools/lane_mutate.sh <scratch> validation-reconciliation, then
            python3 -m unittest tests.tools.test_golden_tools in <scratch>: the named case reports FAIL or
            ERROR under unittest's own categories. A Traceback alone is not the signal; unittest prints one
            for every AssertionError.
focused     sh tools/verify_round9_lane.sh "$PWD" 124_goldens exits 0
both        a case proves ok is false when physical validation fails and reconciliation passes, and false
            when reconciliation fails and physical validation passes
known-bad   a case proves the round 13 delivery still fails, by its measured counts
frozen      tests/test_beacon_placement_incident.lua still passes, so the parsed line shape is intact
```
