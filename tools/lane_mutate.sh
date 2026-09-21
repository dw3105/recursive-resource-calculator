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
    #changes. Replacing every match of `<name>.quality` also hit the assignment TARGET and produced
    #`if nil and nil ~= "normal" then nil = nil end`, which does not parse, so the intended assertion was
    #never reached and a correct lane result was blocked by a syntax error.
    port-quality-nil)
        apply tests/golden/engine/mod/scenario.lua '([a-z_]+[.]quality *= *)[a-z_]+[.]quality' '\g<1>nil' ;;
    #115: the empty-plan fallback returns, which is the defect at generate.lua:382.
    validation-plan-empty)
        apply tests/golden/generate.lua 'plan = prepared[.]plan_result[^,]*' 'plan = {}' ;;
    *)
        echo "lane_mutate.sh: unknown mutation: $mutation" >&2
        exit 2 ;;
esac
