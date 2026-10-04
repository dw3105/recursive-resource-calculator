--Round 56 engine sample (2026-10-04, 2.0.77, 4000 ops): prepare end (capture copy 27 ms, persist + bridge 24 ms,
--Search.begin 25 ms on red-1s) ran with plan and the binding surface in one 139-245 ms tick. Each now ends its tick:
--prepare tick 1, capture tick 2, persist tick 3, Search.begin tick 4, first Search.step tick 5.
local H = require "tests.harness"

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " GP1 prepare finish: capture, persist, search begin each on a fresh tick", function()
        local world = H.new_world(shape)
        world.add_default_infrastructure()
        world.add_blueprint_item()
        world.add_player(1)
        world.init()
        require "control"
        world.handlers.on_init()
        local pane, sheet = H.fill_sheet({})
        storage[1].sheet_section = {sheet_pane = pane}
        local sid = sheet.tags.hxrrc_sheet_id
        storage[1].sheet_revision, storage[1].config_revision = {[sid] = 0}, 0
        local Registry = require "logic.registry"
        Registry.calculation = {get = function() return nil end}
        local Generation = require "logic.bp.generation"
        local Search = require "logic.bp.search"
        local tick, begun_at, stepped_at = 0, nil, nil
        Search.begin = function(input)
            begun_at = begun_at or tick
            return {input = input, phase = "search", progress = {phase = "search", done_units = 0, total_units = 1}}
        end
        Search.step = function(state, budget)
            stepped_at = stepped_at or tick
            budget.ops = 0
            state.done, state.ok, state.result = true, true, {entities = {{name = "assembling-machine-1", position = {x = 0, y = 0}}}}
        end
        local id = Generation.start{player_index = 1, sheet_id = sid, prepared_input = {
            snapshot = {sheet_id = sid, state = "current", fingerprint = {input = "prepare-ticks"}},
            solver_result = {status = "ok", columns = {}}, catalog = {}, settings = {}, options = {},
            revisions = {sheet = 0, config = 0}, surface = "nauvis", force = "player"}, deliver = false}
        local capture_tick
        for n = 1, 8 do
            tick = n
            H.run_ticks(world, 1)
            local capture = Generation.capture(1, id)
            if capture and not capture_tick then
                capture_tick = n
                H.equal(capture.source_kind ~= nil, true, "a capture is complete when first seen")
            end
        end
        H.deep_equal({capture_tick, begun_at, stepped_at}, {3, 4, 5}, "capture at tick 3, Search.begin 4, first step 5")
        H.equal(Generation.status(1, id).state, "success", "the job still finishes")
    end)
end

H.done("test_generation_prepare_ticks")
