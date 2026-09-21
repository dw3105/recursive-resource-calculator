# Round 13 baseline ledger

Host legalcopilot-dev, 2026-09-21. Spine tree: the commit that adds
`tests/test_blueprint_physical_contract.lua`. Written before any lane starts, so a lane cannot be credited for
a failure it did not cause, nor blamed for one it inherited.

Aggregate counts are never the allowlist. Every entry names its invocation, its test identity and its
interpreter.

## Pre-spine baseline, at `7c5429e`

| invocation | red |
|---|---|
| `lua5.2 tests/test_search.lua` | BP-20: `a larger grid that needs fewer beacons wins`, `the better candidate found second wins`, `the better first candidate survives a worse follow-up`, `equal beacon counts defer to footprint area`; 2 shapes each |
| `lua5.4 tests/test_search.lua` | the same four, 2 shapes each |
| `lua5.2 tests/test_corpus_setups.lua` | `shared-intermediate-multi-target`, `fluid-byproduct-chain`; 2 shapes each |
| `lua5.4 tests/test_corpus_setups.lua` | the same two, 2 shapes each |
| `python3 -m unittest tests.tools.test_golden_tools` | `test_accept_generated_case_promotes_reviewed_draft`, `test_accept_changes_only_the_named_expectation` — both `only captured cases may be accepted`, `tests/golden/lib/runner.py:1118` |

## Post-spine baseline

Spine goes **known, not green**. The physical contract is written against behaviour that does not exist yet,
so it is red on purpose; a lane closes its rows, and nothing else may change.

### `lua5.2 tests/test_blueprint_physical_contract.lua` — 68 cases, 16 passed, 52 failed
### `lua5.4 tests/test_blueprint_physical_contract.lua` — 68 cases, 16 passed, 52 failed

Identical on both interpreters. Per shape, 2.0 and 2.1 alike:

The seven `FL` rows were added after a review measured the generator emitting item inserters for FLUID
connections: one fluid input, one item input and one fluid output produced 3 materialized inserters, **2 of
them on fluid flows**, under both interpreters and at all four rotations, with explicit fluid flags supplied.
`tests/test_groups.lua` passes 30 of 30 while that is true, so a count is not evidence and named cases are.

`BE1` was also strengthened: it asserted only the absence of a shortage code, so it could have stayed green
while extra-beacon factories were rejected for some other reason. It now requires `state.ok == true`.

**Green already (8):**

| case | why it already holds |
|---|---|
| `PC1` the hand-built working factory is accepted | the positive control is genuinely valid under today's rules, so every rejection below is a real catch and not a broken base |
| `ID6` a lost module is rejected | `BP_V_MODULE_MISMATCH` already exists |
| `BE1` influence above the configured count is accepted | today's check is `got < required`, which is the behaviour the user asked to keep |
| `BE2` a speed beacon reaching a quality machine is rejected | `validate.lua:635-638`, already geometry-driven |
| `SR2` a furnace member never receives a recipe field | true today only because **no** member receives one |
| `SR3` serialization preserves the recipe and its quality | `serialize.lua:393` copies the field when it is present; the producer is what never sets it |
| `FL1` a machine fed by pipe and emptied by inserter is accepted | the fluid positive control is valid under today's rules |
| `FL5` two fluids sharing one network is rejected | `BP_V_FLUID_MIXING` already exists |

**Red on purpose (26 per shape, 52 in total):**

| case | closed by |
|---|---|
| `ID1` recipe deleted | lane 111 |
| `ID2` recipe replaced | lane 111 |
| `ID3` recipe on a furnace | lane 111 |
| `ID4` machine prototype changed | lane 111 |
| `ID5` machine quality changed | lane 111 |
| `TR1` input inserter removed | lane 111 |
| `TR2` output inserter removed | lane 111 |
| `TR3` input inserter moved off target | lane 111 |
| `TR4` output inserter reversed | lane 111 |
| `TR5` middle belt removed | lane 111 |
| `TR6` middle belt reversed | lane 111 |
| `TR7` every belt removed | lane 111 |
| `TR8` every inserter removed | lane 111 |
| `TR9` input belt no longer reaches its supply port | lane 111 |
| `TR10` output branch over capacity | lane 111 |
| `BE3` per-instance influence records | lane 111 |
| `MT1` measured transport cost and production area | lane 111 |
| `MT2` an absent metric rejects | lane 111 |
| `MT3` the published comparator order | lane 111 |
| `SR1` grouping carries the recipe | lane 110 |
| `SR4` a serializer-only mutation is detected | lane 111 produces `Validate.reconcile_artifact`, lane 113 calls it on the production path |
| `FL2` an item inserter on a fluid connection | lane 111 rejects it, lane 110 stops emitting it |
| `FL3` a pipe removed from the middle | lane 111 |
| `FL4` every pipe removed | lane 111 |
| `FL6` a pipe run that reaches no fluid box | lane 111 |
| `FL7` grouping emits no inserter for a fluid-only connection | lane 110 |

