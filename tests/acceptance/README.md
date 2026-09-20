# Acceptance gate: generation must really succeed

These cases are the delivery gate for blueprint generation. Each one drives the real generation service and
demands a successful, independently validated, non-empty blueprint. They are expected to be **red** until the
feature works, so `tests/run.sh` never discovers them: the fast tier guards regressions, this directory
guards delivery.

Run them explicitly:

```sh
sh tests/acceptance/run
```

Rules for a case here:

- terminal `state == "success"`; `pending` after the bound is a failure, never a pass.
- the published result carries entities and a blueprint string.
- the accepted candidate passed the independent validator (`Validate.ok == true`), and that exact candidate is
  the one serialized.
- no stage is stubbed, no constraint is weakened, no assertion says the feature may stay missing.

A case that cannot pass yet stays here and stays red. Deleting its assertion is never the fix.
