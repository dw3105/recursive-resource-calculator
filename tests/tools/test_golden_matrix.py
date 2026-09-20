"""Machine-readable coverage checks for the required golden corpus."""

from __future__ import annotations

import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MATRIX_PATH = ROOT / "tests" / "golden" / "required-matrix.json"
CASES_ROOT = ROOT / "tests" / "golden" / "cases"
COVERAGE_PATH = ROOT / "docs" / "golden-coverage.md"
RUN_PATH = ROOT / "tests" / "golden" / "run"
REASON_CODES_PATH = ROOT / "logic" / "bp" / "reason_codes.lua"

CAPTURE_DEPENDENT_FIELDS = {
    "targets": [],
    "setup.selection": [],
    "engine_scenario.supply": [],
    "engine_scenario.drain": [],
    "engine_scenario.expected_rates": {},
}

GOLD09_CATEGORIES = (
    "provided assembler-chain example",
    "base-only crafting and smelting",
    "shared-intermediate multi-target case",
    "mixed fluids with deterministic byproducts",
    "shared beacons and competing beacon loadouts",
    "2x2-to-larger grid growth with a larger-grid beacon improvement",
    "quality of machines and infrastructure",
    "a standard modded machine or interface",
    "belt and inserter bottleneck handling",
    "connected multi-pole coverage",
    "repeatability",
    "unsupported cycles",
    "unsupported quality-changing behaviour",
    "unsupported spoilage",
    "unsupported probabilistic behaviour",
    "unsupported custom behaviour",
    "known-feasible case at the 100-machine and 30-step boundary",
)


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def matrix_rows(path: Path = MATRIX_PATH):
    value = read_json(path)
    if not isinstance(value, dict) or not isinstance(value.get("cases"), list):
        raise AssertionError("required matrix must contain a cases array")
    return value["cases"]


def coverage_rows(path: Path = COVERAGE_PATH):
    if not path.is_file():
        raise AssertionError(f"missing coverage document: {path}")
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| ") or line.startswith("| ---"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) == 7 and cells[0] in {"GOLD-09", "matrix"}:
            rows.append(cells)
    return rows


def reason_code_groups(path: Path = REASON_CODES_PATH):
    source = path.read_text(encoding="utf-8")
    groups = {}
    for match in re.finditer(r"ReasonCodes\.([A-Z]+)\s*=\s*{(.*?)}", source, re.DOTALL):
        groups[match.group(1)] = set(re.findall(r'"([^"]+)"', match.group(2)))
    if not groups:
        raise AssertionError(f"no reason-code groups found in {path}")
    return groups


def _reason_code_group(code, groups):
    return next((group for group, codes in groups.items() if code in codes), "UNKNOWN")


def assert_terminal_reason_codes(manifest, case_id, groups):
    declared = manifest.get("reason_codes", manifest.get("expected_reason_codes", []))
    if declared is None:
        return
    if not isinstance(declared, list):
        raise AssertionError(f"reason_codes is not a list: {case_id}")
    allowed = {code for group in ("REJECT", "FAIL") for code in groups.get(group, set())}
    for code in declared:
        group = _reason_code_group(code, groups)
        if code not in allowed:
            raise AssertionError(
                f"declared reason code {code!r} for {case_id} belongs to {group}; "
                "only REJECT and FAIL codes are terminal"
            )


def _capture_dependent_values(manifest):
    setup = manifest.get("setup")
    scenario = manifest.get("engine_scenario")
    return {
        "targets": manifest.get("targets"),
        "setup.selection": setup.get("selection") if isinstance(setup, dict) else None,
        "engine_scenario.supply": scenario.get("supply") if isinstance(scenario, dict) else None,
        "engine_scenario.drain": scenario.get("drain") if isinstance(scenario, dict) else None,
        "engine_scenario.expected_rates": (
            scenario.get("expected_rates") if isinstance(scenario, dict) else None
        ),
    }


def assert_draft_content_is_honest(manifest, case_id, baseline):
    if manifest.get("targets") == baseline.get("targets"):
        raise AssertionError(f"draft {case_id} copies accepted baseline targets")
    setup = manifest.get("setup") if isinstance(manifest.get("setup"), dict) else {}
    baseline_setup = baseline.get("setup") if isinstance(baseline.get("setup"), dict) else {}
    if setup.get("selection") == baseline_setup.get("selection"):
        raise AssertionError(f"draft {case_id} copies accepted baseline setup.selection")
    values = _capture_dependent_values(manifest)
    for field, empty in CAPTURE_DEPENDENT_FIELDS.items():
        if values[field] != empty:
            raise AssertionError(
                f"draft {case_id} has non-empty capture-dependent field {field}; "
                "capture_pending must supply this category's captured sheet"
            )


#A captured case says how it was captured, because the two kinds carry different weight. A harness capture is
#synthetic and reproducible here; a capture taken from a player's running game is real evidence of what the
#engine and the player's own sheet actually did. Neither is coverage until an engine observation is bound.
CAPTURED_COVERAGE = (
    "open gap: harness capture only; engine observation pending; not coverage"
)
CAPTURED_COVERAGE_BY_SOURCE = {
    "harness": CAPTURED_COVERAGE,
    "engine": (
        "open gap: captured from the player's game; today it does not deliver a blueprint; engine "
        "observation pending; not coverage"
    ),
}

