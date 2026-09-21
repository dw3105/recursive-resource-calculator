#!/usr/bin/env python3
"""Run one captured sheet through the generator and report what the validator refused, by code.

Why this exists.  Round 14 ran five parallel lanes, all five passed their gates, all five merged, and the
product still could not produce a working blueprint.  The cause was structural rather than technical: no lane
gate drove the player's real sheet, and none could, because only `player-am2-chain` gets past preflight and
every other corpus case rejects with BP_REJ_PROTOTYPE_FACTS_MISSING.  A gate that cannot see the real input
cannot fail for the real reason.

So this tool produces a census and nothing else.  It exits 0 whatever the census says: producing a number is
deliberately NOT a pass.  Judging the number is `tools/census_gate.py`, because producing evidence and ruling
on evidence are different jobs and collapsing them is how a gate quietly becomes a rubber stamp.

The census is already in the envelope; no instrumentation is invented here.  Every terminal failure attaches
`reason_details` (logic/bp/search.lua:1105, :1250, :1292, propagated through tests/golden/generate.lua), and
each record carries the `attempt` ordinal and refusing `stage` stamped by `record_rejection`
(logic/bp/search.lua:112).  That stamp is what makes a flat record list countable.

RATE, NEVER RAW COUNT.  A raw count rewards a change that judges fewer candidates: try three instead of
thirty and the total falls tenfold while the product gets no better.  The rate is a code's count divided by
the number of attempts that reached `validate`, so it measures how wrong a candidate is rather than how many
were looked at.  The denominator is reported alongside, because a rate with a collapsing denominator is the
other half of the same lie and `census_gate.py` floors it.

BOUNDED BY OPS, NEVER BY SECONDS.  `search_budget` sets `state.max_ops` (logic/bp/search.lua:135-137) and the
search then ends through `finish_search_budget` with a real BP_FAIL_SEARCH_BUDGET envelope that still carries
its records.  A wall-clock cutoff would make the census depend on what else the host is doing, and a census
that is not reproducible cannot be compared to a baseline at all.  The budget is injected into a private copy
of the input and is NEVER written into the committed case: `tests/golden/lib/runner.py` refuses a case whose
prepared input carries a generation option, and it is right to.
"""

import argparse
import collections
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA_VERSION = 1


def case_dir(case):
    return os.path.join(REPO, "tests", "golden", "cases", case)


def load_prepared(case):
    path = os.path.join(case_dir(case), "prepared_input.json")
    if not os.path.exists(path):
        raise SystemExit(f"real_sheet_census.py: no prepared input for case {case}: {path}")
    with open(path, "rb") as handle:
        raw = handle.read()
    return path, raw, json.loads(raw.decode("utf-8"))


def records_of(payload):
    """Every rejection record the envelope carries, from a failure or from a success.

    A failing run reports them under errors[].reason_details.  A succeeding run still discarded alternatives,
    and those carry their own codes, so a census does not go blind the moment the product starts working.
    """
    records = []
    for error in payload.get("errors") or []:
        for record in error.get("reason_details") or []:
            if isinstance(record, dict):
                records.append(record)
    result = payload.get("result")
    if isinstance(result, dict):
        for alternative in result.get("discarded_alternatives") or []:
            for code in (alternative or {}).get("reason_codes") or []:
                records.append({"code": code, "stage": "validate", "attempt": alternative.get("candidate_id")})
    return records


