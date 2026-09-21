#!/bin/sh
#Apply ONE named mutation to a disposable worktree, so a red proof can say exactly what it broke.
#
#Why this exists, twice over. First, plan section 8.1 requires one named mutation and one named assertion:
#restoring a whole implementation file from the base tag proves only that the old file is old, and it can be
#satisfied by any unrelated failure the baseline already records. Second, writing these mutations inline put
#sed backslashes inside the task's JSON, where `\1` is an invalid escape and the whole checks block stopped
#parsing. A named mutation here keeps the task free of escaping entirely.
#
#Every mutation must leave the file syntactically valid. A file that no longer loads makes the harness report
#[error], and an [error] is never an assertion result -- tools/lane_rows.sh refuses it -- so a mutation that
#breaks the parse turns a red proof into a false negative.
#
#usage: lane_mutate.sh <worktree> <mutation-name>
set -eu

worktree=${1:-}
mutation=${2:-}

if [ -z "$worktree" ] || [ -z "$mutation" ] || [ ! -d "$worktree" ]; then
    echo "usage: lane_mutate.sh <worktree> <mutation-name>" >&2
    exit 2
fi

apply() {
    file=$1
    pattern=$2
    replacement=$3
    target="$worktree/$file"
    if [ ! -f "$target" ]; then
        echo "lane_mutate.sh: $mutation names a missing file: $file" >&2
        exit 2
    fi
    before=$(cksum < "$target")
    python3 - "$target" "$pattern" "$replacement" <<'PY'
import pathlib, re, sys
path, pattern, replacement = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
path.write_text(re.sub(pattern, replacement, path.read_text()))
PY
    after=$(cksum < "$target")
    if [ "$before" = "$after" ]; then
        echo "lane_mutate.sh: $mutation changed nothing in $file; the target it names is absent" >&2
        exit 1
    fi
    #A mutant that does not parse makes the harness report [error], which lane_rows.sh refuses, so the red
    #proof would fail for the wrong reason and block a correct lane result. Measured: the first
    #port-quality-nil rule produced `scenario.lua:894: unexpected symbol near 'nil'` on both interpreters.
    case "$file" in
        *.lua)
            if ! luac5.2 -p "$target" >/dev/null 2>&1; then
                echo "lane_mutate.sh: $mutation left $file unparseable; a syntax error is never a red proof" >&2
                luac5.2 -p "$target" 2>&1 | head -3 >&2
                exit 1
            fi ;;
        *.py)
            if ! python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$target" >/dev/null 2>&1; then
                echo "lane_mutate.sh: $mutation left $file unparseable" >&2
                exit 1
            fi ;;
    esac
    echo "lane_mutate.sh: applied $mutation to $file"
}

