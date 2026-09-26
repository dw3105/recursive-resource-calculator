# Headless Factorio tests (round 42, 2026-09-26)

Real engine, both branches: `~/factorio-2.0/factorio` (2.0.77) and `~/factorio-2.1/factorio` (2.1.20), fetched by
`sh tools/fetch_factorio.sh <2.0|2.1>`. Harness = FactorioTest (CLI 3.6.0 in `tools/ft`, mod 3.0.1 for 2.0 / 3.1.0
for 2.1 from `~/share/sushi-packer`), copied from `~/sushi-packer-mod`. Tests run inside RRC's own Lua state.

## Who runs what

- **Lanes: offline only.** `lua5.2 tests/game/offline.lua tests/game/<file>.lua` runs one game test file on the
  `tests/harness.lua` mock (seconds). Lanes NEVER run headless (player rule 2026-09-26); every headless runner
  refuses under `LANE_RUN_ID` (`tests/test_game_runner_guard.lua`).
- **Integrator: headless at merge and release.**
  - one test: `sh tools/game_test.sh <2.0|2.1> 'tests/game/<file>.lua::<describe> > <it>'` (fails unless exactly
    one test ran and passed; a typo fails)
  - all: `sh tools/game_test.sh <2.0|2.1> --full` → `game-full-<FV>-ok`
  - zip: `sh tools/game_load_check.sh <zip> <2.0|2.1>` → `load-check-<FV>-ok`
  - `tests/run.sh` ends with offline game files, then both headless suites.

## Setup once per host

    M=$(git rev-parse --path-format=absolute --git-common-dir)/../tools/ft
    mkdir -p "$M" && cp tools/ft/package*.json tools/ft/patch-cli.sh "$M" && (cd "$M" && npm ci && sh patch-cli.sh)

## Files

- `tools/game_stage.sh <FV>`: stages working tree to `build/<FV>/mods/RRC-Fork_<ver>/` (same file list as
  `generate_release.sh`), marks it packaged, adds `? factorio-test`, turns `tests/game/fixtures.txt` cases into
  `tests/game/fixtures/<case>.lua` + `<case>_expected.lua`.
- `tools/game_expect.sh <case>`: offline entity lines `tests/game/expected/<case>.txt`; rerun after layout changes.
- `tests/game/support.lua`: shared helpers (sheet fill, bind, calculate, wait_until, entity lines).
- `tests/game/index.lua`: files FactorioTest loads. `require` only at file top; never in `before_each`.

## Measured (legalcopilot-dev, 2026-09-26)

| run | 2.0.77 | 2.1.20 |
|---|---|---|
| one trivial test (boot + run) | 6.5-6.8 s, 352-360 MB | 6.3-11.2 s, 432-452 MB |
| golden parity red-1s (generation 5.5-6.8 s) | 14.7 s | 12.8 s |
| `--full` 8 tests | 23.6 s, 358 MB | 20.9 s, 427 MB |
| offline shim, 5 probes | 6.3 s | — |

## Engine facts the mock missed (found by first headless run, 2026-09-26)

1. 2.0.77 + 2.1.20: `LuaItemStack.preview_icons = {}` on a blueprint with entities raises "Cannot set empty preview
   icons for a non-empty blueprint." Delivery set `{}` whenever metadata had no icons, so `stage()` failed and the
   blueprint never reached the cursor (`blueprint_delivery_failed`).
2. 2.1.20: `LuaItemPrototype.fuel_category` is gone; `fuel_categories` is an array of names. Reading the old key
   raised, so every 2.1 generation failed `BP_FAIL_INTERNAL_ERROR` in prepare.
3. 2.1.20: `effect_receiver.quality_limits = {high = 1000, low = 0}`; code read `min`/`minimum`/`[1]`, so every 2.1
   machine was `BP_REJ_UNSUPPORTED_INTERFACE`.
