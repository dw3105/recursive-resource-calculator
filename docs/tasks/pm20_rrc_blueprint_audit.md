# PM0928-P20 — delivered blueprint with hands turned backward, or a string the game will not import, is refused by the audit

Repo `recursive-resource-calculator`. Worktree `/home/dev_zaigraev_gmail_com/wt-rrc-pm20`, branch `lane/pm20`,
base `BASE_SHA`. Host `legalcopilot-dev`.

**Operator ruling (`docs/RULINGS.md` `lanes-suites`, `RRC-04`): this lane never runs a full suite.** Never
`sh tests/run.sh`, `suite_parallel.sh`, `tests/golden/generate.lua`, `tools/golden_profile.lua`, headless
`factorio`, `tools/deliver.sh` on a real case, or a whole sheet. Never `python3 -m pytest tests/` over a directory.
Run only the three test modules named in the checks block, one at a time, or single nodes
(`python3 -m pytest -q "tests/tools/test_blueprint_audit.py::HandDirectionTest::<name>"`). Owner runs full suite
after merge. **Running a full suite is a stop, not a fix.**

## What is true

**PRESERVE:** `load_entities()` name, signature, return and both refusal messages byte-identical
(`tools/blueprint_audit.py:87-100`; imported by `tools/lane_sim.py:36`, `tools/entity_names.py:10`,
`tools/measure_sheet.sh:23`; `tests/test_entity_names.py:22-24` feeds it strings WITHOUT `item`/`version`, so no
schema rule may live in `load_entities`). Every existing count key, its value on every existing input, every group
title, exit 0/1 rule, `--json` / `-q` / `--expect-target` / `--expect-wires` behaviour. The four source lines
`tests/tools/test_blueprint_audit.py:131-134` pin byte-for-byte (`tools/blueprint_audit.py:219`, `:220`, `:342`,
`:344`): never touch those four lines. All 27 existing tests in `tests/tools/test_blueprint_audit.py` stay green;
only line `:147` changes (below). `tests/tools/test_deliver.py` 8 passed, `tests/test_entity_names.py` 2 passed,
untouched. `tools/blueprint_string.py` untouched (read-only import).

- Requirement RRC-03 part 2 (`~/postmortem/260928/FIX-REQUIREMENTS_2026-09-28.md:286`): each blueprint string gets
  decode + import test, entity direction and connection audit (`tools/blueprint_audit.py`) on golden sheets.
  Evidence row: 43 of 72 "result bad in real use" inputs in rrc; blueprint string failed to load; all inserters
  inverted.
- `tools/blueprint_audit.py` is 628 lines. Docstring `:10-15` lists four questions: hand endpoints, underground
  pairs, unused transport, redundant beacons. No check reads which WAY a hand moves product, and no check reads the
  string's schema. `load_entities()` `:87-100` decodes with non-strict `base64.b64decode` `:96`; a bad string dies
  with a Python traceback, not a named line.
- Direction convention, three sources agree: `docs/feature-contracts.md:173` (inserter `dir` points at its
  pickup); `logic/bp/serialize.lua:406-416` `published_direction` turns every inserter 180 degrees at publish
  (`:415` `return (direction + 8) % 16`); `tools/blueprint_audit.py:213` pickup at `+VEC[direction]`, drop at
  `-VEC[direction]` (`:219-220`). Fix commits `14f0b79` (serialize) and `db60472` (audit) say round 18 shipped
  all 26 hands 180 degrees wrong and `invalid_inserters` read 0 throughout.
- Why endpoint validity misses it: `audit_inserters()` `:202-227` only asks "belt or machine at both ends"; a
  turned hand still has a belt at one end and a machine at the other. Test `:189-204` (ACC4) states that limit.
