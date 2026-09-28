# PM0928-P21 — handover carries a game receipt: zip loads, GUI opens, calculation under 5 s

Repo `recursive-resource-calculator`. Worktree `/home/dev_zaigraev_gmail_com/wt-rrc-pm21`, branch `lane/pm21`,
base `BASE_SHA`. Host `legalcopilot-dev`.

**Operator ruling (`docs/RULINGS.md` `lanes-suites`, `RRC-04`, `HO-05`): this lane never runs a full suite and
never runs headless Factorio.** Never `sh tests/run.sh`, `suite_parallel.sh`, `tests/golden/generate.lua`,
`tools/golden_profile.lua`, a real `factorio` binary, `tools/game_test.sh` or `tools/game_load_check.sh` without
the fake env of step 6, or a whole sheet. Run only the test files named in the checks block, one at a time:
`python3 -m pytest -q tests/tools/<file>.py` or one node `python3 -m pytest -q tests/tools/test_release_gate.py::HandoverReceiptTests::<name>`.
No `lua5.2` test. Running a full suite or the real game is a stop, not a fix. Integrator runs the real game after merge.

## What is true

**PRESERVE:** legacy form `python3 tools/release_gate.py <2.0|2.1|--release> [--matrix ..] [--evidence-root ..]
[--golden-root ..] [--candidate ..] [--archive ..] [--archive-dir ..] [--version ..] [--repo ..]` byte-identical:
same checks, same `release gate: ...` / `release ready: ...` stdout lines, same `release refused: <reason>` stderr
line, exit 0/2. Callers: `prepare_release.sh:76` and `:86`. Module names `load_matrix` (loaded by
`tests/golden/lib/runner.py:91`), `run_gate`, `check_case`, `ReleaseGateError`, `_archive_for_branch`, `RECEIPT`
unchanged. CLI and bytes of `tools/build_test_zip.sh`, `tools/game_load_check.sh`, `tools/game_test.sh`,
`tools/game_stage.sh` unchanged (peer `rrc_fixer_3` calls the first two in its release step). All 33 existing tests
(8 subtests) in `tests/tools/test_release_gate.py` byte-identical and green; new tests appended only. Names
`GATE`, `PRODUCTION_EXAMPLE`, `ReleaseGateFixture` stay importable (`tests/tools/test_evidence_contract.py:12-16`).
No assert weakened or deleted.

- `tools/release_gate.py` (665 lines) is a file verifier: docstring `:3-7` "never starts Factorio"; `_parser()`
  `:609-621` has positional `branch` `nargs="?"` (`:611`), so today `release_gate.py receipt` parses `receipt` as a
  branch and exits 2 `release refused: mismatched archive: no archive supplied for branch receipt`. `main()`
  `:624-661`; stdout lines `:652`, `:654`; refusals `:656-661`. `_archive_for_branch()` `:588-606` finds one zip per
  branch in `--archive-dir` by glob `*factorio-<branch>*.zip` (`:601`). `RECEIPT` `:49` = `tools/evidence_receipt.py`;
  `RECEIPT.zip_sha256()` `evidence_receipt.py:35`, `RECEIPT.read_build_id()` `evidence_receipt.py:60-73` (needs one
  `logic/build_id.lua` in zip with `candidate_sha`, `factorio_branch`, `packaged = true`). `_git_candidate()` `:564`.
  No receipt of game tests exists anywhere.
- `tools/build_test_zip.sh` (39 lines) only builds: `build_one()` `:27-35` writes
  `RRC-Fork_<ver>_factorio-<branch>-test.zip`, prints `TEST BUILD: <sha256>  <archive>  (Factorio <branch>)`.
