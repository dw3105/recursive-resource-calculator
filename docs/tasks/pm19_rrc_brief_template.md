# PM0928-P19 — lane ownership manifest written and checked by tool; brief template

Repo `recursive-resource-calculator`. Worktree `/home/dev_zaigraev_gmail_com/wt-rrc-pm19`, branch `lane/pm19`,
base `BASE_SHA`. Host `legalcopilot-dev`.

**Operator rule: this lane never runs a full suite.** No `sh tests/run.sh`, no `suite_parallel.sh`, no
`python3 -m pytest tests/` over a directory, no `unittest discover`, no `lua5.2` test, no headless `factorio`.
Run only the two test modules named in the checks block and single test nodes
(`python3 -m pytest -q tests/tools/test_lane_ownership.py::LaneOwnership::<name>`).
Owner runs full suite after merge. **Running a full suite is a stop, not a fix.**

## What is true

**PRESERVE:** legacy form `python3 tools/lane_ownership.py --base <ref> --manifest <file> [--repo <dir>]`
byte-identical: same checks, same `OWNERSHIP: ...` lines, same `owned-only: %d file(s) changed, %d required
deliverable(s) present` line, exit 0/1; old briefs call it with tags (`docs/tasks/147_route.md:146`,
`docs/tasks/149_shortfall.md:97`). `read_manifest()` and `ownership_overlaps()` names, signatures, results
unchanged (`tools/check_dispatch.py:39-42` imports `ownership_overlaps`). All 9 existing tests in
`tests/tools/test_lane_ownership.py` byte-identical and green; new tests appended only.
`tests/tools/test_dispatch_preflight.py` untouched and green (11 passed, 13 subtests). No assert weakened or
deleted.

- `tools/lane_ownership.py` (107 lines) checks only. `main()` `:68-103`: one argparse parser, `--base` and
  `--manifest` required (`:70-71`); `read_manifest()` `:35-45` (`!` prefix = required, `#` comment, trailing
  `/` = directory); changed set `:77` (`git diff --name-only base HEAD`); descent check `:94`; pass line `:102`.
  No code writes a manifest.
- Manifests are hand-written: `docs/tasks/270.manifest`, `docs/tasks/264.manifest` (first line `# bound: 3000s`,
  one path per line). Briefs 264-270 carry hand-escaped filters instead of the tool, all on moving tags:
  `docs/tasks/264_route_keys_no_garbage.md:77` and `docs/tasks/270_generation_prune_finished_jobs.md:71`
  (`git diff --name-only round-46-base-270 HEAD | grep -Ev '^(logic/bp/generation\\.lua|control\\.lua|...)$'`).
- `tools/check_dispatch.py` preflight rules the writer must satisfy: `:133-134` refuses literal `\n` bytes;
  `:146-147` refuses blank lines; `:152-153` full-line `#` comments allowed; `:192-200` a manifest entry without
  `!` must already exist in the repo; `:214-216` task must hold exactly one ` ```checks ` block (regex `:47`,
  line-start fence).
- Tests: `tests/tools/test_lane_ownership.py:46` owned-only lane passes, `:105` and `:120` foreign file fails,
  `:168` command runs under `/bin/sh` (lane_verify runs checks with `shell=True`). Helpers `build()` `:23`,
  `manifest()` `:37`, `run_tool()` `:42`, module-level `git()` `:18` (no output returned).
- skills lane_verify accepts a check line only with exactly keys `name, command, expect_exit, expect_regex,
  timeout_s` (`~/skills/tools/lane_verify.py:167`, missing/extra refused `:215-219`); `expect_regex` must compile
  (`:236-239`).
- Lua test summary: `tests/harness.lua:2247-2253` `H.done` prints `<file> [Lua 5.2]: N cases, P passed, F failed`
  and exits 1 when F > 0.
- `docs/RULINGS.md` rows `lanes-suites` and `RRC-04`: lanes run single test files only.
- No template exists under `docs/tasks/`. No pre-commit hook in this repo (`core.hooksPath` unset, hooks dir
  holds samples only): plain `git commit`.
- Trap: a task file that holds a template containing a line-start ` ```checks ` fence counts as two checks
  blocks. The template below is indented 4 spaces for that reason; the file you write is NOT indented.

## What to build

1. `tools/lane_ownership.py`: keep legacy form. When `argv[0]` is `write-manifest` or `check`, dispatch to a
   subcommand; otherwise run the legacy parser unchanged. Move the three checks of `main()` into one function
   both forms call; legacy output stays byte-identical. Update the module docstring usage lines.
