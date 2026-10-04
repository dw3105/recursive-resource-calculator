-- Must fail on base code: gate56 runner and row verdict are missing. 2026-10-04
local G=require "tools.gate56"
local same=G.row({case="x",pack="layered",ticks=3,worst_ms=4,cpu_s=2,sha="12345678",valid="ok"},{cpu_s=2.5,sha="12345678",valid="ok"})
assert(same.verdict=="SAME" and same.line:match("ROW case=x pack=layered ticks=3 worst_ms=4 cpu_s=2 sha=12345678 valid=ok main_cpu_s=2.5 main_sha=12345678 verdict=SAME"),"GT1")
local slower=G.row({case="x",pack="layered",ticks=3,worst_ms=4,cpu_s=4,sha="12345678",valid="ok"},{cpu_s=2,sha="87654321",valid="ok"}); assert(slower.verdict=="SLOWER","GT2")
print("GT1 GT2")