`SR2` is expected to **stay** green and to become meaningful once `SR1` closes: today it passes vacuously,
because no member carries a recipe at all.

### `python3 -m unittest discover -s tests/tools -t .` — 147 tests, 3 failures, 1 error

Two are the pre-spine `test_golden_tools` pair above, unchanged. Two are new, and both are producer/consumer
handoffs created by the receipt bindings, not defects in the tools that report them:

| test | why it is red | closed by |
|---|---|---|
| `tests.tools.test_evidence_contract.EvidenceContractTests.test_companion_shape_is_the_bytes_consumed_by_the_gate` | the synthetic controller drives `tests/golden/engine/mod/scenario.lua`, which does not yet emit `prepared_input_sha256`, `config_sha256` or `harness_qualification_id` | lane **114** emits them; integration re-runs this test after 114 merges |
| `tests.tools.test_golden_tools.GoldenToolsTests.test_receipt_refuses_hash_candidate_case_and_development_build` | its happy-path observation carries no bindings, so `make_receipt` now refuses before reaching the assertion | lane **115**, which owns `tests/tools/test_golden_tools.py` |

Spine did not repair either. Editing them here would be doing a lane's work in the commit that defines that
lane's gate, and the ledger exists precisely so a lane cannot be blamed for a failure it inherited or credited
for one it never caused.

## Receipt bindings, proven before the tag

`tools/evidence_receipt.py` and `tools/release_gate.py` now require `prepared_input_sha256`, `config_sha256`
and `harness_qualification_id`, and recompute the first two wherever their source is supplied.

| check | result |
|---|---|
| `tests.tools.test_release_gate` with the fixture carrying real bindings | 23 tests, all pass |
| an observation with no `prepared_input_sha256` | `evidence refused: missing binding` |
| `--prepared-input` whose bytes disagree with the declared digest | `evidence refused: prepared input mismatch` |
| a case whose `prepared_input` file is swapped after the receipt is written | `release refused: mismatched input` |

## Dispatcher, proven before the tag

`tools/verify_round9_lane.sh`, with traps for `lua`, `lua5.2`, `lua5.4`, `python3` and `gateslot` first on
`PATH`:

| command | result |
|---|---|
| `--dispatch-only "$PWD" 110_producer` … `115_goldens` | bounded selection, right runner, **none** `dispatch=suite` |
| `--dispatch-only "$PWD" 999_missing` | exit 2 |
| `"$PWD" 112_capture --dispatch-only` | exit 2, never executes |
| `--dispatch-only "$PWD" 112_capture extra` | exit 2 |
| traps fired across all of the above | **0** |

## Rule

Any change to a line above, other than a lane closing its own listed rows, blocks the merge that caused it.

## Historical-negative registry, published before the tag

`tests/golden/historical-negatives.json` is the single list both runners consume. Spine publishes the schema
and the one entry; lane 115 implements consumption in `tests/golden/lib/runner.py`, and integration owns the
registry file and the matrix transfer.

| field | meaning |
|---|---|
| `structural_outcome`, `structural_reason_code` | structural execution RUNS the case and requires exactly this rejection. Unexpected success, a different rejection, or missing input each fail |
| `raw_bytes_immutable`, `observed_outcome_immutable` | the raw export, the PreparedInput and the historical observations stay byte-for-byte unchanged |
| `production_coverage_transferred_to` | release discovery excludes this case only because its required coverage moved to the named case. An unregistered missing case still fails, so coverage can never be dropped by deleting a row |
| `clauses_transferred`, `branches_transferred` | the exact coverage that moved, so the transfer is checkable rather than assumed |

Until `player-am2-chain-fresh` exists, the transfer target is absent and strict release acceptance stays red.
That is the intended state: engine acceptance is pending, and no relabelling makes it otherwise.

## Lane gates, proven to refuse before the lanes start

A gate that already passes cannot report a repair. Every repair gate was run against the unchanged base:

| gate | result on base |
|---|---|
| all four of 110, except `counts-unreduced` | refuses |
| all four of 111 | refuses |
| all four of 112 | refuses |
| all four of 113, including `five-second-ceiling` at **12934ms** against the 5000ms limit | refuses |
| all four of 114 | refuses |
| all six of 115, except `frozen-text` | refuses |

`counts-unreduced` and `frozen-text` pass on purpose: they are protections, not repairs. They fail the moment
a lane reduces the player's configured beacon counts or reflows the frozen `local input_path,` line.

Two holes were measured and closed before relaunch:

