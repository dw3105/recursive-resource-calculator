#!/bin/sh
#Player run lane checks (plan ~/.claude/plans/rrc-player-run-plan-2026-10-05.md). One lane = one number.
#Each check: diff stays inside the lane's own files; its new test passes and prints every marker; each related test
#file it can break ends " 0 failed"; guards green. Single test files only, each under timeout 100. Never a suite,
#census, whole golden sheet or headless run. Usage: sh tools/lane_check_pr.sh <316|317|318>
set -u
lane=${1:?lane number}
base=player-run-base
GUARDS='test_no_runtime_require test_no_item_names test_locale_keys'
case "$lane" in
    316) OWNS='^(tests/game/lib/lab\.lua|tests/game/test_sheets\.lua|tools/sheet_refs\.py|tools/game_stage\.sh|tests/game/offline\.lua|tests/test_lab_meter\.lua|tests/fixtures/sheets/[^/]+\.refs\.json)$'
         NEW='test_lab_meter:MT1,MT2,MT3,MT4,MT5,MT6'; REL='test_game_stage_tools'
         GAME='test_sheets test_feed test_box_binding test_flip_fluidboxes test_turn_flip_sims test_twins' ;;
    317) OWNS='^(tests/game/lib/ports\.lua|tools/sheet_entities\.py|tests/test_ports_find\.lua|tests/fixtures/sheets/[^/]+\.entities\.json)$'
         NEW='test_ports_find:PF1,PF2,PF3,PF4,PF5'; REL=''; GAME='' ;;
    318) OWNS='^(tests/game/lib/player_drive\.lua|tests/game/test_player_drive\.lua|tests/game/index\.lua)$'
         NEW='game/test_player_drive:PD1,PD2,PD3,PD4,PD5'; REL=''; GAME='test_gui test_generate test_probe' ;;
    *) echo "lane_check_pr: unknown lane $lane" >&2; exit 2 ;;
esac
bad=$(git diff --name-only "$base" HEAD | grep -Ev "$OWNS")
[ -z "$bad" ] || { echo "SCOPE files outside lane $lane:"; echo "$bad"; exit 1; }
run_lua() { o=$(timeout 100 lua5.2 "tests/$1.lua" 2>&1); echo "$o" | tail -1 | grep -q ' 0 failed' || { echo "FAIL $1"; echo "$o" | tail -5; return 1; }; LAST=$o; }
run_game() { o=$(timeout 100 lua5.2 tests/game/offline.lua "tests/game/$1.lua" 2>&1); echo "$o" | tail -1 | grep -q ' 0 failed' || { echo "FAIL game/$1"; echo "$o" | tail -5; return 1; }; LAST=$o; }
for spec in $NEW; do
    file=${spec%%:*}; marks=${spec#*:}
    case "$file" in game/*) run_game "${file#game/}" || exit 1 ;; *) run_lua "$file" || exit 1 ;; esac
    for m in $(echo "$marks" | tr ',' ' '); do echo "$LAST" | grep -qw "$m" || { echo "NOMARK $m in $file"; exit 1; }; done
done
for t in $REL $GUARDS; do run_lua "$t" || exit 1; done
for t in $GAME; do run_game "$t" || exit 1; done
echo "lane$lane-ok"
