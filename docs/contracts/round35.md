# Round 35 contract — finished blueprint lands in the hand; progress text never overlaps

Host `legalcopilot-dev`, 2026-09-25. Base tag `round-35-base` (from `main` c1e255c, layered pack default-on).
Merge target `int/r35`. Bytes must stay `tests/fixtures/bytes_round35.txt` (no layout code changes).

## Player's report (1.1.79, 2026-09-25)

1. Generation finished (export `~/share/RRC/inserter-10s-1.1.79.txt`: `generation.state=success`, 413 entities,
   `interim.sequence=1`, no `delivered_sequence`) but no blueprint came to the hand and no message said why.
2. Screenshot: the sentence under the progress bar ("Blueprint generation attempt 1/3: T… s)") runs over Cancel.
3. Reload cancel works (round 34).

## Causes (measured on base)

- C1 `logic/bp/generation.lua` publish: final delivery runs only when no interim existed
  (`if handle.deliver and not equal_delivered and not had_interim`). With an interim, the final never goes to the hand.
- C2 `generation.lua` interim path delivers the first interim and drops a failure: no reason kept, no note.
- C3 `gui/blueprint_delivery.lua` `BlueprintDelivery.deliver`: a pending record `storage[p].blueprint_delivery`
  (set once when the hand was busy) makes every later call return `blueprint_pending`. `BlueprintDelivery.retry`
  has no caller. Probe (harness, real red job, `deliver=true`): fresh → hand holds 148 entities at tick 175;
  with a stale pending record → hand stays empty, `state=success`, nothing shown.
- C4 `gui/progress_panel.lua` `ProgressPanel.update` writes the whole sentence as the progressbar `caption`; the
  bar sits in the narrow grid cell `progress_cell` (`gui/sheet.lua`), the engine draws the caption past the bar.

## Names every lane uses

- Locale (en/cs/ro), delivery (lane 207 adds at the end of `[hxrrc]`):
  `blueprint_not_delivered=Blueprint is ready but could not be put in your hand (__1__). Use Copy string.`,
  `blueprint_waiting_hand=Blueprint is ready: empty your hand to receive it.`, `copy_string=Copy string`.
- Locale, progress (lane 208): `progress_bar_percent=__1__ %` and `progress_status=__1__ attempt __2__/__3__: __4__`
  (the old `progress_caption` may stay unused).
- GUI names: status label `hxrrc_progress_status` (child of the sheet flow, right after the controls grid);
  button `hxrrc_copy_blueprint_string` (tags `{job_id = n}`), shown inside the job note flow `hxrrc_job_note`.
- `Registry.progress_note(player_index, sheet_id, caption)` exists; lane 207 may add an optional 4th argument
  `extra` = `{copy_job_id = n}` handled INSIDE `gui/blueprint_dialog.lua`/`gui/blueprint_delivery.lua` code it owns,
  never by editing `gui/progress_panel.lua` (lane 208 owns it): add the button to the note flow found by name
  `hxrrc_job_note` after calling `Registry.progress_note`.

## Clauses

- D1 (207) Only the FINAL result is delivered automatically. The interim is never auto-delivered (it stays the
  "Deliver" offer). Final delivered unless the exact same result was already delivered.
- D2 (207) A new delivery replaces any stale pending record (newest wins); never `blueprint_pending` forever.
- D3 (207) Hand busy → record pending, note `blueprint_waiting_hand`; on `on_player_cursor_stack_changed` with an
  empty hand, deliver it (chain after `Pipette.on_cursor_changed` in `control.lua`).
- D4 (207) Any other failure → note `blueprint_not_delivered` with reason + button `hxrrc_copy_blueprint_string`
  that opens the existing string box (export dialog or blueprint dialog text box) holding the blueprint string.
  Generation state stays `success`.
- D5 (207) Debug export (`logic/export_payload.lua`) carries `delivery = {pending = bool, last_reason = s|nil,
  delivered_sequence = n|nil}`.
- S1 (208) Progressbar caption is percent only (`progress_bar_percent`).
- S2 (208) Label `hxrrc_progress_status` holds the sentence, `style.single_line = false`, `style.maximal_width`
  set (≤ 400); present only while a job runs; removed by `ProgressPanel.sweep`/hide.
- S3 (208) A sheet saved by an older version gets the label when a job starts (no repair of the grid needed).
