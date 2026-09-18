# 025 — one unchanged sheet exports one string

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-025`, branch `lane/025`, base = `feat/round-8-blueprints`, tag `wave-2-candidate` (resolve it with `git rev-parse wave-2-candidate`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

Repair lane. A mutation batch planted a defect in `logic/export_payload.lua` and every test stayed green, so that behaviour has no case.

## What is true

**PRESERVE:**
- You own `logic/export_payload.lua` and `tests/test_export_payload.lua` only. Everything else is frozen; if you need a change elsewhere, stop and report.
- Every existing case in `tests/test_export_payload.lua` stays. You add; you never weaken or delete.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.

Current facts:
- The planted defect: `table.sort(values)` was deleted from `sorted_values`, which builds the exported lists of referenced entities, items, fluids and modules. Every one of the twenty payload cases stayed green.
- Lua's `pairs` order is unspecified. Two runs in one process often agree, so a weak case passes by luck; the guarantee the export owes is that one unchanged snapshot exports one payload (EX-A7).
- The envelope already sorts keys where order carries no meaning; order that does carry meaning, like targets and module slots, is preserved instead.
- Assert a value exists before reading it, so a failure is an assertion and not a nil index (`docs/feature-contracts.md` §2b).

## What to build

1. Add a case that the referenced entity, item, fluid and module lists come out sorted, by asserting the list equals its own sorted copy and that a known member sits at its sorted index rather than merely being present.
2. Add a case that builds the same snapshot twice from tables inserted in different key order and asserts both payloads are identical, so insertion order cannot leak into the output.
3. Add a case that order which does carry meaning still survives: targets stay in UI order and module slots stay in slot order.
4. Name them in the existing `E<n>` sequence.
5. Plant the defect yourself, paste the new case red, then paste it green with the defect reverted.

## What done mean

```checks
{"name": "payload_order-tests", "command": "lua5.2 tests/test_export_payload.lua && lua5.4 tests/test_export_payload.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "whole-suite", "command": "gateslot --label rrc/heavy --no-autostart -- sh tests/run.sh", "expect_exit": 0, "expect_regex": "(?s).*", "timeout_s": 5400}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base wave-2-candidate --manifest docs/tasks/025.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

- Paste the new case failing against the planted defect, then passing once the defect is reverted.
- `git diff --stat wave-2-candidate HEAD` pasted.

Run the checks as your **last** action, after your final commit: a commit afterwards moves the tree the proof was
taken against, and the supervisor refuses it with the reason `tree-moved`.

## Files this lane owns

- `logic/export_payload.lua`
- `tests/test_export_payload.lua`

Touch nothing else.

# bound: 2000s

Reviewer ask: does a payload built from differently ordered tables come out byte-identical, while targets keep their UI order?