DRAFT_COVERAGE = "open gap: capture pending; content arrives with capture; not coverage"


def assert_captured_content_is_honest(manifest, case_id):
    """A captured case carries a real harness capture and still is not accepted coverage.

    draft means nothing has been captured; captured means the sheet was taken through the real preparation
    path and the engine observation is still missing. The two states have opposite content rules, so a case
    can never silently sit in the one whose rules it does not meet.
    """
    if not isinstance(manifest.get("engine_capture_pending"), str) or not manifest["engine_capture_pending"]:
        raise AssertionError(f"captured case has no engine_capture_pending note: {case_id}")
    if manifest.get("source_kind") not in ("harness", "engine"):
        raise AssertionError(f"captured case has no source_kind: {case_id}")
    if not isinstance(manifest.get("observed_outcome"), dict):
        raise AssertionError(f"captured case has no observed_outcome: {case_id}")
    if manifest.get("actual") is not None:
        raise AssertionError(f"captured case claims an accepted actual: {case_id}")
    values = _capture_dependent_values(manifest)
    #expected_rates is measured in the engine, never by the harness capture, so it stays empty here.
    for field, empty in CAPTURE_DEPENDENT_FIELDS.items():
        if field == "engine_scenario.expected_rates":
            continue
        if values[field] == empty or values[field] is None:
            raise AssertionError(
                f"captured case {case_id} has empty capture-dependent field {field}; "
                "a captured case must carry what its capture produced"
            )
    if values["engine_scenario.expected_rates"] not in ({}, None):
        raise AssertionError(
            f"captured case {case_id} states expected rates before an engine observation exists"
        )


def assert_matrix_and_cases(matrix_path: Path, cases_root: Path) -> None:
    rows = matrix_rows(matrix_path)
    groups = reason_code_groups()
    seen = set()
    baseline = None
    for row in rows:
        case_id = row.get("case_id")
        if not isinstance(case_id, str) or not case_id:
            raise AssertionError(f"matrix row has no case_id: {row!r}")
        if case_id in seen:
            raise AssertionError(f"duplicate matrix case_id: {case_id}")
        seen.add(case_id)
        case_dir = cases_root / case_id
        if not case_dir.is_dir():
            raise AssertionError(f"matrix row names missing case directory: {case_id}")
        manifest_path = case_dir / "manifest.json"
        if not manifest_path.is_file():
            raise AssertionError(f"case has no manifest.json: {case_id}")
        manifest = read_json(manifest_path)
        if manifest.get("case_id") != case_id:
            raise AssertionError(f"manifest case_id disagrees with matrix: {case_id}")
        if manifest.get("expected_outcome") != row.get("outcome_kind"):
            raise AssertionError(f"outcome mismatch: {case_id}")
        if manifest.get("state", "accepted") != row.get("state"):
            raise AssertionError(f"state mismatch: {case_id}")
        if manifest.get("factorio_branch") not in row.get("branches", []):
            raise AssertionError(f"branch mismatch: {case_id}")
        assert_terminal_reason_codes(manifest, case_id, groups)
        for branch in row.get("branches", []):
            if not (cases_root / case_id).is_dir():
                raise AssertionError(f"matrix branch names missing case directory: {case_id}@{branch}")
        if row.get("state") == "captured":
            assert_captured_content_is_honest(manifest, case_id)
            scenario = manifest.get("engine_scenario")
            if not isinstance(scenario, dict) or not isinstance(
                scenario.get("allowed_discrete_error"), (int, float)
            ):
                raise AssertionError(f"captured case has no allowed discrete error: {case_id}")
        if row.get("state") == "draft":
            if baseline is None:
                baseline_path = cases_root / "basic-canonical" / "manifest.json"
                if not baseline_path.is_file():
                    raise AssertionError(f"missing accepted baseline manifest: {baseline_path}")
                baseline = read_json(baseline_path)
            if not isinstance(manifest.get("capture_pending"), str) or not manifest["capture_pending"]:
                raise AssertionError(f"draft has no capture_pending note: {case_id}")
            if not isinstance(manifest.get("engine_scenario"), dict):
                raise AssertionError(f"draft has no engine scenario: {case_id}")
            assert_draft_content_is_honest(manifest, case_id, baseline)
            scenario = manifest["engine_scenario"]
            if not isinstance(scenario.get("allowed_discrete_error"), (int, float)):
                raise AssertionError(f"draft has no allowed discrete error: {case_id}")
        if row.get("outcome_kind") == "rejection":
            if not manifest.get("reason_codes"):
                raise AssertionError(f"rejection has no reason_codes: {case_id}")
            if manifest.get("stage") not in {"preflight", "search", "validate"}:
                raise AssertionError(f"rejection has no release-gate stage: {case_id}")
            if "expected" in manifest or "actual" in manifest:
                raise AssertionError(f"rejection declares blueprint fields: {case_id}")


