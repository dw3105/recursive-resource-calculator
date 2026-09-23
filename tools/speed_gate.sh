#!/bin/sh
# Gate on tools/speed_probe.sh output.  Reads probe lines on stdin.
#   speed_gate.sh worst <module.fn> <max_seconds>     worst single call of that function <= max
#   speed_gate.sh ratio <module.step> <module.begin> <max>  calls of step per call of begin <= max
#   speed_gate.sh tick <max_seconds>                  worst single Search.step tick <= max
#   speed_gate.sh end <max_cpu_seconds> <max_entities> search finished ok within cpu and entities
# Prints `speed-gate-ok` and exits 0 when the gate holds, else prints the failing line and exits 1.
mode=$1; shift
awk -v mode="$mode" -v a="$1" -v b="$2" -v c="$3" '
function val(line, key,   i, n, parts, kv) {
  n = split(line, parts, " ")
  for (i = 1; i <= n; i++) { split(parts[i], kv, "="); if (kv[1] == key) return kv[2] }
  return ""
}
{ lines[NR] = $0 }
$1 == "MOD" { calls[$2] = val($0, "calls") + 0; worst[$2] = val($0, "worst") + 0 }
$1 == "SPEED" { speed = $0 }
END {
  if (mode == "worst") { ok = (a in worst) && worst[a] <= b + 0; msg = a " worst=" worst[a] " max=" b }
  else if (mode == "ratio") { ok = (b in calls) && calls[b] > 0 && calls[a] / calls[b] <= c + 0
    msg = a "/" b " = " (calls[b] ? calls[a] / calls[b] : "inf") " max=" c }
  else if (mode == "tick") { ok = speed != "" && val(speed, "worst_tick") + 0 <= a + 0; msg = speed " max_tick=" a }
  else if (mode == "end") { ok = speed ~ /^SPEED END/ && val(speed, "ok") == "true" && val(speed, "cpu") + 0 <= a + 0 \
      && val(speed, "entities") + 0 <= b + 0 && val(speed, "entities") + 0 > 0; msg = speed " max_cpu=" a " max_entities=" b }
  else { ok = 0; msg = "unknown mode " mode }
  if (ok) { print "speed-gate-ok " msg; exit 0 } else { print "speed-gate-FAIL " msg; exit 1 }
}'
