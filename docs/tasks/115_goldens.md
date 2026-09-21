# 115 goldens: validate against the real plan, select the real case, fail closed

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-115`, branch `lane/115`, base tag `round-13-base` (resolve with `git rev-parse round-13-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Contract: `docs/feature-contracts.md` section 25, rules 25.5, 25.7.
Registry: `tests/golden/historical-negatives.json`. Baseline: `docs/round-13-baseline.md`.

`tests/golden/generate.lua:382` and `:407` validate with `prepared.plan_result or prepared.plan or {}`. The
captured incident has **neither field**, so external validation receives `{}`, `configured_groups` falls back
to candidate-supplied data at `logic/bp/validate.lua:570-572`, and machine-count checks iterate an empty
`work.steps`.

`tests/incident/replay.py:26` hardcodes `CASE = ROOT/"tests"/"golden"/"cases"/"player-am2-chain"`. There is no
case selector, so `--require-success` can only ever target that one input.

`tests/golden/lib/runner.py:931` discovers every case directory, and `:1289` refuses a `draft` or `captured`
case before any outcome comparison. Measured: `FAIL player-am2-chain: captured case cannot satisfy the release
corpus`, exit 1. `--drafts report` still counts it as a failure.

`tests/golden/required-matrix.json:344` requires `player-am2-chain` as production coverage for `PLAYER-AM2` on
branch 2.0.

`tests.tools.test_golden_tools.GoldenToolsTests.test_receipt_refuses_hash_candidate_case_and_development_build`
is RED at base: its happy-path observation carries none of the three receipt bindings spine now requires, so
`make_receipt` refuses before reaching the assertion. This lane closes it.
`test_accept_generated_case_promotes_reviewed_draft` and `test_accept_changes_only_the_named_expectation` are
red from before round 13 and this lane closes them too.

PRESERVE: every `logic/**` file, `tests/harness.lua`, `tests/test_blueprint_physical_contract.lua`,
`tests/golden/historical-negatives.json`, `tests/golden/required-matrix.json`,
`tests/golden/cases/**` (every fixture and manifest), `docs/feature-contracts.md`, `tools/**`, `info.json`,
`mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `tests/golden/generate.lua`, `tests/golden/lib/runner.py`, `tests/incident/replay.py`,
`tests/tools/test_golden_tools.py`.

**Trap.** `tests/test_beacon_placement_incident.lua` parses `tests/golden/generate.lua` source text, keyed on
the literal `local input_path,` at `generate.lua:349`. That line and the success envelope at `:412-415` are
FROZEN TEXT. Add keys; never reflow those lines.

## What to build

**Fail closed on the plan.** The wrapper obtains the real planning result from the captured input, or from a
verified matching plan artifact. A missing plan FAILS; `{}` is never a fallback. Recompute canonical content
and digest; never trust a supplied `ok` flag or digest string.

**Case selector.** `replay.py` takes an explicit case over a verified registry. `--require-success` targets
ONLY a complete case. A registered historical negative gets its own required-rejection check with its named
code. A missing fresh input FAILS rather than passing by absence.

**Structural mode.** Add an offline structural replay that validates a captured input WITHOUT promoting it to
engine-accepted. It runs the selected case, fails on missing input and on invalid output, and reports engine
status as pending. It must satisfy BOTH: a registered historical negative must reject with its named code,
and a complete case must produce a nonempty physically valid artifact. A single rule of "every captured input
must produce valid output" cannot express that, which is why the registry carries the role.

**Release discovery reads the registry.** `tests/golden/historical-negatives.json` excludes a registered case
from release discovery, and ONLY a registered case. An unregistered missing case still fails, so coverage can
never be dropped by deleting a row. The captured and draft refusal stays in force for every required
production case.

**Reconcile the artifact.** The wrapper decodes the exported artifact and calls
`Validate.reconcile_artifact` (lane 111). A canonical hash of a broken factory is never accepted as proof.

**Receipts.** Observations in this lane's fixtures carry `prepared_input_sha256`, `config_sha256` and
`harness_qualification_id`. `observed_outcome` stays immutable; `current_outcome` stays revision-bound; the
316-entity output and the original failure are retained as regression evidence.

## What integration gates

`tests.tools.test_golden_tools` must be green, including
`test_receipt_refuses_hash_candidate_case_and_development_build`, which is RED at base because its happy-path
observation carries none of the three receipt bindings.

`sh tests/incident/run --case player-am2-chain --require-rejection` must PASS, and
`--case player-am2-chain --require-success` on that same case must FAIL. One command cannot be both, which is
why the selector and the registry role exist.

The red proof replaces the validation plan in `tests/golden/generate.lua` with `{}` and requires a named
plan-related case to fail, with no `ERROR:` lines. Restoring an unrelated whole file is never accepted as
detection.

## What done mean

```checks
{"name": "red-proof", "command": "PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.tools.test_golden_tools 2>&1 | tail -3 | grep -q OK || { echo 'the lane result is not green before its mutation'; exit 1; }; S=$(mktemp -d) || exit 1; git worktree add --detach $S HEAD >/dev/null 2>&1 || exit 1; rc=0; sh tools/lane_mutate.sh $S validation-plan-empty >/dev/null 2>&1 || rc=1; out=$(cd $S && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.tools.test_golden_tools 2>&1); echo $out | grep -q FAILED || rc=1; echo $out | grep -q 'Traceback' && rc=1; git worktree remove --force $S >/dev/null 2>&1; [ $rc -eq 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 1800}
{"name": "golden-tools-green", "command": "PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.tools.test_golden_tools 2>&1 | tail -3 | grep -q OK || { echo 'the lane owned python suite is not green'; exit 1; }; echo golden-tools-green", "expect_exit": 0, "expect_regex": "golden-tools-green", "timeout_s": 1800}
{"name": "no-empty-plan", "command": "grep -qE 'plan_result or prepared[.]plan or' tests/golden/generate.lua && { echo 'the empty-plan fallback survives'; exit 1; }; echo plan-fails-closed", "expect_exit": 0, "expect_regex": "plan-fails-closed", "timeout_s": 120}
{"name": "case-selector", "command": "sh tests/incident/run --case player-am2-chain --require-rejection >/dev/null 2>&1 || { echo 'the historical negative does not reject'; exit 1; }; sh tests/incident/run --case player-am2-chain --require-success >/dev/null 2>&1 && { echo 'require-success passed on the historical negative'; exit 1; }; echo case-selector-ok", "expect_exit": 0, "expect_regex": "case-selector-ok", "timeout_s": 2400}
{"name": "registry-consumed", "command": "grep -q historical-negatives tests/golden/lib/runner.py || { echo 'release discovery never reads the registry'; exit 1; }; echo registry-consumed", "expect_exit": 0, "expect_regex": "registry-consumed", "timeout_s": 120}
{"name": "frozen-text", "command": "grep -qF 'local input_path,' tests/golden/generate.lua || { echo 'the frozen line was reflowed'; exit 1; }; sh tools/lane_rows.sh tests/test_beacon_placement_incident.lua --min-cases 4 --pass BI1,BI2,BI3,BI4 || { echo 'the incident oracle broke'; exit 1; }; echo frozen-text-kept", "expect_exit": 0, "expect_regex": "frozen-text-kept", "timeout_s": 1200}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh $PWD 115_goldens", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-13-base --manifest docs/tasks/115.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 3600s
