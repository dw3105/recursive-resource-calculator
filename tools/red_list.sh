#!/bin/sh
#Refuse any test file that got WORSE than a frozen list, whatever lane owns it.
#
#Why this exists.  Round 15 lane 131 took tests/test_route_footprints.lua from 6 passing to 0 and
#tests/test_route_budget.lua from 8 to 6, and its gate reported PASS, because the `131_bindings` arm in
#tools/verify_round9_lane.sh never named either file.  A lane gate sees only what its tag names.  This check
#names NO file, so no arm can omit one: it runs the whole fast tier and compares every file's failing count
#against docs/round-16-red-list.txt.
#
#It is a ratchet, not a pass/fail on green.  Pre-existing red stays allowed at exactly its recorded count.
#One more failure in any file, or a file that disappears from the run, exits 1 and says which.
#
#usage: red_list.sh [frozen-list] [--write | --observed <file>]
#  --write regenerates the list from this run.  Only spine does that, and only at a tag.
#  --observed reads an already-collected inventory instead of running the suite.  It exists so the comparison
#    can be exercised on its own -- new-and-green, new-and-red, worse, better, vanished -- without a
#    twenty minute suite run standing between the rule and its proof.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
list=${1:-$root/docs/round-16-red-list.txt}
mode=${2:-check}
supplied=${3:-}

raw=$(mktemp) || exit 2
observed=$(mktemp) || exit 2
trap 'rm -f "$raw" "$observed"' EXIT

if [ "$mode" = "--observed" ]; then
    [ -f "$supplied" ] || { echo "red_list.sh: no such observed inventory: $supplied" >&2; exit 2; }
    sort < "$supplied" > "$observed"
    mode=check
else

#tests/run.sh exits non-zero whenever anything is red, which is the normal state here, so its status is not
#the signal.  Its per-file summary lines are.
( cd "$root" && sh tests/run.sh ) > "$raw" 2>&1 || true

#Each Lua file prints one summary line per interpreter:
#  test_route_budget [Lua 5.2]: 8 cases, 8 passed, 2 failed
#The python tier prints unittest's own summary, so it is recorded under one synthetic identity.
awk '
    match($0, /^([a-z0-9_]+) \[Lua ([0-9.]+)\]: ([0-9]+) cases, ([0-9]+) passed, ([0-9]+) failed/, m) {
        printf "%s\tlua%s\t%s\n", m[1], m[2], m[5]
        next
    }
    /^(OK|FAILED)/ { python = $0 }
    /^Ran [0-9]+ tests? in/ { ran = $2 }
    END {
        failed = 0
        if (python ~ /failures=([0-9]+)/) { match(python, /failures=([0-9]+)/, f); failed += f[1] }
        if (python ~ /errors=([0-9]+)/) { match(python, /errors=([0-9]+)/, e); failed += e[1] }
        if (ran != "") printf "python_tools\tpython\t%d\n", failed
    }
' "$raw" | sort > "$observed"
fi

if [ "$mode" = "--write" ]; then
    {
        echo "#Frozen failing counts per test file per interpreter, at tag round-16-base."
        echo "#Regenerate with tools/red_list.sh docs/round-16-red-list.txt --write, and only at a tag."
        echo "#file<TAB>interpreter<TAB>failing"
        cat "$observed"
    } > "$list"
    echo "RED-LIST written $(grep -vc '^#' "$list") rows"
    exit 0
fi

if [ ! -f "$list" ]; then
    echo "red_list.sh: no frozen list at $list; run with --write at a tag first" >&2
    exit 2
fi

frozen=$(mktemp) || exit 2
grep -v '^#' "$list" | sort > "$frozen"

status=0
#A file that got worse, and a file that vanished from the run, are both refusals.  A file that got BETTER is
#never a refusal: this is a ratchet, and spine re-freezes the list at each merge.
while IFS="$(printf '\t')" read -r file interpreter failing; do
    [ -n "$file" ] || continue
    was=$(awk -F"$(printf '\t')" -v f="$file" -v i="$interpreter" '$1==f && $2==i {print $3}' "$frozen")
    if [ -z "$was" ]; then
        #`[ ... ] && status=1` is NOT safe here.  Under `set -e` an && list whose left side is false returns
        #non-zero as the loop body's result and aborts the whole script, so a brand new file that is GREEN --
        #exactly what a lane adds -- would have been reported as a red-list failure.  Written as an `if`, a
        #green new file is a note and a red one is a refusal.
        echo "RED-LIST new $file [$interpreter] failing=$failing (not in the frozen list)"
        if [ "$failing" -gt 0 ]; then status=1; fi
        continue
    fi
    if [ "$failing" -gt "$was" ]; then
        echo "RED-LIST worse $file [$interpreter] failing=$failing frozen=$was"
        status=1
    elif [ "$failing" -lt "$was" ]; then
        echo "RED-LIST better $file [$interpreter] failing=$failing frozen=$was"
    fi
done < "$observed"

while IFS="$(printf '\t')" read -r file interpreter failing; do
    [ -n "$file" ] || continue
    if ! awk -F"$(printf '\t')" -v f="$file" -v i="$interpreter" '$1==f && $2==i {found=1} END{exit !found}' "$observed"; then
        echo "RED-LIST missing $file [$interpreter] was in the frozen list and did not run"
        status=1
    fi
done < "$frozen"

rm -f "$frozen"

if [ "$status" -eq 0 ]; then
    echo "RED-LIST ok $(wc -l < "$observed" | tr -d ' ') identities, none worse than $list"
else
    echo "red_list.sh: the fast tier got worse than $list" >&2
fi
exit $status