- Load test already exists: `tools/game_load_check.sh <zip> <2.0|2.1>` (35 lines). Refuses exit 2 under
  `LANE_RUN_ID` `:8`, bad FV `:9`, missing zip `:10`. Factorio root `${FACTORIO_ROOT:-$HOME/factorio-$FV/factorio}`
  `:11` (the fake-binary seam); binary `$FACTORIO/bin/x64/factorio` `:30`; writes `$ROOT/build/load-$FV` `:13-15`
  (`build/` is in `.gitignore`). Pass: exit 0, last stdout line `load-check-<FV>-ok` `:32`, needs log line
  `Loading mod RRC-Fork` and no `error|failed` (case-insensitive) `:31`. Fail: 40 log lines then
  `load-check-<FV>-FAIL`, exit 1 `:34`. Zip must hold `<dir>/info.json` with `name`, `version` `:17-21`.
- GUI test already exists, runs the WORKING TREE, not the zip: `tools/game_test.sh <FV> '<file>::<name>'` (89 lines).
  Refuses under `LANE_RUN_ID` exit 2 `:11-14`. Factorio root `:17` same seam; `FT_ZIP_DIR` `:18`
  (`factorio-test_3.0.1.zip` for 2.0, `factorio-test_3.1.0.zip` for 2.1, `:19`, copied `:30-31`); CLI dir
  `RRC_FT_DIR` `:23`, CLI `$FT/node_modules/.bin/factorio-test` `:24`; `patch-cli.sh` runs with `FT_DIR=$FT` `:34`
  and needs `$FT/node_modules/factorio-test-cli/factorio-process.js` holding `}, 120_000);`
  (`tools/ft/patch-cli.sh:5-6`); CLI gets `--output-file <build/FV/results.json>` `:39` and `--test-pattern` `:40`.
  One-test mode prints `game test='<path>' result=[...] ...` and exits 0 only when exactly one test passed `:76-88`.
  `tools/game_stage.sh:14` needs `$FACTORIO/bin/x64/factorio` executable; stages into `build/<FV>/`.
  GUI test used: `tests/game/test_gui.lua:20` `describe("gui"`, `:23` `it("toggle opens and closes twice"` →
  argument `tests/game/test_gui.lua::gui > toggle opens and closes twice`, results path
  `tests.game.test_gui > gui > toggle opens and closes twice`.
- Calculation = blueprint generation of one sheet (what player waits on). Entry point
  `lua5.2 tests/golden/generate.lua --input <prepared_input.json> --output <result.json>` (`generate.lua:462-471`);
  exits 0 even when generation failed, result JSON top-level `"ok": true|false` (`:489-490`, `:514-515`, `:530`);
  exit 2 on error `:15-18`, `:539`. Golden input `tests/golden/cases/player-red-science-1s/prepared_input.json`
  (also default of `tools/speed_probe.sh`). In-game generation of that sheet measured 5.5-6.8 s
  (`docs/game-tests.md:38`), so the real budget run today likely FAILs: that is the honest result, not a lane defect.
  No calc-budget tool exists.
- Tests of owned files: `tests/tools/test_release_gate.py` (33 passed, 8 subtests, 1.3 s on base);
  `tests/tools/test_evidence_contract.py` imports it (1 passed); `tests/golden/lib/runner.py:87-98` loads
  `release_gate.load_matrix`, exercised by `tests/tools/test_capture_workflow.py` (15 passed) and
  `tests/tools/test_golden_tools.py` (14 passed, 21 s under load). `tests/tools/test_handoff.py:131` writes its own
  fake `release_gate.py`, never imports ours.
- Handover script `tools/handoff.sh` is NOT owned; wiring `handover` into it is owner follow-up after merge.
- No pre-commit hook (`core.hooksPath` unset): plain `git commit`.
- Trap: `game_load_check.sh` and `game_test.sh` refuse under `LANE_RUN_ID`, which the lane runner sets. Tests that
  drive them through the fake must remove `LANE_RUN_ID` from the child env and MUST set `FACTORIO_ROOT`,
  `RRC_FT_DIR`, `FT_ZIP_DIR`, `RRC_LUA` to fakes under a `tempfile.TemporaryDirectory()`; a helper asserts each
  of the four points under that temp dir before any subprocess starts. Never remove `LANE_RUN_ID` without all four.
