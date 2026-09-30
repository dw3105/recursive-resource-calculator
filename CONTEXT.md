# RRC

Factorio 2.0 + 2.1 mod that plans a production chain and generates its blueprint. Tests judge generated
blueprints; real Factorio is the final judge.

## Language

### Judging

**Twin**:
One tiny factory written once as data, judged twice: by our validator offline and by real Factorio headless.
Both judges must give the same answer.
_Avoid_: scenario, case, probe

**Case**:
One golden sheet under `tests/golden/cases/`, a whole player chain from a real capture.
_Avoid_: twin, sheet fixture

**Fixture**:
Frozen file a test reads.
_Avoid_: twin, case

**Probe**:
Throwaway in-memory patch script used to try a fix without editing code.
_Avoid_: twin, test

**Verdict**:
A judge's answer on a twin: ok, defect or waste. Offline verdict also carries exact set of codes.
_Avoid_: result, outcome

**Speed tie**:
Two runs of one sheet whose wall times differ by at most 1 s or 10%, whichever is bigger, and whose worst ticks differ by at most 10%. Only on a Speed tie do entity counts decide which run is better; otherwise the faster valid run wins.
_Avoid_: same speed, within noise

**Entity tie**:
Two runs of one sheet in a Speed tie whose entity counts differ by at most 10%. Neither run is better; only a run more than 10% bigger loses.
_Avoid_: close enough

**Sheet sim**:
A delivered sheet blueprint built for real in headless Factorio, powered, fed at its ports, run, and its output rate counted.
_Avoid_: sheet test, golden run

**Bytes baseline**:
The sha256 of each gated sheet's delivered blueprint string at one round (`bytes_roundNN.txt`). It detects change; the sheet sim judges whether the change is good.
_Avoid_: golden hash

**Port feed**:
Items pushed onto a sheet's input port belt in a sheet sim: unlimited, both lanes full, stacked to the maximum belt stack research allows.
_Avoid_: supply, source chest

### Rule classes

**Engine rule**:
Validator rule whose breach makes the real factory fail (wrong items, no power, short rate).
_Avoid_: hard rule

**Waste rule**:
Validator rule whose breach leaves the factory working but spends entities for nothing (unused belt, redundant beacon).
_Avoid_: soft rule, style rule

**Player rule**:
Validator rule the player set by taste; real game has no opinion (buffer ring, one source per item).
_Avoid_: house rule

### Game profiles

**Player profile**:
Headless Factorio loaded with the player's exact captured mod set, versions and startup settings.
_Avoid_: modded profile, full profile

**Vanilla profile**:
Headless Factorio with base, quality, elevated-rails, space-age only.
_Avoid_: default profile

### Layout

**Block**:
The unit the packer places: machines of one recipe, machine and beacon setup laid out together with their beacons, inserters and belt runs, with ports on its outside.
_Avoid_: group (the code's bucket of steps before a Block is built), cell, module

**Row**:
A Block of two or more machines touching along one axis, input hands on one long side, output hands on the other.

**Flow graph**:
Directed graph whose nodes are Blocks, Sources and Outputs, and whose edges are item or fluid flows from producer to consumer.
_Avoid_: recipe tree, dependency graph

**Source**:
Flow graph node for one item or fluid entering the blueprint from outside, at the input edge.
_Avoid_: input (ambiguous with a Block's input port), ore node

**Output**:
Flow graph node for one product leaving the blueprint, at the output edge.
_Avoid_: sink (graph jargon), product node

**Layer**:
One band of the Flow graph running parallel to the input edge; Sources are layer 0 and every consumer sits at least one layer past its producers.
_Avoid_: column (true only when the input edge is left or right), level

**Turn**:
Rotating a Block or a machine by a multiple of 90 degrees.
_Avoid_: rotate-and-mirror, orient (covers both Turn and Flip)

**Flip**:
Mirroring a machine so its fluid boxes move to the opposite side without a Turn.
_Avoid_: mirror (the blueprint field name), reverse (used for a Row's belt run)

**Drawn pack**:
Packing that first draws the whole Flow graph with fewest Crossings, then aims each Block at its drawn spot and Turns and Flips it. An experiment, off by default, until every golden delivers a drawn layout (no Fallback) and at most one golden loses to the Layered pack.
_Avoid_: sugiyama mode, graph pack

**Layered pack**:
Today's default packing: Blocks placed one by one in columns away from the input edge, each near partners already placed.
_Avoid_: normal pack

**Fallback**:
A sheet the Drawn pack gave up on and the Layered pack delivered. It keeps the player safe but counts as a Drawn pack loss, never as a valid drawn sheet.
_Avoid_: drawn delivered, soft pass

**Dead pair**:
An underground belt pair that carries no items. A Waste rule breach, yet the player ruled it invalid: a candidate holding one is rejected.
_Avoid_: unused underground, spare pair

**Box binding**:
Which fluid box of a machine each fluid of its recipe uses, as the engine decides it. A recipe that fills every box of a kind binds fluid k to box k; a recipe with fewer fluids binds per machine. The validator trusts only measured Box bindings.
_Avoid_: fluid slot, port order

**Crossing**:
Two Flow graph edges whose drawn lines cross between adjacent Layers.
_Avoid_: using "crossing" for an underground belt passing under a run (that is an **Underpass**)

## Relationships

- A **Flow graph** has one node per **Block**; the node sits at the Block's midpoint.
- A **Flow graph** has one **Source** per external item or fluid and one **Output** per product.
- An **Output** sits one **Layer** past its producer, at the output-edge end of that Layer.
- No two **Sources** or **Outputs** share a border position.
- A **Block** Turns as a whole; the machines inside a Block all share one Turn and one Flip.

- A **Dead pair** makes a layout invalid whichever pack placed it (Drawn pack or Layered pack).
- A **Drawn pack** run beats a **Layered pack** run when it is valid and faster; on a **Speed tie** it loses only when it is not in an **Entity tie** and has more entities.

## Flagged ambiguities

- "block" vs "group": the code builds one **Block** from each bucket of steps it calls a group. The placed unit is the Block, never a single machine or a whole recipe.
- "crossing" in route and validate code means an underground belt under a run; in the Flow graph it means edges crossing. Canonical: **Crossing** (graph) vs **Underpass** (belt).
