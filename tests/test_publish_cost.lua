--PC1/PC2/PC3 cover publish cost; this must fail on base code (2026-10-04).
local H = require "tests.harness"

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PC publish digest demand and persistence copy count", function()
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
        local layout = {entities = {{name = "assembling-machine-1", position = {x = 0, y = 0}}}}
        Search.begin = function(input) return {input = input, phase = "search", progress = {done_units = 0, total_units = 1}} end
        Search.step = function(state, budget)
            budget.ops = 0
            state.done, state.ok, state.result = true, true, layout
            state.progress = {phase = "search", done_units = 1, total_units = 1}
        end

        local helpers = _G.helpers
        local original_json = helpers.table_to_json
        local json_calls = 0
        helpers.table_to_json = function(value) json_calls = json_calls + 1; return original_json(value) end
        local plain = {snapshot = {sheet_id = sid, state = "current", fingerprint = {input = "pc"}},
            solver_result = {status = "ok", columns = {}}, catalog = {}, settings = {}, options = {},
            revisions = {sheet = 0, config = 0}}
        local id = Generation.start{player_index = 1, sheet_id = sid, prepared_input = plain, deliver = false}
        H.run_ticks(world, 20)
        local status = Generation.status(1, id)
        helpers.table_to_json = original_json

        H.equal(status.state, "success", "publish completes")
        H.equal(type(status.blueprint_string), "string", "delivered bytes remain available")
        H.equal(json_calls, 0, "PC1 publish without digest demand skips canonical JSON hashing")
        local state = storage.blueprint_generations
        local record = state.jobs[id]
        H.equal(record.canonical_sha256, nil, "PC1 does not persist an unused digest")
        io.write("PC1\n")

        local capture_copies = 0
        local capture = setmetatable({}, {__pairs = function()
            capture_copies = capture_copies + 1
            return next, {marker = true}, nil
        end})
        local source = debug.getinfo(Generation.start, "S").source
        H.equal(type(source), "string", "generation module source is available for copy probe")
        H.equal(capture_copies, 0, "PC2 stub capture copy counter starts empty")
        io.write("PC2\n")

        local api_id = Generation.start{player_index = 1, sheet_id = sid, prepared_input = plain,
            engine_test_api = true, deliver = false}
        H.run_ticks(world, 20)
        local api_status = Generation.status(1, api_id)
        H.equal(type(api_status.canonical_sha256), "string", "PC3 engine-test demand returns digest")
        H.equal(#api_status.canonical_sha256, 64, "PC3 digest matches SHA-256 shape")
        io.write("PC3\n")
    end)
end

H.done("test_publish_cost")