- Trap: a `subTest` in new tests changes the `8 subtests` count the check pins. No `subTest` in new tests.

## Expected to change

- none

## What to build

1. New `tools/calc_budget.sh` (POSIX sh, `set -u`):
   - Usage `tools/calc_budget.sh [--budget <seconds>] <case> [<case> ...]`; default budget `5`. No case, bad flag, or
     budget not a positive integer: stderr `usage: tools/calc_budget.sh [--budget <seconds>] <case> [<case> ...]`,
     exit 2.
   - First, before anything else: `if [ -n "${LANE_RUN_ID:-}" ] && [ -z "${RRC_LUA:-}" ]` → stderr
     `calc_budget: refuse, lanes never run a whole sheet`, exit 2.
   - `ROOT=$(cd "$(dirname "$0")/.." && pwd)`; `cd "$ROOT"`; `LUA=${RRC_LUA:-lua5.2}`; work dir `mktemp -d`, removed
     on exit.
   - Per case: input `tests/golden/cases/<case>/prepared_input.json`; missing → stderr `calc_budget: no input <path>`,
     exit 2. Run `timeout -k 2 <budget> "$LUA" tests/golden/generate.lua --input <input> --output <work>/<case>.json`,
     stdout/stderr to `<work>/<case>.log`. Wall seconds from `date +%s%N`, printed with 2 decimals. Print exactly one
     line: `calc-budget <case> ok wall_s=<t> budget_s=<b>` when rc 0 and output JSON has `"ok": true`;
     `calc-budget <case> FAIL timeout wall_s=<t> budget_s=<b>` when rc 124 or 137;
     `calc-budget <case> FAIL exit=<rc> wall_s=<t> budget_s=<b>` for other non-zero rc;
     `calc-budget <case> FAIL not-ok wall_s=<t> budget_s=<b>` when rc 0 but `ok` not `true` or output unreadable.
   - Last line `calc-budget-ok` exit 0 when every case ok, else `calc-budget-FAIL` exit 1.
2. `tools/release_gate.py`: `main(argv)` takes `argv = list(sys.argv[1:] if argv is None else argv)`. When
   `argv[0]` is `receipt` or `handover`, dispatch to that subcommand with its own parser; otherwise run the legacy
   parser and body unchanged. Update docstring: file verifier mode never starts Factorio; `receipt` runs the
   integrator's game scripts (integrator only, lanes never).
