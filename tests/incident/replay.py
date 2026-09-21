"""Replay the player's captured sheet and record what the generator actually does with it.

This is not a target and not a wish. `tests/golden/cases/player-am2-chain/manifest.json` records the outcome the
player saw in game on 2026-09-20, Factorio 2.0.77 + Space Age. This script replays the exact same PreparedInput
offline and asserts the generator still produces that outcome.

So it fails in two directions, and both are useful:

  * the generator gets worse  -> the replay stops matching the recorded outcome;
  * the generator gets better -> the replay stops matching the recorded outcome.

The second is the point. When a lane improves generation, this goes red, and the recorded outcome is updated
with the new evidence beside it. The assertion never moves ahead of what was measured.

The capture is the player's own configuration, unchanged: no search budget is baked in, and no beacon count is
reduced. Both are checked here, because a replay that quietly weakens the input proves nothing.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CASE = ROOT / "tests" / "golden" / "cases" / "player-am2-chain"
GENERATOR = ROOT / "tests" / "golden" / "generate.lua"
INTERPRETERS = ("lua5.2", "lua5.4")

# A production case runs at default configuration. These keys would cap or widen the search and make the
# replay a statement about the cap rather than about the generator.
FORBIDDEN_OPTIONS = ("search_budget", "max_ops", "max_search_grids", "max_grid_trials")

failures: list[str] = []
checks = 0


def check(condition: bool, label: str) -> None:
    global checks
    checks += 1
    if condition:
        print(f"PASS {label}")
    else:
        print(f"FAIL {label}")
        failures.append(label)


def equal(actual, expected, label: str) -> None:
    check(actual == expected, f"{label}: expected {expected!r}, got {actual!r}")


def load(path: Path):
    return json.loads(path.read_text())


def run_generator(interpreter: str) -> dict:
    proc = subprocess.run(
        [interpreter, str(GENERATOR), "--input", str(CASE / "prepared_input.json")],
        cwd=str(ROOT), capture_output=True, text=True, check=False, timeout=1800,
    )
    if proc.returncode != 0:
        raise SystemExit(f"FAIL the generator aborted under {interpreter} "
                         f"(exit {proc.returncode}): {proc.stderr[-2000:]}")
    return json.loads(proc.stdout)


def main() -> int:
    if not CASE.is_dir():
        raise SystemExit(f"FAIL the incident case is missing: {CASE}")
    manifest = load(CASE / "manifest.json")
    prepared = load(CASE / "prepared_input.json")
    # observed_outcome is history: what the player's game did, kept immutable. current_outcome is what this
    # source revision does now. Compare against the current one when it exists, so improving the generator
    # never means rewriting what the player saw.
    recorded = manifest.get("current_outcome") or manifest["observed_outcome"]
    # --require-success is the completion gate. It rejects a failure WHATEVER either field records, so a run
    # can never pass by faithfully reproducing a failure.
    require_success = "--require-success" in sys.argv

    # The input is the player's, unchanged.
    options = prepared.get("options") or {}
    for key in FORBIDDEN_OPTIONS:
        check(key not in options, f"the captured input bakes in no {key}")
    check(manifest["provenance"]["default_configuration"] is True,
          "the case declares itself default configuration")

    # Configured beacon counts survive the replay. Reducing one was a diagnostic counterfactual, never a fixture.
    counts: list[int] = []

    def walk(node) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "beacons" and isinstance(value, list):
                    for group in value:
                        if isinstance(group, dict) and isinstance(group.get("count"), (int, float)):
                            counts.append(int(group["count"]))
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(prepared.get("snapshot"))
    check(max(counts) >= 3 if counts else False,
          f"the captured sheet still asks for its configured beacon counts (max {max(counts) if counts else 0})")

    for interpreter in INTERPRETERS:
        result = run_generator(interpreter)
        label = f"[{interpreter}]"
        codes = [error.get("code") for error in result.get("errors") or []]
        progress = result.get("progress") or {}

        if require_success:
            equal(result.get("ok"), True, f"{label} the replay delivers a blueprint")
            entities = ((result.get("result") or {}).get("entities")
                        or result.get("entities") or [])
            check(len(entities) > 0, f"{label} the delivered blueprint carries entities")
            validation = result.get("validation") or {}
            check(validation.get("ok") is True,
                  f"{label} the delivered blueprint passes independent validation")
        elif recorded["state"] == "failure":
            equal(result.get("ok"), False, f"{label} the replay reproduces a failure")
            equal(codes, recorded["reason_codes"], f"{label} the reason codes match the recorded outcome")
            equal(progress.get("done_units"), recorded["progress"]["done_units"],
                  f"{label} the work done matches the recorded outcome")
            equal(progress.get("total_units"), recorded["progress"]["total_units"],
                  f"{label} the work planned matches the recorded outcome")
            equal(progress.get("phase"), recorded["progress"]["phase"],
                  f"{label} the terminal phase matches the recorded outcome")
        else:
            equal(result.get("ok"), True, f"{label} the replay reproduces a delivered blueprint")
            # The generator's success envelope carries its entities under `result`, never at the top level.
            # Reading the top level alone made this check pass on an empty blueprint.
            entities = ((result.get("result") or {}).get("entities")
                        or result.get("entities") or [])
            check(len(entities) > 0, f"{label} the delivered blueprint carries entities")
            validation = result.get("validation") or {}
            check(validation.get("ok") is True,
                  f"{label} the delivered blueprint passes independent validation")
            if recorded.get("entity_count") is not None:
                equal(len(entities), recorded["entity_count"],
                      f"{label} the entity count matches the recorded outcome")
            if recorded.get("canonical_sha256") is not None:
                equal(result.get("canonical_sha256"), recorded["canonical_sha256"],
                      f"{label} the canonical digest matches the recorded outcome")

    print(f"incident replay: {checks} checks, {checks - len(failures)} passed, {len(failures)} failed")
    if failures:
        print("")
        print("The recorded outcome is what the player saw and what this input used to replay to. If the")
        print("generator has changed, update tests/golden/cases/player-am2-chain/manifest.json with the new")
        print("evidence beside it. Never edit the captured input to make this pass.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
