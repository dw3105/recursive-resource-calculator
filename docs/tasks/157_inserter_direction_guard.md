# 157 guard: every generated inserter direction, judged against the player's own factory

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-157`, branch
`lane/157`, base tag `round-19-base`, merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Round 18 shipped a blueprint whose **26 inserters were all 180 degrees wrong**, the player placed it, and
nothing in this repo had noticed. **No test anywhere asserts a concrete `direction` for a GENERATED
inserter.**

What the existing tests actually do:

- `tests/test_inserter_geometry.lua:89-99` IG2 is role-split, but it asserts the pickup and drop **positions
  that `logic/bp/groups.lua` itself published**. A reversed pair with matching positions passes. Self
  consistent by construction.
- `tests/test_inserter_geometry.lua:216-236` IG11's two branches assert the identical two things; only the
  message strings differ. It cannot detect a reversed machine-to-machine hand.
- `tests/test_hand_economy.lua` contains no `dir` or `direction` token at all.
- `tests/test_physical_witness.lua:149-162` WI2 and `tests/test_blueprint_physical_contract.lua:393-401`
  TR4 both mutate a direction and expect a named code — but on **hand-built fixtures**, never on generator
  output.
- `tools/blueprint_audit.py` checks only that both cells are occupied, which a reversed hand satisfies.

**A blueprint inserter's `direction` names its PICKUP**: the game takes from the tile the inserter faces and
drops behind it. `docs/feature-contracts.md:172-173` says so. The proof is the player's own working factory,
`~/share/RRC/red_science_1s_manual_bp.txt`, measured 2026-09-22 on this host: its belt columns run
`186.5 .. 205.5` and then jump to an **isolated** `211.5`. Nothing inside can feed `211.5`, so ingredients
must arrive at the science machines from `205.5`, which makes the WEST-facing hand at `(206.5, 1076.5)` the
INPUT — true only when `direction` names the pickup.

The spine fixes `logic/bp/serialize.lua` so the published direction is the opposite of the internal one.
**This lane is the guard that should have existed**, and it must be written by a hand that did not write
that fix.

## Traps, each measured

**Trap: do NOT assert against our own published pickup/drop positions.** That is exactly how IG2 missed it.
The assertion has to be about the published `direction` integer and the tiles around it.

**Trap: the internal frame and the published frame are DIFFERENT, on purpose.** Internally
`pickup_offset` is `{x = 0, y = 1}` and `drop_offset` is `{x = 0, y = -1.203125}` — the real prototype
numbers, captured — so an internal inserter with `dir = NORTH` DROPS north. The published direction is the
opposite. Read `state.result`, which has been through `Serialize`, never `state.work.validate_candidate`,
which has not. Round 17 lost a whole session to that distinction.

**Trap: `Grid.NORTH` is `0`, `EAST` is `4`, `SOUTH` is `8`, `WEST` is `12`**, and opposite is `(d + 8) % 16`.

**Trap: an inserter is legal with a machine on one side and a belt on the other, EITHER way round.** Both
readings put a real thing on both cells, which is why occupancy proves nothing. The row must pin the
DIRECTION of the transfer: an input hand's **drop** cell is the machine, an output hand's **pickup** cell is
the machine, under the published rule.

**Trap: `tests/harness.lua`'s `H.shapes()` yields two shapes**, so each `H.test` inside that loop counts
twice per interpreter. Both `lua5.2` and `lua5.4` must be green.

**Trap: keep it cheap.** Do not run the full generator on the player's sheet; that costs over 200 seconds.
Drive a small fixture through `logic.bp.search` or reuse
`tests/fixtures/routing/player_chain_first_candidate.lua`'s shape, and read the serialized result.

PRESERVE: `logic/**`, `tools/**`, `tests/harness.lua`, and every other file under `tests/`,
`docs/**`, `info.json`, `mod-description.md`, `.agent-lane.toml`.

## Files this lane owns

`tests/test_inserter_direction.lua` (new). **This lane changes NO production file.**

## What to build

`tests/test_inserter_direction.lua`. Rows:

- **ID0** the player's own factory is the oracle: decode `~/share/RRC/red_science_1s_manual_bp.txt` and
  assert its hand at `(206.5, 1076.5)` facing WEST has the machine on its **drop** side, so the published
  rule is pinned by a factory the game runs. If the file is absent, the row fails by name; it is never
  skipped.
- **ID1** every generated inserter whose role is `input` publishes a direction whose **drop** cell is its
  own machine.
- **ID2** every generated inserter whose role is `output` publishes a direction whose **pickup** cell is
  its own machine.
- **ID3** the published direction is the OPPOSITE of the internal one, for every inserter, so the boundary
  is asserted and not merely its effect.
- **ID4** a negative control the file can fail on: flip one published direction by hand and the same helper
  the real rows use reports it.

**Each row prints the inserter's id, its role, its internal direction, its published direction, and what
sits on each of its two cells.**

**RED AT `round-19-base`** — that tree still publishes the internal direction unchanged, so ID1, ID2 and
ID3 must fail there. State in the lane report which rows are red at base with their exact failure text.

## What done mean

```checks
{"name": "inserter-direction", "command": "git diff --name-only round-19-base HEAD | grep -v '^docs/tasks/157' | grep -v '^tests/test_inserter_direction\\.lua$' | ( ! grep . ) && sh tools/lane_rows.sh tests/test_inserter_direction.lua --min-cases 5 && for l in lua5.2 lua5.4; do $l tests/test_inserter_direction.lua 2>&1 | tail -1 | grep -q ' 0 failed' || exit 1; $l tests/test_inserter_geometry.lua 2>&1 | tail -1 | grep -q '26 cases, 26 passed' || exit 1; done && echo inserter-direction-ok", "expect_exit": 0, "expect_regex": "inserter-direction-ok", "timeout_s": 1800}
{"name": "red-at-base", "command": "set -e; base=$(mktemp -d); git worktree add -q --detach \"$base\" round-19-base; cp tests/test_inserter_direction.lua \"$base/tests/test_inserter_direction.lua\"; cd \"$base\"; out=$(lua5.2 tests/test_inserter_direction.lua 2>&1 || true); cd - >/dev/null; git worktree remove --force \"$base\"; for row in ID1 ID2 ID3; do echo \"$out\" | grep '^FAIL' | grep -q \"$row\" || { echo \"$row is GREEN at round-19-base, where every inserter publishes the internal direction unchanged; it proves nothing\"; exit 1; }; done; echo red-at-base-ok", "expect_exit": 0, "expect_regex": "red-at-base-ok", "timeout_s": 1200}
```

Re-cut because: none

# bound: 4000s

Reviewer ask: is any row satisfied by the positions `logic/bp/groups.lua` published, rather than by the
published `direction` integer and the tiles around it?