3. `receipt --archive-dir <dir> --out <receipt.json> [--candidate <sha>] [--no-game] [--calc-budget <s>]
   [--calc-case <case> ...]` (defaults: budget `5`, case `player-red-science-1s`). `REPO = Path(__file__).resolve().parents[1]`;
   every script runs as `["sh", str(REPO / "tools" / <script>), ...]`, `cwd=REPO`, env = `os.environ` unchanged,
   `capture_output=True, text=True`.
   - Zips: for `2.0` and `2.1`, `_archive_for_branch(None, fv, "", archive_dir)`. For each: `sha256` =
     `RECEIPT.zip_sha256`, build id = `RECEIPT.read_build_id`; `factorio_branch` must equal fv, both zips same
     `candidate_sha`, equal `--candidate` when given. Else stderr `receipt refused: <reason>` exit 2, no file written.
   - Game mode (no `--no-game`): `git -C REPO rev-parse HEAD` must equal the zips' candidate, else exit 2
     `receipt refused: gui test stages the working tree at <head>, zips are <candidate>; check out <candidate>`.
     Per fv: load = `game_load_check.sh <zip> <fv>` (subprocess timeout 600 s); gui = `game_test.sh <fv>
     'tests/game/test_gui.lua::gui > toggle opens and closes twice'` (timeout 900 s).
     Load result `ok` iff rc 0 and last non-empty stdout line == `load-check-<fv>-ok`; `FAIL` iff rc 1; else
     `not-run` (reason = last non-empty stderr line, or `exit <rc>`). Gui result `ok` iff rc 0 and a stdout line
     starts `game test='tests.game.test_gui > gui > toggle opens and closes twice' result=['passed']`; `FAIL` iff rc 1;
     else `not-run` as load. Subprocess timeout → `FAIL`, reason `timeout after <n> s`.
   - `--no-game`: load and gui never run; each result `not-run`, reason `--no-game`.
   - Calc (both modes): `calc_budget.sh --budget <b> <case>...` (timeout `(b + 30) * cases` s). Result `ok` iff rc 0
     and last line `calc-budget-ok`; `FAIL` iff rc 1; else `not-run`. Per case parse
     `calc-budget <case> <ok|FAIL ...> wall_s=<t>` lines.
   - `tested_in_game` = `"yes"` iff all four load/gui results are `ok` or `FAIL` (game ran), else `"no"`;
     `not_tested_reason` = `null` when yes, else `not tested in game: <first not-run reason>`.
   - Write `--out` (parent dirs created, `json.dumps(indent=2, sort_keys=True)` + `\n`) with exactly these keys:

     ```text
     {"schema": "rrc-handover-receipt/1", "candidate_sha": str, "written_utc": "YYYY-MM-DDTHH:MM:SSZ",
      "tested_in_game": "yes"|"no", "not_tested_reason": str|null,
      "zips": {"2.0": {"path": str, "sha256": str}, "2.1": {...}},
      "load": {"2.0": {"result": "ok"|"FAIL"|"not-run", "exit": int|null, "last_line": str, "reason": str|null}, "2.1": {...}},
      "gui":  {"2.0": {same keys, plus "staged_tree_head": str|null}, "2.1": {...}},
      "calc_budget": {"result": "ok"|"FAIL"|"not-run", "budget_s": int, "exit": int|null,
                      "cases": {"<case>": {"result": "ok"|"FAIL", "detail": str, "wall_s": float|null}}}}
     ```
   - Print one stdout line `receipt <out>: tested-in-game=<yes|no> load-2.0=<r> load-2.1=<r> gui-2.0=<r> gui-2.1=<r>
     calc=<r>`. Exit 0 when calc `ok` and (tested yes with all four `ok`, or `--no-game`); else exit 1 (file still
     written).
4. `handover --receipt <receipt.json> --archive-dir <dir> [--accept-not-tested]`: checks in this order, first
   failure → stderr `handover refused: <reason>`, exit 2:
   - file missing → `no receipt: <path>`; unreadable JSON or `schema` != `rrc-handover-receipt/1` → `bad receipt: <path>`;
   - per fv, `_archive_for_branch` zip sha256 != receipt → `zip <fv> sha256 <actual> is not the receipt's <recorded>`;
   - `tested_in_game` != `yes` and no `--accept-not-tested` → `<not_tested_reason>; pass --accept-not-tested to hand
     over untested`;
   - `tested_in_game` == `yes`: each of `load-2.0`, `load-2.1`, `gui-2.0`, `gui-2.1` not `ok` → `<name> <result>`;
   - calc result not `ok` → `calc budget <result>`.
   Pass: stdout `handover ready: <candidate_sha> tested-in-game=yes`, or with an untested receipt accepted
   `handover ready: <candidate_sha> NOT TESTED IN GAME`; exit 0.
