#!/usr/bin/env python3
"""Judge a census against the frozen baseline.  This is the gate every round 15 lane shares.

The problem it solves.  Each lane owns one file, so no single lane can drive the player's sheet to zero
errors on its own; a gate demanding full success would force the lanes to run one after another and destroy
the parallelism.  A gate demanding only "it ran" proves nothing, which is exactly how round 14 passed five
lanes and shipped a broken product.  So the contract is monotone: a lane must drive its own named codes DOWN
and must raise NOTHING.

Three checks together make that ungameable; each one alone is gameable.

  rate         A code's count divided by the candidates that reached `validate`.  Gate on raw counts and a
               lane wins by judging fewer candidates.
  denominator  `validate_attempts` may not fall below the baseline.  Gate on rate alone and a lane wins by
               judging exactly one near-clean candidate.
  stage floor  The run must still reach `search` or `done`.  Break preflight and every BP_V_ code goes to
               zero, which would read as a triumph.

And one more, outside this file: `tests/test_census_codes_live.lua` proves each counted code can still be
provoked, because deleting the check that emits a code also takes its census to zero.  That test is
spine-owned and PRESERVE-listed precisely because a lane that owns `tests/test_validate.lua` could otherwise
weaken the thing that guards it.

WAIVERS.  The codes are coupled, so a correct fix can legitimately make one RISE: routes that finally connect
mean belts that used to be discarded before validation now survive to the unused check.  Forbidding every
increase would forbid the correct fix.  A waiver is therefore a ceiling rather than a mute, it names the task
that repays it, and `--prove-waiver` runs the gate twice to show the waiver is load-bearing -- a waiver that
changes no outcome is a lie.  `--no-waivers` is what integration runs on the merged tree: a lane may borrow,
the round must repay.
"""

import argparse
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CENSUS = os.path.join(REPO, "tools", "real_sheet_census.py")
#Below this many records a "strict decrease" is noise rather than evidence: 5 -> 4 says nothing about a fix.
SENSITIVITY_FLOOR = 50


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def run_census(case, ops, interpreter, timeout):
    command = [sys.executable, CENSUS, "--case", case, "--ops", str(ops),
               "--interpreter", interpreter, "--timeout", str(timeout), "--quiet"]
    completed = subprocess.run(command, cwd=REPO, capture_output=True, text=True)
    if completed.returncode != 0:
        sys.stderr.write(completed.stderr)
        raise SystemExit(f"census_gate.py: the census did not complete (exit {completed.returncode})")
    return json.loads(completed.stdout)


def rate(report, code):
    return float(report.get("rates", {}).get(code, 0.0))


