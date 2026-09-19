# Golden workflow

Golden cases are reviewed, deterministic comparisons of the blueprint path.
The comparator canonicalizes the blueprint structure with the rules owned by
`logic/bp/serialize.lua`: entity numbers and translation are normalized, while
directions, module quality, recipes, connections and wires remain meaningful.
Compressed blueprint bytes are never compared.

## Add a case

Capture the debug export and provide generation options, including the frozen
engine scenario:

```sh
tests/golden/add_case iron-gear --export export.txt --options options.json
```

The tool fills versions, targets and setup from the snapshot and creates a
draft `candidate.json`; it does not create an expectation. Reviewers then add
the expected result and the small human-owned fields in `manifest.json`, such
as `expected_outcome`, `engine_scenario.expected_rates`, and any independent
entity-count assertions. A case manifest records at least:

```json
{
  "engine_scenario": {
    "initial_state": {},
    "supply": [],
    "drain": [],
    "warm_up_ticks": 600,
    "sampling_window_ticks": 3600,
    "expected_rates": {"item/example": 1.0},
    "allowed_discrete_error": 0.01,
    "timeout_seconds": 60
  }
}
```

The candidate is a draft until reviewed. A generator or a game capture is not
proof by itself.

## Run and accept

```sh
sh tests/golden/run --branch 2.0
tests/golden/accept iron-gear
```

`run` discovers case directories, compares canonical structures or sorted
reason codes for rejection cases, and checks independent invariants. On a
failure it writes diagnostics under `.golden-failures/` (expected/actual
canonical JSON, a readable diff, candidate string, inputs and timings).

The normal run has no code path that writes `expected*` files. It may write
failure diagnostics, but never rewrites an expectation. Only the explicit
`accept` command replaces one expectation, after independent checks pass, and
it leaves a reviewable old/new/diff/provenance record under the artifact
directory.

Run the fast suite with `sh tests/run.sh`; it does not invoke this corpus or
start a game. Run the corpus during release preparation, with the engine
companion and the packaged candidate when in-game evidence is required.