def assert_coverage_document(matrix_path: Path, coverage_path: Path, cases_root: Path = CASES_ROOT) -> None:
    rows = matrix_rows(matrix_path)
    ids = {row["case_id"] for row in rows}
    doc_rows = coverage_rows(coverage_path)
    gold_rows = {row[1]: row for row in doc_rows if row[0] == "GOLD-09"}
    if set(gold_rows) != set(GOLD09_CATEGORIES):
        raise AssertionError(f"GOLD-09 categories differ: {sorted(set(GOLD09_CATEGORIES) ^ set(gold_rows))}")
    mentioned = {row[2] for row in doc_rows}
    if mentioned != ids:
        raise AssertionError(f"coverage/matrix ids differ: {sorted(mentioned ^ ids)}")
    for row in doc_rows:
        if row[2] not in ids:
            raise AssertionError(f"coverage names unknown matrix case: {row[2]}")
        matrix_row = next(item for item in rows if item["case_id"] == row[2])
        if row[3] != ", ".join(matrix_row["branches"]):
            raise AssertionError(f"coverage branches disagree with matrix: {row[2]}")
        if row[4] != matrix_row["outcome_kind"] or row[5] != matrix_row["state"]:
            raise AssertionError(f"coverage disagrees with matrix: {row[2]}")
        if matrix_row["state"] == "draft":
            if row[6] != DRAFT_COVERAGE:
                raise AssertionError(f"draft is not reported as an open gap: {row[2]}")
        elif matrix_row["state"] == "captured":
            manifest_path = cases_root / row[2] / "manifest.json"
            source_kind = "harness"
            if manifest_path.is_file():
                source_kind = read_json(manifest_path).get("source_kind", "harness")
            expected = CAPTURED_COVERAGE_BY_SOURCE.get(source_kind, CAPTURED_COVERAGE)
            if row[6] != expected:
                raise AssertionError(f"captured case is not reported as an open gap: {row[2]}")
        elif row[6] in (DRAFT_COVERAGE, CAPTURED_COVERAGE):
            raise AssertionError(f"accepted case is reported as a gap: {row[2]}")


class GoldenMatrixTests(unittest.TestCase):
    def test_every_matrix_row_has_a_matching_case_manifest(self):
        assert_matrix_and_cases(MATRIX_PATH, CASES_ROOT)

    def test_internal_reason_code_is_not_a_terminal_declaration(self):
        with self.assertRaisesRegex(AssertionError, r"BP_R_CAPACITY.*INTERNAL"):
            assert_terminal_reason_codes(
                {"reason_codes": ["BP_R_CAPACITY"]},
                "belt-inserter-bottleneck",
                reason_code_groups(),
            )

    def test_draft_cannot_copy_accepted_baseline_content(self):
        baseline = read_json(CASES_ROOT / "basic-canonical" / "manifest.json")
        with self.assertRaisesRegex(AssertionError, "copies accepted baseline targets"):
            assert_draft_content_is_honest(dict(baseline), "copied-baseline", baseline)

    def test_draft_capture_dependent_fields_must_be_empty(self):
        baseline = read_json(CASES_ROOT / "basic-canonical" / "manifest.json")
        manifest = {
            "targets": [],
            "setup": {"selection": []},
            "engine_scenario": {
                "supply": [{"full_name": "item/iron-plate", "rate_per_second": 2}],
                "drain": [],
                "expected_rates": {},
            },
        }
        with self.assertRaisesRegex(AssertionError, "engine_scenario.supply"):
            assert_draft_content_is_honest(manifest, "copied-supply", baseline)

    def test_every_gold09_category_and_matrix_row_is_in_coverage_doc(self):
        assert_coverage_document(MATRIX_PATH, COVERAGE_PATH)

    def test_missing_case_directory_is_a_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            matrix = root / "required-matrix.json"
            matrix.write_text(json.dumps({"cases": [{"case_id": "missing", "branches": ["2.0"],
                                                       "outcome_kind": "production", "state": "draft"}]}),
                              encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "missing case directory"):
                assert_matrix_and_cases(matrix, root / "cases")

    def test_coverage_rows_are_markdown_table_rows(self):
        for row in coverage_rows(COVERAGE_PATH):
            self.assertEqual(len(row), 7)
            self.assertRegex(row[2], r"^[a-z0-9-]+$")

    def test_drafts_report_names_every_draft_and_fails(self):
        result = subprocess.run(
            ["sh", str(RUN_PATH), "--branch", "2.0", "--drafts", "report"],
            cwd=ROOT, text=True, capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("PASS basic-canonical", result.stdout)
        drafts = sum(row.get("state") == "draft" for row in matrix_rows())
        captured = sum(row.get("state") == "captured" for row in matrix_rows())
        self.assertEqual(result.stdout.count("DRAFT "), drafts, result.stdout)
        self.assertEqual(result.stdout.count("CAPTURED "), captured, result.stdout)
        self.assertIn(f", {drafts} drafts", result.stdout)
        self.assertIn(f", {captured} captured", result.stdout)
