# Round 16 baseline — every measurement, on the host that made it

Host `legalcopilot-dev`. Branch `feat/round-8-blueprints`. Spine commit tagged `round-16-base`.
Plan: `~/.claude/plans/let-s-implement-this-feature-recursive-lighthouse.md`.
Round 15 outcome: `~/.claude/plans/rrc-round-15-handoff-2026-09-22.md`, ledger `docs/round-15-baseline.md`.

Numbers here were produced by commands in this repo, on this host, on the date each section names. A number
without a command is not in this file.

## 1. The demand sort: measured in both directions, and KEPT

`logic/bp/route.lua:748-757` sorts demands by pairing cost, descending. Lane 131 added it in `c9f50bc`
"WIP: 131_bindings". Round 15's handoff blamed per-hand demands for the splitter regression. That was wrong.

Measured 2026-09-22, by loading patched sources from strings and editing no file:

| variant | RF1 splitter | RF2 splitters | RF3 splitters | RB4 segments after 500 ops |
|---|---|---|---|---|
| HEAD | `(5.5,4)` dir E | 1 | 0 | 0 |
| `per_port_demands = false`, sort kept | `(5.5,4)` dir E | 1 | 0 | 0 |
| per-port kept, **sort removed** | `(6,3.5)` dir N | 0 | 1 | 8 |

Forcing `per_port_demands = false` changes nothing, so per-hand demands are innocent for all four cases.

Then the census, same case, same ops, 3 candidates reaching `validate` either way:

| variant | `BP_V_TRANSPORT_UNUSED` | `BP_V_ROUTE_DISCONTINUOUS` | `BP_V_TARGET_SHORTFALL` | wall |
|---|---:|---:|---:|---:|
| sort kept | **853** | **63** | 3 | 141.2 s |
| sort removed | 949 | 67 | 3 | 201.7 s |

So removing the sort makes the two splitter files whole and the **product worse**. The plan's section 7 item
1 said the measurement decides. It decided: **the sort stays**, and the comment above it now carries both
numbers so nobody deletes it again on the strength of the test failures alone.

`test_route_footprints` 6 failing and `test_route_budget` 2 failing therefore remain in the frozen red list at
`round-16-base`, and lane 140 must take them to zero **without** worsening the census — which is contract
28.5, 28.7 and 28.8, not a deletion.

## 2. Where the belt chain actually breaks

`tools/route_chain_probe.sh` plus `tools/route_chain_report.py`, new at spine. The probe appends a body to
`tests/golden/generate.lua`'s source in memory, cut at `local input_path,`, so it reuses that file's JSON
reader, `sha256` and `captured_plan` and reads the **same** prepared input the generator reads. It stops at
the first candidate to reach `validate` — `logic/bp/search.lua:1477` sets `state.work.validate_candidate`
immediately before `Validate.begin` — and prints that candidate. The report walks it breadth first with the
validator's own successor rule, `logic/bp/validate.lua:478-512`.

Measured 2026-09-22, `sh tools/route_chain_probe.sh player-red-science-1s 5000000 lua5.2`:

```
CHAIN candidate entities=437 belts=382 inserters=26 machines=11 ports=29 ops_used=1500000
CHAIN splitters=2 undergrounds=44
CHAIN bindings=22 whole=13 broken=9
CHAIN reason nothing ahead                                  7
CHAIN reason walk closed with no dead end and no target     2
```

### 2.1 The mechanism I guessed, and why it is dead

The plan's section 4.4 named splitter conversion at `logic/bp/route.lua:1048-1052` as the leading mechanism:
converting a committed belt into a splitter rewrites its direction and breaks a chain an earlier demand
depends on. **Refuted.** The whole candidate carries **2** splitters, and not one break tile is a splitter —
every broken record reports `splitter=False`. The hypothesis was reasonable and it was wrong, and it was
wrong before any lane was dispatched, which is the only reason spine measures before it writes contracts.

### 2.2 The mechanism that is measured

Seven of nine breaks are `nothing ahead`: the run simply **stops short of its sink**, 4 to 24 tiles away,
with empty ground in front of its last belt.

