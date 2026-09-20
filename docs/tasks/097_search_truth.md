# 097 search truth: one cause per stop, reasons kept, and a bound that is not a cheap failure

## What is true

Base tag `round-11-base`. Contract: `docs/feature-contracts.md` section 24, rules 24.4, 24.6, 24.7.

The spacing fallback is already migrated. `logic/bp/search.lua:198` reads
`finite(robo.connection_distance, finite(robo.logistic_radius, 0) * 2)`, and `tests/test_search.lua` cases
`BP-11` fail if the old literal `1` returns. **This lane never re-proves that deletion.** Four jobs remain.

**One. One error code stands for three unrelated causes.** `logic/bp/search.lua:935` `finish_search_budget`
emits `BP_FAIL_SEARCH_BUDGET` from five call sites covering three causes:

```
ops cap          search.lua:1047, :1054, :1176   budget_limit_reached
grid cap         search.lua:965  via :831        state.work.grid_limit_hit
power bound      search.lua:966  via :1118       state.work.power_bound_hit
```

The player's run stopped with `gridhit=true` and `max_ops=nil`: an exhausted grid ladder reported as a budget
failure, while no operation cap had ever been derived.

**Two. Rejections are thrown away.** `logic/bp/search.lua:92` `record_rejection` has ONE caller,
`logic/bp/search.lua:1147`, the validator. `discard_candidate` (`:1031`) is reached from five places and four
of them record nothing: pack `:1095`, route input `:1105`, route `:1112`, power `:1128`.
`logic/bp/search.lua:80` `failure` replaces `state.errors` with a bare `{{code = code}}`, erasing whatever the
stage list held. `candidate_fits_grid` (`:982`) skips a candidate with no record at all.

**Three. The whole job's ceiling can be set by a candidate that FAILED.** `logic/bp/search.lua:920`
`derive_allowance` is reached from `finish_candidate`, which `discard_candidate` calls at `:1031`, so a cheap
rejection sets `state.max_ops` for everything after it. `CANDIDATE_ALLOWANCE` is `4` at `:914`. Separately
`grid_trial_limit` (`:130`) defaults to 12 over a ladder that can hold 49, so the two bounds contradict.
`docs/tasks/084_search_allowance.md` mandates `tests/test_search_allowance.lua`, which has never been written.

**Four. Nothing carries where the roboport spacing came from.** The record the export needs is fixed by the
contract:

```
grid_spacing = {resolved, kind = "override" | "derived",
                source = "caller" | "logistic_radius", source_value, generation_job_id}
```

The real path, verified on this tree, and every hop is an explicit-field projection that silently drops
anything new:

```
identity handoff   logic/bp/generation.lua:1135-1139  sets player, sheet, revisions - NOT generation_job_id
search input       logic/bp/generation.lua:1058-1077  carries no generation_job_id
grid build         logic/bp/search.lua:191-195        grid_model returns a NEW table, copying named fields
candidate build    logic/bp/search.lua:650, :721      narrows grid data again
persistence        logic/bp/generation.lua:98         persist_handle, explicit fields
rehydration        logic/bp/generation.lua:129        handle_from_record, explicit fields
lookup             logic/bp/generation.lua:1263       public_attempt builds its OWN record
                   logic/bp/generation.lua:1309       Generation.lookup calls it
bridge             logic/bp/generation.lua:158        bridge_record, the export fallback
```

**Trap.** `public_status` (`logic/bp/generation.lua:1247`) is NOT on the export path.
`logic/export_payload.lua:878` picks `generation.lookup`, which reaches `public_attempt`, which never calls
`public_status`. Putting the record only on `public_status` leaves the export unchanged.

**Trap.** A field carried only on an in-memory handle disappears after reload, because `:98` and `:129` copy
named fields.

**Trap.** The ops cap KEEPS `BP_FAIL_SEARCH_BUDGET`. It is a genuine budget, and
`tests/golden/setup/tiny-chain.lua:58` drives `tests/test_case_capture.lua` cases through that exact path. Two
NEW codes are added instead, for the grid cap and the power bound. Each needs an entry in
`logic/bp/reason_codes.lua:23-26` AND one locale line in `locale/en`, `locale/cs` and `locale/ro`, or
`tests/test_locale_keys.lua` fails.

**Trap.** Never raise a limit after a failing run to turn it green.

PRESERVE: `logic/bp/groups.lua`, `logic/bp/validate.lua`, `logic/bp/geometry.lua`, `logic/catalog.lua`,
`logic/export_payload.lua`, `logic/bp/route.lua`, `logic/bp/pack.lua`, `logic/bp/power.lua`,
`tests/harness.lua`, `tests/golden/**`, `info.json`, `mod-description.md`.

Files this lane owns: `logic/bp/search.lua`, `logic/bp/generation.lua`, `logic/bp/reason_codes.lua`,
`locale/en/locale.cfg`, `locale/cs/locale.cfg`, `locale/ro/locale.cfg`, `tests/test_search.lua`,
`tests/test_search_budget.lua`, `tests/test_search_allowance.lua` (new), `tests/test_generation_reload.lua`,
`tests/test_generation_attempt_lookup.lua`, `tests/test_blueprint_pipeline.lua`,
`tests/test_external_ports.lua`, `tests/test_locale_keys.lua`.