def judge(report, baseline, require_down, require_new, waivers, allow_total_rise):
    """Return a list of failure sentences.  Empty means the gate passes."""
    failures = []
    policy = baseline.get("policy", {})

    # 1. comparability -- a stale baseline must never pass silently
    for field in ("prepared_input_sha256", "ops_budget", "interpreter", "case"):
        if report.get(field) != baseline.get(field):
            failures.append(f"not comparable: {field} is {report.get(field)!r}, "
                            f"the baseline was measured at {baseline.get(field)!r}")
    if report.get("schema_version") != baseline.get("schema_version"):
        failures.append("not comparable: census schema_version differs from the baseline")
    if failures:
        return failures

    # 2. stage floor -- breaking preflight zeroes every BP_V_ code and would read as success
    stage = (report.get("envelope") or {}).get("stage")
    if stage not in ("search", "failed", "done"):
        failures.append(f"stage floor: the run stopped at stage {stage!r}; "
                        "a census is only comparable when the search still ran")

    # 3. denominator floor -- stops "judge fewer candidates"
    got = (report.get("counters") or {}).get("validate_attempts", 0)
    floor = (baseline.get("counters") or {}).get("validate_attempts", 0)
    delivering = ((report.get("counters") or {}).get("entities_delivered", 0) > 0
                  and (report.get("envelope") or {}).get("ok") is True and stage == "done")
    delivery_boundary = ((baseline.get("counters") or {}).get("entities_delivered", 0) == 0 and delivering)
    if got < floor and not delivering:
        failures.append(f"denominator floor: {got} candidates reached validate, the baseline reached {floor}; "
                        "fewer candidates judged is not an improvement")

    # 4. named codes must fall
    for code in require_down:
        base_count = baseline.get("census", {}).get(code, 0)
        if base_count < SENSITIVITY_FLOOR:
            failures.append(f"sensitivity: baseline count for {code} is {base_count}, under {SENSITIVITY_FLOOR}; "
                            "too small to gate on -- use the larger budget tier")
            continue
        if delivery_boundary:
            now_count = report.get("census", {}).get(code, 0)
            before_count = baseline.get("census", {}).get(code, 0)
            if now_count >= before_count:
                failures.append(f"{code} records {now_count} did not fall below the baseline "
                                f"{before_count} across delivery")
        elif not rate(report, code) < rate(baseline, code):
            failures.append(f"{code} rate {rate(report, code)} did not fall below the baseline "
                            f"{rate(baseline, code)}")

    # 5. nothing rises.  A code absent from the baseline has baseline 0, so a renamed or brand new code is
    #    caught by the same rule rather than needing one of its own.
    total_waived = 0.0
    for code in sorted(set(report.get("rates", {})) | set(baseline.get("rates", {}))):
        if delivery_boundary:
            now_count = report.get("census", {}).get(code, 0)
            before_count = baseline.get("census", {}).get(code, 0)
            if now_count > before_count:
                failures.append(f"{code} records {before_count} -> {now_count} (increase across delivery)")
            continue
        now, before = rate(report, code), rate(baseline, code)
        if now <= before:
            continue
        waiver = waivers.get(code)
        if waiver is None:
            failures.append(f"{code} rate {before} -> {now} (increase, no waiver)")
            continue
        ceiling = float(waiver.get("ceiling_rate", 0.0))
        if now > ceiling:
            failures.append(f"{code} rate {before} -> {now} exceeds its waived ceiling {ceiling}")
        total_waived += max(0.0, ceiling - before)

    # 5b. a round that waives everything fails on arithmetic, so nobody has to argue about it
    if waivers:
        baseline_total = sum(float(value) for value in baseline.get("rates", {}).values())
        budget = float(policy.get("waiver_budget_rate", 0.15)) * baseline_total
        if total_waived > budget:
            failures.append(f"waiver budget: {total_waived:.2f} of waived rate exceeds the round budget "
                            f"{budget:.2f}")

    # 6. a stricter validator finds MORE, so a gate lane is judged the other way round
    if require_new:
        for code in require_new:
            if report.get("census", {}).get(code, 0) <= 0:
                failures.append(f"{code} was never emitted; this lane must make the validator see something "
                                "it could not see before")
    if allow_total_rise:
        failures = [line for line in failures if "(increase, no waiver)" not in line]

    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--tier", default="fast", choices=("fast", "full"))
    parser.add_argument("--require-down", default="")
    parser.add_argument("--require-new", default="")
    parser.add_argument("--waiver", default=None)
    parser.add_argument("--no-waivers", action="store_true")
    parser.add_argument("--prove-waiver", action="store_true")
    parser.add_argument("--allow-total-rise", action="store_true")
    args = parser.parse_args()

    baselines = load(args.baseline)
    tiers = baselines.get("tiers") or {}
    if args.tier not in tiers:
        raise SystemExit(f"census_gate.py: the baseline has no {args.tier!r} tier")
    baseline = tiers[args.tier]
    baseline.setdefault("policy", baselines.get("policy", {}))

    require_down = [code for code in args.require_down.split(",") if code]
    require_new = [code for code in args.require_new.split(",") if code]

    waivers = {}
    if args.waiver and not args.no_waivers and os.path.exists(args.waiver):
        for entry in load(args.waiver).get("waivers", []):
            if entry.get("code"):
                waivers[entry["code"]] = entry

    report = run_census(baseline["case"], baseline["ops_budget"],
                        baseline["interpreter"], baseline.get("timeout", 1800))

    failures = judge(report, baseline, require_down, require_new, waivers, args.allow_total_rise)

    #A waiver that changes no outcome is a lie, so prove it is load-bearing rather than take its word.
    if args.prove_waiver and waivers:
        without = judge(report, baseline, require_down, require_new, {}, args.allow_total_rise)
        if not without:
            failures.append("waiver proof: the gate passes without any waiver, so this waiver is not "
                            "load-bearing and must be deleted")

    counters = report.get("counters", {})
    if failures:
        for line in failures:
            print(f"CENSUS-GATE fail: {line}", file=sys.stderr)
        print(f"CENSUS-GATE fail tier={args.tier} validate_attempts={counters.get('validate_attempts')} "
              f"total={sum(report.get('census', {}).values())}", file=sys.stderr)
        return 1

    baseline_total = sum(baseline.get("census", {}).values())
    report_total = sum(report.get("census", {}).values())
    print(f"CENSUS-GATE ok tier={args.tier} down={','.join(require_down) or 'none'} "
          f"validate_attempts={counters.get('validate_attempts')} "
          f"total={report_total} baseline_total={baseline_total} waivers={len(waivers)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
