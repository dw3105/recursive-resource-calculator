# 275_tools_slow_guard slow tools refuse to start without a named slot and a reason

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-275`, branch `lane/275`,
base tag `round-47-base`, merge target `int/r44`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 45 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and BOTH checks pass. Commit early, commit again, run the
checks LAST. **Never edit this task file. Touch only the files this lane owns.**

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/measure_sheet.sh`, `tools/gate_sheet.sh`,
`tools/bytes_hash.sh`, `tools/golden_profile.lua`, `tools/game_test.sh`, `tests/golden/generate.lua`,
`tools/first_stage.lua`, `tools/ckpt.lua save|list|uninterrupted`, `factorio`, or any full suite, whole sheet or
headless run of any kind. No command may take more than 60 s.** Run only single test files, one at a time, with
`timeout 90 lua5.2 tests/<file>.lua` (lua5.2 ONLY). Never use `coroutine`. `require` only at file top level. **No
game item or entity name in `logic/`.** Every new test must FAIL on the base code where this task says "red on
base" (say so in its header comment); commit it red first.

## Explain very simply

The player ordered (2026-09-28): "put a mechanism preventing using slow checks when fast checks are available".
Whole-sheet runs cost 5-40 min; the fast checks (checkpoint reads, one-stage replays, single test files) cost
seconds. Today nothing stops a slow run. Build a guard INSIDE the slow tools, so it binds every caller (people,
Claude sessions, Codex lanes).

Rule: a slow tool starts only when env `RRC_SLOW=<slot>:<reason>` is set, slot in
{`profile`, `bytes`, `suite`, `headless`, `ckpt-save`, `release`, `test`}, reason at least 20 characters (slot
`test` reason at least 3). Otherwise it prints ONE line to stderr and exits 7:
`SLOW-REFUSED <tool> -> fast rung: <hint>` where hint names the fast rung for that tool, e.g.
generate/golden_profile → "ckpt.lua resume <checkpoint> | one-stage replay"; bytes_hash/gate_sheet → "merge gate
only (RRC_SLOW=bytes:...)"; ckpt save → "reuse an existing checkpoint in tests/fixtures/route_snaps".
Every allowed start appends one TAB line to `${RRC_SLOW_LEDGER:-$HOME/.cache/rrc/slow_ledger.tsv}`: ISO time,
wave (content of `${RRC_WAVE_FILE:-$HOME/.cache/rrc/wave}` or `unset`), slot, tool, reason, host. Budget per slot
per wave in `tools/slow_budget.json` (`{"profile":1,"bytes":1,"suite":2,"headless":1,"ckpt-save":3,"release":2,
"test":-1}`, -1 = unlimited): over budget → refuse (same one-line form, hint "budget used").
Slot `test` is only for small inputs: allowed when the tool's input file is NOT under `tests/golden/cases/`
(generate / golden_profile / ckpt save on a small fixture); a golden case with slot `test` is refused.
Child processes inherit the env: `RRC_SLOW=suite:... sh tests/run.sh` lets the `*_delivers` tests run inside the
suite; running such a test alone without RRC_SLOW makes it fail fast with the refusal (that is intended).

Tools guarded (first executable lines only; nothing else in these files changes):
`tests/golden/generate.lua`, `tools/golden_profile.lua`, `tools/ckpt.lua` (modes `save`, `list`, `uninterrupted`;
`resume` is NOT guarded — its cost is bounded by the checkpoint), `tools/first_stage.lua`, `tools/bytes_hash.sh`,
`tools/gate_sheet.sh`, `tools/measure_sheet.sh`, `tools/speed_probe.sh`, `tests/run.sh`, `tools/game_test.sh`.
Lua tools call `require("tools.lib.slow_guard").check(tool_name, input_path)` (keep `package.path` working from repo
root; the module must not `require` anything outside the Lua standard library); shell tools call
`sh tools/slow_guard.sh <tool> <input>` which runs the same Lua module (single source of truth).
Note: `tools/golden_profile.lua` runs `tests/golden/generate.lua` inside itself — the check must pass once per
process (set a global flag so the inner call does not log a second ledger line).

