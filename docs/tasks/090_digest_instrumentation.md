# 090 — The acceptance gate compares content, never a list of ids

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-090`, branch `lane/090`, base tag `round-9-base` (resolve with `git rev-parse round-9-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `tests/acceptance/lib/gate.lua` and new `tests/acceptance/gate_digest_case.lua`.
- `tests/acceptance/lib/chains.lua`, the three `*_case.lua` files and `tests/acceptance/README.md` are frozen. Lane 091 owns them in wave 2.
- `logic/bp/search.lua` and `logic/bp/serialize.lua` are frozen. Runtime prevention is lane 095's job, not yours.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- Never edit a file this lane does not own. If you need a change elsewhere, stop and report it.
- Never weaken an assertion, delete a case, or accept a new baseline. A changed expectation stops the lane.
- Never edit `info.json` or `mod-description.md`; both carry the player's own uncommitted work.
- Never add a "skip if the dependency is missing" branch to any test.

Measured on this base, `tests/acceptance/lib/gate.lua:8-15`: the fingerprint is the entity count plus the sorted
entity ids. Two candidates with the same ids and different positions, directions, recipes, modules, qualities or
wires produce the same string, so the README's claim that "the serialized candidate is the one the validator
accepted" is weaker than it reads.

**Scope:** this is test instrumentation. It detects a mismatch after the fact; it prevents nothing at runtime.
Say so plainly in your report, and deliver the README wording lane 091 will apply.

## What to build

1. A deterministic digest over the content that decides a blueprint: entity id, name, position, direction, quality, recipe, module loadout, and wire endpoints, in a stable order.
2. `demand_success` compares digests, and its failure message names the first differing field.
3. `tests/acceptance/gate_digest_case.lua` mutates one position after validation and proves the acceptance case fails.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-9-base -- tests/acceptance/lib/gate.lua || exit 1; if out=$(cd \"$S\" && lua5.2 tests/acceptance/gate_digest_case.lua 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL 2\\.0 GD1 .* \\[assert\\]' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 900}
{"name": "owned-case", "command": "lua5.2 tests/acceptance/gate_digest_case.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "delivery-set-still-passes", "command": "sh tests/acceptance/run 2>&1 | tail -6", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "suite", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 090_digest_instrumentation", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-9-base --manifest docs/tasks/090.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Case names: `GD1` a position changed after validation blocks the acceptance case; `GD2` an unchanged candidate
still passes; `GD3` a changed module loadout is caught; `GD4` a changed wire endpoint is caught.

## Files this lane owns

`tests/acceptance/lib/gate.lua`, `tests/acceptance/gate_digest_case.lua`

# bound: 2400s
