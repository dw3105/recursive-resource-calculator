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
