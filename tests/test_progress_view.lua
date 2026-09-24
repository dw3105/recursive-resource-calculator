--The progress view converts saved job records into a stable, forward only display model.
local H = require "tests.harness"

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PV-00 red science blueprint job progress is forward only until its record is done", function()
        local world=H.new_world(shape); world.add_player(1); world.init()
        local f=assert(io.open("tests/golden/cases/player-red-science-1s/prepared_input.json","r"))
        local prepared=helpers.json_to_table(f:read("*a")); f:close()
        local Jobs=require "logic.jobs"; local Generation=require "logic.bp.generation"
        storage[1].sheet_revision={red=0}; storage[1].config_revision=0
        local id,err=Generation.start{player_index=1,sheet_id="red",prepared_input=prepared}
        H.equal(id~=nil,true,"the captured red science input starts")
        local last=0; local keys={}; local finished=false
        for tick=1,20000 do
            world.advance_tick(1); Jobs.on_tick({tick=world.tick})
            local view=require("logic.progress_view").of(1,"red")
            local job=storage[1].blueprint_job
            if view then
                H.equal(view.fraction>=last,true,"the fraction never moves backwards")
                H.equal(view.fraction<1 or job.done,true,"a live job never reaches one")
                last=view.fraction; keys[view.stage_key]=true
            end
            if not job then
                local status=Generation.status(1,id)
                if status and status.state~="pending" then finished=true; break end
            end
            if job and job.done then finished=true; break end
        end
        H.equal(finished or (storage[1].blueprint_job and storage[1].blueprint_job.done),true,"the real job reaches its terminal record")
        storage[1].blueprint_job={kind="blueprint",sheet_id="red",done=true,progress={stage="done",shown=last}}
        local done=require("logic.progress_view").of(1,"red")
        H.equal(done.fraction,1,"done is exactly one")
        keys[done.stage_key]=true
        for key in pairs(keys) do
            local f=assert(io.open("locale/en/locale.cfg","r")); local locale=f:read("*a"); f:close()
            H.equal(locale:find("progress_stage_"..key.."=",1,true)~=nil,true,"stage "..key.." has a locale entry")
        end
    end)
    H.test(shape .. " PV-01 blueprint job progress has stage, elapsed time and a stable fraction", function()
        local ProgressView = require "logic.progress_view"
        storage = {[1] = {blueprint_job = {kind = "blueprint", sheet_id = "main", started_tick = 10,
            progress = {stage = "pack", stage_done = 4, stage_total = 8, attempt = 1, attempts = 2, shown = 0.2}}}}
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
            progress = {stage = "solve", stage_done = 1, stage_total = 100}}}}}
        game = {tick = 10}
        H.equal(ProgressView.of(1, "main").eta_ticks, nil, "small progress has no ETA")
        storage[1].calc_jobs.main.progress.stage_done = 10
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
        H.equal(ProgressView.of(1,"main").eta_ticks,nil,"an ETA is omitted before five percent")
        for _, file in ipairs({"locale/en/locale.cfg","locale/cs/locale.cfg","locale/ro/locale.cfg"}) do
            local f=assert(io.open(file,"r")); local text=f:read("*a"); f:close()
            H.equal(text:find("progress_stage_power=",1,true)~=nil,true,file.." has the stage caption")
        end
    end)
end

H.done("test_progress_view")
