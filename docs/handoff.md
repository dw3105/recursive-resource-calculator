# Handoff records

`sh tools/handoff.sh <sha> <2.0 version> <2.1 version>` is the refusal-only
last local step before a test archive is handed to a player. It builds both
archives from the requested commit, extracts each archive, adds the requested
commit's `tests/`, `tools/`, and supporting `docs/` with `git archive`, and runs
the gates from those extracted roots. It never uses tests or production Lua
from the live checkout.

`sh tools/handoff.sh --diagnostic <sha> <2.0 version> <2.1 version>` is the
diagnostic transition. It runs `tests/test_export_completeness.lua` for each
archive. Export failure refuses the handoff. Release gates, including an
unfinished or failing golden corpus, are recorded as named blockers with their
exit status and do not by themselves refuse the diagnostic archive. A
diagnostic receipt has `mode: "diagnostic"`, a `blockers` array, and
`verdict: "unverified_internal"` on every archive; it can never contain a
`verified` verdict. The receipt records the resolved candidate SHA and the
SHA-256 of the exact archive bytes copied to `RRC_HANDOFF_KEEP_ARCHIVES`.

Neither the ordinary mode nor diagnostic mode means that the blueprint
generator works. A diagnostic archive is evidence-collection input, not a
blueprint-generator verification.

The command refuses an already narrowed `RRC_SHAPES` or `LUAS` environment,
then supplies the full `2.0,2.1` and `lua5.2 lua5.4` values to every child. It
also gives Lua an extracted-root-only module path and refuses a module resolved
outside that root. The expected case census is made by loading the candidate
test files with their test bodies replaced by a counter; a missing summary or a
different count is a refusal.

The gating set is run once for each extracted branch package:

* `sh tests/run.sh`
* `sh tests/acceptance/run`
* `lua5.2 tests/test_quality_policy.lua`
* `sh tests/golden/run --branch <branch> --drafts report`

The corpus receives the extracted package's own branch. Its non-zero status
refuses an ordinary handoff. Diagnostic mode keeps the same run but records a
failed corpus as a named blocker so the archive can collect engine evidence.

## Record shape

Each attempt writes a JSON record below:

```text
docs/handoff/<resolved candidate sha>/<archive set sha256>.json
```

The archive-set digest is SHA-256 over these two canonical lines, in this
order:

```text
2.0<TAB><requested version><TAB><2.0 archive sha256>
2.1<TAB><requested version><TAB><2.1 archive sha256>
```

The record has schema version `1`, the resolved `candidate_sha`, `result`
(`pass` or `refused`), an `archives` array, every branch-tagged check's name,
command, `exit`, case counts and `log_sha256`, and refusal reasons. The log
digest remains in the record after the temporary work directory is cleaned up.
A missing archive is recorded as a null archive hash. Diagnostic records
additionally carry `mode`, named `blockers`, and the per-archive internal
verdict. If an identical digest already exists, an `-attempt-N` suffix is used
so an earlier attempt is never overwritten.

The result is `pass` only when both archives exist, all four gating commands
pass for both packages, every expected case is executed, and all production
modules resolve inside the extracted package. There is no force mode.

## Verified promotion

`prepare_release.sh` is the promotion transition. It requires an existing
archive (or archive directory), runs the mandatory golden corpus for the
requested branch or both branches, then runs `tools/release_gate.py` against
those exact archive bytes and the bound engine evidence. Only when both steps
exit successfully does it print `release verdict: verified`; it never rebuilds
an archive. Diagnostic handoffs remain `unverified_internal` and are never
promoted by changing their verdict in place.

## Keeping the archives a passing run verified

```sh
RRC_HANDOFF_KEEP_ARCHIVES=~/share sh tools/handoff.sh <sha> <2.0 version> <2.1 version>
```

The command builds its archives in a temporary workspace and deletes it. Rebuilding afterwards produces
different bytes and therefore a different sha256, so the record would describe an archive nobody holds. With
this variable the two archives it verified are copied out, and only when the record passes: a refused run hands
over nothing.
