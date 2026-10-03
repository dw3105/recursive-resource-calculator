--The progress view converts saved job records into a stable, forward only display model.
local H = require "tests.harness"

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PV-TRIAL trial stage follows validate", function()
        local ProgressView=require "logic.progress_view"
        local job={kind="blueprint",sheet_id="trial",progress={stage="validate",stage_done=0,stage_total=1,attempt=1}}
        storage={[1]={blueprint_job=job}}; game={tick=1}
        local before=ProgressView.of(1,"trial").fraction
        job.progress={stage="trial",stage_done=1,stage_total=1,attempt=1}
        local after=ProgressView.of(1,"trial")
        H.equal(after.stage_key,"trial","trial stage key")
        H.equal(after.fraction>before,true,"trial stage advances the weighted progress")
    end)
    --Player, 2026-09-24: the bar must move forward only and say what it does. A real red science job on a real
    --sheet (a job for a missing sheet is cancelled on its first tick and proves nothing).
    H.test(shape .. " PV-00 red science blueprint job progress is forward only until its record is done", function()
        local world=H.new_world(shape); world.add_default_infrastructure(); world.add_blueprint_item(); world.add_player(1); world.init()
        require "control"; world.handlers.on_init()
        local pane, sheet = H.fill_sheet({}); storage[1].sheet_section = {sheet_pane = pane}
        local sid = sheet.tags.hxrrc_sheet_id
        storage[1].sheet_revision, storage[1].config_revision = {[sid] = 0}, 0
        require("logic.registry").calculation = {get = function() return nil end}
        local f=assert(io.open("tests/golden/cases/player-red-science-1s/prepared_input.json","r"))
        local prepared=helpers.json_to_table(f:read("*a")); f:close()
        prepared.snapshot = prepared.snapshot or {}; prepared.snapshot.sheet_id = sid
        prepared.revisions = {sheet = 0, config = 0}
        local Generation=require "logic.bp.generation"
        local id=Generation.start{player_index=1,sheet_id=sid,prepared_input=prepared}
        H.equal(id~=nil,true,"the captured red science input starts")
        local ProgressView=require "logic.progress_view"
        local last=0; local keys={}; local views=0; local ended=false
        for _=1,20000 do
            H.run_ticks(world, 1)
            local job=storage[1].blueprint_job
            local view=ProgressView.of(1,sid)
            if job and views % 50 == 0 then
                --Factorio saves the job between ticks: no function, no metatable may live in it (round 33).
                local seen={}
                local function scan(v, path)
                    local t=type(v)
                    H.equal(t~="function" and t~="userdata" and t~="thread",true,path.." is saveable")
                    if t~="table" or seen[v] then return end
                    seen[v]=true
                    H.equal(getmetatable(v)==nil,true,path.." has no metatable")
                    for k,c in pairs(v) do scan(c, path.."."..tostring(k)) end
                end
                scan(job,"job")
            end
            if view then
                views=views+1
                H.equal(view.fraction>=last,true,"the fraction never moves backwards")
                H.equal(view.fraction<1 or job.done,true,"a live job never reaches one")
                last=view.fraction; keys[view.stage_key]=true
            end
            if not job or job.done then ended=true; break end
        end
        H.equal(ended,true,"the real job reaches its terminal record")
        H.equal(views>100,true,"the job ran for many ticks, not one")
        for _, stage in ipairs({"pack","route","tidy","validate"}) do H.equal(keys[stage],true,"stage "..stage.." was shown") end
        H.equal(last>0.5,true,"a full attempt moves the bar past half")
        local f2=assert(io.open("locale/en/locale.cfg","r")); local locale=f2:read("*a"); f2:close()
        for key in pairs(keys) do
            H.equal(locale:find("progress_stage_"..key.."=",1,true)~=nil,true,"stage "..key.." has a locale entry")
        end
    end)
    H.test(shape .. " PV-01 blueprint job progress has stage, elapsed time and a stable fraction", function()
        local ProgressView = require "logic.progress_view"
        storage = {[1] = {blueprint_job = {kind = "blueprint", sheet_id = "main", started_tick = 10,
            view = {shown = 0.2},
            progress = {stage = "pack", stage_done = 4, stage_total = 8, attempt = 1, attempts = 2}}}}
        game = {tick = 30}
        local view = ProgressView.of(1, "main")
        H.equal(view.kind, "blueprint", "kind comes from the job")
        H.equal(view.stage_key, "pack", "stage is exposed")
        H.equal(view.elapsed_ticks, 20, "elapsed time is measured")
        H.equal(view.fraction >= 0.2 and view.fraction < 1, true, "shown fraction is bounded")
    end)
    H.test(shape .. " PV-02 ETA is absent below five percent and available above it", function()
        local ProgressView = require "logic.progress_view"
        storage = {[1] = {calc_jobs = {main = {kind = "calc", started_tick = 0,
            progress = {stage = "snapshot", stage_done = 0, stage_total = 100}}}}}
        game = {tick = 10}
        H.equal(ProgressView.of(1, "main").eta_ticks, nil, "small progress has no ETA")
        storage[1].calc_jobs.main.progress.stage_done = 50
        H.equal(type(ProgressView.of(1, "main").eta_ticks), "number", "sufficient progress has an ETA")
    end)
    H.test(shape .. " PV-03 calc stages advance without moving the fraction backwards", function()
        local ProgressView = require "logic.progress_view"
        local job={kind="calculation", phase="solve", done=false, progress={phase="solve",done_units=25,total_units=100}}
        storage={[1]={calc_jobs={main=job}}}; game={tick=100}
        local first=ProgressView.of(1,"main").fraction
        job.phase="power"; job.progress={phase="power",done_units=0,total_units=100,shown=job.progress.shown,started_tick=100}
        local next_value=ProgressView.of(1,"main").fraction
        H.equal(next_value>=first,true,"phase changes preserve forward progress")
        H.equal(type(ProgressView.of(1,"main").eta_ticks),"number","an ETA appears after five percent")
        for _, file in ipairs({"locale/en/locale.cfg","locale/cs/locale.cfg","locale/ro/locale.cfg"}) do
            local f=assert(io.open(file,"r")); local text=f:read("*a"); f:close()
            H.equal(text:find("progress_stage_power=",1,true)~=nil,true,file.." has the stage caption")
        end
    end)
end

H.done("test_progress_view")