2. Owned-list parser `owned_from_task(text)` (shared by both subcommands): section starts at line
   `## Files this lane owns`, ends at next line starting `# ` or `## ` or EOF. Inside, a line starting `- ` must
   match `^- \x60(!?)([^\x60]+)\x60` (\x60 = backtick; text after closing backtick is a scope note, ignored);
   other non-bullet lines ignored. `!` = required deliverable. Path refused when absolute, contains `\`,
   whitespace, empty component or `..` component, or duplicated.
3. `write-manifest (--task <task.md> | --path <p> [--path <p> ...]) --out <file> [--repo <dir>]`:
   `--path` value takes same `!` prefix rule. Refusals, exit 2, message on stdout, `--out` not created:
   - `refused: no '## Files this lane owns' section in <task>`
   - `refused: owned line is not "- \x60path\x60": <line>`
   - `refused: bad owned path: <path>`
   - `refused: no owned paths in <task-or-"--path">`
   - `refused: owned path must exist at base or carry '!': <path>` (non-`!` path missing under `--repo`,
     same rule as `tools/check_dispatch.py:192-200`)
   On success write `<file>`: line 1 `# written by tools/lane_ownership.py write-manifest`, then one entry per
   line in input order (`!` kept), real `\n`, trailing `\n`, no blank line. Print
   `wrote <file>: N path(s), M required`, exit 0.
4. `check --base <sha> (--task <task.md> | --manifest <file>) [--repo <dir>]`:
   - `--base` must match `^[0-9a-f]{7,40}$`, else exit 2 `refused: base must be a commit sha, not a ref: <base>`.
   - `--task`: owned list read from the task file AS IT IS AT BASE (`git show <base>:<repo-relative task path>`),
     never the working-tree copy, so a lane cannot widen its own list. Task path absent at base: exit 2
     `refused: task not in base <base>: <path>`.
   - Same three checks as legacy, plus one problem line per `git status --porcelain --untracked-files=all` entry:
     `OWNERSHIP: uncommitted change: <path>`. Pass/fail output and exit codes as legacy.
   - Path match is literal string/prefix compare, never regex (`logic/bp/pack.lua` owns nothing but itself).
5. Append to `tests/tools/test_lane_ownership.py` (class `LaneOwnership`, existing lines untouched), each
   asserting exit code AND exact message:
   - `test_write_manifest_from_task_has_real_newlines`: task with 3 owned lines (one `!`, one directory) →
     file bytes equal expected exactly; `b"\\n"` not in bytes; line count 4.
   - `test_written_manifest_passes_dispatch_preflight`: import `check_dispatch` from `tools/`
     (`sys.path` insert); `parse_manifest(out, repo).problems == ()` and `_check_manifest_files(...) == []`.
   - `test_write_manifest_refuses_task_without_owned_paths` (comma-prose list like brief 270 → rc 2).
   - `test_write_manifest_refuses_missing_path_without_bang` (rc 2, out not created).
   - `test_check_from_task_owned_file_passes` (task committed at base; lane changes owned file → rc 0,
     `owned-only`).
   - `test_check_from_task_foreign_file_fails` (lane changes `control.lua` → rc 1,
     `OWNERSHIP: not owned by this lane: control.lua`).
   - `test_check_reads_task_at_base_not_worktree` (lane adds `control.lua` to its own task list and edits
     `control.lua` → rc 1, both files named not owned).
   - `test_check_dot_is_literal` (owns `pack.lua`, changes `packXlua` → rc 1).
   - `test_check_refuses_moving_ref_base` (`--base master` or a tag → rc 2, exact message).
   - `test_check_refuses_uncommitted_file` (untracked file → rc 1, `OWNERSHIP: uncommitted change: <f>`).
   - `test_check_runs_under_posix_sh_in_one_line` (`check --base <sha> --task <t> --repo <d>` via
     `subprocess.run(..., shell=True, executable="/bin/sh")` → rc 0).
   Total after change: 20 tests.
6. Create `docs/tasks/TEMPLATE.md` = the block below with the leading 4 spaces removed from every line (empty
   lines stay empty). Byte-exact; check `template-exact` compares it.

~~~~text
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
~~~~

7. Red proof in scratch copy, never in this worktree:
   `D=$(mktemp -d); git archive BASE_SHA | tar -x -C "$D"; cp tests/tools/test_lane_ownership.py "$D/tests/tools/";
   cd "$D" && python3 -m pytest -q tests/tools/test_lane_ownership.py 2>&1 | tail -15` → the 11 new tests FAIL,
   the 9 old pass. Paste as `EVIDENCE-RED:`.
