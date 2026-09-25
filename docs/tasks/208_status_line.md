# 208_status_line progress panel: bar shows percent, the sentence gets its own wrapping row

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-208_status_line`, branch `lane/208_status_line`,
base tag `round-35-base`, merge target `int/r35`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 50 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data in `storage` only (save/load safe, no
closures, no metatables). Every unit test you write must finish in under 20 s (a real red job test may take up to
60 s) and loop over `H.shapes()` (Factorio 2.0 and 2.1). Tests move time ONLY with `H.run_ticks(world, n)` (it fires
on_tick and then nth-tick handlers, like the engine); never call `Registry.progress_refresh()` directly.

Read `docs/contracts/round35.md` first: it is the contract. Your clauses: S1, S2, S3.

## Explain very simply

Player screenshot (1.1.79, 2026-09-25, `~/share/RRC/Screenshot 2026-09-25 105336.png`): the sentence
"Blueprint generation attempt 1/3: Tidying belts (41 %)" runs past the bar and over the Cancel button. Cause:
`gui/progress_panel.lua` `ProgressPanel.update` puts the whole sentence in the progressbar `caption`; the bar lives
in the narrow grid cell `progress_cell` (`gui/sheet.lua`), and the engine draws a caption past the bar's edge.

## What to build

1. S1 bar caption = `{"hxrrc.progress_bar_percent", percent}` only.
2. S2 label `hxrrc_progress_status` (child of the sheet flow, placed right after the controls grid), caption
   `{"hxrrc.progress_status", kind, attempt, attempts, stage}`, `style.single_line = false`,
   `style.maximal_width` ≤ 400; created when a job shows, destroyed by `ProgressPanel.hide` and `ProgressPanel.sweep`.
   Write the caption only when it changes (signature tag, as the bar does today).
3. S3 works on a sheet whose grid predates round 8 (`Sheet.add_missing_controls` path).
4. Locale keys `progress_bar_percent`, `progress_status` in en/cs/ro.
5. Tests (red at base first): new `tests/test_progress_status_line.lua`, both shapes: a real red job driven only by
   `H.run_ticks` (pattern `tests/test_progress_view.lua` PV-00) → bar caption key is `hxrrc.progress_bar_percent`;
   label present, `single_line == false`, `maximal_width` set; after the job ends and 10 ticks the label is gone;
   a legacy sheet (`H.legacy_save`) gets it too.

## Files this lane owns

gui/progress_panel.lua, gui/sheet.lua, locale/en/locale.cfg, locale/cs/locale.cfg, locale/ro/locale.cfg, tests/test_progress_status_line.lua, tests/test_progress_panel.lua, tests/test_panel_sweep.lua, docs/tasks/208_status_line.md.
Never touch anything else.

## Commit, THEN check

Commit on `lane/208_status_line`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane208-tests", "command": "git diff --name-only round-35-base HEAD | grep -Ev '^(gui/progress_panel\\.lua|gui/sheet\\.lua|locale/en/locale\\.cfg|locale/cs/locale\\.cfg|locale/ro/locale\\.cfg|tests/test_progress_status_line\\.lua|tests/test_progress_panel\\.lua|tests/test_panel_sweep\\.lua|docs/tasks/208_status_line\\.md)$' | ( ! grep . ) && ! git diff round-35-base HEAD -- logic gui control.lua | grep -q '^+.*coroutine' && for t in test_progress_status_line test_progress_panel test_panel_sweep test_job_flow test_progress_view test_locale_keys test_calc_pipeline; do timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && for c in player-red-science-1s player-green-science-1s player-inserter-10s; do sh tools/bytes_hash.sh $c | tail -1; done > /tmp/b$$ && grep -f /tmp/b$$ tests/fixtures/bytes_round35.txt | wc -l | grep -q 3 && echo lane208-tests-ok", "expect_exit": 0, "expect_regex": "lane208-tests-ok", "timeout_s": 2700}
```

# bound: 3000s

## Implementation

The progressbar caption now shows only the percentage. The stage sentence sits in a wrapping label immediately after the controls grid, with a 400 pixel width limit. The panel removes that label when progress hides or the idle sweep runs. The label is added on demand, so repaired sheets saved before round 8 receive it when progress first appears.
