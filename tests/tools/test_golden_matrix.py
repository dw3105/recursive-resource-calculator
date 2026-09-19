"""Machine-readable coverage checks for the required golden corpus."""

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MATRIX_PATH = ROOT / "tests" / "golden" / "required-matrix.json"
CASES_ROOT = ROOT / "tests" / "golden" / "cases"
COVERAGE_PATH = ROOT / "docs" / "golden-coverage.md"
RUN_PATH = ROOT / "tests" / "golden" / "run"

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


def assert_matrix_and_cases(matrix_path: Path, cases_root: Path) -> None:
    rows = matrix_rows(matrix_path)
    seen = set()
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
        for branch in row.get("branches", []):
            if not (cases_root / case_id).is_dir():
                raise AssertionError(f"matrix branch names missing case directory: {case_id}@{branch}")
        if row.get("state") == "draft":
            if not isinstance(manifest.get("capture_pending"), str) or not manifest["capture_pending"]:
                raise AssertionError(f"draft has no capture_pending note: {case_id}")
            if not isinstance(manifest.get("engine_scenario"), dict):
                raise AssertionError(f"draft has no engine scenario: {case_id}")
            scenario = manifest["engine_scenario"]
            if not scenario.get("supply") or not scenario.get("drain") or not scenario.get("expected_rates"):
                raise AssertionError(f"draft engine scenario is incomplete: {case_id}")
            if not isinstance(scenario.get("allowed_discrete_error"), (int, float)):
                raise AssertionError(f"draft has no allowed discrete error: {case_id}")
        if row.get("outcome_kind") == "rejection":
            if not manifest.get("reason_codes"):
                raise AssertionError(f"rejection has no reason_codes: {case_id}")
            if "expected" in manifest or "actual" in manifest:
                raise AssertionError(f"rejection declares blueprint fields: {case_id}")


def assert_coverage_document(matrix_path: Path, coverage_path: Path) -> None:
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
            if row[6] != "open gap: capture pending; not coverage":
                raise AssertionError(f"draft is not reported as an open gap: {row[2]}")
        elif row[6] == "open gap: capture pending; not coverage":
            raise AssertionError(f"accepted case is reported as a gap: {row[2]}")


class GoldenMatrixTests(unittest.TestCase):
    def test_every_matrix_row_has_a_matching_case_manifest(self):
        assert_matrix_and_cases(MATRIX_PATH, CASES_ROOT)

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
        expected = sum(row.get("state") == "draft" for row in matrix_rows())
        self.assertEqual(result.stdout.count("DRAFT "), expected, result.stdout)
        self.assertIn(f", {expected} drafts", result.stdout)
