--Builds the serializable display model from the live job record.
local ProgressView = {}
local WEIGHTS = {groups=2,pack=10,route=13,hands=1,power=4,tidy=65,validate=5}
local function finite(n, fallback) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge and n or fallback end
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
function ProgressView.of(player_index, sheet_id)
    local data = type(storage)=="table" and storage[player_index]
    if not data then return nil end
    local job = data.calc_jobs and data.calc_jobs[sheet_id]
    if not job and data.blueprint_job and data.blueprint_job.sheet_id==sheet_id then job=data.blueprint_job end
    if not job then return nil end
    local p = type(job.progress)=="table" and job.progress or {}
    local kind = job.kind=="blueprint" and "blueprint" or "calc"
    local stage = p.stage or p.phase or job.phase or "snapshot"
    local fraction
    if job.done then fraction=1
    elseif kind=="blueprint" then
        local attempt=math.max(1,finite(p.attempt,1)); local attempts=math.max(attempt,finite(p.attempts,attempt))
        local progress=stage=="prepare" and 0 or clamp(finite(p.stage_done,0)/math.max(1,finite(p.stage_total,1)),0,1)
        local weight=WEIGHTS[stage] or 0
        local order={"groups","pack","route","hands","power","tidy","validate"}
        local completed=0
        for _, key in ipairs(order) do if key==stage then break end; completed=completed+(WEIGHTS[key] or 0) end
        fraction=0.02 + 0.98*((attempt-1)/attempts + (completed+weight*progress)/(attempts*100))
        fraction=math.min(0.99,fraction)
    else
        local weights={snapshot=10,solve=50,power=10,report=30}
        local order={"snapshot","solve","power","report"}
        local completed=0
        for _, key in ipairs(order) do if key==stage then break end; completed=completed+(weights[key] or 0) end
        local done=finite(p.stage_done,p.done_units or 0)
        local total=finite(p.stage_total,p.total_units or 1)
        fraction=(completed+(weights[stage] or 0)*clamp(done/math.max(1,total),0,1))/100
        fraction=math.min(0.99,fraction)
    end
    p.shown=math.max(finite(p.shown,0),fraction)
    if job.done then p.shown=1 end
    if p.started_tick == nil then p.started_tick=finite(game and game.tick,0) end
    local elapsed=math.max(0,finite(game and game.tick,0)-finite(p.started_tick,0))
    local f=p.shown
    return {kind=kind,stage_key=stage,attempt=math.max(1,finite(p.attempt,1)),attempts=math.max(1,finite(p.attempts,1)),fraction=f,
        elapsed_ticks=elapsed,eta_ticks=f>=0.05 and elapsed*(1-f)/f or nil,best_entities=job.best_entities}
end
return ProgressView
