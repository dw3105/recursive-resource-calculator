#!/usr/bin/env python3
"""Small semantic comparison for debug-export completeness tests.

The expected values in this directory are authored fixtures.  They are never
written from an observed export.  The comparator deliberately compares fields
recursively instead of reducing an export to blueprint entities.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from collections.abc import Mapping
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIB = HERE.parent / "golden" / "lib"
if str(LIB) not in sys.path:
    sys.path.insert(0, str(LIB))

from common import CaseInputError, read_export, read_json  # noqa: E402


class ComparisonError(Exception):
    pass


def _path_text(path: tuple[object, ...]) -> str:
    return "$" + "".join("[" + repr(part) + "]" for part in path)


def _compare(actual: object, expected: object, path: tuple[object, ...]) -> None:
    if isinstance(expected, Mapping):
        if not isinstance(actual, Mapping):
            raise ComparisonError(f"{_path_text(path)} expected an object, got {type(actual).__name__}")
        for key, expected_value in expected.items():
            if key not in actual:
                raise ComparisonError(f"{_path_text(path + (key,))} is missing")
            _compare(actual[key], expected_value, path + (key,))
        return
    if isinstance(expected, list):
        if not isinstance(actual, list):
            raise ComparisonError(f"{_path_text(path)} expected a list, got {type(actual).__name__}")
        if len(actual) != len(expected):
            raise ComparisonError(f"{_path_text(path)} expected {len(expected)} entries, got {len(actual)}")
        for index, expected_value in enumerate(expected):
            _compare(actual[index], expected_value, path + (index,))
        return
    if actual != expected or type(actual) is not type(expected):
        raise ComparisonError(f"{_path_text(path)} expected {expected!r}, got {actual!r}")


def compare(export_path: Path, expected_path: Path) -> None:
    actual, _ = read_export(export_path)
    expected = read_json(expected_path, "expected export")
    if not isinstance(actual, Mapping) or not isinstance(expected, Mapping):
        raise ComparisonError("export and expectation must both be objects")
    _compare(actual, expected, ())


def _set_path(value: object, path: list[object], replacement: object) -> None:
    cursor = value
    for part in path[:-1]:
        cursor = cursor[part]  # type: ignore[index]
    cursor[path[-1]] = replacement  # type: ignore[index]


def self_test() -> int:
    fixture_path = HERE / "fixture.json"
    expected_path = HERE / "expected.json"
    controls_path = HERE / "negative_controls.json"
    for path in (fixture_path, expected_path, controls_path):
        if not path.is_file():
            raise ComparisonError(f"required comparator fixture is missing: {path.name}")

    actual = read_json(fixture_path, "comparator fixture")
    expected = read_json(expected_path, "comparator expectation")
    controls = read_json(controls_path, "negative controls")
    if not isinstance(controls, list) or not controls:
        raise ComparisonError("negative controls are empty")
    _compare(actual, expected, ())

    executed = 0
    for control in controls:
        if not isinstance(control, Mapping) or not isinstance(control.get("path"), list):
            raise ComparisonError("negative control has no path")
        mutated = copy.deepcopy(actual)
        path = control["path"]
        _set_path(mutated, path, control["replacement"])
        try:
            _compare(mutated, expected, ())
        except ComparisonError:
            executed += 1
        else:
            raise ComparisonError(f"negative control unexpectedly passed: {control.get('name', path)}")
    if executed == 0:
        raise ComparisonError("zero negative comparisons executed")
    print(f"export_golden comparisons={executed + 1} negative_controls={executed}")
    return executed + 1


def negative_test(index: int) -> int:
    fixture_path = HERE / "fixture.json"
    expected_path = HERE / "expected.json"
    controls_path = HERE / "negative_controls.json"
    actual = read_json(fixture_path, "comparator fixture")
    expected = read_json(expected_path, "comparator expectation")
    controls = read_json(controls_path, "negative controls")
    if not isinstance(controls, list) or index < 1 or index > len(controls):
        raise ComparisonError(f"negative control {index} does not exist")
    control = controls[index - 1]
    mutated = copy.deepcopy(actual)
    _set_path(mutated, control["path"], control["replacement"])
    try:
        _compare(mutated, expected, ())
    except ComparisonError:
        print(f"export_golden comparisons=1 negative={control.get('name', index)}")
        return 1
    raise ComparisonError(f"negative control unexpectedly passed: {control.get('name', index)}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--negative", type=int)
    parser.add_argument("export", nargs="?")
    parser.add_argument("expected", nargs="?")
    args = parser.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if args.negative is not None:
        negative_test(args.negative)
        return 0
    if not args.export or not args.expected:
        parser.error("provide EXPORT EXPECTED or --self-test")
    compare(Path(args.export), Path(args.expected))
    print("export_golden comparisons=1")
    return 0


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (CaseInputError, ComparisonError, KeyError, IndexError, TypeError) as exc:
        print(f"export_golden: {exc}", file=sys.stderr)
        raise SystemExit(1)
