-- Offline estimate of one engine tick: ADR 0003, calibrated 2026-10-04.
local TickCost = {}
function TickCost.of(instr, tostring_calls)
    return 20.28 * (tonumber(instr) or 0) / 1000000 + 1.58 * (tonumber(tostring_calls) or 0) / 1000 + 0.51
end
function TickCost.parse(lines)
    local rows = {}
    for _, line in ipairs(lines) do
        local case, tick, instr, ts, ms, phase = line:match("^TICK case=(%S+) tick=(%d+) instr=(%d+) ts=(%d+) ms=([%d%.]+) phase=(%S+)")
        if case then rows[#rows + 1] = {case=case,tick=tonumber(tick),instr=tonumber(instr),ts=tonumber(ts),ms=tonumber(ms),phase=phase} end
    end
    return rows
end
function TickCost.worst_line(rows)
    local best
    for _, row in ipairs(rows or {}) do if not best or row.ms > best.ms then best = row end end
    if not best then return nil end
    return string.format("WORST case=%s ms=%.2f tick=%d phase=%s", best.case, best.ms, best.tick, best.phase)
end
if arg and (arg[0] == "tools/tick_cost.lua" or arg[0] == "./tools/tick_cost.lua" or arg[0]:match("/tools/tick_cost%.lua$")) then
    local path = assert(arg[1], "usage: lua5.2 tools/tick_cost.lua <per-tick.log>")
    local f=assert(io.open(path,"r")); local rows=TickCost.parse((function() local a={}; for l in f:lines() do a[#a+1]=l end; f:close(); return a end)())
    for _, r in ipairs(rows) do print(string.format("TICK case=%s tick=%d instr=%d ts=%d ms=%.2f phase=%s",r.case,r.tick,r.instr,r.ts,r.ms,r.phase)) end
    print(TickCost.worst_line(rows) or "WORST case=none ms=0 tick=0 phase=none")
end
return TickCost
