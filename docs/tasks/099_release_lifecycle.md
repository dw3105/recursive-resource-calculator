# 099 release lifecycle: a red corpus refuses, a branch means itself, a promotion never rebuilds

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-099`, branch `lane/099`, base tag `round-11-base` (resolve with `git rev-parse round-11-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Base tag `round-11-base`. Contract: `docs/feature-contracts.md` section 24, rule 24.7.

`tools/handoff.sh` cannot fail on the golden corpus, and says `pass` while it is red.

- It passes `false` as the gating argument for the corpus check, so a failure is rewritten to
  `status=informational` instead of refusing.
- The record's top-level `result` is `pass` unless `OVERALL_FAILURE` was set, and only gating checks set it.
- The corpus command hardcodes `--branch 2.0` even when the branch under handoff is `2.1`.
- Every informational row is flattened into the record under one literal name, `golden-corpus-status`,
  discarding the real check name and its branch.
- The archive is rebuilt unconditionally, while `prepare_release.sh:8-9` already accepts `--archive`,
  `--archive-dir` and `--candidate`.

`tools/release_gate.py` already refuses a draft or captured case, already requires an archive whose embedded
build id matches the candidate sha and branch, and already requires an observation and a receipt per case. It
is not yet a prerequisite of any verdict: nothing calls it before writing one.

Two archive transitions exist and stay distinct.

```
diagnostic handoff   export checks pass, build identity recorded, every current blocker listed
                     verdict is always unverified_internal, and can never become verified
verified promotion   mandatory golden run AND tools/release_gate.py against an existing archive
                     and bound engine evidence
```

**Trap.** `--diagnostic` must keep working with a red corpus. That archive is how engine evidence gets
collected in the first place, so requiring evidence to produce it is circular. It records blockers and stamps
`unverified_internal`, and this lane does not change that.

**Trap.** The corpus is red by design on this host: 22 rows, 1 accepted, 6 captured, 15 draft, exit 1. Gating
it means a non-diagnostic handoff REFUSES, not that the corpus is expected to pass.

**Trap.** `tests/tools/test_handoff.py` scrubs ambient `RRC_HANDOFF_KEEP_ARCHIVES` from its fixture
environment. A test that writes into the operator's handover directory has already happened once. Keep the
scrub.

PRESERVE: every `logic/**` file, `tests/harness.lua`, `tests/golden/**`, `info.json`, `mod-description.md`.

Files this lane owns: `tools/handoff.sh`, `tools/release_gate.py`, `prepare_release.sh`,
`tests/tools/test_handoff.py`, `docs/handoff.md`.

Lane 098 owns `tests/golden/lib/runner.py` and `tests/golden/required-matrix.json`. This lane reads the matrix
and never writes it.

## What to build

1. Corpus gating replaces the informational escape for a non-diagnostic run. A red corpus refuses, and the
   record never says `pass`.
2. `--branch "$branch"` replaces the hardcoded value, and each check keeps its own name and branch in the
   record. Logs survive cleanup.
3. Promotion accepts an EXISTING archive and never rebuilds. `tools/release_gate.py` exit 0 becomes a
   prerequisite of a `verified` verdict.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-11-base -- tools/handoff.sh || exit 1; if out=$(cd \"$S\" && python3 -m unittest -v tests.tools.test_handoff 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL: test_a_red_corpus_refuses_a_non_diagnostic_handoff' || { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE '^ERROR:' && { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE '^FAILED \\(failures=[1-9]' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 900}
{"name": "diagnostic-still-survives-a-red-corpus", "command": "grep -q 'unverified_internal' tools/handoff.sh || { echo 'the diagnostic verdict was lost'; exit 1; }; echo diagnostic-kept", "expect_exit": 0, "expect_regex": "diagnostic-kept", "timeout_s": 60}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 099_release_lifecycle", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-11-base --manifest docs/tasks/099.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

```
red-proof   git checkout round-11-base -- tools/handoff.sh
            python3 -m unittest -v tests.tools.test_handoff
            emits ^FAIL: <your named case>, zero ^ERROR:, and ^FAILED \(failures=[1-9]
gating      a non-diagnostic handoff with a red corpus refuses; its record never says pass
branch      a 2.1 handoff runs the 2.1 corpus; each check keeps its own name and branch in the record;
            no row is flattened under a single literal name
promote     promotion given an existing archive never rebuilds; a verified verdict without
            tools/release_gate.py exit 0 is refused
diagnostic  --diagnostic with a red corpus still exits 0, lists every blocker, and writes
            verdict "unverified_internal"; it never writes verified whatever else passes
never       no test writes into the operator's handover directory; the ambient-env scrub stays
focused     sh tools/verify_round9_lane.sh "$PWD" 099_release_lifecycle
```

Your own tests must include, in `tests/tools/test_handoff.py`, by these exact case names. The red proof greps for `test_a_red_corpus_refuses_a_non_diagnostic_handoff`, so a different spelling fails the launch rather than the work.

- `test_a_red_corpus_refuses_a_non_diagnostic_handoff`
- `test_a_handoff_runs_the_corpus_for_its_own_branch`
- `test_promotion_accepts_an_existing_archive_and_never_rebuilds`
- `test_a_diagnostic_run_survives_a_red_corpus_and_stays_unverified_internal`

# bound: 3600s
