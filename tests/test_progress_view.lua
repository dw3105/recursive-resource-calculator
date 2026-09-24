--The progress view converts saved job records into a stable, forward only display model.
local H = require "tests.harness"

for _, shape in ipairs(H.shapes()) do
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
end

H.done("test_progress_view")
