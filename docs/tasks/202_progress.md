# 202_progress progress bar: forward only, real units, says what it does, ETA, best so far

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-202_progress`, branch `lane/202_progress`,
base tag `round-33-base`, merge target `int/r33`. Host `legalcopilot-dev`.

This task is complete in itself. It names no other lane and no other branch.

## You have about 60 minutes — do NOT stop early

Do not stop until every item in "What to build" is done and its checks pass. Commit early, commit again, run the
checks LAST.

**NEVER run `tests/run.sh`, `suite_parallel.sh`, `tools/round21_regress.sh`, `tools/round21_product.sh` or any full
suite of any kind.** Run only single test files, one at a time, with `lua5.2 tests/<file>.lua` (lua5.2 ONLY), and
the tools named below. Never use `coroutine` (Factorio has none). Plain data in `storage` only (save/load safe, no
closures). Every unit test you write must finish in under 20 s and loop over `H.shapes()` (Factorio 2.0 and 2.1)
when it touches the GUI or control.

Read `docs/contracts/round33.md` first: it is the contract. Your clauses: P1, P2, P3, P4, P5.

## Explain very simply

Today the bar always shows "Reading recipes" at 0: `Jobs.progress_of` (`logic/jobs.lua:536-560`) returns
`phase, fraction` but `refresh_all` (`gui/progress_panel.lua:218-245`) treats the first value as a table
(`progress.phase`, `.done_units`). Test PP-06 hides it by stubbing `progress_of`. Blueprint `done_units` counts ops
while `total_units` counts grids (`logic/bp/search.lua:1408`, `:1171`), so even fixed it would read full at once. It
resets every phase and every candidate; blueprint phases have no locale words; it refreshes every tick twice. Build
the bar the contract describes. You do NOT change what the search decides: blueprint bytes must stay identical.

## What to build

1. P1 `logic/progress_view.lua` (`ProgressView.of`), P2 search progress fields (only `progress.*` writes in
   `logic/bp/search.lua`; never a decision), P3 panel, P4 locale en/cs/ro, P5 note (`ProgressPanel.set_note`,
   `Registry.progress_note`, canceled note moved out of `output_flow`).
2. Tests (red at base first): new `tests/test_progress_view.lua`: PV1 full red generation (`tests/golden/cases/
   player-red-science-1s/prepared_input.json`) stepped at 2000 ops per tick through the blueprint job record:
   fraction never decreases, stays < 1 until done, is 1 at done, stage keys all have locale entries; PV2 calc job
   stages forward only; PV3 ETA nil below 5 %, number after. `tests/test_progress_panel.lua`: remove PP-06's stub and
   drive the real path; add caption/tooltip/best-so-far/note checks (note is a child of the sheet flow ABOVE
   `output_flow`, never inside it).

## Same bytes

`sh tools/bytes_hash.sh player-red-science-1s` and `sh tools/bytes_hash.sh player-green-science-1s` print exactly
`tests/fixtures/bytes_round32.txt`.

## Files this lane owns

gui/progress_panel.lua, logic/progress_view.lua, logic/bp/search.lua, locale/en/locale.cfg, locale/cs/locale.cfg,
locale/ro/locale.cfg, tests/test_progress_view.lua, tests/test_progress_panel.lua. Never touch anything else.

## Commit, THEN check

Commit on `lane/202_progress`. **Run the checks as the very LAST action.**

## What done mean

```checks
{"name": "lane202_progress-tests", "command": "git diff --name-only round-33-base HEAD | grep -v '^docs/tasks/202_progress' | grep -Ev '^(gui/progress_panel\\.lua|logic/progress_view\\.lua|logic/bp/search\\.lua|locale/(en|cs|ro)/locale\\.cfg|tests/test_progress_view\\.lua|tests/test_progress_panel\\.lua)$' | ( ! grep . ) && ! git diff round-33-base HEAD -- logic gui | grep -q '^+.*coroutine' && for t in test_progress_view test_progress_panel test_search test_search_pipeline test_calc_pipeline test_locale; do [ -f tests/$t.lua ] || continue; timeout 400 lua5.2 tests/$t.lua 2>&1 | tail -1 | grep -q ' 0 failed' || { echo FAIL $t; exit 1; }; done && echo lane202_progress-tests-ok", "expect_exit": 0, "expect_regex": "lane202_progress-tests-ok", "timeout_s": 2400}
{"name": "lane202_progress-same", "command": "sh tools/first_verdict.sh | grep -q 'FIRST-VERDICT ok=true' && sh tools/bytes_hash.sh player-red-science-1s > /tmp/r202.txt && sh tools/bytes_hash.sh player-green-science-1s >> /tmp/r202.txt && diff tests/fixtures/bytes_round32.txt /tmp/r202.txt && echo lane202_progress-ok", "expect_exit": 0, "expect_regex": "lane202_progress-ok", "timeout_s": 900}
```

# bound: 3600s
