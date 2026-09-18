# 007 — the debug envelope, and an encoding that decodes offline

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-007`, branch `lane/007`, base = `feat/round-8-blueprints`, tag `wave-1-green` (resolve it with `git rev-parse wave-1-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/export_payload.lua` and `tests/test_export_payload.lua` only.
- `gui/export_dialog.lua` is another lane's file and calls `ExportPayload.build(player_index, sheet_flow)` and `ExportPayload.encode(payload)`. Keep both names and their return shapes: `encode` returns the string, or nil plus a reason.
- Serialization is read-only: building a payload never recalculates, never repairs and never writes a stored setting.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/export_payload.lua` carries `ExportPayload.FORMAT = "rrc-sheet-debug"`, `SCHEMA_VERSION = 1` and the stubs.
- `logic/snapshot.lua` (merged in wave 1) gives the sheet half: `Snapshot.of_sheet`, `Snapshot.fingerprint`, `Snapshot.state_of`. `logic/catalog.lua` gives `Catalog.for_export(player_index, referenced)`, which projects only what the calculation referenced. Use both; do not re-read the GUI or walk every prototype yourself.
- `logic/solver.lua:832-840` documents the result: `status`, `columns`, `recipe_rates`, `solved_rates`, `unsolved_rates`, `reasons_by_column`, `product_parts`, `feed_rounds`. A column carries `recipe_name`, `product_full_name`, `consumer`, `burner`, `quality_loop`, `net_amounts`, `binding_full_name`. Every reason is a locale key, and the export carries the key, never a translated sentence.
- Encoding is `helpers.encode_string(helpers.table_to_json(payload))`, with no leading Factorio blueprint character. The harness serves both, and `H.decode_export(string)` is the inverse your tests read.
- `helpers.table_to_json` refuses NaN and infinity: a non-finite diagnostic value must be tagged, for example `{rrc_non_finite = "nan"}`, before it reaches the encoder.
- `world.fail_next_encode()` makes the next encode return nil exactly once.
- The offline acceptance is `python3 -c 'import base64, json, zlib; ...'` on the string. Keep the payload JSON-safe: no Lua object, no function, no cycle, and sorted keys wherever order carries no meaning.

## What to build

1. `ExportPayload.build` assembles the versioned envelope: format, schema version, encoding name, mod version; environment (base game version, active mods and versions, relevant mod settings, force research and quality unlocks the calculation used); the snapshot; the selection; the calculation with full-precision rates, statuses, reason keys and the quality-loop stage results; the referenced prototypes; and diagnostics (missing prototypes, rejected values, the last blueprint attempt when there was one).
2. Current settings and the result's own settings stay apart, each with its fingerprint, plus the state and the calculation tick. An old result is never labelled current.
3. Order that carries meaning is preserved (targets, module slots); everything else is sorted so one unchanged sheet exports to one string. Full precision, no display rounding. Empty list and empty object stay distinguishable. A non-finite value is tagged rather than written as a broken number. An unavailable prototype appears as its identity plus an explanation.
4. `ExportPayload.encode` returns the encoded string, or nil and a reason when encoding fails. It never returns a shortened string.
5. Red-first cases in `tests/test_export_payload.lua`: a payload decodes through `H.decode_export` with format and schema version intact; targets keep order and full precision; a failed calculation exports with its reason keys and no invented rates; an empty sheet exports; a stale result is labelled stale and carries the settings it was computed with; the same unchanged sheet exported twice gives equal payloads apart from explicitly volatile fields; a removed prototype appears as an identity with an explanation and nothing crashes; NaN or infinity is tagged and the encode still succeeds; `world.fail_next_encode()` yields nil and a reason; the payload contains no value whose `type` is `"userdata"`; a second player's sheets never appear.
6. A Python acceptance case: write the string to a file and decode it with `base64.b64decode` then `zlib.decompress` then `json.loads`, asserting `format` and `schema_version`. Put it in your own test through `io.popen("python3 -c ...")` and assert the output, so the documented decoder is proven rather than described.
7. Planted breach, pasted red then reverted: label a stale result current, and the stale case must go red.

## What done mean

```checks
{"name": "export_payload-tests", "command": "lua5.2 tests/test_export_payload.lua && lua5.4 tests/test_export_payload.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-1-green --manifest docs/tasks/007.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-1-green -- logic/export_payload.lua; out=$(cd \"$S\" && lua5.2 tests/test_export_payload.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-1-green HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree
the proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green
every check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/export_payload.lua`
- `tests/test_export_payload.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: does the exported string decode with python3 base64 plus zlib, and can an old result ever be labelled current?
