# Engine evidence

Engine evidence is an observation made by the companion mod against the exact
packaged candidate under test. The candidate exposes `rrc-engine-test`; the
companion exposes the thin `rrc-golden-companion` proxy. Generation is polled
as a job (`start_generation`, `generation_status`, `cancel_generation`), so the
observation follows the same tick-driven path as a player rather than calling
an offline fixture builder.

An observation records:

- stable `case` identity and the `candidate_sha` returned by `build_id()`;
- the Factorio branch, mod version, surface, force research and other
  environment details needed to reproduce the case;
- one outcome: production with canonical digest, blueprint string, measured
  rates, warm-up, sampling window and timings; rejection with stage and reason
  codes; or export with the decoded envelope and digest;
- the scenario inputs: initial state, external supply, continuous drain,
  expected rates, allowed discrete error and timeout.

The host receipt command is deliberately the authority for the archive hash:

```sh
python3 tools/evidence_receipt.py observation.json RRC-Fork_1.1.36.zip \
  --case basic-canonical --candidate "$CANDIDATE_SHA" \
  --environment '{"factorio_branch":"2.0"}' \
  --output basic-canonical.receipt.json
```

It computes `zip_sha256` from the supplied archive, reads the packaged
`logic/build_id.lua`, and refuses a case, candidate, environment or declared
hash mismatch. It also refuses an archive without a packaged build id and any
observation marked `packaged = false`. Consequently a source checkout can run
offline tests, but it can never file in-game evidence or masquerade as a
release candidate.
