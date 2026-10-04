--PC1/PC2/PC3 cover publish cost; this must fail on base code (2026-10-04).
local H = require "tests.harness"

local function upvalue(fn, wanted, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for index = 1, math.huge do
        local name, value = debug.getupvalue(fn, index)
        if not name then return nil end
        if name == wanted then return value end
        if type(value) == "function" then
            local found = upvalue(value, wanted, seen)
            if found then return found end
        end
    end
end

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
        H.equal(json_calls, 1, "PC1 skips the additional canonical JSON conversion used only for hashing")
        local state = storage.blueprint_generations
        local record = state.jobs[id]
        H.equal(record.canonical_sha256, nil, "PC1 does not persist an unused digest")
        io.write("PC1\n")

        local persist = upvalue(Generation.register, "persist_handle")
        H.equal(type(persist), "function", "PC2 reaches the persistence function for its copy probe")
        local capture = {pc_marker = "capture"}
        local pair_count, original_pairs = 0, pairs
        _G.pairs = function(value)
            if type(value) == "table" and rawget(value, "pc_marker") == "capture" then
                pair_count = pair_count + 1
            end
            return original_pairs(value)
        end
        persist({job_id = 99999, player_index = 1, sheet_id = "pc2", state = "pending", capture = capture})
        _G.pairs = original_pairs
        H.equal(pair_count, 1, "PC2 persist traverses the stub capture exactly once")
        io.write("PC2\n")

        local api_id = Generation.start{player_index = 1, sheet_id = sid, prepared_input = plain,
            provenance = {packaged = true, candidate_sha = "fixture"}, deliver = false}
        H.run_ticks(world, 20)
        local api_status = Generation.status(1, api_id)
        H.equal(type(api_status.canonical_sha256), "string", "PC3 engine-test demand returns digest")
        H.equal(#api_status.canonical_sha256, 64, "PC3 digest matches SHA-256 shape")
        local expected = assert(io.open("tests/fixtures/r56/313/canonical_sha256.txt", "r"))
        local expected_digest = expected:read("*l")
        expected:close()
        H.equal(api_status.canonical_sha256, expected_digest, "PC3 digest matches the pinned base digest")
        io.write("PC3\n")
    end)
end

H.done("test_publish_cost")
