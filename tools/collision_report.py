#!/usr/bin/env python3
"""Name the entities and physical boxes in every candidate collision.

The input is the candidate emitted by ``tools/collision_probe.sh``.  This is a
diagnostic, not a gate: it always exits successfully after printing the pairs
it can find.  The validator's collision pass is the authority.

The fallback footprints below mirror ``tests/test_route_footprints.lua`` and
``logic/bp/geometry.lua``.  In particular, an entity's published position wins
over its tile rectangle, a belt is 0.9 by 0.9, and a splitter occupies two
tiles in its perpendicular span.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


NORTH, EAST, SOUTH, WEST = 0, 4, 8, 12
DIRECTION_NAME = {NORTH: "N", EAST: "E", SOUTH: "S", WEST: "W"}
EPSILON = 1e-9


def _number(value: Any, fallback: Optional[float] = None) -> Optional[float]:
    if isinstance(value, bool):
        return fallback
    if isinstance(value, (int, float)) and math.isfinite(float(value)):
        return float(value)
    return fallback


def _direction(entity: Dict[str, Any]) -> int:
    value = entity.get("direction", entity.get("dir", NORTH))
    number = _number(value, NORTH)
    return int(number) % 16


def direction_name(entity: Dict[str, Any]) -> str:
    return DIRECTION_NAME.get(_direction(entity), str(_direction(entity)))


def _is_splitter(entity: Dict[str, Any]) -> bool:
    name = str(entity.get("name") or entity.get("entity") or "").lower()
    return bool(entity.get("splitter")) or entity.get("type") == "splitter" or "splitter" in name


def _ug_role(entity: Dict[str, Any]) -> Optional[str]:
    role = entity.get("ug_role")
    return str(role) if role not in (None, "") else None


def _name(entity: Dict[str, Any]) -> str:
    value = entity.get("name", entity.get("entity", entity.get("prototype", "?")))
    if isinstance(value, dict):
        value = value.get("name", value.get("id", "?"))
    name = str(value)
    if _is_splitter(entity) and "splitter" not in name.lower():
        name += "[splitter]"
    role = _ug_role(entity)
    if role and role.lower() not in name.lower():
        name += "[" + role + "]"
    return name


def _center(entity: Dict[str, Any]) -> Tuple[float, float]:
    position = entity.get("position")
    if isinstance(position, dict):
        px, py = _number(position.get("x")), _number(position.get("y"))
        if px is not None and py is not None:
            return px, py
    width = _number(entity.get("w"), 1.0)
    height = _number(entity.get("h"), 1.0)
    return (_number(entity.get("x"), 0.0) or 0.0) + width / 2.0, (
        _number(entity.get("y"), 0.0) or 0.0
    ) + height / 2.0


def _rotated_local_box(box: Dict[str, Any], direction: int) -> Optional[Tuple[float, float, float, float]]:
    left_top = box.get("left_top")
    right_bottom = box.get("right_bottom")
    if not isinstance(left_top, dict) or not isinstance(right_bottom, dict):
        return None
    left = _number(left_top.get("x"))
    top = _number(left_top.get("y"))
    right = _number(right_bottom.get("x"))
    bottom = _number(right_bottom.get("y"))
    if None in (left, top, right, bottom):
        return None
    corners = ((left, top), (left, bottom), (right, top), (right, bottom))
    rotated = []
    quarter_turns = (direction % 16) // 4
    for x, y in corners:
        if quarter_turns == 0:
            rotated.append((x, y))
        elif quarter_turns == 1:
            rotated.append((-y, x))
        elif quarter_turns == 2:
            rotated.append((-x, -y))
        elif quarter_turns == 3:
            rotated.append((y, -x))
    xs, ys = zip(*rotated)
    return min(xs), min(ys), max(xs), max(ys)


def _box(entity: Dict[str, Any]) -> Dict[str, float]:
    cx, cy = _center(entity)
    direction = _direction(entity)
    local = entity.get("collision_box")
    if isinstance(local, dict):
        rotated = _rotated_local_box(local, direction)
    else:
        rotated = None
    if rotated is None:
        if _is_splitter(entity):
            horizontal = direction in (NORTH, SOUTH)
            width, height = (1.9, 0.9) if horizontal else (0.9, 1.9)
        elif entity.get("ug_role") or "underground-belt" in str(entity.get("name") or ""):
            width = height = 0.9
        elif "transport-belt" in str(entity.get("name") or "") or entity.get("type") == "belt":
            width = height = 0.9
        else:
            width = _number(entity.get("w"), 1.0) or 1.0
            height = _number(entity.get("h"), 1.0) or 1.0
        rotated = (-width / 2.0, -height / 2.0, width / 2.0, height / 2.0)
    left, top, right, bottom = rotated
    return {"left": cx + left, "top": cy + top, "right": cx + right, "bottom": cy + bottom}


def _mask(entity: Dict[str, Any]) -> Optional[set[str]]:
    value = entity.get("collision_mask")
    if not isinstance(value, (list, tuple, dict)):
        return None
    result: set[str] = set()
    if isinstance(value, dict):
        for key, enabled in value.items():
            if enabled:
                result.add(str(key))
    else:
        result.update(str(item) for item in value if isinstance(item, (str, int, float)))
    return result


def _masks_collide(left: Dict[str, Any], right: Dict[str, Any]) -> bool:
    left_mask, right_mask = _mask(left), _mask(right)
    if left_mask is None or right_mask is None:
        return True
    return bool(left_mask & right_mask)


def _overlap(left: Dict[str, float], right: Dict[str, float]) -> Optional[Tuple[float, float]]:
    width = min(left["right"], right["right"]) - max(left["left"], right["left"])
    height = min(left["bottom"], right["bottom"]) - max(left["top"], right["top"])
    if width <= 0.0 or height <= 0.0:
        return None
    return width, height


def _info(entity: Dict[str, Any]) -> Dict[str, Any]:
    cx, cy = _center(entity)
    box = _box(entity)
    return {
        "entity": entity,
        "id": str(entity.get("id", entity.get("entity_id", "?"))),
        "name": _name(entity),
        "cx": cx,
        "cy": cy,
        # For a multi-tile shape the anchor is the top-left covered tile, not
        # the tile containing its centre.  This is why the sample splitter at
        # (12.5, 9.0) publishes tile=(12,8).
        "tile": (math.floor(box["left"] + EPSILON), math.floor(box["top"] + EPSILON)),
        "direction": direction_name(entity),
        "span": 2 if _is_splitter(entity) else 1,
        "box": box,
    }


def overlapping_pairs(entities: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Return every strict, mask-compatible physical overlap in entity order."""
    infos = [_info(entity) for entity in entities if isinstance(entity, dict)]
    result = []
    for index, left in enumerate(infos):
        for right in infos[index + 1 :]:
            if not _masks_collide(left["entity"], right["entity"]):
                continue
            overlap = _overlap(left["box"], right["box"])
            if overlap is not None:
                result.append({"left": left, "right": right, "overlap": overlap})
    return result


