--The engine companion is a thin packaged-only adapter over Generation, never a second job owner.
local H = require "tests.harness"

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

local function prepared(sheet_id)
    return {schema_version = 1, snapshot = {sheet_id = sheet_id, state = "current", fingerprint = {input = "api"},
        targets = {}, selection = {}}, solver_result = {status = "ok", columns = {}}, catalog = {}, settings = {},
        options = {}, revisions = {sheet = 0, config = 0}, source_export = {name = "api-export"}}
end

local function fixture(shape)
    local world = H.new_world(shape)
    world.add_player(1)
    world.init()
    local pane = H.gui_root({type = "tabbed-pane", name = "sheet_pane"}, 1)
    require("gui.sheet").new(pane)
    storage[1].sheet_section = {sheet_pane = pane}
    local sheet = pane.tabs[1].content
    local sheet_id = sheet.tags.hxrrc_sheet_id
    storage[1].sheet_revision = {[sheet_id] = 0}
    storage[1].config_revision = 0
    local Registry = require "logic.registry"
    Registry.calculation = {get = function() return nil end}
    local Generation = require "logic.bp.generation"
    local Api = require "logic.engine_test_api"
    return world, Registry, Generation, Api, sheet_id
end

local function terminal(Generation, world, id)
    local result
    for _ = 1, 80 do
        result = Generation.status(1, id)
        if result and result.state ~= "pending" then return result end
        world.advance_tick(1)
        require("logic.jobs").on_tick({tick = world.tick})
    end
    H.equal(false, true, "engine generation reaches a terminal state")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " engine case: the interface refuses an unpackaged candidate", function()
        local _, _, _, Api = fixture(shape)
        --This file runs in a source checkout and, during a handoff, inside an extracted package. The rule is
        --the same in both: an unpackaged tree is refused, a packaged one is accepted and names its candidate.
        local build = Api.build_id()
        if build.packaged then
            H.equal(type(build.candidate_sha) == "string" and #build.candidate_sha == 40, true,
                "a packaged tree names the commit it was built from, saw " .. tostring(build.candidate_sha))
            --A packaged tree may still refuse, because registration also needs the engine's remote global.
            --What must never happen is the opposite: serving an interface the package could not identify.
            H.equal(Api.register(), rawget(_G, "remote") ~= nil,
                "a packaged candidate registers exactly when the engine offers remote")
        else
            H.equal(build.packaged, false, "the source checkout is not packaged")
            H.equal(Api.register(), false, "the interface refuses an unpackaged candidate")
        end
    end)

    H.test(shape .. " engine case: the interface registers no blueprint job kind of its own", function()
        local _, _, _, Api = fixture(shape)
        Api.build_id = function() return {candidate_sha = "test", mod_version = "1", factorio_branch = shape, packaged = true} end
        local Jobs = require "logic.jobs"
        local registered = 0
        local register = Jobs.register
        Jobs.register = function(...)
            registered = registered + 1
            return register(...)
        end
        local interface
        _G.remote = {add_interface = function(_, functions) interface = functions end}
        H.equal(Api.register(), true, "the packaged interface registers")
        H.equal(registered, 0, "the adapter never registers the blueprint kind")
        H.equal(type(interface.start_generation), "function", "the adapter publishes its remote functions")
    end)

    H.test(shape .. " engine case: a terminal result is returned once and stays stable", function()
        local world, _, Generation, Api, sheet_id = fixture(shape)
        Api.build_id = function() return {candidate_sha = "test", mod_version = "1", factorio_branch = shape, packaged = true} end
        local interface
        _G.remote = {add_interface = function(_, functions) interface = functions end}
        Api.register()
        local first = interface.start_generation({player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)})
        H.equal(type(first), "number", "the packaged interface returns a job identity")
        local first_terminal = terminal(Generation, world, first)
        local first_read = interface.generation_status(first)
        local second_read = interface.generation_status(first)
        H.equal(first_read.state, first_terminal.state, "the interface reports the service terminal state")
        H.deep_equal(second_read, first_read, "a terminal result is cached and returned once")
        local capture = Generation.capture(1, first)
        H.equal(capture.source_kind, "runtime", "engine requests mark captures as runtime evidence")
        H.equal(capture.provenance.candidate_sha, "test", "engine provenance carries the candidate identity")
        H.equal(game.players[1].cursor_stack.valid_for_read, false, "engine generation never delivers to the cursor")
    end)

    H.test(shape .. " engine case: a second same-sheet request cannot publish into the first", function()
        local world, _, Generation, Api, sheet_id = fixture(shape)
        Api.build_id = function() return {candidate_sha = "test", mod_version = "1", factorio_branch = shape, packaged = true} end
        local interface
        _G.remote = {add_interface = function(_, functions) interface = functions end}
        Api.register()
        local first = interface.start_generation({player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)})
        local second = interface.start_generation({player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)})
        H.equal(interface.generation_status(first).state, "cancelled", "the first request is superseded")
        local second_terminal = terminal(Generation, world, second)
        H.equal(interface.generation_status(second).state, second_terminal.state,
            "the second request receives its own service result")
        H.equal(interface.generation_status(first).state, "cancelled",
            "the first request cannot receive the second publication")
    end)

    H.test(shape .. " engine case: cancel returns a terminal cancellation", function()
        local _, _, Generation, Api, sheet_id = fixture(shape)
        Api.build_id = function() return {candidate_sha = "test", mod_version = "1", factorio_branch = shape, packaged = true} end
        local interface
        _G.remote = {add_interface = function(_, functions) interface = functions end}
        Api.register()
        local first = interface.start_generation({player_index = 1, sheet_id = sheet_id, prepared_input = prepared(sheet_id)})
        local cancelled = interface.cancel_generation(first)
        H.equal(cancelled.state, "cancelled", "cancel returns a terminal cancellation")
        H.equal(interface.generation_status(first).state, "cancelled", "cancel stays terminal")
        H.equal(Generation.capture(1, 999), nil, "unknown generation has no capture")
    end)
end

H.done("test_engine_test_api")
