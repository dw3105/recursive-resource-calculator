# Release preparation

Release preparation is a refusal-only process.  It verifies evidence made by
the packaged candidate; it never starts Factorio and it has no override flag.
The archive passed to the gate must be the same bytes that were tested.

Run the commands in this order from the repository root:

```sh
VERSION=1.1.99
CANDIDATE=$(git rev-parse HEAD)
ARCHIVES=$(mktemp -d)

# Builds both branches from one committed tree.  The output is labelled TEST BUILD.
sh tools/build_test_zip.sh "$CANDIDATE" "$VERSION" "$VERSION" "$ARCHIVES"

# Run the engine companion against each test build, then place each observation at:
# docs/engine-evidence/$CANDIDATE/<2.0-or-2.1>/<case>.observation.json
# The companion's runner instructions are in docs/engine-evidence/README.md.

python3 tools/evidence_receipt.py \
  "docs/engine-evidence/$CANDIDATE/2.0/basic-canonical.observation.json" \
  "$ARCHIVES/RRC-Fork_${VERSION}_factorio-2.0-test.zip" \
  --case basic-canonical --candidate "$CANDIDATE" \
  --environment '{"factorio_branch":"2.0"}' \
  --output "docs/engine-evidence/$CANDIDATE/2.0/basic-canonical.receipt.json"

# Check one branch while collecting evidence.
sh prepare_release.sh "$VERSION" 2.0 \
  --candidate "$CANDIDATE" \
  --archive "$ARCHIVES/RRC-Fork_${VERSION}_factorio-2.0-test.zip"

# Final declaration: both branches, every accepted matrix case, and all timing/rate checks.
sh prepare_release.sh --release --version "$VERSION" \
  --candidate "$CANDIDATE" --archive-dir "$ARCHIVES"
```

`tools/build_test_zip.sh` uses `git archive`, so it does not package uncommitted
source files.  A test zip is useful for collecting evidence but remains a test
build; preparing one does not promote it or make it a release artifact.

The gate reads `tests/golden/required-matrix.json`.  It selects the cases whose
`branches` contain the requested branch, then checks the offline golden,
packaged `logic/build_id.lua`, observation digest, receipt, candidate SHA,
branch, active mods and engine environment.  Production cases additionally
check canonical version/digest, rates, warm-up/sample timing and timeout.

## Frozen observation contract

Observation schema 1 follows the companion's producer shape.  The top-level
`outcome_kind` is `production`, `rejection`, or `export`, and exactly one block
with that name carries the result.  The older top-level `outcome` block remains
accepted as a compatibility synonym.  Production windows are objects with
`warm_up.ticks` and `window.ticks`; the older flat
`warm_up_ticks`/`sampling_window_ticks` names remain accepted as synonyms.

Rates are lower bounds.  For every expected rate, the measured value must be at
least `target - allowed_discrete_error`.  Extra production is valid and is not
a rate mismatch; missing or empty measured-rate data and any expected shortfall
are refusals.

Window and generation values are engine ticks, not wall-clock seconds.  The
scenario `timeout_seconds` bounds generation ticks at 60 ticks per second.  A
separate wall-clock target, when declared as `wall_clock_seconds`, is compared
only with `production.timings.wall_clock_seconds`; a missing measurement never
counts as meeting that target.  Engine tick fields are never used for that
wall-clock comparison.

Refusals are intentionally specific:

- `empty selection`: the requested branch has no matrix cases.
- `absent case`: a selected case has no offline golden manifest/result.
- `draft baseline`: a selected matrix case is not accepted; drafts are never skipped.
- `unsupported schema version`: the matrix, observation, or receipt is not schema 1.
- `missing branch`: the command or evidence does not identify 2.0 or 2.1.
- `missing observation` / `missing receipt`: the required engine evidence pair is incomplete.
- `unexpected rejection`: the engine rejected a case whose matrix outcome is production/export.
- `rates below target`: a measured production rate is below the manifest target and tolerance.
- `invalid timing`: timing is absent, non-finite, over the engine-tick or wall-clock target, or timed out.
- `mismatched archive`: the receipt hash is not the hash of the supplied archive, or its build identity differs.
- `mismatched environment`: the packaged branch, mod version, engine version, or required active mod differs.

The final command must pass for readiness.  There is no force-release path.
