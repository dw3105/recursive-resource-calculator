# Fast paths

Read by the Estimate hook's judge before a slow Bash call in this repo runs (`~/skills/docs/ETA-HOOK-SPEC.md` section 12). Agents never edit this file. Entries come from the daily review and land on the player's word. `match` is a Python regular expression searched in the command text.

## Fast paths

None yet. A known gap moves here once its `use instead` command is built and measured.

## Known gaps

### stage replay from route snapshot
- match: drive\.sh (layered|sugiyama)|rdrive\.sh
- missing: replay one stage from a saved route snapshot onward, with tick counts, instead of a full game-rate driver run
- seen: 34 slow calls, 2026-10-02 21:20Z to 2026-10-04 00:45Z
- since: 2026-10-04

### magenta and stack1 route-begin checkpoints
- match: drive\.sh layered\b.*(player-magenta-science-10s|player-inserter-10s-stack1)
- missing: saved route-begin checkpoints at game rate for player-magenta-science-10s and player-inserter-10s-stack1
- seen: 23 slow calls, 2026-10-02 21:20Z to 2026-10-04 00:45Z
- since: 2026-10-04

### checkpoint chunking for the 4 big sheets
- match: for c in .*tests/golden/generate\.lua
- missing: checkpoint chunking for the 4 big sheets, so a study over drawn goldens does not rerun them whole
- seen: 4 slow calls, 2026-10-02 21:20Z to 2026-10-04 00:45Z
- since: 2026-10-04