5. Append to `tests/tools/test_release_gate.py`, after the last existing line, class `HandoverReceiptTests`
   (existing lines untouched; no `subTest`). Fixture per test in `tempfile.TemporaryDirectory()`:
   two zips `RRC-Fork_0.0.1_factorio-<fv>-test.zip` each holding `RRC-Fork_0.0.1/info.json`
   (`{"name": "RRC-Fork", "version": "0.0.1"}`) and `RRC-Fork_0.0.1/logic/build_id.lua`
   (`return {candidate_sha = "<ROOT HEAD>", mod_version = "0.0.1", factorio_branch = "<fv>", packaged = true}`,
   `<ROOT HEAD>` = `git -C ROOT rev-parse HEAD` read at test time);
   fake `factorio` (`<tmp>/factorio/bin/x64/factorio`, executable: appends argv to `$FAKE_GAME_LOG`; prints
   `Loading mod RRC-Fork 0.0.1 (data.lua)`, exit 0; with `FAKE_FACTORIO_FAIL=1` prints `Error: mod crashed`, exit 1);
   fake FactorioTest dir (`<tmp>/ft/node_modules/.bin/factorio-test` executable: appends to `$FAKE_GAME_LOG`, writes
   to the `--output-file` value a results JSON with one test, path
   `tests.game.test_gui > gui > toggle opens and closes twice`, result `${FAKE_GUI_RESULT:-passed}`, summary
   `describeBlockErrors` 0; plus `<tmp>/ft/node_modules/factorio-test-cli/factorio-process.js` holding `}, 120_000);`);
   `<tmp>/ftzips/factorio-test_3.0.1.zip` and `factorio-test_3.1.0.zip` (any bytes); fake lua (`<tmp>/lua`,
   executable: sleeps `${FAKE_LUA_SLEEP:-0}`, writes `{"ok": ${FAKE_LUA_OK:-true}}` to the `--output` value).
   Env via `mock.patch.dict(os.environ, ...)`: `FACTORIO_ROOT=<tmp>/factorio`, `RRC_FT_DIR=<tmp>/ft`,
   `FT_ZIP_DIR=<tmp>/ftzips`, `RRC_LUA=<tmp>/lua`, `FAKE_GAME_LOG=<tmp>/game.log`, `LANE_RUN_ID` removed (except
   test 9); helper asserts all four seam vars under `<tmp>` first. Call `GATE.main([...])` capturing stdout/stderr.
   Every test asserts exit code AND exact message line(s). Twelve tests, exact names:
   1. `test_receipt_all_ok_records_zip_sha_load_gui_calc` — rc 0; receipt keys exactly as step 3; both `sha256` equal
      `hashlib.sha256` of the zip bytes; four results `ok`; `tested_in_game` `yes`; calc `ok`; stdout line exact.
   2. `test_receipt_load_fail_recorded_and_handover_refuses` — `FAKE_FACTORIO_FAIL=1`: receipt rc 1, load `FAIL`
      both fv; `handover` rc 2, stderr `handover refused: load-2.0 FAIL`.
   3. `test_receipt_gui_fail_recorded_and_handover_refuses` — `FAKE_GUI_RESULT=failed`: gui `FAIL`; handover rc 2
      `handover refused: gui-2.0 FAIL`.
   4. `test_calc_over_budget_fails` — `--calc-budget 1`, `FAKE_LUA_SLEEP=3`: calc `FAIL`, case detail starts
      `FAIL timeout`; handover rc 2 `handover refused: calc budget FAIL`.
   5. `test_calc_not_ok_output_fails` — `FAKE_LUA_OK=false`: case detail starts `FAIL not-ok`, calc `FAIL`.
   6. `test_no_game_records_not_tested_in_game` — `--no-game`: rc 0; `tested_in_game` `no`; `not_tested_reason`
      `not tested in game: --no-game`; `FAKE_GAME_LOG` absent (game never started); handover without flag rc 2
      `handover refused: not tested in game: --no-game; pass --accept-not-tested to hand over untested`; with
      `--accept-not-tested` rc 0, stdout `handover ready: <head> NOT TESTED IN GAME`.
   7. `test_handover_refuses_missing_receipt` — rc 2 `handover refused: no receipt: <path>`.
   8. `test_handover_refuses_zip_changed_after_receipt` — rewrite 2.0 zip after receipt: rc 2, message starts
      `handover refused: zip 2.0 sha256 `.
   9. `test_lane_run_id_makes_game_not_run` — `LANE_RUN_ID=x` kept, other fakes set: load and gui `not-run`, load
      reason contains `lanes never run headless Factorio`, `tested_in_game` `no`, receipt rc 1, `FAKE_GAME_LOG` absent.
   10. `test_receipt_refuses_zip_branch_or_candidate_mismatch` — 2.1 zip build_id says `factorio_branch = "2.0"`:
       rc 2, stderr starts `receipt refused: `, `--out` not created.
   11. `test_calc_budget_refuses_in_lane_without_fake_lua` — run `sh tools/calc_budget.sh player-red-science-1s` with
       `LANE_RUN_ID=x` and no `RRC_LUA`: rc 2, stderr exactly `calc_budget: refuse, lanes never run a whole sheet`.
   12. `test_calc_budget_prints_case_and_summary_lines` — direct run with fake lua: rc 0, line matches
       `^calc-budget player-red-science-1s ok wall_s=[0-9]+\.[0-9]{2} budget_s=5$`, last line `calc-budget-ok`.
   Total after change: 45 passed, 8 subtests. Keep whole module under 60 s on this host.
