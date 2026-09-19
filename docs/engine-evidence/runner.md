# Running the engine companion

The companion is a factory runner, not a blueprint proxy. It calls the packaged
candidate's `rrc-engine-test.start_generation`, polls the returned job on
`on_tick`, builds that returned blueprint string, and measures the resulting
factory. It never inserts into a machine or removes from one. Inputs are put
into perimeter source buffers and outputs/byproducts are removed from perimeter
sink buffers; the observation records the counts the buffers actually accepted
and released.

## The one game command

Install the packaged `RRC-Golden-Companion` and the matching packaged candidate,
load a save with the required technologies, and paste this as one Factorio
console command. Replace the angle-bracket values and paste the reviewed case
table in the marked fields; `prepared_input` must be the captured input from
the candidate's debug export, not a handwritten plan.

```text
/c remote.call("rrc-golden-companion", "run", {case_id="<case-id>", expected_candidate_sha="<candidate-sha>", sheet_id="<sheet-id>", prepared_input=<captured-prepared-input>, setup=<reviewed-setup>, engine_scenario=<reviewed-engine-scenario>})
```

The command immediately returns a status such as `accepted=true, state=environment`
and prints:

```text
[RRC engine evidence] queued <case-id>
[RRC engine evidence] <case-id> production
```

The last line is also printed for `rejection` and `export`. A development build
or a candidate SHA mismatch is rejected during the command before environment,
sheet, generation, blueprint construction, supply, power, drain, warm-up or
sampling work. The companion writes that rejection observation immediately.

## Observation and timing

The game writes
`script-output/rrc-engine-evidence/<case-id>.observation.json`.
The file is schema version 1 and has exactly one of `production`, `rejection`,
or `export` as its outcome block. Production includes the returned blueprint
string, canonical digest/version, measured rates, accepted supply, drained
outputs, warm-up, sample window and engine-tick timings.

All timing is in engine ticks; 60 ticks is one reported second. `generation_ticks`
is the tick delta from the `start_generation` call to its terminal status.
`build_ticks` is the delta from terminal generation status to blueprint creation.
The warm-up interval is half-open: after perimeter setup, exactly the declared
number of ticks is serviced and discarded. The sampling interval is also
half-open in the controller's boundary model and reports exactly the declared
number of sampled ticks. A rate is `drained_count * 60 / sampling_window_ticks`.
Timeout is bounded to at most one hour of engine ticks; timeout and explicit
cancellation call `cancel_generation` and clean up created entities and buffers.

## Send back

Send the observation JSON, the exact candidate archive used for the run, the
case id, branch, and the printed terminal line. The host receipt remains the
authority for the archive hash:

```sh
python3 tools/evidence_receipt.py <case-id>.observation.json <candidate.zip> \
  --case <case-id> --candidate <candidate-sha> \
  --environment '{"factorio_branch":"2.0"}' \
  --output <case-id>.receipt.json
```

For Factorio 2.1, use `{"factorio_branch":"2.1"}`. The branch-specific
prototype names and package `factorio_version` values are kept together in
`tests/golden/engine/mod/branch-manifest.json` and `scenario.lua`; packaging
selects the matching `info.json` value without changing the runner state
machine.