Lane 096 consumes `grid_spacing` from the attempt. This lane produces it and carries it to the lookup. The
end-to-end export check belongs to integration.

## What to build

1. Distinct codes: grid-ladder exhaustion and power bound each emit their own `BP_FAIL_*`; the ops cap keeps
   `BP_FAIL_SEARCH_BUDGET`. Register each and give it an en, cs and ro line.
2. `record_rejection` is called from pack `:1095`, route input `:1105`, route `:1112` and power `:1128`.
   `candidate_fits_grid` `:982` records why a candidate was too large. `failure` `:80` stops erasing.
3. Two budgets. A finite, declared, resumable feasibility bound derived from the problem, never from a failed
   or incomplete candidate. A separate improvement budget that can never destroy an incumbent.
   `grid_trial_limit` `:130` stops contradicting `CANDIDATE_ALLOWANCE` `:914`. Write
   `tests/test_search_allowance.lua` with the four cases `docs/tasks/084_search_allowance.md` names.
4. Build the `grid_spacing` record, attach the attempt identity at the handoff, and carry it every hop above,
   through persistence and rehydration, to `public_attempt` and `bridge_record`.

## What done mean

```checks
{"name": "red-proof", "command": "S=$(mktemp -d) || exit 1; git worktree add --detach \"$S\" HEAD >/dev/null || exit 1; git -C \"$S\" checkout round-11-base -- logic/bp/search.lua || exit 1; if out=$(cd \"$S\" && lua5.2 tests/test_search.lua 2>&1); then rc=0; else rc=$?; fi; git worktree remove --force \"$S\"; printf '%s\\n' \"$out\" | grep -qE '^FAIL .*ST1 an exhausted grid ladder reports its own code, never the budget code .*\\[assert\\]' || { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -q '\\[error\\]' && { printf '%s\\n' \"$out\"; exit 1; }; printf '%s\\n' \"$out\" | grep -qE '^test_search \\[Lua 5\\.[24]\\]: [1-9][0-9]* cases, ' || { printf '%s\\n' \"$out\"; exit 1; }; [ \"$rc\" -ne 0 ] || exit 1; echo red-proof-ok", "expect_exit": 0, "expect_regex": "red-proof-ok", "timeout_s": 900}
{"name": "mandated-allowance-test-written", "command": "test -f tests/test_search_allowance.lua || { echo 'docs/tasks/084_search_allowance.md mandates tests/test_search_allowance.lua'; exit 1; }; echo allowance-test-present", "expect_exit": 0, "expect_regex": "allowance-test-present", "timeout_s": 60}
{"name": "spacing-stays-derived", "command": "grep -q 'robo.logistic_radius' logic/bp/search.lua || { echo 'the derived roboport gap was lost'; exit 1; }; echo spacing-derived", "expect_exit": 0, "expect_regex": "spacing-derived", "timeout_s": 60}
{"name": "focused", "command": "sh tools/verify_round9_lane.sh \"$PWD\" 097_search_truth", "expect_exit": 0, "expect_regex": "ran|OK", "timeout_s": 3600}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-11-base --manifest docs/tasks/097.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 120}
```

Every Lua check runs on both interpreters.

```
red-proof    git checkout round-11-base -- logic/bp/search.lua; lua5.2 tests/test_search.lua
             emits FAIL <your named case> ... [assert], zero [error], and a summary line matching
             ^test_search \[Lua 5\.[24]\]: [1-9][0-9]* cases,
             the BP-11 spacing cases stay green throughout
codes        an exhausted grid ladder emits its own code; a power bound emits its own code; an ops cap still
             emits BP_FAIL_SEARCH_BUDGET; lua5.2 tests/test_case_capture.lua stays green
reasons      a pack, route-input, route or power rejection reaches reason_details with its code; a candidate
             refused for size is recorded with its size; a failure that followed a rejection never carries an
             empty details list
budget       a candidate that FAILED cheaply never sets the job ceiling; an incumbent is never destroyed;
             the same input yields the same allowance twice
carry        a default-config attempt that fails downstream reports grid_spacing with resolved, kind, source
             and the exact generation_job_id; the same for a successful attempt
reload       after a persistence round trip with storage preserved, Generation.lookup still answers with all
             four fields; reverting persist_handle or handle_from_record makes this go red
isolation    another sheet's or another player's newer attempt never supplies the record
locale       lua5.2 tests/test_locale_keys.lua green with every new code present in en, cs and ro
focused      sh tools/verify_round9_lane.sh "$PWD" 097_search_truth
```

Your own tests must include, in `tests/test_search.lua`, by these exact case names. The red proof greps for `ST1 an exhausted grid ladder reports its own code, never the budget code`, so a different spelling fails the launch rather than the work.

- `ST1 an exhausted grid ladder reports its own code, never the budget code`
- `ST2 a power bound reports its own code, never the budget code`
- `ST3 an operation cap still reports BP_FAIL_SEARCH_BUDGET`
- `ST4 a pack, route, route-input or power rejection reaches reason_details`
- `ST5 a candidate refused for size is recorded with its size`
- `ST6 a cheap failed candidate never sets the whole job's ceiling`
- `ST7 a failing attempt still reports grid_spacing with its kind, source and generation_job_id`
- `ST8 grid_spacing survives a persistence round trip and answers through Generation.lookup`