- a gate written as "grep for FAIL <case>; absent means pass" returned **exit 0** with a stub interpreter that
  printed a startup error and exited 77. `tools/lane_rows.sh` now requires a completed harness summary under
  every interpreter, a minimum case count, zero `[error]`, and the named case to exist in the file.
- `--pass CG1` against a file containing no `CG1` also returned exit 0, because a case that does not exist
  looks exactly like a case that passed. The named case must now appear in the test file.

## Second gate correction, 2026-09-21, with the lanes left running

A second review measured five more holes. The lanes were **not** restarted: a lane snapshots its checks into
`required.json` at launch, so editing a task afterwards never changes what that lane verifies. Every fix below
lands on the integration branch, each lane's self-reported verdict is advisory, and I re-run the corrected
gates myself at merge.

| hole | measured | closed by |
|---|---|---|
| the gate proved source text, not execution | a file whose `CG1` was only in a COMMENT passed; so did a file containing only `CG10`; so did a case that genuinely failed under an unmatched shape label; so did a run that printed its summary then crashed | `tests/harness.lua` prints `CASE <outcome> <name>` and `CASES-COMPLETE <n>` under `RRC_CASE_REPORT=1`; `tools/lane_rows.sh` consumes that inventory and checks exit status against the summary |
| the 114 mutation produced invalid Lua | `if nil and nil ~= "normal" then nil = nil end`, `scenario.lua:894: unexpected symbol near 'nil'` on both interpreters, so the intended assertion was never reached | the mutation changes only the assigned VALUE, and every mutation is now parse-checked before the proof runs |
| the 115 red proof rejected ordinary failures | python unittest prints a traceback for an `AssertionError`, and the predicate banned `Traceback`, so a correctly killed mutant was refused | the predicate uses unittest's own categories: a named `FAIL: test_` must appear and no `ERROR:` may |
| the ceiling accepted invalid output | `{"ok":true,"validation":{"ok":false}}` gave `ceiling-met 2ms` | it now requires `ok`, `validation.ok` and a non-empty artifact |
| `SR4` had no positive control | replacing `Validate.reconcile_artifact` with a stub returning `{ok = false}` moved the oracle to 18 passed with no `SR4` failure | `SR4` asserts acceptance of the unmodified artifact first; the stub now fails it |

`RRC_CASE_REPORT` is opt-in, so ordinary suite output is unchanged: `test_groups` still reports 30 of 30 and
the oracle still reports 68 cases, 16 passed, 52 failed.

**The five-second ceiling is lane-local only.** Its input is the player capture, because at this base every
other fixture carrying a `prepared_input.json` refuses with `BP_REJ_PROTOTYPE_FACTS_MISSING`, and that capture
is a registered historical negative that must REJECT once lane 112 lands. At integration the gate re-points to
the fresh export from Milestone A prime. The end-to-end player ceiling stays **pending**; measured at this
base it is **10722ms** against the 5000ms limit.

## Merge-time findings, recorded as they land

Lane verdicts are advisory: every lane snapshotted its checks before the gate corrections above, so each
result is re-verified here with the corrected tooling.

### Lane 111 validator — verified, genuinely closed

Merged onto the integration tip and run under the corrected `lane_rows.sh`, which requires each named case to
have actually executed:

```
68 cases, 64 passed, 4 failed   (both interpreters)
lane-rows-ok
```

The oracle moved from 16 passed to 64. The four still red are `SR1` and `FL7` on both shapes, and both belong
to lane **110**: grouping must carry the recipe, and grouping must stop emitting an inserter for a fluid-only
connection.

### Lane 115 goldens — verified alone, one cross-lane break with 111

Alone on the integration tip: `tests.tools.test_golden_tools` 13 tests, **OK**.

Merged together with lane 111, two cases fail:

| test | cause |
|---|---|
| `test_prepared_input_runs_real_generator_and_tiny_change_goes_red` | `run_golden(root, "generated-case")` returns 1 where it expects 0 |
| `test_accept_generated_case_promotes_reviewed_draft` | the same generated case can no longer be produced |

Neither is a lane defect. Lane 111 made validation physical, so the toy fixture those tests generate cannot
produce and is now correctly rejected. The repair belongs to integration: the fixture becomes a physically
valid miniature, or the test asserts the rejection.

**Permitted between the 111 merge and the 115 merge, and only there.** Both must be green at the
zero-failure checkpoint.

### Lane 110 producer — verified

Alone on the integration tip: oracle **16 → 20 passed**, `lane-rows-ok`. `SR1` and `FL7` closed, so grouping
carries the recipe and stops putting an inserter on a fluid-only connection.

With lane 111 together, both interpreters:

```
68 cases, 68 passed, 0 failed
lane-rows-ok
```

