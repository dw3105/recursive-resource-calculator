# 061 — The search keeps its optimisation and still ends

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-061`, branch `lane/061`, base tag `routing-recovery-base` (resolve with `git rev-parse routing-recovery-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/search.lua`, `tests/test_search.lua` and new `tests/test_search_budget.lua`. Everything else is frozen. If you need a change elsewhere, stop and report it.
- `logic/bp/route.lua`, `logic/bp/power.lua`, `logic/bp/pack.lua`, `logic/bp/groups.lua` and `logic/bp/validate.lua` have other owners. Never edit them.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- `tests/test_companion_api_shapes.lua` is red on this base, by design: it names three companion calls another lane repairs. Ignore it. Never run the whole suite as your gate.

A commit on this base, `a73f347`, changed `finish_grid_or_search` in `logic/bp/search.lua` to stop growing the
grid as soon as any incumbent exists:

```lua
local function finish_grid_or_search(state)
    if state.incumbent == nil and next_grid(state) then return end
```

Its comment claims a larger grid can never lower a beacon count because the candidate list does not depend on
the grid. **That claim is not supported.** Whether a lower-beacon candidate *fits* does depend on grid size, and
the user explicitly asked for larger-grid exploration when it can reduce beacons. The existing
"larger grid wins" case in `tests/test_search.lua` passes either way, so it does not guard this shortcut.

Why the shortcut was made, measured on this base, host `legalcopilot-dev`, 2026-09-19: the grid list is every
`cols` from 2 to 8 by every `rows` from 2 to 8, 49 sizes, and the smallest is already 54 by 54 tiles. The whole
fixture spent 1200 ticks without a terminal result:

```text
PROF pack   calls=34   ops=440      time=1.18
PROF route  calls=1180 ops=2295680  time=29.95
PROF power  calls=64   ops=102436   time=61.27
```

## What to build

Replace the unsupported assumption with a stopping rule that is tested.

1. Add a case where the first grid holds a **valid incumbent with a higher beacon count**, and a larger grid makes
   a lower-beacon candidate feasible. That case must fail on this base and pass on your work.
2. Explore grid and candidate combinations that can still improve the beacon-first score, until the deterministic
   budget is exhausted. Skip work only with a defensible lower bound, or because every relevant candidate for that
   grid is already covered.
3. When the budget ends, keep the best fully validated incumbent and reserve enough work to serialize it. With no
   incumbent, return the budget failure code, never an unsupported-sheet verdict.
4. Keep the agreed order: fewest beacons, then compactness, then fewer poles. Keep breadth bounded; never walk all
   49 grids unconditionally.
5. Revisions and cancellation are checked before publication, as they are today.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d); git worktree add --detach \"$S\" HEAD >/dev/null; git -C \"$S\" checkout routing-recovery-base -- logic/bp/search.lua; out=$(cd \"$S\" && lua5.2 tests/test_search_budget.lua 2>&1); rc=$?; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL .* \\[assert\\]' && [ \"$rc\" -ne 0 ] && echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_search.lua && lua5.4 tests/test_search.lua && lua5.2 tests/test_search_budget.lua && lua5.4 tests/test_search_budget.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "pipeline-gate", "command": "lua5.2 tests/test_blueprint_pipeline.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1200}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base routing-recovery-base --manifest docs/tasks/061.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

`tests/test_search_budget.lua` must contain, at least:

- The larger-grid beacon improvement case described above.
- Equal-score determinism: two runs on one input choose the same layout.
- Two tick slice sizes reach the same published result.
- Budget exhaustion with an incumbent publishes that incumbent; budget exhaustion with none reports the budget
  code, never `BP_FAIL_NO_LAYOUT_GRID_LIMIT` when the limit was work rather than grid size.

## Files this lane owns

`logic/bp/search.lua`, `tests/test_search.lua`, `tests/test_search_budget.lua`.

# bound: 1918s
