# 012 — what this release refuses, said all at once

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-012`, branch `lane/012`, base = `feat/round-8-blueprints`, tag `wave-1-green` (resolve it with `git rev-parse wave-1-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/bp/preflight.lua`, `logic/bp/reason_codes.lua` and `tests/test_bp_preflight.lua`.
- Every rejection carries a code from the enum and names the recipe, machine or product at fault. Codes never change spelling: goldens compare codes.
- Report every reason at once, not the first one found. A player fixes one sheet, not one blocker per attempt.
- An unsupported choice that is inactive or running at zero rate does not block an otherwise supported sheet.
- A rejection is what this version cannot model. It is never a claim that something is impossible.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/bp/preflight.lua` carries the stub `Preflight.check(snapshot, solver_result, catalog, options)` returning a list, and the limits `MAX_MACHINES = 100`, `MAX_STEPS = 30`.
- `logic/bp/reason_codes.lua` holds every code and `ReasonCodes.locale_key(code)`. Every `BP_REJ_*` key already exists in en, cs and ro; `tests/test_locale_keys.lua` fails if one is missing, so adding a code means adding its three locale lines, which you cannot do from this lane: if you need a new code, stop and report.
- What must be rejected (BP-03): spoilage-sensitive production, probabilistic or random-amount products, quality-changing production and quality loops, other dependency cycles, mining, burner-powered machines and fuel-burning consumers, handcrafting, non-electric machines, unsupported machine interfaces and geometry, unresolved prototypes, non-finite rates, a sheet with no finished calculation or a stale one, equal input and output edges, an unusable infrastructure choice, a belt with no family, a quality that is not unlocked, a machine set up with more modules than slots, a quality machine configured to receive speed beacons, and the two size limits.
- The solver already reports cycles and loops through `reasons_by_column` and the quality-loop `reason` field (`logic/solver.lua:832-840`); read those rather than re-deriving them.
- Spoilage, probability and random amounts are prototype facts in the catalog: a product with a probability below 1, an `extra_count_fraction`, or an item with a spoil result. Identify modules by their effects, never by name.
- `Utils.IS_2_1` marks the branch; quality-changing production is refused on both.

## What to build

1. `Preflight.check` returns every applicable rejection, each `{code, subject = {kind, name, quality}, detail, locale_key}`, sorted so the same sheet always reports them in the same order.
2. Size limits are checked before anything expensive, and their detail carries the count and the limit so the message can say both.
3. An empty list means the request may proceed.
4. Red-first cases in `tests/test_bp_preflight.lua`, one per code that a fixture can produce: a cycle; a quality loop; a quality module changing product quality; a spoiling ingredient; a probabilistic product; a random-amount product; a mining step; a burner machine; a fuel-burning consumer; a hand-crafted step; a non-electric machine; a stale snapshot; a non-finite rate; a sheet with nothing to build; an unresolved prototype; a machine with more modules than slots; a locked quality; equal edges; a belt with no family; a quality machine configured with speed beacons; a sheet over 100 machines; a sheet over 30 steps. Plus: a supported sheet returns an empty list; an inactive unsupported recipe at zero rate does not block; several problems at once are all reported; every returned code exists in the enum and has a locale key.
5. Planted breach, pasted red then reverted: return on the first rejection found, and the several-problems case must go red.

## What done mean

```checks
{"name": "bp_preflight-tests", "command": "lua5.2 tests/test_bp_preflight.lua && lua5.4 tests/test_bp_preflight.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-1-green --manifest docs/tasks/012.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-1-green -- logic/bp/preflight.lua; git -C \"$S\" checkout wave-1-green -- logic/bp/reason_codes.lua; out=$(cd \"$S\" && lua5.2 tests/test_bp_preflight.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-1-green HEAD` pasted.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/bp/preflight.lua`
- `logic/bp/reason_codes.lua`
- `tests/test_bp_preflight.lua`

Touch nothing else.

# bound: 7200s

Reviewer ask: does a sheet with three separate blockers report all three, and does an unsupported recipe at zero rate block anything?