```
in:item/iron-ore -> iron-plate:...:3:input:1   stopped_at=(17,42) facing=S ahead=(17,43) empty distance=4
in:item/iron-ore -> iron-plate:...:2:input:1   stopped_at=(17,42) facing=S ahead=(17,43) empty distance=8
in:item/iron-ore -> iron-plate:...:1:input:1   stopped_at=(17,42) facing=S ahead=(17,43) empty distance=12
iron-gear-wheel:out -> science:...:2:input:2   stopped_at=(16,1)  facing=S ahead=(16,2)  empty distance=10
iron-gear-wheel:out -> science:...:1:input:2   stopped_at=(16,1)  facing=S ahead=(16,2)  empty distance=12
copper-plate:...:2:output:1 -> science:...:2   stopped_at=(20,3)  facing=W ahead=(19,3)  empty distance=10
iron-gear-wheel:out -> science:...:3:input:2   stopped_at=(16,1)  facing=S ahead=(16,2)  empty distance=24
```

Read the sources: **one source port, several sinks, one dead end.** Four science machines take gear from one
gear machine; three iron-plate machines take ore from one external supply. Every one of those sinks gets its
own binding — `logic/bp/route.lua:1083` and `:1116` append one binding per sink with
`segment_id = first_segment.segment_id` — and `add_allocation` puts that sink's rate on the shared trunk. The
trunk is laid once. **The branch from trunk to each further sink's own port tile is never laid**, and the
binding is recorded anyway. So router reports success on a run that ends in mid-air.

The remaining two breaks are the science output runs: the walk closes with no dead end and no target, which
is a cycle, and it is the same family — a shared run reused past the point where it still leads anywhere.

That is contract **28.8**'s other half, and it is the real defect: sharing a trunk is correct, and every
branch off that trunk still needs its own belt to its own port tile.

### 2.3 The size of what gets built, against the factory that runs

| metric | this candidate | player's `red_science_1s_manual_bp.txt` |
|---|---:|---:|
| entities | 437 | **131** |
| transport belts | 382 | **84** |
| underground endpoints | 44 | **0** |
| splitters | 2 | **0** |
| inserters | 26 | **22** |
| machines | 11 | **11** |

Machine count already matches. Nothing else does. 44 undergrounds on a sheet whose author used none is its
own finding, and it is what makes the delivery bar — the player's decision, "hold until it matches my factory
closely" — load-bearing rather than cosmetic.

## 3. `tools/ceiling.sh` was timing an unbounded search

`tests/golden/cases/player-red-science-1s/prepared_input.json` carries no `search_budget`, and
`logic/bp/search.lua:143-151` leaves the bound `nil` when nobody supplies one. Measured 2026-09-22:
`sh tools/ceiling.sh player-red-science-1s 5.00 lua5.2` was killed at **900 s**, exit 143, nothing delivered.

`sh tests/acceptance/run` was killed the same way at **900 s**, exit 143, printing no line at all: the same
unbounded case drives it, so the delivery gate could not be read. Fixed at spine —
`tests/acceptance/red_science_case.lua` now supplies `search_budget = 5000000` and `tests/acceptance/run`
carries a `timeout` backstop that FAILS by name instead of hanging.

Round 14 measured the first candidate arriving at **3 s** on this same input. So the five second ceiling is
answered by **acceptance**, never by a speed lane, and no speed lane is cut.

`tools/ceiling.sh` now carries its own hard bound of `24 x limit`, at least 60 s, and the case input is still
never given a budget, because a golden case must run at default configuration. A run that does not return is
over the limit by construction and now says so:

```
ceiling: case=player-red-science-1s interpreter=lua5.2 elapsed=>120s limit=5.00s exit=124 result=killed-at-hard-limit
ceiling.sh: the run did not finish inside 120s, so it is over the 5.00s limit by construction
```

Exit 1 in 120 s, where it used to hang past 900 s.

## 4. What spine built

