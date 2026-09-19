# 030 — half a belt family is not a family

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-030`, branch `lane/030`, base = `feat/round-8-blueprints`, tag `wave-3-repair-base` (resolve it with `git rev-parse wave-3-repair-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair lane. A mutation batch planted a defect in `logic/bp/settings.lua` and all eleven settings cases stayed green, so that behaviour has no case.

## What is true

**PRESERVE:**
- You own `logic/bp/settings.lua`, `gui/blueprint_dialog.lua` and `tests/test_bp_settings.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_bp_settings.lua` stays. You add; you never weaken or delete.
- `prototypes`, `game`, `settings` and every prototype list are **userdata** in the game, never tables. Never write `type(prototypes) == "table"`; ask `rawget(_G, "prototypes")` instead (`docs/feature-contracts.md` §2c).
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- The planted defect: `logic/bp/settings.lua:308` is `if not underground or not splitter then return nil end`. Changing `or` to `and` accepts a belt that has an underground belt but no splitter, and a belt that has a splitter but no underground belt. Every case stayed green.
- Why nothing fails: the only rejecting fixture is `orphan-belt`, added at `tests/test_bp_settings.lua:92` and `:106` with `world.add_transport_belt({name = "orphan-belt", items_per_second = 15})`. It has **neither** family member, so `or` and `and` agree on it. No fixture has exactly one half.
- The family rule is in `logic/bp/settings.lua:100-122`: the underground belt is found either by the engine relation `related_underground_belt` (`logic/bp/settings.lua:84`) or by the `<prefix>-underground-belt` convention, while the splitter must use the belt's own prefix, `<prefix>-splitter`.
- A refusal must name the belt and substitute nothing, as `tests/test_bp_settings.lua:97-101` already requires for the orphan.
- `world.add_underground_belt` and `world.add_splitter` are harness fixture builders; a modded underground belt can carry `related_underground_belt` pointing at its belt.
- Assert a value exists before reading it, so a failure is an assertion and not a nil index (`docs/feature-contracts.md` §2b).

## What to build

1. Add a case for a belt with an underground belt and **no** splitter: `Settings.belt_family` returns nil, `Settings.validate` refuses with `BP_REJ_BELT_FAMILY_MISSING`, and neither `underground` nor `splitter` is written onto the choice.
2. Add a case for a belt with a splitter and **no** underground belt, with the same three assertions.
3. Add a case for a modded belt whose underground belt is named outside the convention but carries `related_underground_belt`, and whose splitter follows the belt's own prefix: the family is accepted, at the belt's quality, with both names returned.
4. Add a case that a splitter belonging to a **different** prefix never completes a family.
5. Name them in the existing `BP<n>` and `BP_REJ_BELT_FAMILY_MISSING` naming style.
6. Plant the defect yourself, paste each new case red, then paste them green with the defect reverted.

## What done mean

```checks
{"name": "settings-tests", "command": "lua5.2 tests/test_bp_settings.lua && lua5.4 tests/test_bp_settings.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-3-repair-base --manifest docs/tasks/030.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste each new case failing against the planted defect, then passing once the defect is reverted.
- `git diff --stat wave-3-repair-base HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `logic/bp/settings.lua`
- `gui/blueprint_dialog.lua`
- `tests/test_bp_settings.lua`

Touch nothing else.

# bound: 2400s

Reviewer ask: does a belt with an underground belt but no splitter turn a named case red?
