# NNN — <one behaviour, as the player sees it>

Repo `recursive-resource-calculator`. Worktree `/home/dev_zaigraev_gmail_com/wt-rrc-NNN`, branch `lane/NNN`,
base `<40-hex sha>`. Host `legalcopilot-dev`.

<!-- Rules for whoever cuts a brief from this template. Delete this comment in the brief.
T-1 (RRC-02) One behaviour per brief. Owned list: 3 paths or less. Two behaviours = two briefs.
T-2 (RRC-02) Every check: timeout_s 120 or less, and timed on base under 120 s before launch. Whole sheet,
    golden run, headless game, suite, any reproducer over 120 s: never a lane check; owner runs it after merge.
T-3 (RRC-05) Base = full 40-hex commit sha. Never a tag or branch: a tag that moves while the lane runs ends
    the lane `tree-moved`. Owner moves a wave tag only after every lane verdict of that wave is in.
T-4 (RRC-05) Every test that pins a hash, byte count, tick count or old contract that another lane of the
    same wave changes: list it under "## Expected to change" with file:line and that lane's number.
T-5 (RRC-01) Owned list: one line per path, "- `path` — scope"; "- `!path`" = lane must change or create it;
    a path new at base carries "!". Never hand-write a manifest or a grep of paths. Before launch:
    python3 tools/lane_ownership.py write-manifest --task docs/tasks/NNN_slug.md --out docs/tasks/NNN.manifest
    python3 tools/check_dispatch.py --repo /home/dev_zaigraev_gmail_com/wt-rrc-NNN --base <sha> --task docs/tasks/NNN_slug.md --manifest docs/tasks/NNN.manifest
T-6 Exactly one checks block, one JSON object per line, keys exactly name, command, expect_exit,
    expect_regex, timeout_s. expect_regex compiles. No <placeholder> left in the brief.
-->

**Operator ruling (`docs/RULINGS.md` `lanes-suites`, `RRC-04`): this lane never runs a full suite.** Never
`sh tests/run.sh`, `suite_parallel.sh`, `tests/golden/generate.lua`, `tools/golden_profile.lua`, headless
`factorio`, or a whole sheet. Run only the single test files named in the checks block, one at a time:
`lua5.2 tests/<file>.lua` (lua5.2 only) or `python3 -m pytest -q tests/tools/<file>.py`. Running a full suite
is a stop, not a fix.

## What is true

**PRESERVE:** <behaviour, messages, exit codes, tests that stay byte-identical>

- <fact, with file:line re-derived against the base sha>

## Expected to change

- `tests/<file>:<line>` pins <hash / count / contract>; lane <MMM> changes it. This lane edits that line only.
- (or: none)

## What to build

1. <imperative step, exact names, exact messages>
2. Red proof in a scratch copy, never in this worktree: `D=$(mktemp -d); git archive <base sha> | tar -x -C "$D"`,
   copy the new test in, run it: FAIL. Paste output as `EVIDENCE-RED:` in the commit body.

## What done mean

```checks
{"name": "owned-only", "command": "python3 tools/lane_ownership.py check --base <base sha> --task docs/tasks/NNN_slug.md", "expect_exit": 0, "expect_regex": "(?m)^owned-only: ", "timeout_s": 60}
{"name": "test-slug", "command": "lua5.2 tests/test_slug.lua 2>&1", "expect_exit": 0, "expect_regex": "(?m), 0 failed$", "timeout_s": 120}
{"name": "tool-test", "command": "python3 -m pytest -q tests/tools/test_tool.py 2>&1", "expect_exit": 0, "expect_regex": "(?m)^N passed in ", "timeout_s": 120}
```

## Files this lane owns

- `logic/bp/<module>.lua` — <scope>
- `!tests/test_<slug>.lua` — new test

## Do not

Never run a full suite or any command over 120 s. Never edit this task file, a manifest, `docs/`, or a test not
named above. Never weaken or delete an assert except lines under "Expected to change". Never amend, rebase,
push, or touch `main` or a wave tag.

# bound: <seconds>s

Reviewer ask: <one line>