| artefact | what it does |
|---|---|
| `tools/route_chain_probe.sh`, `tools/route_chain_report.py` | say WHERE a run stops being a directed chain; the validator's records carry no tile |
| `tools/red_list.sh`, `docs/round-16-red-list.txt` | refuse any test file worse than a frozen count; names no file, so no lane arm can omit one. **213 identities** frozen at `round-16-base`, of which exactly ten are red: `test_blueprint_pipeline` 2, `test_corpus_setups` 6, `test_route_budget` 2, `test_route_footprints` 6 and `test_search` 6, each per interpreter, plus `python_tools` at 0 |
| `tests/test_census_codes_live.lua` CL5a and CL5b | `BP_V_TARGET_SHORTFALL` counts 3, under the sensitivity floor of 50, so only a direct test can guard it |
| `multi_flow_hands = false` in `groups.lua`, `route.lua`, `validate.lua` | lets three lanes build three halves of contract 28.1 in parallel without sharing a file |
| `docs/round-16-census-baseline.json` | re-frozen; round 15's file pins `validate_attempts: 8` and the tree now reaches 3, so the denominator floor refused every comparison |
| `tools/ceiling.sh` hard bound, `tests/acceptance/run` timeout, `red_science_case.lua` budget | three gates that hung now refuse by name |
| dispatcher arms `140_route`, `141_witness`, `142_economy` | each names EVERY test that requires its lane's module |
| mutations `splitter-footprint-silent`, `binding-without-run`, `trunk-sharing-off`, `unused-detail-bare`, `census-code-shortfall`, `shared-hand-off` | each binds to code its task mandates |

## 5. The frozen baseline, measured

Both tiers measured on `legalcopilot-dev` 2026-09-22, with the demand sort **in place**, from
`python3 tools/real_sheet_census.py --case player-red-science-1s --ops <n>`:

| tier | ops | candidates | terminal | `TRANSPORT_UNUSED` | `ROUTE_DISCONTINUOUS` | `TARGET_SHORTFALL` | `PW_DISCONNECTED` | wall |
|---|---:|---:|---|---:|---:|---:|---:|---:|
| fast | 5,000,000 | 3 | `BP_FAIL_SEARCH_BUDGET` | 853 | 63 | 3 | 0 | 141.2 s |
| full | 40,000,000 | 11 | `BP_FAIL_GRID_LIMIT` | 3148 | 230 | 11 | 1 | 1050.9 s |

Rates hold across budgets — 284.33 / 21.0 / 1.0 at the fast tier against 286.18 / 20.91 / 1.0 at the full
tier — and that is what makes gating on rate meaningful rather than gating on a total that moves with the
number of candidates judged. The full tier ends on `BP_FAIL_GRID_LIMIT` rather than the budget, so 11
candidates is the whole grid ladder for this sheet at that breadth.

`docs/round-16-census-baseline.json` carries both, keeps round 15's policy block verbatim, and records in its
own note that the fast tier was measured with the sort in place.

## 6. The acceptance gate can be read again

Before: `sh tests/acceptance/run` passed 900 s and was killed, exit 143, printing nothing.

After the spine fix it terminates and prints. First run, `search_budget = 5000000` with the harness's default
1,200 ticks:

```
GATE red-science-chain: state=pending stage=power codes= ticks=1200 validate calls=1 ok=0 rejected=1
    rejections=BP_V_ROUTE_DISCONTINUOUSx21,BP_V_TARGET_SHORTFALLx1,BP_V_TRANSPORT_UNUSEDx302
```

Two things worth keeping. The gate's own numbers — 21 discontinuous and 302 unused on one candidate — match
the census exactly, so the in-harness path and the offline census agree about the same fault. And
`state=pending` means the **tick allowance** ran out, not the budget, which says only "did not finish". So the
case now carries `search_budget = 2000000` and `ticks = 2400`: the first candidate arrives at about 1,500,000
ops, so the budget ends the run inside the allowance and the gate prints a real refusal with codes.

`acceptance_item_chain` 1 failing and `acceptance_gate_digest` 4 failing are **pre-existing**, verified by
running both at `cb7a636` in a throwaway worktree before any spine change. `acceptance_item_chain` fails at
tick 1 with `BP_FAIL_GRID_LIMIT`. The acceptance suite is not in the fast tier, so `tools/red_list.sh` does
not cover it; its state is recorded here instead.

## 7. A defect in my own gate, found before any lane ran

`tools/red_list.sh` compared each observed identity against the frozen list and wrote

```sh
[ "$failing" -gt 0 ] && status=1
```

Under `set -eu` that `&&` list returns non-zero when its left side is false, and it was the loop body's
result, so the whole script aborted. The case that triggers it is **a brand new file that is GREEN** —
exactly what a lane adds. The gate meant to catch a lane's regression would have failed the lane for adding
a passing test. Written as an `if`, a green new file is a note and a red one is a refusal.

