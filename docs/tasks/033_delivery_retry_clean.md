# 033 — retry hands over once, and a refusing cursor stays empty

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-033`, branch `lane/033`, base = `feat/round-8-blueprints`, tag `wave-4-delivery-base` (resolve it with `git rev-parse wave-4-delivery-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair lane. A mutation batch planted two defects in `gui/blueprint_delivery.lua` and all seven delivery cases stayed green, so neither behaviour has a case.

## What is true

**PRESERVE:**
- You own `gui/blueprint_delivery.lua` and `tests/test_blueprint_delivery.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_blueprint_delivery.lua` stays. You add; you never weaken or delete.
- `prototypes`, `game`, `settings` and every prototype list are **userdata** in the game, never tables. Never write `type(prototypes) == "table"`; ask `rawget(_G, "prototypes")` instead (`docs/feature-contracts.md` §2c).
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- Defect 1: `gui/blueprint_delivery.lua:193` is `state[PENDING_KEY] = nil` inside `BlueprintDelivery.retry`. Deleting it keeps every case green, so a kept result can be handed over twice.
  Why nothing fails: the only case about two deliveries, `tests/test_blueprint_delivery.lua:145`, delivers to an **empty** cursor, which never sets `PENDING_KEY` (`gui/blueprint_delivery.lua:174`), then calls `retry` once and gets `nothing_to_deliver`. No case reaches a successful `retry` and then calls `retry` again.
- Defect 2: `gui/blueprint_delivery.lua:153` is `if not cursor.is_blueprint_setup() then error("cursor blueprint is not set up") end`. Deleting it keeps every case green.
  Why nothing fails: the harness reports a stack set up whenever it holds a blueprint carrying entities (`tests/harness.lua:942`), so the cursor is always set up in every fixture. The one case that models a stack refusing to set up, `tests/test_blueprint_delivery.lua:159`, replaces `game.create_inventory`, which is the **staging** stack, never the cursor.
- The publication path is `publish` at `gui/blueprint_delivery.lua:138-158`: cursor emptiness, then `set_stack`, `set_blueprint_entities`, label, `preview_icons`, description, then the set-up check. On any error it calls `player.clear_cursor()` inside `pcall`, so the player's hand ends as it began.
- BP-18 is the clause: nothing changes on a failed delivery, and a blueprint reaches the player once.
- Assert a value exists before reading it, so a failure is an assertion and not a nil index (`docs/feature-contracts.md` §2b).

## What to build

1. Add a case that fills the cursor, delivers (result kept, `blueprint_cursor_busy`), empties the cursor, retries once with success, then retries a second time: the second retry reports `nothing_to_deliver`, and the cursor still holds exactly one blueprint with the same entities.
2. Add a case that the kept result is gone from player state after a successful retry, so a later delivery of a different blueprint is never blocked by `blueprint_pending`.
3. Add a case where the **cursor** stack refuses to become a set-up blueprint, the way case at `tests/test_blueprint_delivery.lua:159` does for the staging stack: delivery fails, the player's hand is empty afterwards, no staging inventory is left behind, and the failure reason is reported.
4. Add a case that the same refusal leaves the result available, so the player can collect it once the fault is gone, or state plainly in the case name that the result is dropped, whichever the module does — then assert exactly that.
5. Name them with the existing `BP-18` clause prefix and a distinct tail, so a mutant can match one case alone.
6. Plant each defect yourself, paste each new case red, then paste it green with the defect reverted.

## What done mean

```checks
{"name": "delivery-tests", "command": "lua5.2 tests/test_blueprint_delivery.lua && lua5.4 tests/test_blueprint_delivery.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-4-delivery-base --manifest docs/tasks/033.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste each new case failing against its planted defect, then passing once the defect is reverted.
- `git diff --stat wave-4-delivery-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `gui/blueprint_delivery.lua`
- `tests/test_blueprint_delivery.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: after a successful retry, does a second retry refuse, and does a cursor that will not set up leave an empty hand?