- Invariant used here (bytes only). `audit_orphans()` `:304-451` builds the belt flow graph and infers a SUPPLY
  terminal at a run head nothing feeds and a DRAIN terminal at a run tail that leads nowhere (`:399-406`). A hand
  that PICKS UP from a run head (nothing feeds it, it has a next tile, no hand drops there), or DROPS ONTO a run tail
  (something feeds it, no next tile, no hand picks there), is turned backward. Prototyped 2026-09-28 on
  legalcopilot-dev against base `2e31f33`:
  | input | backward hands | all hands turned 180 |
  |---|---|---|
  | `tests/golden/cases/player-red-science-1s/reference_manual_blueprint.txt` (player's working factory) | 0 | 8 |
  | `tests/fixtures/blueprints/round22_v5.txt` | 0 | 16 |
  | `tests/fixtures/blueprints/round20_delivered.txt` | 0 | 17 |
  | `~/share/RRC/player-red-science-1s-20260922-INVERTED-INSERTERS.txt` (round 18 delivered bytes) | 20 | 0 |
  | 45 other decodable blueprints in `~/share/RRC/*.txt` | 0 each | 3 to 37 each |
  Single hand turned: caught 8 of 22 on reference, 16 of 26 on round22_v5 (rule sees run ends only; stated limit).
- Round 18 capture: `~/share/RRC/player-red-science-1s-20260922-INVERTED-INSERTERS.txt`, 3314 bytes, sha256
  `5e57d26956f090211ad0f479cda1f00e3f151a7575630fbc71f17a0f41c03c0b`, 352 entities, 26 inserters; holds the three
  hands commit `14f0b79` measured: (16.5,2.5) dir 0, (15.5,3.5) dir 4, (19.5,3.5) dir 12. Base audit already
  exits 1 on it, for `sideload_blocked` 4 only; `backward_hands` is the new reason.
- Import allow-list lives in `tools/blueprint_string.py`: `KEEP` `:53-55` ("everything the engine understands on
  an ordinary blueprint entity"), `TYPED` `:49-50` (only these carry `type`; untyped underground imports as an
  entrance `:46-48`). `:6` records a string that failed to load (2026-09-21); `:10-15` names the causes: `type` on
  non-underground, `type` on pipe-to-ground, `port_id`/`ug_pair_id`, bad wire connector ids (placeholder 0 wrong
  `:19`). `logic/bp/serialize.lua:446-448` still writes `ug_pair_id`, `partner_id`, `port_id`.
  Schema prototype: 0 problems on all 45 decodable `~/share/RRC` blueprints and the 3 repo blueprints; 16
  non-blueprint exports (`eN...`, no `0`) keep the old refusal `:95`.
- Connection audit (lane spec item 3) exists: `audit_inserters()` `:202-227` fails any hand whose pickup or drop
  cell is not belt or machine (ACC2 `:174`, ACC3 `:181`). This lane adds no rule there.
- Consumers: `tools/deliver.sh:300-304` runs the audit with `--json`; `load_counts` `:128-131` tolerates empty
  stdout. `tests/tools/test_deliver.py:22` drives it with the golden reference; must stay 8 passed.
- Golden sheets as generated strings are NOT stored in repo (`tests/golden/cases/*/export.txt` is the mod's
  export input, no leading `0`; `tests/fixtures/bytes_round*.txt` hold hashes). The only repo blueprint strings are
  the three above. `tests/fixtures/route_snaps/*` is peer `rrc_fixer_3`'s: never touch.
- Traps: `tests/tools/test_blueprint_audit.py:144-151` (splitter, asserts exit 0) has a hand at (6.5,5.5) dir 4
  that drops onto a dead-end belt tail; the new rule refuses it, so line `:147` changes its direction to 12 (picks
  from the belt, drops into the machine: what the test name says). `:320-321` `unittest.main()` sits mid-file:
  classes after it run under pytest only; checks use pytest. ACC13 `:291-317` pins exact round 13 counts on
  `~/share/RRC/rrc-round13-mine.txt`: prototype leaves them unchanged (schema 0, backward 0) and stays green.
  `tests/tools/test_blueprint_audit.py` runs 27 passed on base in 5-27 s under load 21.
- No pre-commit hook in this repo (`core.hooksPath` unset): plain `git commit`.

## Expected to change

- `tests/tools/test_blueprint_audit.py:147` pins `inserter(6.5, 5.5)` (dir 4, backward under RRC-03); this lane
  changes it to `inserter(6.5, 5.5, 12)`, asserts unchanged. No other lane of this wave touches the file.

## What to build

1. Copy the round 18 capture byte-exact:
   `cp /home/dev_zaigraev_gmail_com/share/RRC/player-red-science-1s-20260922-INVERTED-INSERTERS.txt tests/fixtures/blueprints/round18_inverted_inserters.txt`
   then `sha256sum` it: must print `5e57d26956f090211ad0f479cda1f00e3f151a7575630fbc71f17a0f41c03c0b`. Different hash:
   stop, report, do not author a fixture by hand.
2. Apply the reference patch below:
   `T=$(mktemp); awk '/^~~~~diff$/{f=1;next} /^~~~~$/{f=0} f' docs/tasks/*_rrc_blueprint_audit.md > "$T"; git apply --check "$T" && git apply "$T"`. It was prototyped against this base: 40 passed, 12 subtests. It adds to `tools/blueprint_audit.py`:
   - `string_problems(text)`: strict base64 (`validate=True`), zlib must end exactly (messages
     `zlib stream is truncated`, `bytes after the zlib stream`), JSON; then schema rows: `item` is `blueprint`,
     `version` int, per entity `name` non-empty str, `entity_number` positive unique int, numeric `position.x/y`,
     `direction` int 0..15, `type` only on `TYPED` and required on `TYPED`, keys within
     `{"entity_number", "type", "drop_position"} | KEEP`; per wire four ints, both entity numbers present, connector
     ids >= 1. A book or planner returns `[]` so `load_entities` keeps its own message.
   - `main()`: for input starting `0`, BEFORE `load_entities`: a `string: ` problem ends the run with
     `blueprint_audit.py: <path> does not decode: <reason>` (exit 1); schema problems print one stderr line each
     `blueprint_audit.py: schema: <problem>`, stdout empty, return 1. Generator JSON input (`{`) skips both.
   - `audit_hand_direction(entities, pairs)`: one finding per hand, pick rule first; messages exactly
     `inserter at (<x>,<y>) facing <dir>: picks up from <cell>, the first tile of a belt nothing feeds` and
     `inserter at (<x>,<y>) facing <dir>: drops onto <cell>, the last tile of a belt that leads nowhere`.
     New count key `backward_hands`; new group `hand direction (RRC-03)` counts toward exit 1.
   - Docstring: two RRC-03 bullets. Test file: line `:147` direction 12; two lines added to ACC4 docstring (limit
     lifted for that shape); classes `HandDirectionTest` (7 tests) and `StringSchemaTest` (6 tests) appended.
   Change nothing else. Patch does not apply cleanly: stop and report, never hand-merge.
3. Red proof in a scratch copy, never in this worktree:
   `D=$(mktemp -d); git archive BASE_SHA | tar -x -C "$D"; cp tests/tools/test_blueprint_audit.py "$D/tests/tools/"; cp tests/fixtures/blueprints/round18_inverted_inserters.txt "$D/tests/fixtures/blueprints/"; cd "$D" && python3 -m pytest -q tests/tools/test_blueprint_audit.py 2>&1 | tail -16`
   → all 13 new tests FAIL (11 `FAILED` lines plus 12 failed subtests), 27 old pass (prototype: `23 failed, 29 passed`).
   Paste as `EVIDENCE-RED:`.
4. Commit once on `lane/pm20` with plain `git commit`, subject
   `pm20: blueprint audit refuses backward hands and strings the game will not import`, body lines
   `EVIDENCE-RED:`, `EVIDENCE-GREEN:` (three modules' pytest summary lines), `EVIDENCE-DIFFSTAT:`
   (`git diff --stat BASE_SHA HEAD`). Never amend, merge, rebase, push, touch `main`, `int/pm-260928` or any tag.
   Run checks LAST.

Reference patch (apply as is):

~~~~diff
--- a/tools/blueprint_audit.py
+++ b/tools/blueprint_audit.py
@@ -7,12 +7,15 @@
 that function never reads a belt, a pipe or an inserter.  An auditor that decodes the delivered string and
 re-derives the geometry cannot be fooled by either, because it never sees our tables at all.
 
-It answers four questions, each of which the round 13 delivery failed:
+It answers these questions; the first four are the ones the round 13 delivery failed:
 
   * does every inserter pick up from, and drop onto, a real belt or a real machine?
   * does every underground endpoint have a legal partner it can actually pair with?
   * does every transport component serve something, or is it decoration?
   * is every beacon load-bearing, or would removing it leave every machine at its configured count?
+  * RRC-03: does any hand take from the first tile of a belt nothing feeds, or drop onto the last tile of a
+    belt that leads nowhere?  Round 18 shipped all 26 hands turned 180 degrees and every count above read 0.
+  * RRC-03: would the game import the string at all?  Decode, schema and wire rows are named before geometry.
 
 Frozen baseline, measured on this host 2026-09-21 against
 ~/share/RRC/rrc-round13-mine.txt (sha256 9e075dddf2a16485cfa4d24e45b5fc62f2ba6cb04fbc23236ca6b8c78cb3d95a):
@@ -27,6 +30,7 @@
 
 import argparse
 import base64
+import binascii
 import json
 import sys
 import zlib
@@ -512,6 +516,153 @@
     return len(side), len(blocked), len(back), cycles, [f"({tile(a)[0]},{tile(a)[1]})->({tile(b)[0]},{tile(b)[1]})" for a,b in blocked]
 
 
+sys.path.insert(0, str(Path(__file__).resolve().parent))
+from blueprint_string import KEEP, TYPED  # noqa: E402  one allow-list, owned by the converter
+
+ENTITY_KEYS = {"entity_number", "type", "drop_position", *KEEP}
+
+
+def _number(value) -> bool:
+    return isinstance(value, (int, float)) and not isinstance(value, bool)
+
+
+def string_problems(text: str) -> List[str]:
+    """RRC-03: every reason the game would refuse to import this string, read from its bytes."""
+    text = text.strip()
+    try:
+        raw = base64.b64decode(text[1:], validate=True)
+    except (ValueError, binascii.Error) as error:
+        return [f"string: base64: {error}"]
+    inflater = zlib.decompressobj()
+    try:
+        body = inflater.decompress(raw) + inflater.flush()
+    except zlib.error as error:
+        return [f"string: zlib: {error}"]
+    if not inflater.eof:
+        return ["string: zlib stream is truncated"]
+    if inflater.unused_data:
+        return ["string: bytes after the zlib stream"]
+    try:
+        payload = json.loads(body)
+    except ValueError as error:
+        return [f"string: JSON: {error}"]
+    blueprint = payload.get("blueprint") if isinstance(payload, dict) else None
+    if not isinstance(blueprint, dict):
+        return []  # a book or planner: load_entities names it
+    problems = []
+    if blueprint.get("item") != "blueprint":
+        problems.append(f"blueprint: item is {blueprint.get('item')!r}, not 'blueprint'")
+    if not isinstance(blueprint.get("version"), int) or isinstance(blueprint.get("version"), bool):
+        problems.append("blueprint: version is not an integer")
+    entities = blueprint.get("entities")
+    if entities is None or entities == []:
+        return problems  # main names an empty artifact
+    if not isinstance(entities, list):
+        return problems + ["blueprint: entities is not a list"]
+    numbers = set()
+    for index, entity in enumerate(entities, start=1):
+        where = f"entity {index}"
+        if not isinstance(entity, dict):
+            problems.append(f"{where}: not an object")
+            continue
+        name = entity.get("name")
+        if isinstance(name, str) and name:
+            where = f"entity {index} ({name})"
+        else:
+            problems.append(f"{where}: name is not a non-empty string")
+        number = entity.get("entity_number")
+        if not isinstance(number, int) or isinstance(number, bool) or number < 1:
+            problems.append(f"{where}: entity_number is not a positive integer")
+        elif number in numbers:
+            problems.append(f"{where}: entity_number {number} repeats")
+        else:
+            numbers.add(number)
+        position = entity.get("position")
+        if not isinstance(position, dict) or not _number(position.get("x")) or not _number(position.get("y")):
+            problems.append(f"{where}: position is not numeric x and y")
+        if "direction" in entity:
+            d = entity["direction"]
+            if not isinstance(d, int) or isinstance(d, bool) or not 0 <= d <= 15:
+                problems.append(f"{where}: direction {d!r} is not an integer 0..15")
+        if "type" in entity and name not in TYPED:
+            problems.append(f"{where}: carries 'type' but is not an underground belt or loader")
+        elif name in TYPED and "type" not in entity:
+            problems.append(f"{where}: has no 'type'; it imports as an entrance")
+        elif "type" in entity and entity["type"] not in ("input", "output"):
+            problems.append(f"{where}: type {entity['type']!r} is not 'input' or 'output'")
+        for key in sorted(set(entity) - ENTITY_KEYS):
+            problems.append(f"{where}: unknown key {key!r}")
+    for index, wire in enumerate(blueprint.get("wires") or [], start=1):
+        if (not isinstance(wire, list) or len(wire) != 4
+                or not all(isinstance(v, int) and not isinstance(v, bool) for v in wire)):
+            problems.append(f"wire {index}: not four integers")
+            continue
+        if wire[0] not in numbers or wire[2] not in numbers:
+            problems.append(f"wire {index}: names an entity_number the blueprint does not hold")
+        if wire[1] < 1 or wire[3] < 1:
+            problems.append(f"wire {index}: connector id below 1")
+    return problems
+
+
+def audit_hand_direction(entities, pairs) -> List[str]:
+    """RRC-03: a hand that takes from the head of a belt nothing feeds, or drops onto the tail of a belt that leads
+    nowhere, is turned 180 degrees."""
+    transport = {tile: e for e in entities if e.get("name") in BELTS | UG_BELTS | SPLITTERS
+                 for tile in occupied_tiles(e)}
+    partner = {}
+    for first, second in pairs:
+        if first in transport and second in transport:
+            partner[first] = second
+            partner[second] = first
+    nexts = {}
+    for cell, entity in transport.items():
+        if entity.get("name") in UG_BELTS and entity.get("type") == "input":
+            dest = [partner[(entity["position"]["x"], entity["position"]["y"])]] if (entity["position"]["x"], entity["position"]["y"]) in partner else []
+        else:
+            d = entity.get("direction", 0)
+            if d not in VEC:
+                dest = []
+            else:
+                vx, vy = VEC[d]
+                if entity.get("name") in SPLITTERS:
+                    dest = [q for t in occupied_tiles(entity) if (q := (t[0] + vx, t[1] + vy)) in transport]
+                else:
+                    q = (cell[0] + vx, cell[1] + vy)
+                    dest = [q] if q in transport else []
+        nexts[cell] = dest
+    for entity in entities:
+        if entity.get("name") not in SPLITTERS or entity.get("direction", 0) not in VEC:
+            continue
+        vx, vy = VEC[entity.get("direction", 0)]
+        lanes = occupied_tiles(entity)
+        for lane in lanes:
+            source = (lane[0] - vx, lane[1] - vy)
+            if source in transport and transport[source].get("name") not in SPLITTERS:
+                nexts[source] = list(nexts[source]) + lanes
+    fed = {q for dest in nexts.values() for q in dest}
+    hands = []
+    for entity in entities:
+        if "inserter" not in entity.get("name", "") or entity.get("direction", 0) not in VEC:
+            continue
+        reach = 2 if "long-handed" in entity.get("name", "") else 1
+        vx, vy = VEC[entity.get("direction", 0)]
+        px, py = entity["position"]["x"], entity["position"]["y"]
+        hands.append((entity, (px + vx * reach, py + vy * reach), (px - vx * reach, py - vy * reach)))
+    drops = {drop for _, _, drop in hands}
+    pickups = {pickup for _, pickup, _ in hands}
+    failures = []
+    for entity, pickup, drop in hands:
+        px, py = entity["position"]["x"], entity["position"]["y"]
+        facing = NAME[entity.get("direction", 0)]
+        if pickup in transport and pickup not in fed and nexts[pickup] and pickup not in drops:
+            failures.append(f"inserter at ({px},{py}) facing {facing}: picks up from {pickup}, "
+                            f"the first tile of a belt nothing feeds")
+        elif drop in transport and not nexts[drop] and drop in fed and drop not in pickups:
+            failures.append(f"inserter at ({px},{py}) facing {facing}: drops onto {drop}, "
+                            f"the last tile of a belt that leads nowhere")
+    return failures
+
+
 def audit_beacons(entities, config: Dict[str, int]) -> Tuple[List[str], int]:
     """Contract 26.6: extra influence is legal, a REDUNDANT beacon is not.
 
@@ -560,6 +711,15 @@
     parser.add_argument("-q", "--quiet", action="store_true", help="print counts only, never each violation")
     args = parser.parse_args(argv)
 
+    raw_text = Path(args.input).read_text().strip()
+    if raw_text.startswith("0"):
+        problems = string_problems(raw_text)
+        if problems and problems[0].startswith("string: "):
+            raise SystemExit(f"blueprint_audit.py: {args.input} does not decode: {problems[0][len('string: '):]}")
+        if problems:
+            for line in problems:
+                print(f"blueprint_audit.py: schema: {line}", file=sys.stderr)
+            return 1
     entities, wires, label = load_entities(Path(args.input))
     if not entities:
         raise SystemExit("blueprint_audit.py: the artifact carries no entities")
@@ -570,6 +730,7 @@
     underground_failures, underground_by_family, underground_pairs = audit_underground(entities)
     orphan_failures, dead_belt, dead_pipe, terminals = audit_orphans(entities, cells, underground_pairs)
     beacon_failures, redundant = audit_beacons(entities, config)
+    hand_failures = audit_hand_direction(entities, underground_pairs)
     sideload, sideload_blocked, back_to_back, cycles, blocked_rows = audit_transport_shapes(entities, underground_pairs)
 
     counts = {
@@ -586,6 +747,7 @@
         "redundant_beacons": redundant,
         "sideload": sideload, "sideload_blocked": sideload_blocked,
         "back_to_back": back_to_back, "cycles": cycles,
+        "backward_hands": len(hand_failures),
     }
     groups = [("inserter endpoints (contract 26.3)", inserter_failures),
               ("underground pairing (contract 26.5)", underground_failures),
@@ -593,7 +755,8 @@
               ("beacon redundancy (contract 26.6)", beacon_failures),
               ("blocked underground side-load", blocked_rows),
               ("underground back-to-back", [str(x) for x in range(back_to_back)]),
-              ("belt route cycles", [str(x) for x in range(cycles)])]
+              ("belt route cycles", [str(x) for x in range(cycles)]),
+              ("hand direction (RRC-03)", hand_failures)]
 
     if args.json:
         print(json.dumps(counts, indent=2, sort_keys=True))
--- a/tests/tools/test_blueprint_audit.py
+++ b/tests/tools/test_blueprint_audit.py
@@ -144,7 +144,7 @@
     def test_splitter_east_west_second_tile_output_and_inserter_pickup(self):
         entities = [belt(2.5, 4.5), belt(3.5, 4.5), belt(2.5, 5.5), belt(3.5, 5.5),
                     splitter(4.5, 5), belt(5.5, 4.5), belt(6.5, 4.5),
-                    belt(5.5, 5.5), inserter(6.5, 5.5), {"name": "assembling-machine-1", "position": {"x": 7.5, "y": 5.5}}]
+                    belt(5.5, 5.5), inserter(6.5, 5.5, 12), {"name": "assembling-machine-1", "position": {"x": 7.5, "y": 5.5}}]
         status, counts = audit(entities)
         self.assertEqual(counts["invalid_inserters"], 0, counts)
         self.assertEqual(counts["unused_belt_tiles"], 0, counts)
@@ -188,6 +188,8 @@
 
     def test_ACC4_a_reversed_output_inserter_is_BEYOND_byte_level_waste(self):
         """Honest limit of this tool, kept as a case so nobody re-adds the claim.
+        LIMIT LIFTED 2026-09-28 (RRC-03) for this exact shape: the hand direction audit refuses it, see
+        test_RRC03_control_output_hand_turned_is_refused. Waste and endpoint counts below stay 0.
 
         Reversing the output inserter makes the machine drain nowhere, which is a broken obligation. It is NOT
         a waste violation: the belt it used to receive from becomes an externally fed run that passes an
@@ -439,3 +441,168 @@
             self.assertIn("1", done.stdout)
         finally:
             pathlib.Path(artifact_path).unlink()
+
+
+GOLDEN_REFERENCE = ROOT / "tests/golden/cases/player-red-science-1s/reference_manual_blueprint.txt"
+GOLDEN_ROUND22 = ROOT / "tests/fixtures/blueprints/round22_v5.txt"
+ROUND18_INVERTED = ROOT / "tests/fixtures/blueprints/round18_inverted_inserters.txt"
+
+
+def decode_file(path):
+    return json.loads(zlib.decompress(base64.b64decode(path.read_text().strip()[1:])))["blueprint"]
+
+
+def run_text(text, *extra):
+    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
+        handle.write(text + "\n")
+        path = handle.name
+    try:
+        done = subprocess.run([sys.executable, str(AUDIT), path, *extra], capture_output=True, text=True)
+        return done, path
+    finally:
+        pathlib.Path(path).unlink()
+
+
+def encode_blueprint(blueprint, tail=b""):
+    body = json.dumps({"blueprint": blueprint}, separators=(",", ":")).encode("utf-8")
+    return "0" + base64.b64encode(zlib.compress(body, 9) + tail).decode("ascii")
+
+
+def turned(blueprint, numbers=None):
+    blueprint = copy.deepcopy(blueprint)
+    for entity in blueprint["entities"]:
+        if "inserter" in entity["name"] and (numbers is None or entity["entity_number"] in numbers):
+            entity["direction"] = (entity.get("direction", 0) + 8) % 16
+    return blueprint
+
+
+class HandDirectionTest(unittest.TestCase):
+    """RRC-03: round 18 shipped every hand 180 degrees wrong and every count here read 0."""
+
+    def counts(self, text):
+        done, _ = run_text(text, "--json")
+        return done.returncode, json.loads(done.stdout)
+
+    def test_RRC03_golden_reference_has_no_backward_hand(self):
+        status, counts = self.counts(GOLDEN_REFERENCE.read_text().strip())
+        self.assertEqual((status, counts["backward_hands"]), (0, 0), counts)
+
+    def test_RRC03_golden_round22_has_no_backward_hand(self):
+        status, counts = self.counts(GOLDEN_ROUND22.read_text().strip())
+        self.assertEqual((status, counts["backward_hands"]), (0, 0), counts)
+
+    def test_RRC03_round18_delivered_inverted_bytes_are_refused(self):
+        status, counts = self.counts(ROUND18_INVERTED.read_text().strip())
+        self.assertEqual(status, 1)
+        self.assertEqual(counts["backward_hands"], 20, counts)
+        self.assertEqual(counts["invalid_inserters"], 0, "endpoint validity alone never saw it")
+        done, _ = run_text(ROUND18_INVERTED.read_text().strip())
+        self.assertIn("hand direction (RRC-03): 20", done.stdout)
+
+    def test_RRC03_every_hand_of_the_reference_turned_is_refused(self):
+        status, counts = self.counts(encode_blueprint(turned(decode_file(GOLDEN_REFERENCE))))
+        self.assertEqual(status, 1)
+        self.assertEqual(counts["backward_hands"], 8, counts)
+
+    def test_RRC03_one_output_hand_turned_is_refused_by_name(self):
+        done, _ = run_text(encode_blueprint(turned(decode_file(GOLDEN_REFERENCE), {107})))
+        self.assertEqual(done.returncode, 1)
+        self.assertIn("  inserter at (210.5,1085.5) facing east: picks up from (211.5, 1085.5), "
+                      "the first tile of a belt nothing feeds\n", done.stdout)
+
+    def test_RRC03_control_output_hand_turned_is_refused(self):
+        """ACC4's shape: the belt the hand fed now starts at a hand that takes from it."""
+        entities = control()
+        entities[4]["direction"] = 4
+        status, counts = audit(entities)
+        self.assertEqual((status, counts["backward_hands"]), (1, 1), counts)
+        _, counts = audit(control())
+        self.assertEqual(counts["backward_hands"], 0, counts)
+
+    def test_RRC03_hand_dropping_onto_a_dead_end_is_refused_by_name(self):
+        entities = [belt(0.5, 0.5), belt(1.5, 0.5), inserter(2.5, 0.5, 4),
+                    {"name": "assembling-machine-3", "position": {"x": 4.5, "y": 0.5}, "recipe": "iron-gear-wheel"}]
+        done, _ = run_text(encode(entities))
+        self.assertEqual(done.returncode, 1)
+        self.assertIn("  inserter at (2.5,0.5) facing east: drops onto (1.5, 0.5), "
+                      "the last tile of a belt that leads nowhere\n", done.stdout)
+
+
+class StringSchemaTest(unittest.TestCase):
+    """RRC-03: a string the game will not import is named before any geometry is judged."""
+
+    def refused(self, text):
+        done, path = run_text(text)
+        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
+        self.assertEqual(done.stdout, "")
+        self.assertNotIn("Traceback", done.stderr)
+        return done.stderr, path
+
+    def blueprint(self, entities=None, **extra):
+        entities = copy.deepcopy(entities if entities is not None else control())
+        for index, entity in enumerate(entities, start=1):
+            entity.setdefault("entity_number", index)
+        return {"item": "blueprint", "version": (2 << 48) | (77 << 16), "entities": entities, **extra}
+
+    def test_RRC03_bad_base64_is_named(self):
+        stderr, path = self.refused("0eNq!!not-base64")
+        self.assertTrue(stderr.startswith(f"blueprint_audit.py: {path} does not decode: base64: "), stderr)
+
+    def test_RRC03_truncated_zlib_is_named(self):
+        whole = encode_blueprint(self.blueprint())
+        raw = base64.b64decode(whole[1:])[:-8]
+        stderr, path = self.refused("0" + base64.b64encode(raw).decode("ascii"))
+        self.assertEqual(stderr, f"blueprint_audit.py: {path} does not decode: zlib stream is truncated\n")
+
+    def test_RRC03_bytes_after_zlib_are_named(self):
+        stderr, path = self.refused(encode_blueprint(self.blueprint(), tail=b"junk"))
+        self.assertEqual(stderr, f"blueprint_audit.py: {path} does not decode: bytes after the zlib stream\n")
+
+    def test_RRC03_schema_rows_are_named(self):
+        cases = {
+            "internal key": (lambda b: b["entities"][2].update(port_id=4),
+                             "blueprint_audit.py: schema: entity 3 (inserter): unknown key 'port_id'"),
+            "untyped underground": (lambda b: b["entities"][6].pop("type"),
+                                    "blueprint_audit.py: schema: entity 7 (underground-belt): has no 'type'; "
+                                    "it imports as an entrance"),
+            "typed pipe": (lambda b: b["entities"].append({"entity_number": 99, "name": "pipe-to-ground",
+                                                            "position": {"x": 30.5, "y": 30.5}, "type": "input"}),
+                           "blueprint_audit.py: schema: entity 10 (pipe-to-ground): carries 'type' but is not an "
+                           "underground belt or loader"),
+            "direction 16": (lambda b: b["entities"][2].update(direction=16),
+                             "blueprint_audit.py: schema: entity 3 (inserter): direction 16 is not an integer 0..15"),
+            "repeated number": (lambda b: b["entities"][1].update(entity_number=1),
+                                "blueprint_audit.py: schema: entity 2 (transport-belt): entity_number 1 repeats"),
+            "string position": (lambda b: b["entities"][0]["position"].update(x="0.5"),
+                                "blueprint_audit.py: schema: entity 1 (transport-belt): position is not numeric x and y"),
+            "wire to nothing": (lambda b: b.update(wires=[[1, 5, 77, 5]]),
+                                "blueprint_audit.py: schema: wire 1: names an entity_number the blueprint does not hold"),
+            "wire connector 0": (lambda b: b.update(wires=[[1, 0, 2, 5]]),
+                                 "blueprint_audit.py: schema: wire 1: connector id below 1"),
+            "not a blueprint item": (lambda b: b.update(item="blueprint-book"),
+                                     "blueprint_audit.py: schema: blueprint: item is 'blueprint-book', not 'blueprint'"),
+        }
+        for label, (plant, line) in cases.items():
+            with self.subTest(label):
+                blueprint = self.blueprint()
+                plant(blueprint)
+                stderr, _ = self.refused(encode_blueprint(blueprint))
+                self.assertIn(line + "\n", stderr)
+
+    def test_RRC03_goldens_pass_the_schema(self):
+        for path in (GOLDEN_REFERENCE, GOLDEN_ROUND22, ROUND18_INVERTED):
+            with self.subTest(path.name):
+                done = subprocess.run([sys.executable, str(AUDIT), str(path), "--json"], capture_output=True, text=True)
+                self.assertNotIn("schema:", done.stderr)
+                self.assertIn("backward_hands", json.loads(done.stdout))
+
+    def test_RRC03_generator_json_skips_the_string_schema(self):
+        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
+            json.dump({"ok": True, "result": {"entities": [dict(e, port_id=1) for e in control()]}}, handle)
+            path = handle.name
+        try:
+            done = subprocess.run([sys.executable, str(AUDIT), path, "--json"], capture_output=True, text=True)
+        finally:
+            pathlib.Path(path).unlink()
+        self.assertEqual(done.returncode, 0, done.stderr)
+        self.assertEqual(json.loads(done.stdout)["backward_hands"], 0)
~~~~

## What done mean

```checks
{"name": "owned-only", "command": "python3 tools/lane_ownership.py check --base BASE_SHA --task docs/tasks/*_rrc_blueprint_audit.md", "expect_exit": 0, "expect_regex": "(?m)^owned-only: 3 file\\(s\\) changed, 3 required deliverable\\(s\\) present$", "timeout_s": 60}
{"name": "audit-tests", "command": "python3 -m pytest -q tests/tools/test_blueprint_audit.py 2>&1", "expect_exit": 0, "expect_regex": "(?m)^40 passed, 12 subtests passed in ", "timeout_s": 120}
{"name": "deliver-tests", "command": "python3 -m pytest -q tests/tools/test_deliver.py 2>&1", "expect_exit": 0, "expect_regex": "(?m)^8 passed in ", "timeout_s": 120}
{"name": "entity-names-tests", "command": "python3 -m pytest -q tests/test_entity_names.py 2>&1", "expect_exit": 0, "expect_regex": "(?m)^2 passed in ", "timeout_s": 60}
{"name": "fixture-captured", "command": "sha256sum tests/fixtures/blueprints/round18_inverted_inserters.txt", "expect_exit": 0, "expect_regex": "^5e57d26956f090211ad0f479cda1f00e3f151a7575630fbc71f17a0f41c03c0b  tests/fixtures/blueprints/round18_inverted_inserters\\.txt$", "timeout_s": 30}
{"name": "golden-reference-clean", "command": "python3 tools/blueprint_audit.py tests/golden/cases/player-red-science-1s/reference_manual_blueprint.txt -q", "expect_exit": 0, "expect_regex": "(?m)^  backward_hands +0$", "timeout_s": 60}
{"name": "round18-inverted-refused", "command": "python3 tools/blueprint_audit.py tests/fixtures/blueprints/round18_inverted_inserters.txt -q", "expect_exit": 1, "expect_regex": "(?m)^  backward_hands +20$", "timeout_s": 60}
{"name": "old-test-lines-kept", "command": "git diff BASE_SHA HEAD -- tests/tools/test_blueprint_audit.py | grep -E '^-([^-]|$)'", "expect_exit": 0, "expect_regex": "\\A-                    belt\\(5\\.5, 5\\.5\\), inserter\\(6\\.5, 5\\.5\\), \\{\"name\": \"assembling-machine-1\", \"position\": \\{\"x\": 7\\.5, \"y\": 5\\.5\\}\\}\\]\\n\\Z", "timeout_s": 30}
{"name": "only-owned-files", "command": "test -z \"$(git status --porcelain --untracked-files=all)\" && git diff --name-only BASE_SHA HEAD | sort | tr '\\n' ' '", "expect_exit": 0, "expect_regex": "^tests/fixtures/blueprints/round18_inverted_inserters\\.txt tests/tools/test_blueprint_audit\\.py tools/blueprint_audit\\.py $", "timeout_s": 30}
{"name": "no-file-deleted", "command": "git diff --diff-filter=D --name-only BASE_SHA HEAD | wc -l", "expect_exit": 0, "expect_regex": "^0$", "timeout_s": 30}
{"name": "one-commit", "command": "git rev-list --count BASE_SHA..HEAD", "expect_exit": 0, "expect_regex": "^1$", "timeout_s": 30}
{"name": "evidence-in-commit-body", "command": "git log -1 --format=%B | grep -cE '^EVIDENCE-(RED|GREEN|DIFFSTAT):'", "expect_exit": 0, "expect_regex": "^([3-9]|[1-9][0-9]+)$", "timeout_s": 30}
```

## Files this lane owns

- `!tools/blueprint_audit.py` — `string_problems`, `audit_hand_direction`, `main()` wiring, docstring; `load_entities` byte-stable
- `!tests/tools/test_blueprint_audit.py` — line 147 direction, 2 ACC4 docstring lines, 13 appended tests; no other line
- `!tests/fixtures/blueprints/round18_inverted_inserters.txt` — new, byte copy of round 18 capture (sha256 above)

## Do not

Never run a full suite, a `lua5.2` test, `sh tests/run.sh`, headless `factorio`, `tools/deliver.sh` on a case,
or any command over 120 s. Never edit this task file, any `*.manifest`, `docs/`, `logic/`, `tools/blueprint_string.py`,
`tests/test_*.lua`, `tests/fixtures/route_snaps/*`, `tests/golden/`, any other fixture, or any other file. Never
weaken or delete an assert; the only removed line is `tests/tools/test_blueprint_audit.py:147`. Never change the
CLI of `tools/build_test_zip.sh` or `tools/game_load_check.sh`. Never amend, rebase, push, or touch `main` or a
wave tag.

Re-cut because: none

# bound: 2700s

Reviewer ask: backward-hand rule reads bytes only and matches the three direction sources (`docs/feature-contracts.md:173`,
`logic/bp/serialize.lua:415`, `tools/blueprint_audit.py:219-220`); golden reference and round22_v5 at 0, round 18
capture at 20; schema allow-list is `blueprint_string.KEEP`, not a second list; `load_entities` untouched.
