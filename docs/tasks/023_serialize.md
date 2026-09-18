# 023 — the blueprint the game reads, and the form a golden compares

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-023`, branch `lane/023`, base = `feat/round-8-blueprints`, tag `wave-2-green` (resolve it with `git rev-parse wave-2-green`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- Every existing test stays green and unmodified. Run `sh tests/run.sh`; never edit a file under `tests/` other than the one this lane owns.
- `control.lua`, `gui/sheet.lua`, `gui/calculator.lua`, `tests/harness.lua`, `locale/*/locale.cfg`, `docs/feature-contracts.md` and everything under `tools/` are frozen. If you need a change in one, stop and report it; do not edit it.
- Nothing you put in `storage` may be a function, a metatable or a LuaObject: the game saves it.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- You own `logic/bp/serialize.lua` and `tests/test_serialize.lua` only.
- Entity numbers are assigned here and nowhere else, by sorting (y, x, id). Every cross reference is remapped in the same pass.
- A golden compares canonical structure, never the compressed string: equal factories can compress to different bytes.
- Work from hand-written layout fixtures; the search does not exist yet.

Current facts:
- `docs/feature-contracts.md` is the contract: units, storage keys, the job shape, the two geometry models, the four rotation operations, entity ids, flows, wires, ports, reason codes. Read it before writing code; it is not negotiable from inside a lane.
- Test files are discovered by `tests/run.sh` as `tests/test_*.lua` and run under lua5.2 then lua5.4. A file starts with a one-line comment saying what it proves, then `local H = require "tests.harness"`, and ends with `H.done("test_<topic>")`.
- Version-dependent cases go in `for _, shape in ipairs(H.shapes()) do ... end` with case names starting `<shape> <clause id> ...`. The clause id matters: the mutation runner matches a mutant to a case by substring.
- Assertions are `H.equal`, `H.near`, `H.near_relative`, `H.deep_equal`, `H.errors(fn, substring, what)`. They tag their failures `[assert]`; anything else prints `[error]` and does not count as a red proof.
- `logic/bp/serialize.lua` carries the contract, `Serialize.CANONICAL_VERSION` and the stubs `begin`, `step`, `entity_order` and `canonical`.
- The pinned `BlueprintEntity` fields are in `docs/api/2.0.77.members.json` and `docs/api/2.1.19.members.json`: `name`, `position`, `entity_number`, `direction`, `quality`, `items`, `tags`, `mirror`, `wires`, plus the entity-specific fields a real blueprint carries (`recipe`, `recipe_quality`, `type` on an underground belt, `drop_position`, `request_filters`).
- A real decoded example is at `/home/dev_zaigraev_gmail_com/codex-reviews/rrc-feature-requirements-2026-09-18/example-blueprint.json`: a foundry carries `recipe` and `recipe_quality` and its modules as `items` with `in_inventory` slots (inventory 4 for a machine, 1 for a beacon); a roboport carries `quality`; an underground belt carries `type = "output"`; a bulk inserter carries `drop_position` as an array pair.
- `BlueprintWire` is a tuple of four numbers: entity number, connector id, entity number, connector id.
- Canonical rules (`docs/feature-contracts.md` §13): keys sorted, arrays in their defined order, entity numbers remapped by (y, x, id), MapPositions written as objects, numbers `%.17g` with integers written whole, volatile metadata dropped, everything affecting layout, connectivity or throughput kept.
- The harness serves `helpers.table_to_json`, and a blueprint item stack takes entities through `set_blueprint_entities`.

## What to build

1. `Serialize.begin`/`Serialize.step` turn a candidate into the blueprint table within the budget: entities in `entity_order`, modules as inventory requests, recipes with their quality, undergrounds with their type and partner, wires as tuples, plus label, icons and a description carrying the target rates, the external ports and the infrastructure choices.
2. `Serialize.canonical(blueprint)` returns the comparable form and its version.
3. Red-first cases in `tests/test_serialize.lua`: entity numbers follow (y, x, id) and every cross reference is remapped with them; the same layout translated to another origin has the same canonical form; renumbering alone changes nothing canonical; a changed module quality, belt direction, wire or machine position changes it; a module request lands in the right inventory with the right slots; an underground pair keeps its type and its partner; a `drop_position` is written as an object and an array in the source normalizes to the same canonical value; two runs over one candidate give byte-identical canonical JSON; a quality entity carries its quality and a normal one omits it.
4. Planted breach, pasted red then reverted: normalize away belt direction, and the direction case must go red.

## What done mean

```checks
{"name": "serialize-tests", "command": "lua5.2 tests/test_serialize.lua && lua5.4 tests/test_serialize.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-2-green --manifest docs/tasks/023.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null 2>&1; git -C \"$S\" checkout wave-2-green -- logic/bp/serialize.lua; out=$(cd \"$S\" && lua5.2 tests/test_serialize.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
```

- Red first pasted, green after pasted, planted breach pasted then reverted.
- `git diff --stat wave-2-green HEAD` pasted.

Run the checks as your **last** action, after your final commit. A commit made after the checks moved the tree the
proof was taken against, and the supervisor refuses that proof with the reason `tree-moved`, however green every
check was.

Run the whole suite through the lease: `gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh`, from the worktree root. Wait for the lease however long; never stop because of queue wait. Commit when a step is finished, with the pasted output in the message body.

## Files this lane owns

- `logic/bp/serialize.lua`
- `tests/test_serialize.lua`

Touch nothing else.

# bound: 8000s

Reviewer ask: does the canonical form survive renumbering and translation while still changing when a belt direction changes?
