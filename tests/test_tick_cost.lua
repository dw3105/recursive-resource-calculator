-- Must fail on base code: tick cost API and per-tick formatter are missing. 2026-10-04
local TickCost = require "tools.tick_cost"
assert(math.abs(TickCost.of(1000000, 1000) - 22.37) < 0.1, "TC1 formula")
local rows = TickCost.parse({"TICK case=x tick=1 instr=100 ts=0 ms=0.51 phase=pack", "TICK case=x tick=2 instr=200 ts=0 ms=0.51456 phase=route", "TICK case=x tick=3 instr=300 ts=0 ms=0.519 phase=validate"})
assert(#rows == 3 and TickCost.worst_line(rows):match("tick=3") and TickCost.worst_line(rows):match("phase=validate"), "TC2 worst")
print("TC1 TC2")