case "$mutation" in
    #110: the machine keeps a recipe field, carrying the WRONG recipe. Deleting the assignment could break
    #the parse; a wrong constant cannot.
    recipe-constant)
        apply logic/bp/groups.lua '(recipe *= *)[A-Za-z_][A-Za-z_.]*' '\1"MUTANT-RECIPE"' ;;
    #111: the identity rejection still fires and still names its entity, under a code nobody expects.
    identity-code)
        apply logic/bp/validate.lua 'BP_V_MACHINE_IDENTITY' 'BP_V_MUTANT_CODE' ;;
    #112: the capture still refuses, under a code nobody expects.
    capture-code)
        apply logic/catalog.lua 'BP_CAP_INCOMPLETE' 'BP_CAP_MUTANT' ;;
    #113: every measured segment length becomes zero, which is exactly the defect route cost had.
    segment-length-zero)
        apply logic/bp/route.lua '([.]length *= *)[^,;}\n]+' '\g<1>0' ;;
    #114: the stack stops carrying quality, which is the defect at scenario.lua:894. Only the assigned VALUE
    #changes. Both `stack.quality =` and `stack["quality"] =` are matched: the lane rewrote the first spelling
    #into the second, which is functionally identical and happened to leave the named mutation with nothing to
    #bind to. A red proof that cannot find its target is not a passing red proof. Replacing every match of `<name>.quality` also hit the assignment TARGET and produced
    #`if nil and nil ~= "normal" then nil = nil end`, which does not parse, so the intended assertion was
    #never reached and a correct lane result was blocked by a syntax error.
    port-quality-nil)
        apply tests/golden/engine/mod/scenario.lua '([a-z_]+(?:[.]quality|\["quality"\]) *= *)[a-z_]+[.]quality' '\g<1>nil' ;;
    #115: the empty-plan fallback returns, which is the defect at generate.lua:382.
    validation-plan-empty)
        apply tests/golden/generate.lua 'plan = prepared[.]plan_result[^,]*' 'plan = {}' ;;
    #Round 14. A red proof runs against the lane's OWN tree, so every mutation here must bind to code that
    #exists AFTER the fix. That is only possible when the task mandates the name, so each mutation below names
    #the exact reason code, field or local its lane is required to introduce. A mutation that finds nothing
    #exits 1 rather than passing quietly.
    #
    #spine and 123: the ports argument reaches make_candidate and is put back on the floor, which is the whole
    #round 13 bypass in one line.
    ports-empty)
        apply logic/bp/search.lua '(ports *= *)ports' '\1{}' ;;
    #120: the witness rejection still fires and still names its first illegal step, under a code nobody expects.
    witness-code)
        apply logic/bp/validate.lua 'BP_V_TRANSFER_BROKEN' 'BP_V_MUTANT_CODE' ;;
    #120: the zero-waste rejection still fires, under a code nobody expects.
    waste-code)
        apply logic/bp/validate.lua 'BP_V_TRANSPORT_UNUSED' 'BP_V_MUTANT_CODE' ;;
    #120: the beacon redundancy rejection still fires, under a code nobody expects.
    beacon-redundant-code)
        apply logic/bp/validate.lua 'BP_V_BEACON_REDUNDANT' 'BP_V_MUTANT_CODE' ;;
    #121: the inserter stops publishing the captured pickup cell, so the validator falls back to guessing from
    #the direction vector -- which is exactly the defect at validate.lua:1100-1106.
    inserter-offset-nil)
        apply logic/bp/groups.lua '(pickup_position *= *)[^,;}\n]+' '\1nil' ;;
    #122: both ends of an underground pipe travel the same way again, which is why all twelve delivered
    #pipe-to-ground endpoints faced east or south and none could pair.
    ptg-same-direction)
        apply logic/bp/route.lua '(exit_direction *= *)[^,;}\n]+' '\1direction' ;;
    #123: external terminals are sized by headcount again instead of by demand, which is what turned one supply
    #into several perimeter-length runs.
    terminals-headcount)
        apply logic/bp/search.lua 'terminals_for_demand\([^()]*\)' '1' ;;
    #Round 15, contract section 27. Each mutation below binds to code the task MANDATES, so a red proof cannot
    #bind to nothing.
    #
    #130: the block port stops carrying the inserter it belongs to, so pack cannot tell an anchored port from
    #a synthetic one and relocates it again -- which is why the belt never ended on the hand's tile.
    port-anchor-off)
        apply logic/bp/groups.lua '(inserter_id *= *)inserter_id' '\1nil' ;;
    #130: packing offers the whole perimeter to an anchored port again, which is pack.lua:141-160 before the fix.
    slot-override-on)
        apply logic/bp/pack.lua '(pinned *= *)[^,;}\n]+' '\1false' ;;
    #130 and spine: the port id goes back to the flow-only form, which collides byte for byte with the
    #perimeter terminal id logic/bp/plan.lua:646 mints for the same flow.
    port-id-flow-only)
        apply logic/bp/groups.lua 'tostring\(step[.]step_id\) [.][.] ":in:"' '"in:"' ;;
    #132: the transport-unused rejection still fires and still names its entity, under a code nobody expects.
    #The census then reads zero for it, which is exactly the suppression tests/test_census_codes_live.lua guards.
    census-code-unused)
        apply logic/bp/validate.lua 'BP_V_TRANSPORT_UNUSED' 'BP_V_MUTANT_CODE' ;;
    #132: the copper connector id goes back to the guess, so every delivered wire reads as non-copper.
    connector-zero)
        apply logic/bp/validate.lua '(pole_copper *= *)5' '\g<1>0' ;;
    #124: the wrapper reports reconciliation as validation again, which is the defect at generate.lua:414.
    validation-reconciliation)
        apply tests/golden/generate.lua '(local physical *= *)[^\n]+' '\1{ok = true}' ;;
    *)
        echo "lane_mutate.sh: unknown mutation: $mutation" >&2
        exit 2 ;;
esac
