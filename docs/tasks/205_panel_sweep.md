# 205_panel_sweep progress panel: old labels swept, cancel words by kind, bar via the 10-tick path

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-205_panel_sweep`, branch `lane/205_panel_sweep`,
base tag `round-34-base`, merge target `int/r34`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data in `storage` only (save/load safe, no
closures, no metatables). Every unit test you write must finish in under 20 s and loop over `H.shapes()` (Factorio
2.0 and 2.1) when it touches the GUI or control.

Read `docs/contracts/round34.md` first: it is the contract. Your clauses: S1, S2, S3, S4.

## Explain very simply

Player screenshot (1.1.77, 2026-09-25): "Calculation canceled. The report below is from before it started." sits LEFT
of the report table and shoves it right. Cause: versions up to 1.1.74 put label `hxrrc_calc_canceled_label` at index
1 INSIDE the horizontal `output_flow`; Factorio keeps GUI elements in a save and nothing removes it. `H.legacy_save(sheet_flow)`
(base, `tests/harness.lua`) recreates exactly that. Second fault: canceling a BLUEPRINT prints the calc words
(`gui/progress_panel.lua` `mark_canceled`). The harness now fires `script.on_nth_tick` handlers inside
`H.run_ticks` (engine order, after on_tick), so the bar's 10-tick `refresh_all` runs in tests as in the game.

## What to build

1. S1: `ProgressPanel.sweep(sheet_flow)` and `Registry.progress_sweep(player_index)` exactly as in the contract.
2. S2: `refresh_all` sweeps each sheet that has no running job.
3. S3: cancel note by kind (`hxrrc.blueprint_canceled` / `hxrrc.calc_canceled`), placed in the sheet flow just
   above `output_flow`. Add both locale keys in en, cs, ro (`locale/*/locale.cfg`).
4. S4: bar + Cancel visible within 10 ticks of any running calc or blueprint job, through `H.run_ticks` only.
5. Tests (red at base first): new `tests/test_panel_sweep.lua`, both shapes: legacy label gone within 10 ticks
   (`H.legacy_save` + `H.run_ticks(world, 10)`), `output_flow` then holds only `report` (and the offer if one);
   blueprint cancel note words; calc cancel note words; note index is `output_flow` index − 1 in the sheet flow;
   bar visible during a real red generation (PV-00 pattern) using ticks only. In `tests/test_progress_panel.lua`
   replace direct `progress_refresh()` calls by `H.run_ticks(world, 10)` wherever that covers the case.

## Files this lane owns

gui/progress_panel.lua, gui/sheet.lua, locale/en/locale.cfg, locale/cs/locale.cfg, locale/ro/locale.cfg, tests/test_panel_sweep.lua, tests/test_progress_panel.lua, tests/test_job_flow.lua, docs/tasks/205_panel_sweep.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/205_panel_sweep`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane205-tests", "command": "git diff --name-only round-34-base HEAD | grep -Ev '^(gui/progress_panel\\.lua|gui/sheet\\.lua|locale/en/locale\\.cfg|locale/cs/locale\\.cfg|locale/ro/locale\\.cfg|tests/test_panel_sweep\\.lua|tests/test_progress_panel\\.lua|tests/test_job_flow\\.lua|docs/tasks/205_panel_sweep\\.md)$' | ( ! grep . ) && ! git diff round-34-base HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_panel_sweep test_progress_panel test_job_flow test_progress_view test_calc_pipeline test_generation_interim test_locale_keys; do timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane205-tests-ok", "expect_exit": 0, "expect_regex": "lane205-tests-ok", "timeout_s": 2400}
```

# bound: 3000s