6. Red proof in a scratch copy, never in this worktree:
   `D=$(mktemp -d); git archive BASE_SHA | tar -x -C "$D"; cp tests/tools/test_release_gate.py "$D/tests/tools/";
   cd "$D" && git init -q && git add -A && git -c user.email=x@x -c user.name=x commit -qm base && python3 -m pytest -q tests/tools/test_release_gate.py 2>&1 | tail -15`
   (git init because tests read ROOT HEAD) → the 12 new tests FAIL, the 33 old pass. Paste as `EVIDENCE-RED:`.
7. Commit once on `lane/pm21` with plain `git commit`, subject `pm21: release_gate receipt and handover; calc budget
   5 s`, body lines `EVIDENCE-RED:`, `EVIDENCE-GREEN:` (pytest summary of the four modules in the checks block),
   `EVIDENCE-DIFFSTAT:` (`git diff --stat BASE_SHA HEAD`). Never amend, merge, rebase, push, touch `main`,
   `int/pm-260928` or any tag. Run checks LAST.

## What done mean

```checks
{"name": "release-gate-tests", "command": "python3 -m pytest -q tests/tools/test_release_gate.py 2>&1", "expect_exit": 0, "expect_regex": "(?m)^45 passed, 8 subtests passed in ", "timeout_s": 120}
{"name": "new-test-names", "command": "grep -cE '^    def test_(receipt_all_ok_records_zip_sha_load_gui_calc|receipt_load_fail_recorded_and_handover_refuses|receipt_gui_fail_recorded_and_handover_refuses|calc_over_budget_fails|calc_not_ok_output_fails|no_game_records_not_tested_in_game|handover_refuses_missing_receipt|handover_refuses_zip_changed_after_receipt|lane_run_id_makes_game_not_run|receipt_refuses_zip_branch_or_candidate_mismatch|calc_budget_refuses_in_lane_without_fake_lua|calc_budget_prints_case_and_summary_lines)\\(' tests/tools/test_release_gate.py", "expect_exit": 0, "expect_regex": "^12$", "timeout_s": 30}
{"name": "evidence-contract-tests", "command": "python3 -m pytest -q tests/tools/test_evidence_contract.py 2>&1", "expect_exit": 0, "expect_regex": "(?m)^1 passed in ", "timeout_s": 120}
{"name": "capture-workflow-tests", "command": "python3 -m pytest -q tests/tools/test_capture_workflow.py 2>&1", "expect_exit": 0, "expect_regex": "(?m)^15 passed in ", "timeout_s": 120}
{"name": "golden-tools-tests", "command": "python3 -m pytest -q tests/tools/test_golden_tools.py 2>&1", "expect_exit": 0, "expect_regex": "(?m)^14 passed in ", "timeout_s": 120}
{"name": "calc-budget-refuses-in-lane", "command": "LANE_RUN_ID=x RRC_LUA= sh tools/calc_budget.sh player-red-science-1s 2>&1; echo rc=$?", "expect_exit": 0, "expect_regex": "^calc_budget: refuse, lanes never run a whole sheet\\nrc=2\\n?$", "timeout_s": 30}
{"name": "legacy-cli-unchanged", "command": "python3 tools/release_gate.py 2.0 --matrix /nonexistent 2>&1; echo rc=$?", "expect_exit": 0, "expect_regex": "^release refused: mismatched archive: no archive supplied for branch 2\\.0\\nrc=2\\n?$", "timeout_s": 30}
{"name": "old-tests-untouched", "command": "git diff BASE_SHA HEAD -- tests/tools/test_release_gate.py | grep -cE '^-([^-]|$)'", "expect_exit": 1, "expect_regex": "^0$", "timeout_s": 30}
{"name": "game-scripts-byte-stable", "command": "git diff --quiet BASE_SHA HEAD -- tools/build_test_zip.sh tools/game_load_check.sh tools/game_test.sh tools/game_stage.sh tools/ft && echo stable", "expect_exit": 0, "expect_regex": "^stable$", "timeout_s": 30}
{"name": "owned-only-by-tool", "command": "python3 tools/lane_ownership.py check --base BASE_SHA --task docs/tasks/pm21_rrc_release_gate.md", "expect_exit": 0, "expect_regex": "(?m)^owned-only: 3 file\\(s\\) changed, 1 required deliverable\\(s\\) present$", "timeout_s": 60}
{"name": "only-owned-files", "command": "test -z \"$(git status --porcelain --untracked-files=all)\" && git diff --name-only BASE_SHA HEAD | sort | tr '\\n' ' '", "expect_exit": 0, "expect_regex": "^tests/tools/test_release_gate\\.py tools/calc_budget\\.sh tools/release_gate\\.py $", "timeout_s": 30}
{"name": "no-file-deleted", "command": "git diff --diff-filter=D --name-only BASE_SHA HEAD | wc -l", "expect_exit": 0, "expect_regex": "^0$", "timeout_s": 30}
{"name": "one-commit", "command": "git rev-list --count BASE_SHA..HEAD", "expect_exit": 0, "expect_regex": "^1$", "timeout_s": 30}
{"name": "evidence-in-commit-body", "command": "git log -1 --format=%B | grep -cE '^EVIDENCE-(RED|GREEN|DIFFSTAT):'", "expect_exit": 0, "expect_regex": "^([3-9]|[1-9][0-9]+)$", "timeout_s": 30}
```

