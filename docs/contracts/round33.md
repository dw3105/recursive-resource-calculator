# Contract: blueprint job you can see and stop; inserter 10/s sheet builds (round 33, 2026-09-24)

Plan: `~/.claude/plans/we-introuced-machine-buffer-linked-pine.md`. Player 2026-09-24: v13/v3 work in game; points
2-7 below. Base tag `round-33-base`.

## Base (done)

- `logic/catalog.lua` build_inserter turns the game's pickup/drop offsets 180 degrees into the generator frame and
  stamps `offset_frame = "rrc"`; `tools/prepared_from_export.py` does the same for unstamped captures. Mock inserter
  prototypes (`tests/harness.lua`) now in game frame (pickup -y). Red/green bytes unchanged.
- Golden case `tests/golden/cases/player-inserter-10s` (real in-game capture). Measured 2026-09-24,
  legalcopilot-dev: pack passes (before: `BP_P_NO_FIT` every grid); now `BP_FAIL_NO_LAYOUT` with
  `BP_R_PORT_BLOCKED` ×3, molten-iron producer port not bound: the 2-foundry casting-iron row lost its fluid ports.

## A. Job flow (lane 201)

Measured facts (file:line, main 0233d55):
- `BlueprintDialog.open` sets `player.opened = frame` (`gui/blueprint_dialog.lua:245`) → `on_gui_closed` hides the
  calculator (`control.lua:125-127`). The dialog's Generate (`blueprint_dialog.lua:289-324`) enqueues and leaves the
  dialog open; its footer "Cancel" (`:166`, handler `:360`) only closes the dialog.
- Sheet Cancel (`gui/sheet.lua:412-423`) → `Jobs.cancel` (`logic/jobs.lua:487-499`): tombstone + removes job, but
  never `Generation.cancel` (`logic/bp/generation.lua:1483-1490`): handle stays `pending`; offer stays
  (`gui/progress_panel.lua:239-240`).
- Tombstone lockout: `request_sheet` refuses when tombstone matches revisions (`jobs.lua:251`); nothing ever raises
  `sheet_revision`, so after one Cancel every Compute/Generate on that sheet is refused (J4 asserts it).
- Canceled note inserted into `output_flow` (`gui/sheet.lua:193`, horizontal by default) at index 1, beside the report
  table (`progress_panel.lua:175-198`), never removed (`ReportSteps.publish` swaps only `report`). Dialog error label
  (`blueprint_dialog.lua:161`) has no wrap; failure with dialog closed is lost (`:346-347`).

Clauses:
- G1 Generate click (valid settings, job queued): dialog closes; calculator becomes visible and `player.opened`, on
  the job's sheet tab; the bar shows at once.
- G2 dialog footer button reads "Close" (`gui.close`); closing never cancels a job.
- G3 sheet Cancel while a blueprint job runs: `Generation.cancel` → handle `canceled`, blueprint job removed, no
  publish/cursor write after it, offer cleared. Blueprint job spec gets `cancel`. Calculation cancel as today.
- G4 Cancel never locks the sheet: the tombstone only stops a late publish of the canceled job itself; a new
  user-started Compute/Generate after Cancel runs. Test J4 rewritten to this rule.
- G5 (lane 201 part) dialog error label: `single_line = false`, `maximal_width = 400`. A generation failure with
  the dialog closed (`blueprint_dialog.lua:346-347`) calls `Registry.progress_note(player_index, sheet_id, caption)`
  when that function exists (lane 202 defines it); tests stub it.
- G6 Opening the calculator while a job runs selects the job's sheet tab.

## B. Progress (lane 202)

- P1 new `logic/progress_view.lua`: `ProgressView.of(player_index, sheet_id)` → nil or
  `{kind = "calc"|"blueprint", stage_key, attempt, attempts, fraction, elapsed_ticks, eta_ticks, best_entities}`
  read from the job record (`storage[p].calc_jobs[sheet_id]`, `storage[p].blueprint_job`, `logic/jobs.lua:7-10`).
  `fraction` in [0,1), 1 only when done, never decreases for one job (kept in the job record as `progress.shown`).
  `eta_ticks` = elapsed × (1−f)/f when f ≥ 0.05, else nil. `Jobs.progress_of` stays for its callers.
- P2 `logic/bp/search.lua` progress fields: `progress.stage` (search phase), `progress.stage_done`,
  `progress.stage_total` from real counts (pack: blocks placed/blocks; route: bindings routed/bindings; tidy: trial
  index/trials; validate: phases done/phases; other stages 0/1 → 1/1), `progress.attempt`, `progress.attempts`.
  Blueprint weights per attempt: groups 2, pack 10, route 13, hands 1, power 4, tidy 65, validate 5; prepare = first
  2 % of job. Attempt k>1 starts where the bar is and shares what is left (bar ≤ 0.99 until done).
  Calculation stages snapshot 10, solve 50, power 10, report 30. No change to search decisions: bytes identical.
- P3 `gui/progress_panel.lua`: caption `{"hxrrc.progress_caption", kind, attempt, attempts, stage, percent}`;
  tooltip adds elapsed and ETA (m:ss); best-so-far line + Deliver button under the bar (the interim offer), cleared
  when no job runs or the attempt is canceled/failed; refresh only on nth_tick(10), writes only when a value changes;
  per-tick `Registry.progress_refresh` call from `Jobs.on_tick` removed (`jobs.lua:480-484` belongs to lane 201:
  lane 202 makes `refresh_all` idempotent and cheap; lane 201 drops the per-tick call).
- P5 (G5 note, lane 202 part) canceled/failure note: `ProgressPanel.set_note(sheet_flow, caption_or_nil)` keeps
  ONE label in its own vertical flow `hxrrc_job_note` placed in the sheet ABOVE `output_flow` (never inside it), word
  wrapped; `mark_canceled` uses it; cleared when the next job starts or publishes. `Registry.progress_note(player_index,
  sheet_id, caption)` finds the sheet flow and calls `set_note`.
- P4 locale keys for every stage (calc + blueprint) in en/cs/ro.

## C. Inserter sheet (lane 203)

- I1 a step with fluid ports keeps them: either a row carries per-machine fluid ports, or a step with any fluid
  input/output is never a row (lane picks by measurement on the inserter sheet; red/green have no fluid).
- I2 hands per flow per machine = ceil(rate_per_machine / hand items_per_second), each its own port, placed on free
  face tiles like today's hands (single-machine blocks and rows).
- Done: inserter sheet delivers `ok=true`, `mixed=0 starved=0 bleed=0`; red ≤ 169, green ≤ 322, both bleed 0.

## Measure (integration, legalcopilot-dev)

`sh tools/measure_sheet.sh player-{red-science-1s,green-science-1s,inserter-10s}`; `tools/tick_parts.lua` worst call
≤ 0.12 s; draftsman 0 errors; suite green.