def _number_text(value: float) -> str:
    return f"{value:.1f}"


def _entity_text(info: Dict[str, Any]) -> str:
    tx, ty = info["tile"]
    return (
        f"{info['id']} {info['name']}   tile=({tx},{ty}) "
        f"pos=({_number_text(info['cx'])},{_number_text(info['cy'])}) "
        f"dir={info['direction']} span={info['span']}"
    )


def format_pair(pair: Dict[str, Any]) -> str:
    width, height = pair["overlap"]
    return (
        "COLLIDE "
        + _entity_text(pair["left"])
        + "  ||  "
        + _entity_text(pair["right"])
        + f" overlap={_number_text(width)}x{_number_text(height)}"
    )


def report_lines(entities: Iterable[Dict[str, Any]]) -> List[str]:
    entities = [entity for entity in entities if isinstance(entity, dict)]
    pairs = overlapping_pairs(entities)
    splitters = sum(1 for entity in entities if _is_splitter(entity))
    underground = sum(1 for entity in entities if _ug_role(entity))
    return [*(format_pair(pair) for pair in pairs),
            f"SUMMARY pairs={len(pairs)} entities={len(entities)} splitters={splitters} underground={underground}"]


def main(argv: List[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {Path(argv[0]).name} CANDIDATE_JSON", file=sys.stderr)
        return 2
    payload = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
    candidate = payload.get("candidate", payload) if isinstance(payload, dict) else {}
    entities = candidate.get("entities", []) if isinstance(candidate, dict) else []
    for line in report_lines(entities):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
