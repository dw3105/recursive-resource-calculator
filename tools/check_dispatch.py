#!/usr/bin/env python3
"""Refuse an unsafe lane dispatch before an agent is started.

This is deliberately a read-only gate.  It validates the ownership manifest,
the task's checks block, and the requested base/worktree.  It also reads the
lane runner's durable records (and optional disposable lane descriptors) to
avoid dispatching work that overlaps a live lane.

Examples::

    python3 tools/check_dispatch.py --repo . --base queue-base \
        --task docs/tasks/054_dispatch_preflight.md \
        --manifest docs/tasks/054.manifest

The manifest-only form is useful for catching malformed task files before a
repository or task has been selected::

    python3 tools/check_dispatch.py --manifest /tmp/candidate.manifest

``--running-lane`` takes a JSON descriptor with ``worktree``, ``manifest``
and optional ``task`` fields.  It exists for isolated callers and tests; the
normal runner records are discovered automatically.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

try:
    from .lane_ownership import ownership_overlaps
except ImportError:  # Executed as ``python3 tools/check_dispatch.py``.
    from lane_ownership import ownership_overlaps


WINDOWS_ABSOLUTE = re.compile(r"^[A-Za-z]:[\\/]")
CHECKS_BLOCK = re.compile(r"(?ms)^```checks[ \t]*\r?\n(.*?)^```[ \t]*\r?$")
TEST_MODULE = re.compile(r"^tests(?:\.[A-Za-z0-9_]+)+$")
TEST_SUFFIXES = (".py", ".lua")


@dataclass(frozen=True)
class ManifestEntry:
    path: str
    required: bool
    line: int


@dataclass(frozen=True)
class ManifestResult:
    entries: tuple[ManifestEntry, ...]
    problems: tuple[str, ...]

    @property
    def owned(self) -> tuple[str, ...]:
        return tuple(entry.path for entry in self.entries)

    @property
    def required(self) -> tuple[str, ...]:
        return tuple(entry.path for entry in self.entries if entry.required)


@dataclass(frozen=True)
class RunningLane:
    label: str
    worktree: Path | None
    manifest: Path | None
    task: Path | None
    source: str


def _input_path(raw: str | Path, repo: Path) -> Path:
    path = Path(raw).expanduser()
    if not path.is_absolute():
        path = repo / path
    return path.resolve(strict=False)


def _inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def _entry_path_error(entry: str, repo: Path) -> str | None:
    if not entry:
        return "malformed empty manifest entry"
    if "\x00" in entry:
        return "manifest entry contains NUL byte"
    if "\\" in entry:
        return f"manifest path carries a backslash: {entry}"
    if entry.startswith("/") or WINDOWS_ABSOLUTE.match(entry):
        return f"manifest path is absolute: {entry}"
    if any(character.isspace() for character in entry):
        return f"malformed manifest entry (whitespace in path): {entry}"
    if entry.endswith("//") or "//" in entry:
        return f"malformed manifest entry (empty path component): {entry}"

    directory = entry.endswith("/")
    bare = entry[:-1] if directory else entry
    if not bare or bare in {".", ".."}:
        return f"malformed manifest entry: {entry}"
    if any(component == "" for component in bare.split("/")):
        return f"malformed manifest entry (empty path component): {entry}"

    resolved = (repo / bare).resolve(strict=False)
    if not _inside(resolved, repo):
        return f"manifest path escapes repository: {entry}"
    return None


def parse_manifest(path: Path, repo: Path) -> ManifestResult:
    """Read and validate a manifest without touching its repository."""
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        return ManifestResult((), (f"missing manifest: {path}",))
    except OSError as exc:
        return ManifestResult((), (f"cannot read manifest {path}: {exc}",))

    problems: list[str] = []
    if b"\\n" in raw:
        problems.append(f"manifest contains literal \\n bytes: {path}")
    if b"\x00" in raw:
        problems.append(f"manifest contains NUL byte: {path}")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        problems.append(f"manifest is not UTF-8 at byte {exc.start}: {path}")
        return ManifestResult((), tuple(problems))

    entries: list[ManifestEntry] = []
    seen: dict[str, int] = {}
    for line_number, raw_line in enumerate(text.splitlines(), 1):
        if not raw_line.strip():
            problems.append(f"empty manifest entry at line {line_number}: {path}")
            continue
        without_comment = raw_line.split("#", 1)[0].strip()
        if not without_comment:
            # Comments are part of the existing manifest format.
            if raw_line.lstrip().startswith("#"):
                continue
            problems.append(f"empty manifest entry at line {line_number}: {path}")
            continue

        required = without_comment.startswith("!")
        entry = without_comment[1:].strip() if required else without_comment
        if required and entry.startswith("!"):
            problems.append(f"malformed manifest entry at line {line_number}: {without_comment}")
            continue
        error = _entry_path_error(entry, repo)
        if error:
            problems.append(f"{error} (line {line_number})")
            continue

        canonical = entry
        if canonical in seen:
            problems.append(
                f"duplicate manifest entry at line {line_number}: {entry} "
                f"(first at line {seen[canonical]})"
            )
            continue
        seen[canonical] = line_number
        entries.append(ManifestEntry(canonical, required, line_number))

    if not entries:
        problems.append(f"manifest has no entries: {path}")
    return ManifestResult(tuple(entries), tuple(problems))


def _required_entry_covers(path: str, required: Iterable[str]) -> bool:
    for entry in required:
        if entry.endswith("/"):
            if path.startswith(entry):
                return True
        elif path == entry:
            return True
    return False


def _check_manifest_files(result: ManifestResult, repo: Path) -> list[str]:
    problems: list[str] = []
    for entry in result.entries:
        if entry.required:
            continue
        bare = entry.path.rstrip("/")
        candidate = (repo / bare).resolve(strict=False)
        if not candidate.exists():
            problems.append(f"manifest entry must already exist: {entry.path}")
        elif candidate.is_dir() and not entry.path.endswith("/"):
            problems.append(f"manifest directory entry must end with '/': {entry.path}")
    return problems


def _task_checks(task: Path, repo: Path, required: Iterable[str]) -> list[str]:
    try:
        text = task.read_text(encoding="utf-8")
    except FileNotFoundError:
        return [f"missing task file: {task}"]
    except (OSError, UnicodeError) as exc:
        return [f"cannot read task file {task}: {exc}"]

    blocks = list(CHECKS_BLOCK.finditer(text))
    if len(blocks) != 1:
        return [f"task must contain exactly one ```checks``` block: {task}"]

    problems: list[str] = []
    body = blocks[0].group(1)
    lines = body.splitlines()
    if not lines:
        return [f"checks block is empty: {task}"]
    for offset, line in enumerate(lines, 1):
        if not line.strip():
            problems.append(f"checks line {offset} is empty; expected one JSON object")
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            problems.append(f"checks line {offset} is not one JSON object: {exc.msg}")
            continue
        if not isinstance(value, dict):
            problems.append(f"checks line {offset} is not one JSON object")
            continue
        command = value.get("command")
        if command is None:
            continue
        if not isinstance(command, str):
            problems.append(f"checks line {offset} has a non-string command")
            continue
        problems.extend(_missing_test_files(command, repo, required))
    return problems


def _candidate_test_paths(command: str) -> Iterable[str]:
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError:
        return ()
    found: list[str] = []
    for token in tokens:
        token = token.rstrip(";,)")
        if "*" in token or "?" in token or "$" in token:
            continue
        while token.startswith("./"):
            token = token[2:]
        if TEST_MODULE.fullmatch(token):
            found.append(token.replace(".", "/") + ".py")
            continue
        if token.startswith("tests/") and token.endswith(TEST_SUFFIXES):
            found.append(token)
    return found


def _missing_test_files(command: str, repo: Path, required: Iterable[str]) -> list[str]:
    problems: list[str] = []
    for raw in _candidate_test_paths(command):
        candidate = Path(raw)
        resolved = candidate.resolve(strict=False) if candidate.is_absolute() else (repo / candidate).resolve(strict=False)
        if not _inside(resolved, repo):
            continue
        relative = resolved.relative_to(repo).as_posix()
        if _required_entry_covers(relative, required):
            continue
        if not resolved.is_file():
            problems.append(f"check names missing test file: {relative}")
    return problems


def _git(repo: Path, *args: str) -> tuple[int, str, str]:
    try:
        result = subprocess.run(
            ["git", *args], cwd=repo, capture_output=True, text=True, check=False
        )
    except OSError as exc:
        return 127, "", str(exc)
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def _base_problems(repo: Path, base: str | None) -> list[str]:
    if base is None:
        return []
    code, resolved, error = _git(repo, "rev-parse", "--verify", "--quiet", f"{base}^{{commit}}")
    if code != 0 or not resolved:
        detail = error or "does not resolve"
        return [f"base does not resolve: {base} ({detail})"]
    head_code, head, head_error = _git(repo, "rev-parse", "--verify", "HEAD")
    if head_code != 0 or not head:
        return [f"worktree HEAD does not resolve: {repo} ({head_error or 'unknown git error'})"]
    if head != resolved:
        return [f"worktree stands at {head}, not base {resolved} ({base})"]
    return []


def _process_starttime(pid: int) -> int | None:
    try:
        text = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return None
    closing = text.rfind(")")
    if closing < 0:
        return None
    fields = text[closing + 2 :].split()
    try:
        return int(fields[19])
    except (IndexError, ValueError):
        return None


def _live_identity(value: Any) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return _process_starttime(value) is not None
    if not isinstance(value, dict):
        return False
    pid = value.get("pid")
    expected = value.get("starttime")
    if isinstance(pid, bool) or not isinstance(pid, int):
        return False
    actual = _process_starttime(pid)
    return actual is not None and (expected is None or actual == expected)


def _common_root(repo: Path) -> Path:
    code, output, _ = _git(repo, "rev-parse", "--git-common-dir")
    if code != 0 or not output:
        return repo
    common = Path(output)
    if not common.is_absolute():
        common = repo / common
    common = common.resolve(strict=False)
    return common.parent if common.name == ".git" else common


def _state_root(repo: Path, override: str | None) -> Path:
    if override:
        return Path(override).expanduser().resolve(strict=False)
    configured = os.environ.get("LANE_STATE_ROOT")
    base = Path(configured).expanduser() if configured else Path.home() / ".local" / "state" / "agent-lane"
    if not base.is_absolute():
        return Path.cwd() / base
    root = _common_root(repo)
    digest = hashlib.sha256(str(root).encode("utf-8")).hexdigest()[:12]
    return (base / f"{root.name}-{digest}").resolve(strict=False)


def _record_manifest(task: Path | None) -> Path | None:
    if task is None:
        return None
    sibling = task.with_suffix(".manifest")
    if sibling.is_file():
        return sibling
    number = re.match(r"^(\d+)(?:[_-].*)?\.md$", task.name)
    if number:
        numbered = task.parent / f"{number.group(1)}.manifest"
        if numbered.is_file():
            return numbered
    return sibling


def _running_from_record(path: Path) -> RunningLane | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None
    if not isinstance(value, dict) or value.get("state") != "running":
        return None
    if not any(_live_identity(value.get(key)) for key in ("worker", "supervisor", "pid")):
        return None
    task_raw = value.get("task")
    worktree_raw = value.get("worktree")
    task = Path(task_raw).expanduser().resolve(strict=False) if isinstance(task_raw, str) else None
    worktree = Path(worktree_raw).expanduser().resolve(strict=False) if isinstance(worktree_raw, str) else None
    return RunningLane(
        str(value.get("label") or path.parent.parent.parent.name),
        worktree,
        _record_manifest(task),
        task,
        str(path),
    )


def _read_descriptor(path: Path) -> tuple[RunningLane | None, str | None]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return None, f"cannot read running lane descriptor {path}: {exc}"
    if not isinstance(value, dict) or value.get("running", True) is not True:
        return None, f"malformed running lane descriptor: {path}"
    worktree_raw = value.get("worktree")
    manifest_raw = value.get("manifest")
    if not isinstance(worktree_raw, str) or not isinstance(manifest_raw, str):
        return None, f"running lane descriptor needs worktree and manifest: {path}"
    task_raw = value.get("task")
    return (
        RunningLane(
            str(value.get("label") or path.stem),
            Path(worktree_raw).expanduser().resolve(strict=False),
            Path(manifest_raw).expanduser().resolve(strict=False),
            Path(task_raw).expanduser().resolve(strict=False) if isinstance(task_raw, str) else None,
            str(path),
        ),
        None,
    )


def _discover_running(repo: Path, state_override: str | None, descriptors: Iterable[str]) -> tuple[list[RunningLane], list[str]]:
    lanes: list[RunningLane] = []
    problems: list[str] = []
    seen: set[tuple[str, str, str]] = set()

    def add(lane: RunningLane) -> None:
        key = (lane.label, str(lane.worktree), str(lane.manifest))
        if key not in seen:
            seen.add(key)
            lanes.append(lane)

    for raw in descriptors:
        lane, error = _read_descriptor(_input_path(raw, repo))
        if error:
            problems.append(error)
        elif lane is not None:
            add(lane)

    common = _common_root(repo)
    audit_root = common / "docs" / "audit" / "runs"
    if audit_root.is_dir():
        for record in sorted(audit_root.glob("*/attempts/*/record.json")):
            lane = _running_from_record(record)
            if lane is not None:
                add(lane)

    state_root = _state_root(repo, state_override)
    state_candidates = [state_root]
    if not state_override:
        state_candidates.append(state_root.parent)
    for candidate_root in state_candidates:
        scratch = candidate_root / "scratch" if candidate_root.name != "scratch" else candidate_root
        if not scratch.is_dir():
            continue
        for pid_path in sorted(scratch.glob("*/[!.]*.pid.json")):
            try:
                value = json.loads(pid_path.read_text(encoding="utf-8"))
            except (OSError, UnicodeError, json.JSONDecodeError):
                continue
            if not isinstance(value, dict) or not _live_identity({"pid": value.get("pid"), "starttime": value.get("starttime")}):
                continue
            worktree_raw = value.get("worktree")
            if isinstance(worktree_raw, str):
                add(RunningLane(str(value.get("label") or pid_path.stem), Path(worktree_raw).resolve(), None, None, str(pid_path)))
    return lanes, problems


def _clash_problems(target: ManifestResult, running: Iterable[RunningLane], repo: Path) -> list[str]:
    problems: list[str] = []
    reported_worktrees: set[Path] = set()
    for lane in running:
        if lane.worktree is not None and lane.worktree == repo:
            if lane.worktree not in reported_worktrees:
                problems.append(f"worktree already holds a running lane: {repo} ({lane.label})")
                reported_worktrees.add(lane.worktree)
        if lane.manifest is None or not lane.manifest.is_file():
            continue
        active_repo = lane.worktree or lane.manifest.parent
        active = parse_manifest(lane.manifest, active_repo)
        for ours in target.owned:
            for theirs in active.owned:
                if ownership_overlaps(ours, theirs):
                    problems.append(
                        f"ownership clash: {ours} overlaps {theirs} "
                        f"(running lane {lane.label})"
                    )
    return problems


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Refuse an unsafe lane dispatch before an agent starts.")
    parser.add_argument("task_positional", nargs="?", help="task markdown file (optional positional spelling)")
    parser.add_argument("--task", help="task markdown file")
    parser.add_argument("--manifest", required=True, help="ownership manifest to preflight")
    parser.add_argument("--base", help="base commit/ref the worktree must exactly contain")
    parser.add_argument("--repo", default=".", help="worktree to inspect (default: current directory)")
    parser.add_argument("--worktree", help="alias for --repo")
    parser.add_argument(
        "--running-lane", "--active-lane", action="append", default=[],
        help="JSON descriptor for a running lane (repeatable; used by isolated callers)",
    )
    parser.add_argument(
        "--state-root", help="lane state root to inspect instead of the default derived root",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    repo = Path(args.worktree or args.repo).expanduser().resolve(strict=False)
    task_raw = args.task
    if args.task_positional and task_raw:
        print("refused: task supplied twice")
        return 1
    task_raw = task_raw or args.task_positional
    task = _input_path(task_raw, repo) if task_raw else None

    manifest_path = _input_path(args.manifest, repo)
    manifest = parse_manifest(manifest_path, repo)
    problems = list(manifest.problems)
    problems.extend(_check_manifest_files(manifest, repo))
    if task is not None:
        problems.extend(_task_checks(task, repo, manifest.required))
    problems.extend(_base_problems(repo, args.base))

    running, running_problems = _discover_running(repo, args.state_root, args.running_lane)
    problems.extend(running_problems)
    problems.extend(_clash_problems(manifest, running, repo))

    if problems:
        for problem in problems:
            print(f"refused: {problem}")
        return 1
    print(f"READY {task or manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