## Files this lane owns

- `tools/release_gate.py` — `receipt` and `handover` subcommands, docstring; legacy form byte-stable
- `tests/tools/test_release_gate.py` — append class `HandoverReceiptTests` (12 tests) only; existing lines untouched
- `!tools/calc_budget.sh` — new, 5 s generation budget per golden case

## Do not

Never run a full suite, a `lua5.2` test, `tests/golden/generate.lua`, a real `factorio`, `tools/game_test.sh` or
`tools/game_load_check.sh` outside the fake env of step 5, or `make` anything. Never edit this task file, any
`*.manifest`, `tools/build_test_zip.sh`, `tools/game_load_check.sh`, `tools/game_test.sh`, `tools/game_stage.sh`,
`tools/ft/`, `tools/handoff.sh`, `prepare_release.sh`, `tools/evidence_receipt.py`, `logic/`, `tests/test_*.lua`,
`tests/game/`, `tests/fixtures/`, `docs/`, or any other file. Never weaken or delete an assert. Never amend,
rebase, push, or touch `main`, `int/pm-260928` or a tag.

Re-cut because: none

# bound: 3000s

Reviewer ask: legacy form byte-identical (old 33 tests + `legacy-cli-unchanged`); receipt runs the REAL
`game_load_check.sh`/`game_test.sh`/`calc_budget.sh` through fake binaries (producer output into consumer, not a
canned string); every test sets all four seam vars under temp before dropping `LANE_RUN_ID`; handover refuses
missing receipt, changed zip, load/gui/calc not ok, untested without `--accept-not-tested`.
