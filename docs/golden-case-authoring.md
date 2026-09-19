# Golden case authoring

`capture_case.lua` records one named setup through the same sliced calculation,
preparation and blueprint search used by the mod.  It never accepts a golden
baseline.

## Exact command

Run this from the repository root.  The temporary case root keeps the draft
out of the checked-in corpus until a reviewer explicitly chooses what to do
with it:

```sh
tmp=$(mktemp -d) && lua5.2 tests/golden/capture_case.lua tiny-chain --output "$tmp/export.txt" --options "$tmp/options.json" && tests/golden/add_case tiny-chain --export "$tmp/export.txt" --options "$tmp/options.json" --cases "$tmp/cases"
```

Use `lua5.4` in place of `lua5.2` for the other offline interpreter.  The
capture command prints the stopped phase, terminal state, source kind and the
preserved prepared input, and writes the encoded export plus the options file.
The example setup intentionally stops Search at its explicit zero-operation
bound, so it demonstrates a `search` failure without pretending that a layout
was produced.

## Setup descriptions

Files under `tests/golden/setup/` are versioned Lua data descriptions.  A
description carries:

- `schema_version` and a stable `setup_id`;
- `prototype_facts`, including items, recipes, machines, modules and beacons;
  `mocked = true` records that these facts come from the offline harness;
- target rows in UI order;
- the selected recipe, machine, machine modules, beacon groups and beacon
  modules;
- the infrastructure choices and input/output edges; and
- `generation` limits plus `engine_scenario` assumptions for later review.

The setup helper uses existing `tests/harness.lua` world and sheet facilities.
It does not copy calculation or blueprint preparation.  Those are run by the
production sliced jobs.

## Runtime captures

A runtime capture is not made from this offline setup.  It needs a packaged
candidate running in the intended Factorio branch, the active mods and their
versions, the player's research and quality unlocks, the player's selected
recipes and machines, the module/beacon setup, infrastructure choices, and a
player/surface setup matching the engine scenario.  Only a capture with
`source_kind = "runtime"` is engine evidence; a harness capture is labelled
`harness`.

`add_case` keeps the prepared input and provenance in a draft.  A search can
fail after preparation and the capture remains usable; its observed state,
stage and reason codes are recorded separately from the supported outcome.
The command never writes an accepted expectation.

Keep these four facts separate when reviewing a case:

1. the setup description exists and says what was mocked;
2. a prepared capture exists and says where it came from;
3. the result meets independent assertions (for example conservation or
   rates); and
4. engine evidence exists from a packaged runtime capture.

None of the first three facts creates the fourth, and a failed observed search
does not by itself change the supported outcome.
