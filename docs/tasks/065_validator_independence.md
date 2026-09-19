# 065 — The validator catches the router's new mistakes on its own

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-065`, branch `lane/065`, base tag `route-cost-base` (resolve with `git rev-parse route-cost-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/validate.lua`, `logic/bp/serialize.lua`, `tests/test_validate.lua`, `tests/test_serialize.lua` and new `tests/test_route_layout_contract.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/route.lua`, `logic/bp/search.lua`, `logic/bp/pack.lua`, `logic/bp/groups.lua` and `logic/bp/power.lua` have other owners. Never edit them. Never change routing or packing in this lane.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Routing gained three behaviours recently, and the validator has no case of its own for any of them, host
`legalcopilot-dev`, 2026-09-19:

1. **Underground crossings.** When a tile is taken, the search dives under it and surfaces within the family's
   underground distance. The tiles between carry no segment. The pair's ends are `type = "input"` at the demand's
   source and `type = "output"` at its sink.
2. **Port approach reservation.** A port owns its own tile and the tile its transport reaches it from. A belt of
   the same flow may pass; a belt of another flow may not.
3. **Rip-up and reorder.** A failed demand rips every segment out and routes again with itself first, so the
   published layout may differ from the first attempt's.

Treat routing output as untrusted candidate data at the validator boundary. A validator case that calls the same
occupancy helper as the producer cannot catch the producer's bug.

## What to build

Independently enumerated tiny layouts, written by hand, never produced by the router:

- Crossings in all four cardinal directions, both endpoint types, a pair beyond its underground distance, a pair
  whose ends face the wrong way, and a pair whose middle tile wrongly carries a segment.
- A belt of another flow standing on a port's approach tile.
- Shared item flow across one trunk with two consumers, and two fluids that must never share a pipe.
- Rotated and asymmetric block occupancy.
- A legal layout in each shape, which must stay accepted. Refusing every crossing is not a fix.

Each broken layout fails by its named reason code, never by an interpreter error. Serialization must preserve the
verified direction, endpoint type, quality and wire of every entity it writes.

If you find a producer defect, report it with the smallest candidate that shows it and the invariant it breaks.
Never repair it here.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout route-cost-base -- logic/bp/validate.lua; out=$(cd \"$S\" && lua5.2 tests/test_route_layout_contract.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_validate.lua && lua5.4 tests/test_validate.lua && lua5.2 tests/test_serialize.lua && lua5.4 tests/test_serialize.lua && lua5.2 tests/test_route_layout_contract.lua && lua5.4 tests/test_route_layout_contract.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "route-untouched", "command": "git diff --name-only route-cost-base HEAD | grep -qE '^logic/bp/(route|search|pack|groups|power)\\.lua$' && exit 1; echo route-untouched", "expect_exit": 0, "expect_regex": "route-untouched", "timeout_s": 120}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base route-cost-base --manifest docs/tasks/065.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

## Files this lane owns

`logic/bp/validate.lua`, `logic/bp/serialize.lua`, `tests/test_validate.lua`, `tests/test_serialize.lua`, `tests/test_route_layout_contract.lua`.

# bound: 1918s