8. Commit once on `lane/pm19` with plain `git commit`, subject `pm19: lane_ownership writes manifest and checks
   from task; brief template`, body lines `EVIDENCE-RED:`, `EVIDENCE-GREEN:` (both modules' pytest summary),
   `EVIDENCE-DIFFSTAT:` (`git diff --stat BASE_SHA HEAD`). Never amend, merge, rebase, push, touch `main`,
   `int/pm-260928` or any tag. Run checks LAST.

## What done mean

```checks
{"name": "lane-ownership-tests", "command": "python3 -m pytest -q tests/tools/test_lane_ownership.py 2>&1", "expect_exit": 0, "expect_regex": "(?m)^20 passed in ", "timeout_s": 120}
{"name": "dispatch-preflight-tests", "command": "python3 -m pytest -q tests/tools/test_dispatch_preflight.py 2>&1", "expect_exit": 0, "expect_regex": "(?m)^11 passed, 13 subtests passed in ", "timeout_s": 120}
{"name": "old-tests-untouched", "command": "git diff BASE_SHA HEAD -- tests/tools/test_lane_ownership.py | grep -cE '^-([^-]|$)'", "expect_exit": 1, "expect_regex": "^0$", "timeout_s": 30}
{"name": "template-exact", "command": "python3 -c \"import glob,re,sys;f=glob.glob('docs/tasks/*_rrc_brief_template.md');assert len(f)==1,f;b=re.search(r'(?ms)^~~~~text\\n(.*?)^~~~~$',open(f[0]).read()).group(1);e=''.join((l[4:] if l.strip() else '')+'\\n' for l in b.splitlines());sys.exit(0 if open('docs/tasks/TEMPLATE.md').read()==e else 1)\" && echo template-exact", "expect_exit": 0, "expect_regex": "^template-exact$", "timeout_s": 30}
{"name": "owned-only-by-tool", "command": "python3 tools/lane_ownership.py check --base BASE_SHA --task docs/tasks/*_rrc_brief_template.md", "expect_exit": 0, "expect_regex": "(?m)^owned-only: 3 file\\(s\\) changed, 1 required deliverable\\(s\\) present$", "timeout_s": 60}
{"name": "only-owned-files", "command": "test -z \"$(git status --porcelain --untracked-files=all)\" && git diff --name-only BASE_SHA HEAD | sort | tr '\\n' ' '", "expect_exit": 0, "expect_regex": "^docs/tasks/TEMPLATE\\.md tests/tools/test_lane_ownership\\.py tools/lane_ownership\\.py $", "timeout_s": 30}
{"name": "no-file-deleted", "command": "git diff --diff-filter=D --name-only BASE_SHA HEAD | wc -l", "expect_exit": 0, "expect_regex": "^0$", "timeout_s": 30}
{"name": "one-commit", "command": "git rev-list --count BASE_SHA..HEAD", "expect_exit": 0, "expect_regex": "^1$", "timeout_s": 30}
{"name": "evidence-in-commit-body", "command": "git log -1 --format=%B | grep -cE '^EVIDENCE-(RED|GREEN|DIFFSTAT):'", "expect_exit": 0, "expect_regex": "^([3-9]|[1-9][0-9]+)$", "timeout_s": 30}
```

## Files this lane owns

- `tools/lane_ownership.py` — subcommands, shared check function, docstring; legacy form byte-stable
- `tests/tools/test_lane_ownership.py` — append 11 tests only; existing lines untouched
- `!docs/tasks/TEMPLATE.md` — new, byte-exact from block above

## Do not

Never run a full suite, a `lua5.2` test, `sh tests/run.sh`, headless `factorio`, or `make` anything. Never edit
this task file, any `*.manifest`, `tools/check_dispatch.py`, `tests/tools/test_dispatch_preflight.py`,
`logic/`, `tests/test_*.lua`, `tests/fixtures/`, `docs/RULINGS.md`, or any other file. Never weaken or delete an
assert. Never change the CLI of `tools/build_test_zip.sh` or `tools/game_load_check.sh`.

Re-cut because: none

# bound: 2400s

Reviewer ask: legacy form output byte-identical (run old 9 tests + one tag-base call by hand); `check --task`
reads task at base, not worktree; manifest bytes have real newlines and pass `check_dispatch.parse_manifest`;
TEMPLATE.md byte-equal to block.
