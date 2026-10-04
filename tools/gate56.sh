#!/bin/sh
# Back-to-back per-case comparison. GATE56_RUN names an executable runner: <runner> <tree> <case> <pack>.
set -eu
head_tree=${1:?usage: gate56.sh <head-tree> <main-tree> <case> <layered|sugiyama>}
main_tree=${2:?}
case_id=${3:?}
pack=${4:?}
runner=${GATE56_RUN:?set GATE56_RUN to a runner that prints RESULT case=... pack=... ticks=... worst_ms=... cpu_s=... sha=... valid=ok|fail}
run_one() {
    tree=$1
    (cd "$tree" && "$runner" "$tree" "$case_id" "$pack") | awk '/^RESULT /{line=$0} END{if(line) print line; else exit 1}'
}
head=$(run_one "$head_tree") || { echo "ROW case=$case_id pack=$pack ticks=0 worst_ms=0 cpu_s=0 sha=unknown valid=fail main_cpu_s=0 main_sha=unknown verdict=FAIL"; exit 1; }
main=$(run_one "$main_tree") || { echo "ROW case=$case_id pack=$pack ticks=0 worst_ms=0 cpu_s=0 sha=unknown valid=fail main_cpu_s=0 main_sha=unknown verdict=FAIL"; exit 1; }
lua5.2 - "$head" "$main" <<'LUA'
package.path="./?.lua;"..package.path
local G={}
function G.row(head, main)
 local delta=math.abs(head.cpu_s-main.cpu_s)
 local tie=delta<=math.max(1,0.1*math.max(head.cpu_s,main.cpu_s)) and math.abs(head.worst_ms-main.worst_ms)<=0.1*math.max(head.worst_ms,main.worst_ms)
 local verdict
 if head.valid~="ok" or main.valid~="ok" or head.worst_ms>50 then verdict="FAIL"
 elseif head.sha==main.sha then verdict="SAME"
 elseif head.cpu_s<main.cpu_s or tie then verdict="DIFF"
 else verdict="SLOWER" end
 return string.format("ROW case=%s pack=%s ticks=%d worst_ms=%.2f cpu_s=%.2f sha=%s valid=%s main_cpu_s=%.2f main_sha=%s verdict=%s",head.case,head.pack,head.ticks,head.worst_ms,head.cpu_s,head.sha,head.valid,main.cpu_s,main.sha,verdict)
end
local function parse(line)
 local r={}; for k,v in line:gmatch("([%w_]+)=([^ ]+)") do r[k]=v end
 for _,k in ipairs({"ticks","worst_ms","cpu_s"}) do r[k]=tonumber(r[k]) end
 return r
end
print(G.row(parse(arg[1]),parse(arg[2])))
LUA
