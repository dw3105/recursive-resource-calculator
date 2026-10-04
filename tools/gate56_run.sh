#!/bin/sh
#Round 56 gate runner for tools/gate56.sh (GATE56_RUN=tools/gate56_run.sh): one golden at game rate through
#tools/ckpt.lua uninterrupted with the Tick cost hook (RRC_TICK_COST=1), bound input (generate.lua applies the
#engine box binding), pack from arg 3. Prints one RESULT line. Ops per tick GATE56_OPS (default 4000, ADR 0003).
#Per-tick lines go to GATE56_LOG_DIR/<case>.<pack>.<tree-name>.log (default /tmp). Caller sets RRC_SLOW.
set -u
tree=${1:?tree}; case_id=${2:?case}; pack=${3:?layered|sugiyama}
ops=${GATE56_OPS:-4000}
log=${GATE56_LOG_DIR:-/tmp}/$case_id.$pack.$(basename "$tree").log
cd "$tree" || exit 1
if [ "$pack" = sugiyama ]; then export RRC_PACK=sugiyama; else unset RRC_PACK; fi
RRC_TICK_COST=1 lua5.2 tools/ckpt.lua uninterrupted "$case_id" --ops "$ops" > "$log" 2>&1
end=$(grep '^RESUMED ' "$log" | tail -1)
worst=$(lua5.2 tools/tick_cost.lua "$log" | grep '^WORST ' | tail -1 | sed -n 's/.* ms=\([0-9.]*\).*/\1/p')
worst_line=$(lua5.2 tools/tick_cost.lua "$log" | grep '^WORST ' | tail -1); echo "$worst_line" >> "$log"
cpu=$(grep '^PROF total step cpu=' "$log" | tail -1 | sed -n 's/.*cpu=\([0-9.]*\)s.*/\1/p')
ok=$(echo "$end" | sed -n 's/.* ok=\([a-z]*\).*/\1/p')
ticks=$(echo "$end" | sed -n 's/.* ticks=\([0-9]*\).*/\1/p')
sha=$(echo "$end" | sed -n 's/.* sha=\([0-9a-f]*\).*/\1/p' | cut -c1-8)
[ -n "$end" ] || { echo "RESULT case=$case_id pack=$pack ticks=0 worst_ms=0 cpu_s=0 sha=unknown valid=fail"; exit 0; }
valid=fail; [ "$ok" = true ] && valid=ok
echo "RESULT case=$case_id pack=$pack ticks=${ticks:-0} worst_ms=${worst:-0} cpu_s=${cpu:-0} sha=${sha:-unknown} valid=$valid"
