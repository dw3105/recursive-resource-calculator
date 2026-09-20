# 098 golden runner truth: enforce every pair, refuse a capped case, and let one case be accepted

## What is true

Base tag `round-11-base`. Contract: `docs/feature-contracts.md` section 24, rule 24.7.

Three defects, each measured on this tree.

**One. Branch readiness counts, it does not enforce.** `tests/golden/lib/runner.py` `check_branch_requirements`
filters the matrix to rows whose `state` is `accepted`, finds matching discovered cases, and fails only when
the count is zero. Deleting a required case directory is therefore invisible as long as one other accepted case
survives. `tools/release_gate.py` selects on `branches` alone and ignores `state` at selection, refusing later
per case. Two readers, two rules, one matrix.

**Two. Production cases are captured with the search capped.** All five captured setups bake a `search_budget`
of 2500 to 3000 into `tests/golden/setup/*`. A case that carries its own cap measures the cap, never the
generator. Current census, measured:

```
sh tests/golden/run --branch 2.0 --drafts report
golden: 1 passed, 0 failed, 15 drafts, 6 captured      exit 1
```

**Three. A captured case cannot be accepted at all.** `tests/golden/accept` lines 12 and 14 run
`exec python3 "$root/run" ...`, and `tests/golden/run` is a `#!/bin/sh` script, so Python meets `set -eu` and
raises a SyntaxError. Behind that, the runner refuses `draft` and `captured` state BEFORE the accept branch can
be reached, so fixing the wrapper alone changes nothing.

**Trap.** `tests/golden/setup/tiny-chain.lua:58` keeps `search_budget = 0`. It is a tool fixture for
`tests/test_case_capture.lua`, it is NOT in the matrix, and `docs/golden-case-authoring.md` records that
carve-out. It stays allowed by name.

**Trap.** Branch readiness runs before acceptance, and the wrapper passes no `--branch`. Accepting ONE captured
case must work while other required cases stay captured or draft. Whole-branch readiness is a separate release
obligation, never a precondition for intake. A change that makes intake wait for a green corpus makes the
corpus unfillable.

**Trap.** `tests/golden/lib/runner.py` refuses a stale or foreign `actual` file when a case has a captured
PreparedInput. That refusal stays.

**Trap.** The matrix now holds 22 rows: 1 accepted, 6 captured, 15 draft. `player-am2-chain` is captured from
the player's own running game and its manifest `source_kind` is `engine`, which `tests/tools/test_golden_matrix.py`
reads to pick its coverage phrase. Do not retype either as harness.

PRESERVE: every `logic/**` file, `tests/harness.lua`, `tests/golden/cases/**`, `tools/handoff.sh`,
`tools/release_gate.py`, `prepare_release.sh`, `info.json`, `mod-description.md`.

Files this lane owns: `tests/golden/lib/runner.py`, `tests/golden/accept`, `tests/golden/required-matrix.json`,
`tests/golden/setup/*`, `tests/tools/test_capture_workflow.py`, `docs/golden-case-authoring.md`.

## What to build

1. One shared matrix reader, used by both gates, enforcing every required (case, branch) pair: a missing or
   deleted required directory fails and names the pair.
2. A default-configuration refusal: a production case carrying `search_budget`, `max_ops`, `max_search_grids`
   or `max_grid_trials` is refused. `tiny-chain` stays allowed by name.
3. `tests/golden/accept` runs, and the runner reaches its accept branch for a captured case with bound
   evidence. Acceptance writes manifest, expectation and matrix together or not at all.

## What done mean

```
red-proof   git checkout round-11-base -- tests/golden/lib/runner.py
            python3 -m unittest -v tests.tools.test_capture_workflow
            emits ^FAIL: <your named case>, zero ^ERROR:, and ^FAILED \(failures=[1-9]
pairs       deleting a required case directory fails the branch check and names the pair; a matrix row with
            no directory fails the same way
default     a production case carrying search_budget is refused by name; tiny-chain stays allowed
accept      sh tests/golden/accept <case> runs python on the runner, never on a shell script; a captured case
            with bound evidence reaches accepted while other required cases remain draft or captured;
            without evidence it never reaches accepted; an interrupted acceptance leaves no partial write
census      sh tests/golden/run --branch 2.0 --drafts report still reports the real census and exit 1;
            the number of drafts and captured cases is unchanged by this lane
focused     sh tools/verify_round9_lane.sh "$PWD" 098_golden_truth
```

No case state is advanced to make any check pass.
