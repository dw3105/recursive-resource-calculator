# 054 — A bad task file is refused before a coder starts

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-054`, branch `lane/054`, base = `feat/round-8-blueprints`, tag `queue-base` (resolve it with `git rev-parse queue-base`, literal SHA in `docs/recovery-status.md`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `tools/lane_ownership.py`, `tests/tools/test_lane_ownership.py`, new `tools/check_dispatch.py` and new `tests/tools/test_dispatch_preflight.py`. Everything else is frozen.
- Lane 053 owns `logic/bp/search.lua` and `tests/test_search.lua`. Lane 055 owns `tools/extract_api.py`, `docs/api/*.json` and `tests/test_api_shapes.lua`. Lane 056 owns `logic/bp/generation.lua` and `logic/engine_test_api.lua`. Lane 057 owns new files under `tests/golden/`. Never touch any of them.
- Every existing case stays. You add; you never weaken, skip or delete one.
- The branch carries one **known red** case: `tests/test_blueprint_pipeline.lua` holds the mandatory real-sheet case, which fails with `BP_FAIL_NO_LAYOUT_GRID_LIMIT` while lane 053 repairs the defect under it. Never edit that file, never change its expected outcome, and never treat its failure as yours. Report `component checks: PASS; feature integration: BLOCKED by tests/test_blueprint_pipeline.lua (lane 053)` when your own work is done.
- `require` runs only while `control.lua` is parsed. Never call it inside a function; `tests/test_no_runtime_require.lua` fails the suite on an indented `require`. Use `logic/registry.lua` for a late edge.
- `prototypes`, `game`, `settings` and prototype lists are **userdata**; ask `rawget(_G, "prototypes")`.
- Nothing in `storage` may be a function, a metatable or a LuaObject.
- The coordinator owns `tests/harness.lua`, `tests/run.sh`, `control.lua`, `gui/sheet.lua`, locale files, `docs/feature-contracts.md`, `tests/golden/required-matrix.json`, the board and every merge. Need one changed? Send the exact small patch and carry on with your other work.
- `info.json` carries the user's own uncommitted edit and `mod-description.md` is the user's untracked file. Never touch either.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

**When something outside your files breaks:** record the first failing stage, the immutable input and a bounded
reproducer, and say so at once. Never edit an unowned file and never weaken an assertion. Continue every owned
piece that does not need that fix. Checkpoint before you end.

Current facts:
- The 2026-09-19 10:28 UTC batch lost five verdicts to one typo: `docs/tasks/048.manifest` through `052.manifest` were written with literal backslash-n bytes, so `tools/lane_ownership.py` read each file as one path and refused every changed file. Five lanes did correct work and every verdict read FAIL.
- `tools/lane_ownership.py` runs **after** a lane commits: it compares `git diff --name-only <base> HEAD` against the manifest and demands each required deliverable changed. Running that check against an untouched starting tree would refuse every valid new task, so preflight is a separate thing.
- A manifest line ending in `/` owns a directory; a line starting with `!` names a required deliverable.

## What to build

1. `tools/check_dispatch.py`, read-only: it never writes a file, never commits, never launches or kills anything.
2. It refuses, naming the exact offender: a literal `\n` or NUL byte in a manifest; an empty, duplicate or malformed entry; a path that is absolute, escapes the repository, or carries a backslash; a manifest with no entries.
3. It refuses an ownership clash between the task under test and any lane running right now, including a directory against a file inside it (`tests/golden/` against `tests/golden/lib/runner.py`).
4. It refuses a base that does not resolve, a worktree standing on a different commit than that base, a missing task file, a missing manifest, a ```checks``` block that is not one JSON object per line, and a check naming a test file that must already exist but does not. A line marked `!` is a new deliverable and is never required to exist yet.
5. It refuses a worktree that already holds a running lane.
6. It prints `READY <task>` or one line per blocker, and exits non-zero when any task is not ready.
7. `tests/tools/test_dispatch_preflight.py` covers every refusal above in disposable repositories built by the test itself. It never reads an active worktree and never runs a lane.
8. `tools/lane_ownership.py` keeps its current behaviour; add only what preflight needs to share, and keep its own tests green.

## What done mean

```checks
{"name": "dispatch-tests", "command": "python3 -m unittest discover -s tests/tools -p 'test_*.py' -t .", "expect_exit": 0, "expect_regex": "OK", "timeout_s": 900}
{"name": "refuses-the-real-typo", "command": "printf 'a.lua\\nb.lua' > /tmp/bad-$$.manifest; python3 tools/check_dispatch.py --manifest /tmp/bad-$$.manifest; test $? -ne 0 && echo refused", "expect_exit": 0, "expect_regex": "refused", "timeout_s": 120}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base queue-base --manifest docs/tasks/054.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the refusal for the literal backslash-n manifest and for a directory-against-file clash.
- `git diff --stat queue-base HEAD` pasted.

Run the checks as your **last** action, after your final commit.

## Files this lane owns

- `tools/lane_ownership.py`
- `tools/check_dispatch.py`
- `tests/tools/test_lane_ownership.py`
- `tests/tools/test_dispatch_preflight.py`

Touch nothing else.

# bound: 1700s

Reviewer ask: would this tool have caught the typo that cost five verdicts?
