-- Must fail on base code: tick cost API and per-tick formatter are missing. 2026-10-04
local TickCost = require "tools.tick_cost"
-- Three calibrated rows represented by the fit in docs/tasks/r56_probes/06-tail-ticks.md.
for _, sample in ipairs({{1000000,1000,22.37},{2000000,500,41.86},{2400000,0,49.182}}) do
    assert(math.abs(TickCost.of(sample[1], sample[2]) - sample[3]) < 0.1, "TC1 formula")
end
print("TC1")
local rows = TickCost.parse({"TICK case=x tick=1 instr=100 ts=0 ms=0.51 phase=pack", "TICK case=x tick=2 instr=200 ts=0 ms=0.51456 phase=route", "TICK case=x tick=3 instr=300 ts=0 ms=0.519 phase=validate"})
assert(#rows == 3 and TickCost.worst_line(rows):match("tick=3") and TickCost.worst_line(rows):match("phase=validate"), "TC2 worst")
print("TC2")
print("test_tick_cost: 2 cases, 2 passed, 0 failed")
