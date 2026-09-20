# 092 — The game remembers which generation attempt belongs to which sheet, after it ends

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-092`, branch `lane/092`, base tag `round-10-base` (resolve with `git rev-parse round-10-base`), merge target `feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

**PRESERVE:**
- You own `logic/bp/generation.lua`, `gui/blueprint_dialog.lua`, and new `tests/test_generation_attempt_lookup.lua`.
- `logic/export_payload.lua` is frozen. Lane 091 owns it and consumes what you publish.
- `logic/jobs.lua` is frozen. Its cleanup is correct for jobs; the durable record belongs to the generation service.
- `logic/bp/search.lua`, `logic/bp/route.lua`, `tools/handoff.sh`, `tests/golden/**` and `tools/release_gate.py` are frozen.
- `docs/feature-contracts.md` §23 is a frozen contract. Read §23.2 and §23.3 first.
- Never `git push`, never touch `main`, never `--no-verify`, never amend, never rebase, never merge.
- Never edit a file this lane does not own. If you need a change elsewhere, stop and report it.
- Never weaken an assertion, delete a case, or accept a new baseline. A changed expectation stops the lane.
- Never edit `info.json` or `mod-description.md`; both carry the player's own uncommitted work.
- Never add a "skip if the dependency is missing" branch to any test.
- Never satisfy a test by writing a generation id into player storage from the test itself. The test drives the real dialog handler and the real scheduler, or it proves nothing.

**Write `tests/test_generation_attempt_lookup.lua` first, before changing either module.**

A player pressed Generate, the search failed, the player pressed Export debug, and the export carried no attempt
at all. Discovery is transient, never durable. Verified on this base, host `legalcopilot-dev`, 2026-09-20:

```text
logic/jobs.lua:202, :257           data.blueprint_job IS written while a blueprint job is queued or stored
logic/export_payload.lua:543-544   the exporter reads that field and walks its ids
logic/jobs.lua:405-407             data.blueprint_job = nil when the job is serviced
logic/jobs.lua:423-426             restored only when the job is NOT terminal
gui/blueprint_dialog.lua:306-321   Generate returns job_id and records no per-sheet attempt of its own
logic/bp/generation.lua:80-100     persist_handle drops reason_details, which :724 had just set
```

An export taken while the search runs can find the attempt. An export taken after it ends — which is exactly
when a player exports, because they are reporting a failure — finds nothing.

`tests/golden/capture_case.lua:90-92` sets `storage[player_index].generation_id` by hand. That is why every
existing export test passes over a gap the game never closes. That file is frozen here, and you never imitate it.

## What to build

1. The generation service owns a durable map from player and sheet to the appropriate attempt, surviving terminal state, the cleanup at `logic/jobs.lua:405-407`, and reload.
2. Selection rule, stated in code and pinned by a test: the newest **terminal or pending** attempt **for that sheet**. Another sheet's attempt is never a fallback. No attempt at all is an explicit absent record, never an omitted section.
3. The record carries what §23.2 lists: actual settings, prepared-input identity, sheet and revision identities, terminal state, reason codes, and whatever diagnostics the current search already produces.
4. `gui/blueprint_dialog.lua` records the attempt it starts, so the lookup is correct from the click onward, including while the job is still queued.
5. `persist_handle` keeps `reason_details`. Today `terminal_failure` (`:724`) sets it and persistence drops it, so a reloaded failure explains less than a live one.
6. Transient discovery through `data.blueprint_job` keeps working. This is an addition, never a replacement.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-10-base -- logic/bp/generation.lua gui/blueprint_dialog.lua || exit 1; if out=$(cd \"$S\" && lua5.2 tests/test_generation_attempt_lookup.lua 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -q '^FAIL AL1 .*\\[assert\\]' || { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -q '\\[error\\]' && { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE '^test_generation_attempt_lookup \\[Lua 5\\.[24]\\]: [1-9][0-9]* cases, ' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 600}
{"name": "owned-tests", "command": "lua5.2 tests/test_generation_attempt_lookup.lua && lua5.4 tests/test_generation_attempt_lookup.lua", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 900}
{"name": "no-hand-written-id", "command": "if grep -nE 'storage\\[[^]]*\\]\\.(generation_id|last_generation_id|last_blueprint_generation_id|last_blueprint_attempt)[[:space:]]*=' tests/test_generation_attempt_lookup.lua; then echo 'the test writes an attempt id by hand'; exit 1; fi; echo no-hand-written-id", "expect_exit": 0, "expect_regex": "no-hand-written-id", "timeout_s": 60}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 092_attempt_lookup", "expect_exit": 0, "expect_regex": "0 failed", "timeout_s": 1800}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-10-base --manifest docs/tasks/092.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Your own tests must include, by these exact case names:

- `AL1` real dialog handler, scheduler run to a terminal failure, normal queue cleanup, and the attempt is still found for that sheet.
- `AL2` that attempt carries its actual settings, prepared-input identity, sheet and revision identities, terminal state and reason codes.
- `AL3` the same survives a persistence round trip, `reason_details` included.
- `AL4` immediately after the click, before any tick, the attempt is found and is honestly named queued or pending.
- `AL5` a newer attempt on another sheet is never returned for this sheet.
- `AL6` a cancelled attempt is named cancelled, never dropped silently.
- `AL7` a player with no attempt for that sheet yields an explicit absent record, never a nil that reads as "no data".
- `AL8` transient discovery through `data.blueprint_job` still works while a job is queued.

## Files this lane owns

`logic/bp/generation.lua`, `gui/blueprint_dialog.lua`, `tests/test_generation_attempt_lookup.lua`

# bound: 2700s