The whole physical contract is met. On the player capture, six of seven machines now carry their recipe and
the `electric-furnace` correctly carries none; inserters fall from 20 to 18, losing exactly the two that sat
on `fluid/molten-iron`; pipes rise from 24 to 29 plus 12 pipe-to-ground. 314 entities, `validation.ok` true.

### Lane 112 capture — verified, after a gate bug of my own

`CG1`–`CG4` green, `CX1`–`CX3` green, and `docs/tasks/112_findings.md` names where the empty inserter offsets
come from: the catalog projection boundary, before `ExportPayload.build` runs, and it says plainly that the
fixture cannot establish whether the runtime or an adapter supplied the array shape.

The gate first reported `executed no case named CX1`. That was **my** defect, not the lane's: `outcomes_for`
required a numeric shape between the outcome and the case id, and this suite registers its cases once with no
shape prefix. The shape is now optional, and all four earlier counterexamples still refuse.

### Lane 114 harness — verified, after re-aiming a mutation

`QS1`, `QD1`, `QC1`, `QP1` green: 26 cases, 26 passed, both interpreters.
`tests.tools.test_evidence_contract` **OK**, so the companion now emits the three receipt bindings and the
failure recorded at spine is closed. `docs/tasks/114_qualification.md` names its warm-up, sampling window,
tolerance and timeout.

The red proof first reported `port-quality-nil changed nothing; the target it names is absent`. The lane had
rewritten `stack.quality = port.quality` as `stack["quality"] = port.quality` — functionally identical, and it
left the named mutation with nothing to bind to. Recorded as a fact, not an accusation: a red proof that
cannot find its target is not a passing red proof, so the mutation now matches both spellings. Re-run, it
kills `QS1` and three more, and the lane's tests do detect the defect.

Milestone E stays **pending**. This is implemented, never qualified: no Factorio on this host.

### Lane 113 layout — FAILED, taken in part

```
113_layout FAIL after 3600s | reason: engine-timeout
```

`RT1` and `RT2` pass: `logic/bp/route.lua` now sets `length` on every belt segment, the real span on every
underground, and carries it through `result_for`. That is +6/-4 lines, exactly the contract, and it is taken.

Everything the lane did to `logic/bp/search.lua` is **rejected**. It crashes —
`search.lua:1279: bad argument #1 to 'remove' (position out of bounds)` — and takes all 18
`test_search_budget` cases with it, 0 passed. The cause is debugging scaffolding left in production code:
sixteen `io.stderr:write("DBG ...")` calls, and

```lua
local preferred = table.remove(state.work.groups.result.candidates, 19)
```

a hardcoded index 19 hand-picking a candidate, which is out of bounds whenever fewer than 19 exist. That is an
experiment, not a repair, and no verdict can rest on it.

**Still open, and now integration's:** the reserved finalization sequence (`FN1`–`FN4`) and the five-second
ceiling. `tests/test_search_budget.lua` from this lane is not taken either, because its `FN` cases require the
implementation that was rejected.

## Integration, all five usable lanes merged

Merge order 112 -> 111 -> 110 -> 113 (route half only) -> 114 -> 115.

The cross-lane break predicted at the 111 merge appeared exactly as recorded, and closed at integration:
`BP_V_ARTIFACT_MACHINE_COUNT: expected 1, actual 0` on the golden tool's generated case. The machine was
present all along. `type` is the internal kind marker on a candidate's own entities and is what `etype` falls
back to when the catalog has no entry, so reading only `kind` made the machine invisible to the count. A real
Factorio blueprint never carries `type = "machine"`; there it is the input/output half of an underground belt.
`tests.tools.test_golden_tools`: 13 of 13.

Two more checker defects surfaced the moment lane 115 removed the `or {}` fallback and reconciliation finally
ran against the real plan. It reported 13 failures; **all 13 were the checker's, not the artifact's**:

| failures | cause |
|---:|---|
| 6 | reconciliation paired the i-th expected machine with the i-th placed machine. That is an ordering, and contract 25.5 forbids it: an `electromagnetic-plant` making `copper-cable`, which is correct, was compared against the foundry step. It now binds by position, using the internal candidate the artifact was serialized from |
| 7 | the module check demanded inventory index 1 for every entity. That is a **beacon's** module inventory; an assembling machine's is 4. All seven machines failed. Offline the validator cannot know `defines.inventory`, so it now checks what it can establish: every module of one entity in one inventory, slots from 0 with no gap |

On the integrated tree, host legalcopilot-dev 2026-09-21:

```
player sheet:  ok=true   validation ok   0 errors   314 entities
contract:      68 of 68  both interpreters
test_validate: 36 of 36  both interpreters
golden tools:  13 of 13
```

`fluid-byproduct-chain`, red since before round 13, now passes.

Still open and now integration's, inherited from lane 113's failure: the reserved finalization sequence
(`FN1`-`FN4`) and the five-second ceiling.