Proving that needed the comparison to run without a twenty minute suite in front of it, so `red_list.sh`
gained `--observed <file>`, which reads an already-collected inventory. Six cases, against the real script,
2026-09-22:

| observed against frozen `alpha 2`, `beta 0` | expected | got |
|---|---|---|
| unchanged | exit 0 | exit 0, `RED-LIST ok 2 identities` |
| new file `gamma` with 0 failing | exit 0 | exit 0, `RED-LIST new gamma [lua5.2] failing=0` |
| new file `gamma` with 3 failing | exit 1 | exit 1, `RED-LIST new gamma [lua5.2] failing=3` |
| `alpha` 2 to 5 | exit 1 | exit 1, `RED-LIST worse alpha [lua5.2] failing=5 frozen=2` |
| `alpha` 2 to 0 | exit 0 | exit 0, `RED-LIST better alpha [lua5.2] failing=0 frozen=2` |
| `beta` vanishes | exit 1 | exit 1, `RED-LIST missing beta [lua5.2] was in the frozen list and did not run` |

A ratchet that cannot go red on a regression and green on an improvement is decoration. These six are why it
is not.

## 8. Attempt 1 of all three lanes died on Codex quota, not on its work

Launched 2026-09-22T04:54Z, `140_route`, `141_witness` and `142_economy`, bound 2266 s each. All three came
back `FAIL reason: engine-exit` after **971 s, 971 s and 993 s**. The verdict says nothing about why. The
reason is only in each lane's `docs/audit/runs/<label>/attempts/<run_id>/engine.log`, and all three carry the
same line:

```
ERROR: You've hit your usage limit. Visit https://chatgpt.com/codex/settings/usage to purchase more credits
or try again at Sep 27th, 2026 6:44 AM.
```

The work up to the cut survived in each worktree, and two of the three were already good. Measured
2026-09-22 by running each lane's own files in its own worktree:

| lane | state | measured |
|---|---|---|
| `142_economy` | committed `3d11d4e`, green | `test_hand_economy` 6 of 6 with HE1, HE2 and HE3; `test_groups` 32 of 32; `test_pack` 30 of 30; `test_inserter_geometry` 26 of 26; `test_transport_handshake` 8 of 8; oracle 88 of 88; codes-live 7 of 7; `multi_flow_hands` still `false` at `groups.lua:511` |
| `141_witness` | uncommitted, green | `test_validate` 44 of 44 against 42 at base; `test_physical_witness` 12 of 12 against 8; `test_validated_candidate` 2 of 2; oracle 88 of 88; codes-live 7 of 7 |
| `140_route` | uncommitted, regressed | `test_route` 36 of 38; `test_route_footprints` 0 of 6; `test_route_budget` 4 of 8 against 6 at base; `test_route_network` 10 of 14; `tests/test_route_chain.lua` never written |

Lane 140 had real work in flight -- `splitter_can_absorb` wired into the crossing decision and a
`segment_has_flow` predicate replacing the scalar flow comparison -- and was mid-edit when the engine was
cut.

Retried 2026-09-22T06:20Z to 06:24Z as attempt 2, in the SAME worktrees so nothing is lost. Two machine
facts, both measured: `lane launch` refuses a worktree it did not find and never creates one, and a second
launch of one label is refused with `attempt-already-exists` unless `--attempt-of <run_id>` is passed.

## 9. Red proofs taken at spine

| proof | result |
|---|---|
| rename `BP_V_TARGET_SHORTFALL` in `logic/bp/validate.lua` | `tests/test_census_codes_live.lua` 7 of 7 becomes 6 of 7; restored, 7 of 7 |
| unchanged tree, nothing required down | `CENSUS-GATE ok tier=fast down=none validate_attempts=3 total=919 waivers=0`, exit 0 |
| unchanged tree, `--require-down BP_V_TRANSPORT_UNUSED,BP_V_ROUTE_DISCONTINUOUS` | exit 1 naming both: `rate 284.3333 did not fall below the baseline 284.3333` and `rate 21.0 did not fall below the baseline 21.0` (`tools/census_gate.py:181-184`) |
| `tools/red_list.sh` on a worse file, and on a new red file | exit 1 both, naming the file |
| `tools/ceiling.sh` on a search that does not accept | exit 1 in 120 s naming `killed-at-hard-limit`, where it used to hang past 900 s |
