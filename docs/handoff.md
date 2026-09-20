# Handoff records

`sh tools/handoff.sh <sha> <2.0 version> <2.1 version>` is the refusal-only
last local step before a test archive is handed to a player. It builds both
archives from the requested commit, extracts each archive, adds the requested
commit's `tests/`, `tools/`, and supporting `docs/` with `git archive`, and runs
the gates from those extracted roots. It never uses tests or production Lua
from the live checkout.

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

`sh tests/golden/run --branch 2.0 --drafts report` is recorded as
informational. Its non-zero status is expected for draft or captured corpus
cases and cannot make a handoff refuse.

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
(`pass` or `refused`), an `archives` array, every gating check's command,
`exit`, case counts and `log_sha256`, a separate `informational` array for the
corpus, and refusal reasons. A missing archive is recorded as a null archive
hash. If an identical digest already exists, an `-attempt-N` suffix is used so
an earlier attempt is never overwritten.

The result is `pass` only when both archives exist, all three gating commands
pass for both packages, every expected case is executed, and all production
modules resolve inside the extracted package. There is no force mode.
