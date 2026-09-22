# 148 deliver: one command from the player's sheet to judged bytes

Repo `recursive-resource-calculator`, lane worktree `/home/dev_zaigraev_gmail_com/wt-rrc-148`, branch
`lane/148`, base tag `round-16-wave4` (resolve with `git rev-parse round-16-wave4`), merge target
`feat/round-8-blueprints`. Host `legalcopilot-dev`.

## What is true

Round 16's goal is a delivered blueprint judged against the player's own factory: **127** entities excluding
roboports, exactly **22** `inserter`, **11** machines, **84** to **126** `transport-belt`, **0** underground,
**0** splitter. Frozen at `docs/round-16-delivery-target.json`.

Every piece already exists. **Nothing joins them.**

```
tests/golden/generate.lua      --input <prepared.json> --output <result.json>   generates
tools/blueprint_string.py      <result.json> -o <string.txt>                    encodes real bytes
tools/blueprint_audit.py       <string.txt> --expect-target <target.json>       judges the bytes
```

Today delivering means assembling that chain by hand, three times, with three sets of paths, under a
five-second whole-calculation ceiling nobody is measuring. Round 13 delivered a blueprint the game refused
to load, and round 12 and round 13 each shipped an `ok=true` that lived only in an internal table. The
auditor exists because of exactly that: it decodes the delivered string and re-derives geometry, so it can
never be fooled by our own tables.

This lane makes the chain one command that reports its own wall seconds.

## Traps, each measured

**Trap: the generator's `result.entities` are the mod's INTERNAL shape and will not load in game.**
`tools/blueprint_string.py` is the conversion and it is not optional. Its own header records four distinct
mistakes that a naive string makes, including `type` meaning `input`/`output` on an underground and nothing
else. Never write a string any other way.

**Trap: `tools/blueprint_string.py` REFUSES by default when it cannot map a wire connector**, on purpose —
contract 26.7 says an unavailable connector id is a named refusal, never a silent drop. Round 13 dropped
them silently and delivered 0 of 10 edges. Do **not** pass `--allow-pole-autoconnect` to make a refusal go
away. Surface the refusal.

**Trap: blueprint strings go to `~/share/RRC/` as FILES, never to standard output and never to chat.** That
is a standing rule of this project. The summary line may name the file's path and its byte count; it must
never print the string itself.

**Trap: the five-second ceiling is real and currently at risk.** One candidate's route costs about **5 s** on
this host, measured 2026-09-22. The tool must print its own wall seconds for the generation step separately
from the encode and audit steps, so the ceiling is visible on every single run rather than discovered later.

**Trap: an audit that refuses is information, never a crash.** Exit non-zero only when the audit refuses or a
step genuinely fails, and always print the family counts that were measured, so a miss can be read from the
summary without rerunning anything.

**Trap: never run the whole generator inside a unit test.** The generation step costs seconds to minutes.
`tests/tools/test_deliver.py` must cover argument handling, path construction, the summary shape and the
exit-code rule against a **recorded** export, never by driving `tests/golden/generate.lua`.

**Trap: `tests/golden/cases/player-red-science-1s/` already carries `prepared_input.json`.** That is the
input. Do not invent a new one, and do not modify anything under `tests/golden/cases/`.

PRESERVE: `logic/**`, `tests/**` except `tests/tools/test_deliver.py`, `tools/blueprint_audit.py`,
`tools/blueprint_string.py`, `tools/census_gate.py`, `tools/red_list.sh`, `docs/round-16-delivery-target.json`,
`docs/round-16-census-baseline.json`, `docs/round-16-red-list.txt`, `docs/feature-contracts.md`,
`info.json`, `mod-description.md`, `.agent-lane.toml`.

Files this lane owns: `tools/deliver.sh` (new), `tests/tools/test_deliver.py` (new).

## What to build

**S1. `tools/deliver.sh <case>`**, where `<case>` names a directory under `tests/golden/cases/`. In order:

1. Generate from that case's `prepared_input.json` with `tests/golden/generate.lua`, into a scratch file.
2. Encode with `tools/blueprint_string.py` into `~/share/RRC/<case>-<YYYYMMDD>.txt`. Create `~/share/RRC/`
   when it is missing. Never overwrite an existing file silently — name the collision and refuse, or add a
   counter, but say which in the summary.
3. Audit with `python3 tools/blueprint_audit.py <file> --expect-target docs/round-16-delivery-target.json`.
4. Print **one** summary line carrying: the case, the output path, the byte count, every family count the
   audit measured, the verdict, and the wall seconds of each of the three steps plus the total.

Exit 0 only when the audit accepts. Exit non-zero when any step fails or the audit refuses, with the reason
on standard error and the summary still printed.

Accept `--keep-intermediate <dir>` so a failed run leaves the generated `result.json` behind for diagnosis,
and `--target <path>` so a future round can judge against a different frozen target without editing the tool.

Follow the slicing habit `tools/route_chain_probe.sh:30-44` already uses if any Lua needs to run beside the
generator, and follow `tools/collision_probe.sh` for the general shape of a probe script in this repo.

**S2. `tests/tools/test_deliver.py`.** Cover, against a recorded export and stub binaries on `PATH`, never the
real generator:

- the summary line carries every family count and all four wall-second figures
- a refusing audit gives a non-zero exit and still prints the summary
- an accepting audit gives exit 0
- the output path is `~/share/RRC/<case>-<date>.txt` and the string never reaches standard output
- an unknown case name is refused by name, never a stack trace
- `--target` overrides the frozen target path

Match the style of `tests/tools/test_blueprint_audit.py` and `tests/tools/test_collision_report.py`, which are
already in the tree.

**S3. Report what it measured.** The lane report states the tool's own wall seconds on one real run of
`player-red-science-1s` if the run completes, and states plainly if it does not. A run that refuses is a
legitimate result for this lane: the tool is the deliverable, never a green verdict about the blueprint.

This lane changes **no** production file under `logic/`. It adds two files and nothing else.

## What done mean

Two checks. A check block takes one `gateslot` lease PER check and hands it back between them, so nine cheap
checks means nine trips to the back of a shared queue. Everything cheap is folded in with `&&`.

```checks
{"name": "deliver-tool", "command": "test -x tools/deliver.sh || test -f tools/deliver.sh || exit 1; sh -n tools/deliver.sh && python3 -m pytest tests/tools/test_deliver.py -q 2>&1 | tail -3 && sh tools/deliver.sh 2>&1 | grep -qi 'usage\\|case' && ! grep -rn 'allow-pole-autoconnect' tools/deliver.sh && python3 -m pytest tests/tools/test_blueprint_audit.py -q 2>&1 | tail -1 && echo deliver-tool-ok", "expect_exit": 0, "expect_regex": "deliver-tool-ok", "timeout_s": 1500}
{"name": "owned-only", "command": "python3 tools/lane_ownership.py --base round-16-wave4 --manifest docs/tasks/148.manifest", "expect_exit": 0, "expect_regex": "owned-only", "timeout_s": 180}
```

# bound: 4000s
