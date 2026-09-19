# Golden workflow

Golden cases compare the candidate's own blueprint path. A captured case has a
`prepared_input.json` in the shape frozen by `docs/feature-contracts.md` §17.2.
`tests/golden/run` invokes `tests/golden/generate.lua`, which drives the real
Lua `logic.bp.search` state machine and its `logic/bp/serialize.lua` canonical
form. Python only performs the independent comparison; it never constructs a
candidate blueprint.

The Lua result contains the canonical structure, `canonical_version`, a digest,
the raw result, stage diagnostics and a fresh `logic/bp/validate.lua` receipt.
The Python side checks the canonical structure and digest again. Canonical
versions must match. Compressed blueprint strings are never compared.

## Add a case

Capture the debug export and provide generation options, including the frozen
engine scenario:

```sh
tests/golden/add_case iron-gear --export export.txt --options options.json
```

The tool preserves `export.json` (and the original `export.txt` when supplied),
`options.json`, a captured `prepared_input.json` when the export contains one,
and `provenance.json`. The manifest is marked `state: "draft"` and the
candidate placeholder is intentionally unfilled. A draft or placeholder cannot
satisfy the release corpus; handwritten fixtures are supported only when an
existing manifest explicitly has no captured input.

A captured input and a handwritten fixture are different provenance classes.
The existing small canonical case is the latter because its frozen manifest has
no prepared input; it exercises canonical comparison only. New production
cases should be captured inputs.

`--force` may replace a draft case only. It cannot replace a case with an
accepted expectation, and it never changes an expectation.

## Run and accept

```sh
sh tests/golden/run --branch 2.0
tests/golden/accept iron-gear
```

For a captured case, `run` refuses any checked-in `actual`/`candidate` file as
stale or foreign and generates a fresh result. A normal run never writes an
expectation. On failure it writes expected and actual canonical JSON, a diff,
inputs, provenance, validator/stage diagnostics, timings, and a production
layout overlay under `.golden-failures/`.

Independent assertions are declared in `independent_assertions` (for example
`conservation`, `simultaneous_demand`, `transport_capacity`,
`beacon_coverage`, `power_connectivity`, or `grid_containment`). They are
proved by a fresh call to `logic/bp/validate.lua`; a stored `ok: true` or an
entity count is not proof.

`accept` is the only expectation-changing path. It first runs the same
generation and validation checks, then writes the named expectation and a
reviewable old/new/diff/provenance receipt. Branch selection reports cases that
do not apply, and fails when it has no accepted required case.

Run the fast suite with `sh tests/run.sh`; it does not invoke this corpus or
start a game. Run the corpus during release preparation, with the engine
companion and packaged candidate when in-game evidence is required.
