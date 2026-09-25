# Round 34 contract — mod update leaves no ghost; every inserter is one the player picked

Host `legalcopilot-dev`, 2026-09-25. Base tag `round-34-base` (from `main` a033f8e). Merge target `int/r34`.

## Player's report (1.1.77, 2026-09-25)

1. Screenshot: "Calculation canceled. The report below is from before it started." sits LEFT of the report table
   and shoves it right.
2. After updating the mod and reloading the save, the old job is "still going" with no way to stop it.
3. Inserter blueprint mixes yellow `inserter` (8) with blue `fast-inserter` (25) though blue was picked.
   Long-handed (4) stay: the player keeps them where reach 2 is needed.

## Causes (measured on base)

- C1 Versions up to 1.1.74 put label `hxrrc_calc_canceled_label` at index 1 INSIDE horizontal `output_flow`
  (`git show 0233d55:gui/progress_panel.lua` 182-197). Factorio keeps GUI elements in a save. Nothing in the current
  code removes it; only a new publish clears `output_flow`. `H.legacy_save(sheet_flow)` recreates it.
- C2 A blueprint cancel prints the calc words `hxrrc.calc_canceled` (`gui/progress_panel.lua` mark_canceled).
- C3 `on_configuration_changed` → `Jobs.invalidate_all` drops `blueprint_job`, but the generation record in
  `storage[PERSISTENCE_KEY]` stays `pending` forever (`Generation.lookup(p, sheet).state == "pending"` 500 ticks later).
- C4 The bar refreshes only through `script.on_nth_tick(10, refresh_all)`. The harness now fires nth-tick handlers
  after `on_tick` (base). Tests must drive the bar through `H.run_ticks`, never by calling `progress_refresh()`.
- C5 Row hands (`logic/bp/groups.lua:1516`) are named `input.inserter.name or "inserter"`; every other hand uses
  `inserter_size(catalog, input and input.inserter)`, which falls back to `catalog.inserter.name`.

## Names every lane uses

- `ProgressPanel.sweep(sheet_flow)` in `gui/progress_panel.lua`: destroys every `hxrrc_calc_canceled_label` anywhere
  under the sheet flow, and when no job runs for that sheet also the offer, the best line and a stale bar/Cancel
  (hidden). Never touches `report`. Never removes a note set in the same tick (a note is removed only on the
  next publish or next job start).
- `Registry.progress_sweep(player_index)`: sweeps every sheet of the player. Published by `gui/progress_panel.lua`.
- `Generation.stop_all(reason)` in `logic/bp/generation.lua`: every `pending` record → `cancelled`, `reason_codes`
  gets `reason`; returns a list of `{player_index = p, sheet_id = s}` that were stopped.
- Locale (en/cs/ro): `hxrrc.blueprint_canceled` = "Blueprint generation canceled.";
  `hxrrc.blueprint_stopped_update` = "Blueprint generation stopped: the mod or game changed. Press Generate again."
- Registry names already on base: `Registry.progress_note(player_index, sheet_id, caption)`,
  `Registry.progress_refresh`, `Registry.generation`.

## Clauses

- U1 (204) `on_configuration_changed`: `Jobs.invalidate_all("configuration_changed")`, then
  `Generation.stop_all("mod_updated")`, then per player `Registry.progress_sweep(p)`, then
  `Registry.progress_note(p, s, {"hxrrc.blueprint_stopped_update"})` for each stopped sheet. Guard every
  Registry call with `type(...) == "function"`.
- U2 (204) `Generation.status`/`Generation.lookup` never return `pending` for a record with no live
  `blueprint_job` of that job id: close it `cancelled` on read.
- U3 (204) Plain reload (no configuration change): a running blueprint job resumes; with module `handles` empty,
  `Generation.cancel(p, job_id)` rebuilds the record from storage, stops the job and returns true.
- S1 (205) `ProgressPanel.sweep` + `Registry.progress_sweep` exactly as above.
- S2 (205) `refresh_all` (the 10-tick handler) calls `ProgressPanel.sweep` on each sheet with no job, so an old
  label goes within 10 ticks of any load, with or without an update event.
- S3 (205) Cancel note by kind: the sheet's blueprint job → `hxrrc.blueprint_canceled`; calc job →
  `hxrrc.calc_canceled`. The note is a child of the sheet flow placed just above `output_flow`, never inside
  `output_flow`.
- S4 (205) Any running job (calc or blueprint) shows bar + Cancel within 10 ticks through `H.run_ticks` alone.
- N1 (206) Row hands named via `inserter_size(catalog, input and input.inserter)`.
- N2 (206) No hard-coded entity-name literal as a fallback in `logic/bp/groups.lua` where a catalog/settings pick
  exists.
- N3 (206) `tools/entity_names.py <bp.txt> <prepared_input.json>`: every entity of type inserter is
  `settings.inserter.name` or `settings.long_inserter.name`; every belt/underground/splitter is
  `settings.belt.name` / `.underground` / `.splitter`; pole, pipe, pipe-to-ground, roboport match their settings.
  Prints one line per wrong entity and last line `NAMES-OK` or `NAMES-BAD n=<count>`.