## What to build

1. `tools/lib/slow_guard.lua`, `tools/slow_guard.sh`, `tools/slow_budget.json`.
2. Guard lines at the top of each listed tool.
3. `tests/test_slow_guard.lua` (run subprocesses with `io.popen`, temp ledger via `RRC_SLOW_LEDGER`, temp wave file):
   SG1 (red on base) `lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json
   --output /tmp/x` without RRC_SLOW exits 7 in < 2 s with `SLOW-REFUSED`. SG2 short reason refused. SG3 unknown slot
   refused. SG4 valid slot+reason: guard passes (call the module's `check` directly, do NOT run the sheet) and one
   ledger line is written. SG5 budget: 2nd `profile` in same wave refused. SG6 slot `test` + golden case refused;
   slot `test` + a small fixture path allowed. SG7 each listed tool refuses without env (shell tools via
   `sh tools/<x>.sh`; stop at refusal, nothing heavy runs). SG8 `ckpt.lua resume` NOT refused.
4. Also keep green: `test_no_item_names`, `test_no_runtime_require`, `test_locale_keys`, `test_route_keys`,
   `test_route_no_replay` (they call ckpt resume; must stay unaffected).

## Files this lane owns

tools/lib/slow_guard.lua, tools/slow_guard.sh, tools/slow_budget.json, tests/test_slow_guard.lua, and ONLY the first
lines of tests/golden/generate.lua, tools/golden_profile.lua, tools/ckpt.lua, tools/first_stage.lua,
tools/bytes_hash.sh, tools/gate_sheet.sh, tools/measure_sheet.sh, tools/speed_probe.sh, tests/run.sh,
tools/game_test.sh, docs/tasks/275_tools_slow_guard.md. Never touch anything else.

## Commit, THEN check

Commit on `lane/275`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane275-tests", "command": "git diff --name-only round-47-base HEAD | grep -Ev '^(tools/lib/slow_guard\\.lua|tools/slow_guard\\.sh|tools/slow_budget\\.json|tests/test_slow_guard\\.lua|tests/golden/generate\\.lua|tools/golden_profile\\.lua|tools/ckpt\\.lua|tools/first_stage\\.lua|tools/bytes_hash\\.sh|tools/gate_sheet\\.sh|tools/measure_sheet\\.sh|tools/speed_probe\\.sh|tests/run\\.sh|tools/game_test\\.sh|docs/tasks/275_tools_slow_guard\\.md)$' | ( ! grep . ) && git diff --quiet round-47-base HEAD -- docs/tasks && [ $(git diff round-47-base HEAD -- tests/golden/generate.lua tools/golden_profile.lua tools/ckpt.lua tools/first_stage.lua tools/bytes_hash.sh tools/gate_sheet.sh tools/measure_sheet.sh tools/speed_probe.sh tests/run.sh tools/game_test.sh | grep -c '^-[^-]') -le 3 ] && for t in test_slow_guard test_no_item_names test_no_runtime_require test_locale_keys test_route_keys test_route_no_replay; do [ -f tests/$t.lua ] || { echo MISSING $t; exit 1; }; timeout 900 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane275-tests-ok", "expect_exit": 0, "expect_regex": "lane275-tests-ok", "timeout_s": 2400}
{"name": "lane275-fast", "command": "out=$(timeout 120 lua5.2 tests/test_slow_guard.lua 2>&1); for c in SG1 SG2 SG3 SG4 SG5 SG6 SG7 SG8; do echo \"$out\" | grep -q \"$c\" || { echo MISSING $c; exit 1; }; done; echo \"$out\" | tail -1 | grep -q ' 0 failed' && echo lane275-ok", "expect_exit": 0, "expect_regex": "lane275-ok", "timeout_s": 600}
```

# bound: 2700s
