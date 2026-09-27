# 248_route_fail_snapshot one failed route demand is replayed alone in seconds

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-248`, branch `lane/248`,
base tag `round-44-wave3`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 40 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns. Never edit anything under `logic/`.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/stage_fail.lua`, `tests/golden/generate.lua`, `tools/game_test.sh`, `factorio`, or any
full suite, sheet run or headless run of any kind.** Run only single test files, one at a time, with
`lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. Every new test must FAIL on the base code (the tools
do not exist there; say so in its header comment).

## Explain very simply

Route on the player's gray + magenta sheet (frozen input `tests/fixtures/route_gray_magenta_154.json`, 92 demands)
is slow to diagnose: building its demands takes 23 s, each demand ~1.4 s, and every failed demand restarts all 92.
So the 5th failure is seen only after minutes (measured legalcopilot-dev, 2026-09-27). We need: stop at the Nth
failure, save the whole route state to a file, and later load that file and run ONLY the failed demand again — in
seconds — optionally with an in-memory patch of `logic/bp/route.lua` to try a fix.

Key fact: a refused commit restores the route state (`append_normal_path` -> `restore_route_snapshot`), and a search
only changes the demand's own fields and counters. So the route state at the ENTRY of `fail_demand` equals the state
before that demand was tried. Save it there; on replay reset the failed demand and run it.

## What to build

1. `tools/route_fail_snapshot.lua` — usage `lua5.2 tools/route_fail_snapshot.lua <route_input.json> <N> <out>`
   (env `PATCH=<file.lua>` optional, see 3). Loads input as `tests/test_route_pipe_join.lua` PJ4 does
   (`H.new_world("2.0")`, `helpers.json_to_table`), loads `logic/bp/route.lua` source, hooks the first line of
   `local function fail_demand(state, work, demand, code, detail)` via `gsub` + `package.preload` (replacement given
   as a function: `%` breaks gsub strings). Runs `Route.begin` + `Route.step(st, {ops = 2000})`. On the Nth call: write
   the WHOLE route state table `state` (everything reachable; tables shared by reference stay shared after load;
   cycles allowed; functions and userdata skipped and listed on stderr) plus the failed demand's position in
   `state.work.demands` and `code`, then exit 0. Print `SNAPSHOT <out> demand=<i> flow=<flow_id> code=<code>
   sink=<sink port_id> t=<cpu s>`. Format is your choice (Lua data chunk or JSON with node ids); loading it must take
   under 5 s for this fixture.
2. `tools/route_replay_one.lua` — usage `lua5.2 tools/route_replay_one.lua <snapshot>` (env `PATCH`, `MAP=1`). Loads
   the snapshot, resets the failed demand (`remaining = amount`, `source_index`/`sink_index` = 1 and
   `source`/`sink` = first candidates, clear `crossing_blocked`, `crossing_retries`, `bury_blocked`; keep flags like
   `curve_allowed`, `free_heading`, `allow_ride`, `no_chain_dive`, `strict_branch` unless env `RESET_FLAGS=1`),
   `state.work.current = nil`, cursor on that demand, `state.done = false`. Hooks `fail_demand` (stop and report, do
   NOT restart) and `append_normal_path` (capture the last path and its result). Steps until the demand is placed or
   fails. Prints `REPLAY placed|failed code=<code> reason=<last_route_rejection.reason> path=<n> cells t=<cpu s>`, the
   path cells (`x,y` list, jumps marked `J<distance>`), and with `MAP=1` a text tile map around source and sink
   (`S`, `T`, `*` own flow, `-` other belt, `=` pipe, `#` obstacle, `p` port cell, `.` free).
3. `PATCH=<file.lua>`: the file returns `function(src) return src end`-style transformer applied to the route source
   before `load` (same in both tools), so a fix can be tried without editing `logic/`.
4. `tests/test_route_fail_snapshot.lua` (commit red first):
   - FS1: snapshot `tests/fixtures/route_gray_magenta_154.json` N=1 to a temp file (`os.tmpname()`); it names
     `item/coal`, sink `in:item/coal:inserter:plastic-bar:2:input:1`, code `BP_R_NO_PATH` (about 30 s). Replay it
     (run the tool as a subprocess via `io.popen("lua5.2 tools/route_replay_one.lua " .. file)`) -> `REPLAY failed`,
     reason `route-discontinuous`, and replay CPU `t` under 10 s.
   - FS2: replay the same snapshot with a PATCH file (written by the test to a temp file) that returns
     `function(src) return (src:gsub('and not %(current.mode == 1 and search.demand.kind == "pipe"%)', 'and not (current.mode == 1)', 1)) end`
     -> `REPLAY placed`. (This proves trial patches work: it is the chain-dive ban traced for this coal demand.)
   Make the snapshot once and reuse it for FS2. Print each case name.

## Files this lane owns

tools/route_fail_snapshot.lua, tools/route_replay_one.lua, tests/test_route_fail_snapshot.lua,
docs/tasks/248_route_fail_snapshot.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/248`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane248-tests", "command": "git diff --name-only round-44-wave3 HEAD | grep -Ev '^(tools/route_fail_snapshot\\.lua|tools/route_replay_one\\.lua|tests/test_route_fail_snapshot\\.lua|docs/tasks/248_route_fail_snapshot\\.md)$' | ( ! grep . ) && git diff --quiet round-44-wave3 HEAD -- docs/tasks/248_route_fail_snapshot.md logic && for t in test_route_fail_snapshot test_no_item_names test_no_runtime_require test_locale_keys; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 600 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane248-tests-ok", "expect_exit": 0, "expect_regex": "lane248-tests-ok", "timeout_s": 1800}
{"name": "lane248-fast", "command": "out=$(lua5.2 tests/test_route_fail_snapshot.lua 2>&1); for n in FS1 FS2; do echo \"$out\" | grep -q \"$n\" || { echo MISSING $n; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane248-ok", "expect_exit": 0, "expect_regex": "lane248-ok", "timeout_s": 600}
```

# bound: 2400s
