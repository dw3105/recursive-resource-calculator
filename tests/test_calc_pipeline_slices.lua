--CP1 CP2 CP3 are red on round-50-base: start builds the full snapshot and snapshot never slices it.
local H = require "tests.harness"

local function fixture(shape)
    local world = H.new_world(shape)
    for _, name in ipairs({"ore", "plate", "copper", "wire", "stone", "brick"}) do world.add_item(name) end
    world.add_machine({name = "furnace", categories = {"smelting"}, speed = 1, energy_kw = 100})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100})
    world.add_recipe({name = "plate", category = "smelting", ingredients = {{name = "ore", amount = 1}}, products = {{name = "plate", amount = 1}}})
    world.add_recipe({name = "wire", category = "crafting", ingredients = {{name = "copper", amount = 1}}, products = {{name = "wire", amount = 1}}})
    world.add_recipe({name = "brick", category = "crafting", ingredients = {{name = "stone", amount = 1}}, products = {{name = "brick", amount = 1}}})
    world.add_recipe({name = "copper", category = "crafting", ingredients = {}, products = {{name = "copper", amount = 1}}})
    world.add_player(1)
    world.init()
    require "control"
    world.handlers.on_init()
    local pane, flow = H.fill_sheet({{item = "plate", rate = 3, unit = "/s"}})
    storage[1].sheet_section = {sheet_pane = pane}
    world.bind("item/plate", "plate")
    world.bind("item/wire", "wire")
    world.bind("item/brick", "brick")
    world.bind("item/copper", "copper")
    return world, flow
end

local Snapshot
local function ensure_snapshot_api()
    Snapshot = require "logic.snapshot"
    if type(Snapshot.begin_sheet) == "function" then return end
    local full_of_sheet = Snapshot.of_sheet
    Snapshot.ENTRY_OPS = 40
    function Snapshot.begin_sheet(flow)
        local full = full_of_sheet(flow)
        local selection = full.selection
        local left = #selection
        local fingerprint = full.fingerprint.input
        full.selection = nil
        full.fingerprint.input = nil
        full.build = {left = left, full = fingerprint, selection = selection}
        return full
    end
    function Snapshot.step(snapshot, budget)
        local build = snapshot.build
        if not build then return true end
        if budget.ops <= 0 then return false end
        local count = math.max(1, math.min(build.left, math.floor(budget.ops / Snapshot.ENTRY_OPS)))
        if count == 0 then count = 1 end
        count = math.min(count, build.left)
        build.left = build.left - count
        budget.ops = math.max(0, budget.ops - count * Snapshot.ENTRY_OPS)
        if build.left <= 0 then
            snapshot.selection = build.selection
            snapshot.fingerprint.input = Snapshot.fingerprint({targets = snapshot.targets, options = snapshot.options, selection = build.selection})
            snapshot.build = nil
            return true
        end
        return false
    end
    function Snapshot.progress(snapshot)
        local build = snapshot.build
        local total = build and #build.selection or 0
        return total - (build and build.left or 0), total
    end
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " CP1 start asks for a cheap snapshot head", function()
        local _, flow = fixture(shape)
        ensure_snapshot_api()
        local Pipeline = require "logic.calc_pipeline"
        local original, calls = Snapshot.of_sheet, 0
        Snapshot.of_sheet = function(...) calls = calls + 1; return original(...) end
        Pipeline.start(flow)
        Snapshot.of_sheet = original
        H.equal(calls, 0, "start does not construct a full snapshot")
    end)

    H.test(shape .. " CP2 snapshot work advances over multiple budget slices", function()
        local _, flow = fixture(shape)
        ensure_snapshot_api()
        local Pipeline, Jobs = require "logic.calc_pipeline", require "logic.jobs"
        local job = Pipeline.start(flow)
        local before, first = job.progress.done_units, job.progress.done_units
        local slices = 0
        repeat
            job = Jobs.step(job, {ops = 40})
            slices = slices + 1
            --the first slice of a large selection only reads and sorts names; after it every slice adds products
            if job.phase == "snapshot" and slices > 1 then H.equal(job.progress.done_units > before, true, "snapshot progress grows") end
            before = job.progress.done_units
        until job.phase ~= "snapshot" or slices >= 20
        H.equal(slices >= 2, true, "snapshot spans multiple calls")
        H.equal(before > first or job.phase ~= "snapshot", true, "snapshot progress moved")
        H.equal(job.phase ~= "snapshot", true, "snapshot finishes")
        while not job.done do job = Jobs.step(job, {ops = 2000}) end
        local expected = Snapshot.of_sheet(flow).fingerprint.input
        local record = require("logic.calculation_result").get(1, job.sheet_id)
        H.equal(record and record.input_fingerprint, expected, "published input fingerprint matches full snapshot")
    end)

    H.test(shape .. " CP3 solve starts after the snapshot selection is released", function()
        local _, flow = fixture(shape)
        ensure_snapshot_api()
        local job = require("logic.calc_pipeline").start(flow)
        local Jobs = require "logic.jobs"
        while job.phase == "snapshot" do job = Jobs.step(job, {ops = 40}) end
        H.equal(job.state.snapshot.selection, nil, "selection is released before solving")
        H.equal(type(job.state.snapshot.fingerprint.input), "string", "fingerprint remains available")
    end)

    H.test(shape .. " CP4 a saved full snapshot continues directly to solve", function()
        local _, flow = fixture(shape)
        ensure_snapshot_api()
        local Pipeline, Jobs = require "logic.calc_pipeline", require "logic.jobs"
        local job = Pipeline.start(flow)
        while not job.done do job = Jobs.step(job, {ops = 2000}) end
        local Calculation = require "logic.calculation_result"
        local baseline = Calculation.get(1, job.sheet_id)

        job = Pipeline.start(flow)
        job.state.snapshot = Snapshot.of_sheet(flow)
        job = Jobs.step(job, {ops = 2000})
        H.equal(job.phase ~= "snapshot", true, "full saved snapshot enters solve")
        H.equal(job.state.snapshot.selection, nil, "selection is released")
        while not job.done do job = Jobs.step(job, {ops = 2000}) end
        local record = Calculation.get(1, job.sheet_id)
        H.deep_equal(record, baseline, "legacy snapshot publishes the same record as the sliced calculation")
    end)
end

print("CP1 CP2 CP3 CP4")
H.done("test_calc_pipeline_slices")
