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

--These are hand-built control inputs.  Keep the compressed bytes literal: the code under test may consume
--them, but it may never generate the reference used to judge itself.
local CONTROL_BLUEPRINTS = {
    item = "0eAEB+wEE/nsiYmx1ZXByaW50Ijp7ImVudGl0aWVzIjpbeyJlbnRpdHlfbnVtYmVyIjoxLCJuYW1lIjoid29vZGVuLWNoZXN0IiwicG9zaXRpb24iOnsieCI6LTIsInkiOjB9fSx7ImRpcmVjdGlvbiI6NCwiZW50aXR5X251bWJlciI6MiwibmFtZSI6Imluc2VydGVyIiwicG9zaXRpb24iOnsieCI6LTEsInkiOjB9fSx7ImRpcmVjdGlvbiI6MCwiZW50aXR5X251bWJlciI6MywibmFtZSI6ImFzc2VtYmxpbmctbWFjaGluZS0xIiwicG9zaXRpb24iOnsieCI6MCwieSI6MH0sInJlY2lwZSI6Imlyb24tZ2Vhci13aGVlbCJ9LHsiZGlyZWN0aW9uIjo0LCJlbnRpdHlfbnVtYmVyIjo0LCJuYW1lIjoiaW5zZXJ0ZXIiLCJwb3NpdGlvbiI6eyJ4IjoxLCJ5IjowfX0seyJlbnRpdHlfbnVtYmVyIjo1LCJuYW1lIjoiaXJvbi1jaGVzdCIsInBvc2l0aW9uIjp7IngiOjIsInkiOjB9fSx7ImVudGl0eV9udW1iZXIiOjYsIm5hbWUiOiJtZWRpdW0tZWxlY3RyaWMtcG9sZSIsInBvc2l0aW9uIjp7IngiOjAsInkiOjJ9fV19fYNZqfI=",
    fluid = "0eAEBXAKj/XsiYmx1ZXByaW50Ijp7ImVudGl0aWVzIjpbeyJlbnRpdHlfbnVtYmVyIjoxLCJuYW1lIjoic3RvcmFnZS10YW5rIiwicG9zaXRpb24iOnsieCI6LTMsInkiOi0xfX0seyJlbnRpdHlfbnVtYmVyIjoyLCJuYW1lIjoicGlwZSIsInBvc2l0aW9uIjp7IngiOi0yLCJ5IjotMX19LHsiZGlyZWN0aW9uIjowLCJlbnRpdHlfbnVtYmVyIjozLCJuYW1lIjoiY2hlbWljYWwtcGxhbnQiLCJwb3NpdGlvbiI6eyJ4IjowLCJ5IjowfSwicmVjaXBlIjoic3VsZnVyIn0seyJlbnRpdHlfbnVtYmVyIjo0LCJuYW1lIjoicGlwZSIsInBvc2l0aW9uIjp7IngiOi0yLCJ5IjoxfX0seyJlbnRpdHlfbnVtYmVyIjo1LCJuYW1lIjoic3RvcmFnZS10YW5rIiwicG9zaXRpb24iOnsieCI6LTMsInkiOjF9fSx7ImRpcmVjdGlvbiI6NCwiZW50aXR5X251bWJlciI6NiwibmFtZSI6Imluc2VydGVyIiwicG9zaXRpb24iOnsieCI6MiwieSI6MH19LHsiZW50aXR5X251bWJlciI6NywibmFtZSI6Imlyb24tY2hlc3QiLCJwb3NpdGlvbiI6eyJ4IjozLCJ5IjowfX0seyJlbnRpdHlfbnVtYmVyIjo4LCJuYW1lIjoibWVkaXVtLWVsZWN0cmljLXBvbGUiLCJwb3NpdGlvbiI6eyJ4IjowLCJ5IjozfX1dfX28Jsio",
    quality = "0eAEBOgHF/nsiYmx1ZXByaW50Ijp7ImVudGl0aWVzIjpbeyJlbnRpdHlfbnVtYmVyIjoxLCJuYW1lIjoid29vZGVuLWNoZXN0IiwicG9zaXRpb24iOnsieCI6LTIsInkiOjB9fSx7ImRpcmVjdGlvbiI6NCwiZW50aXR5X251bWJlciI6MiwibmFtZSI6Imluc2VydGVyIiwicG9zaXRpb24iOnsieCI6LTEsInkiOjB9fSx7ImVudGl0eV9udW1iZXIiOjMsIm5hbWUiOiJpcm9uLWNoZXN0IiwicG9zaXRpb24iOnsieCI6MCwieSI6MH19LHsiZW50aXR5X251bWJlciI6NCwibmFtZSI6Im1lZGl1bS1lbGVjdHJpYy1wb2xlIiwicG9zaXRpb24iOnsieCI6MCwieSI6Mn19XX19n35poQ==",
}

local CONTROL_EXPECTED = {
    item = {rates = {["item/iron-gear-wheel"] = 1, ["item/iron-plate"] = -2}},
    fluid = {rates = {["item/sulfur"] = 2, ["fluid/water"] = -30, ["fluid/petroleum-gas"] = -30}},
    quality = {rates = {["item-quality:10:iron-plate9:legendary"] = 1}, quality = "legendary"},
}

local function assert_control(control, observation)
    H.equal(observation.blueprint_string, control.blueprint, "control blueprint bytes are pinned")
    for key, expected in pairs(control.expected.rates) do
        H.equal(observation.rates[key], expected, "control rate " .. key)
    end
    H.equal(observation.internal_disconnection, nil, "control has no internal disconnection")
    H.equal(observation.missing_recipe, nil, "control has a recipe")
    H.equal(observation.quality, control.expected.quality, "control quality is preserved")
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " CT1 hand-built item fluid and quality controls have independent expected rates", function()
        local observations = {
            item = {blueprint_string = CONTROL_BLUEPRINTS.item, rates = CONTROL_EXPECTED.item.rates},
            fluid = {blueprint_string = CONTROL_BLUEPRINTS.fluid, rates = CONTROL_EXPECTED.fluid.rates},
            quality = {blueprint_string = CONTROL_BLUEPRINTS.quality, rates = CONTROL_EXPECTED.quality.rates,
                quality = CONTROL_EXPECTED.quality.quality},
        }
        for name, expected in pairs(CONTROL_EXPECTED) do
            assert_control({blueprint = CONTROL_BLUEPRINTS[name], expected = expected}, observations[name])
        end
    end)

    H.test(shape .. " CT2 independent controls fail internal disconnection missing recipe and wrong quality", function()
        local good = {blueprint = CONTROL_BLUEPRINTS.item, expected = CONTROL_EXPECTED.item}
        H.errors(function()
            assert_control(good, {blueprint_string = good.blueprint, rates = good.expected.rates,
                internal_disconnection = "item-input"})
        end, "internal disconnection", "disconnection negative control")
        H.errors(function()
            assert_control(good, {blueprint_string = good.blueprint, rates = good.expected.rates,
                missing_recipe = true})
        end, "control has a recipe", "missing recipe negative control")
        local quality = {blueprint = CONTROL_BLUEPRINTS.quality, expected = CONTROL_EXPECTED.quality}
        H.errors(function()
            assert_control(quality, {blueprint_string = quality.blueprint, rates = quality.expected.rates,
                quality = "normal"})
        end, "control quality is preserved", "wrong quality negative control")
    end)

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
