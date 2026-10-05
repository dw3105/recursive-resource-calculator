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
Two runs of one sheet whose wall times differ by at most 1 s or 10%, whichever is bigger, and whose worst ticks differ by at most 10%. Only on a Speed tie does Material cost decide which run is better; otherwise the faster valid run wins.
_Avoid_: same speed, within noise

**Material tie**:
Two runs of one sheet in a Speed tie whose whole-blueprint Material cost (machines, beacons, inserters, poles and transport) differs by at most 10%. Neither run is better; only a run costing more than 10% more loses.
_Avoid_: entity tie (retired 2026-09-30: entity count treats a pipe and an underground belt as equal), close enough

**Sheet sim**:
A delivered sheet blueprint, generated offline, built for real in headless Factorio, powered, given a Metered feed, run, and its output rate counted. Same pass rule as a Player run.
_Avoid_: sheet test, golden run

**Parity row**:
One sheet generated inside headless Factorio and offline from the same input and code, delivered sha compared. Same sha means the offline Sheet sim covers what the player gets; a different sha is a drift defect owed a fix.
_Avoid_: engine check, in-game golden

**Accepted DIFF**:
A gate row whose bytes differ from the Bytes baseline and that ships: faster or Speed tie against `main` run back to back, proven valid (offline validate and lane sim; Sheet sim and Parity row for a layered sheet), and written into the next baseline by the baseline tool, which refuses a row without proof.
_Avoid_: known diff, expected change

**Tick cost**:
Engine milliseconds of one game tick predicted offline from the Lua work done in it: 20.28 x million VM instructions + 1.58 x thousand `tostring` calls + 0.51 (ADR 0003). Gates judge the worst tick by it, not by host clock.
_Avoid_: tick time (host ms, noisy), ops per tick (the budget, not the cost)

**Turn/Flip slice**:
The suite's share of the forced Turn and Flip census: 18 cases with one pose each, the pose rotating by round, on 2.0. The full census and full sims run only on demand and at release.
_Avoid_: mini census, sample

**Split unit**:
The smallest piece of the suite a runner can hand to one machine: one harness case, one census sheet, one headless test file or one sheet sim, named by its JUnit prefix.
_Avoid_: shard (one machine's share of units), chunk

**Integrator-proven row**:
A gate row a lane cannot check in a 60 s single test (a whole big sheet, a worst tick on a big sheet); the lane task names it and the integrator proves it before merge or at the round gate.
_Avoid_: deferred check, skipped row

**Bytes baseline**:
The sha256 of each gated sheet's delivered blueprint string at one round (`bytes_roundNN.txt`). It detects change; the sheet sim judges whether the change is good.
_Avoid_: golden hash

**Port feed**:
Items pushed onto an input belt as fast as it takes them: unlimited, both lanes full, stacked to the maximum belt stack research allows. In a Sheet sim or Player run only during warm-up, which ends with every belt emptied.
_Avoid_: supply, source chest

**Player run**:
One golden driven end to end the way a player does it, in headless Factorio: calculation sheet set up through the GUI, blueprint generated from the generation dialog into the cursor, built from the cursor, given a Metered feed, run at full speed. Passes when each output's measured rate R over the calculation's rate is at least 0.98; making more than the calculation never fails.
_Avoid_: e2e test, finishing test, sheet sim (a Sheet sim starts from delivered bytes and skips the GUI)

**Metered feed**:
Inputs pushed into a built sheet at exactly the calculation's rate per input item or fluid, pooled across all its entry belts and pipes (whichever has room takes it), after a Port feed warm-up that primes machines and pipes and ends with every belt emptied, so output can never beat the calculation by round-up machines eating a belt stock, and is judged only after it settles: the last three 60-second windows of every output agree within 1.5%.
_Avoid_: port feed (unlimited), endless supply

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

**Blocked fluid port**:
A fluid box the recipe uses whose pipe tile no pipe can reach because machines wall it in. A Turn or Flip that leaves one is invalid. A port hemmed in only by belts, pipes of another fluid or electric poles is not blocked: rerouting or moving them frees it.
_Avoid_: inaccessible port (also used for a merely crowded face)

**Drawn pack**:
Packing that first draws the whole Flow graph with fewest Crossings, then aims each Block at its drawn spot and Turns and Flips it. An experiment, off by default, until every golden delivers a drawn layout (no Fallback) and at most one golden loses to the Layered pack; the release that meets that bar makes it the default, with the Layered pack kept as its Fallback.
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

**Port side**:
The side of a Block, after its Turn, that one of its ports sits on, plus the port's place along that side. The Drawn pack draws every flow from Port side to Port side.
_Avoid_: port direction (a belt's facing), attach offset (the code's unturned number)

**Material cost**:
What a stretch of transport costs to craft: the raw resources inside its belts, splitters, underground belts, pipes and underground pipes, worked out from the recipes in the game: follow each recipe down to raw items (whatever a mined resource yields or a tile gives: ores, stone, coal, crude oil, water, even where some recipe also makes them) and add every unit, fluids included, one each.
_Avoid_: entity count (treats a pipe and an underground belt as equal), price

**Footprint**:
The bounding-box area of a delivered blueprint, width × height in tiles, empty corners included. Decides between two runs only inside a Material tie; the smaller wins.
_Avoid_: size, area, entity tiles (counts occupied tiles only)

**Turn trial**:
One other Turn, or Turn plus Flip, tried for one Block of a finished Drawn pack layout: the sheet is packed and routed again with it and kept only when valid and better (lower Material cost of the whole blueprint, then smaller Footprint inside a Material tie).
_Avoid_: reorient, retry, orient trial

**Trial fail**:
A Turn trial that leaves the sheet invalid for any reason other than a Blocked fluid port. Always a defect the code owes a fix for; the layout before the trial is kept.
_Avoid_: forbidden (that is the Blocked fluid port case), rejected trial

## Relationships

- A **Flow graph** has one node per **Block**; the node sits at the Block's midpoint.
- A **Flow graph** has one **Source** per external item or fluid and one **Output** per product.
- An **Output** sits one **Layer** past its producer, at the output-edge end of that Layer.
- No two **Sources** or **Outputs** share a border position.
- A **Block** Turns as a whole; the machines inside a Block all share one Turn and one Flip.

- A **Dead pair** makes a layout invalid whichever pack placed it (Drawn pack or Layered pack).
- A **Turn trial** tries Flip only on a **Block** that uses a fluid; a Flip moves nothing else.
- A **Drawn pack** run beats a **Layered pack** run when it is valid and faster; on a **Speed tie** it loses only when it is not in a **Material tie** and costs more.

## Flagged ambiguities

- "block" vs "group": the code builds one **Block** from each bucket of steps it calls a group. The placed unit is the Block, never a single machine or a whole recipe.
- "crossing" in route and validate code means an underground belt under a run; in the Flow graph it means edges crossing. Canonical: **Crossing** (graph) vs **Underpass** (belt).