def census_of(records):
    counts = collections.Counter()
    attempts = collections.defaultdict(set)
    for record in records:
        stage = record.get("stage")
        if record.get("attempt") is not None:
            attempts[stage].add(record["attempt"])
        code = record.get("code")
        if code:
            counts[code] += 1
    return counts, {stage: len(values) for stage, values in attempts.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--case", default="player-red-science-1s")
    parser.add_argument("--ops", type=int, required=True,
                        help="search_budget injected at runtime; never written into the committed case")
    parser.add_argument("--interpreter", default="lua5.2")
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--json", dest="json_out", default=None)
    parser.add_argument("--quiet", "-q", action="store_true")
    args = parser.parse_args()

    path, raw, prepared = load_prepared(args.case)
    digest = hashlib.sha256(raw).hexdigest()

    #`certifiable: false` marks an input whose facts were repaired rather than captured whole.  This tool is a
    #development probe and is only ever pointed at such an input; refusing a certifiable one keeps a repaired
    #measurement from ever being mistaken for a certification.
    provenance = prepared.get("provenance") if isinstance(prepared.get("provenance"), dict) else {}
    certifiable = provenance.get("certifiable", True)
    if certifiable is not False:
        raise SystemExit("real_sheet_census.py: refuses a certifiable input; this is a development probe. "
                         f"{path} carries provenance.certifiable = {certifiable!r}")

    work = tempfile.mkdtemp(prefix="rrc-census-")
    try:
        budgeted = dict(prepared)
        budgeted["search_budget"] = args.ops
        input_path = os.path.join(work, "prepared_input.json")
        output_path = os.path.join(work, "result.json")
        with open(input_path, "w", encoding="utf-8") as handle:
            json.dump(budgeted, handle)

        command = [args.interpreter, "tests/golden/generate.lua",
                   "--input", input_path, "--output", output_path]
        started = time.time()
        try:
            completed = subprocess.run(command, cwd=REPO, capture_output=True, timeout=args.timeout)
        except subprocess.TimeoutExpired:
            print(f"real_sheet_census.py: {args.interpreter} did not finish within {args.timeout}s "
                  f"at search_budget={args.ops}", file=sys.stderr)
            return 3
        wall = time.time() - started

        if not os.path.exists(output_path):
            sys.stderr.write((completed.stderr or b"").decode("utf-8", "replace")[-2000:])
            print(f"real_sheet_census.py: the run produced no output (exit {completed.returncode})",
                  file=sys.stderr)
            return 3
        with open(output_path, encoding="utf-8") as handle:
            payload = json.load(handle)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    records = records_of(payload)
    counts, attempts = census_of(records)
    validate_attempts = attempts.get("validate", 0)
    rates = {code: round(count / validate_attempts, 4) for code, count in counts.items()} \
        if validate_attempts else {}

    terminal = None
    for error in payload.get("errors") or []:
        if error.get("code"):
            terminal = error["code"]
            break

    report = {
        "schema_version": SCHEMA_VERSION,
        "tool": "real_sheet_census",
        "case": args.case,
        "prepared_input_sha256": digest,
        "certifiable": certifiable,
        "ops_budget": args.ops,
        "interpreter": args.interpreter,
        "envelope": {"ok": payload.get("ok"), "stage": payload.get("stage"), "terminal_code": terminal},
        "counters": {
            "records": len(records),
            "attempts_by_stage": attempts,
            "validate_attempts": validate_attempts,
            "entities_delivered": len((payload.get("result") or {}).get("entities") or []),
        },
        "census": dict(sorted(counts.items())),
        "rates": dict(sorted(rates.items())),
        "timings": {"wall_seconds": round(wall, 2)},
    }

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=1, sort_keys=True)
            handle.write("\n")
    else:
        print(json.dumps(report, indent=1, sort_keys=True))

    if not args.quiet:
        e = report["envelope"]
        print(f"CENSUS case={args.case} ops={args.ops} ok={e['ok']} stage={e['stage']} "
              f"terminal={e['terminal_code']} wall={wall:.1f}s", file=sys.stderr)
        print(f"CENSUS validate_attempts {validate_attempts}", file=sys.stderr)
        for code, count in sorted(counts.items(), key=lambda item: -item[1]):
            print(f"CENSUS code {code} {count} rate {rates.get(code, 0)}", file=sys.stderr)
        print(f"CENSUS total {sum(counts.values())}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
