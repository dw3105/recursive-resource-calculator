--Event handlers in control.lua, driven through the handlers the mod registers with script
local H = require "tests.harness"

local TECHNOLOGY_MEMBERS = {"name", "valid", "prototype", "force"}
local TECHNOLOGY_PROTOTYPE_MEMBERS = {"name", "valid", "effects"}

--A world with one gear recipe, the given player indexes, and control.lua loaded and initialized
local function control_world(shape, player_indexes)
    local world = H.new_world(shape)
    world.add_item("raw")
    world.add_item("gear")
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "gear", category = "crafting", ingredients = {{name = "raw", amount = 1}}, products = {{name = "gear", amount = 1}}})
    for _, index in ipairs(player_indexes) do world.add_player(index) end
    world.init()
    require "control"
    world.handlers.on_init()
    return world
end

local function drain_ticks(world)
    local ticks = 0
    while storage.computation_stack[1] do
        world.handlers.events[defines.events.on_tick]({tick = ticks})
        ticks = ticks + 1
        assert(ticks < 1000, "computation stack never drained")
    end
    return ticks
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " B1 productivity research recomputes the force's players by player index", function()
        local world = control_world(shape, {3})
        local force = game.players[3].force
        local research = H.lua_object("LuaTechnology", {name = "gear-productivity", valid = true, force = force,
            prototype = H.lua_object("LuaTechnologyPrototype", {name = "gear-productivity", valid = true,
                effects = {{type = "change-recipe-productivity", recipe = "gear", change = 0.1}}}, TECHNOLOGY_PROTOTYPE_MEMBERS)}, TECHNOLOGY_MEMBERS)
        world.handlers.events[defines.events.on_research_finished]({research = research})
        assert(storage.computation_stack[1], "no recomputation queued")
        for _, entry in ipairs(storage.computation_stack) do
            H.equal(entry.player_index, 3, "queued player index")
        end
        drain_ticks(world)
    end)

    H.test(shape .. " B4 a drained recomputation leaves the calculator enabled", function()
        local world = control_world(shape, {1})
        require("gui.calculator").recompute_everything(1)
        drain_ticks(world)
        H.equal(storage[1].backlogged_computation_count, 0, "backlog after drain")
        H.equal(game.players[1].gui.screen.hxrrc_calculator.enabled, true, "calculator enabled")
    end)

    H.test(shape .. " B4 V8 configuration change resets a backlog inflated by older versions", function()
        local world = control_world(shape, {1})
        storage[1].backlogged_computation_count = 12
        world.handlers.on_configuration_changed({mod_changes = {}})
        drain_ticks(world)
        H.equal(storage[1].backlogged_computation_count, 0, "backlog after upgrade and drain")
        H.equal(game.players[1].gui.screen.hxrrc_calculator.enabled, true, "calculator enabled")
    end)

    H.test(shape .. " B6 removing a player with queued computations does not break later ticks", function()
        local world = control_world(shape, {1, 2})
        require("gui.calculator").recompute_everything(2)
        world.handlers.events[defines.events.on_player_removed]({player_index = 2})
        game.players[2] = nil
        for _, entry in ipairs(storage.computation_stack) do
            assert(entry.player_index ~= 2, "removed player's computation still queued")
        end
        require("gui.calculator").recompute_everything(1)
        drain_ticks(world)
        H.equal(storage.computation_stack[1], nil, "queue drained")
        H.equal(game.players[1].gui.screen.hxrrc_calculator.enabled, true, "remaining player's calculator enabled")
    end)

    H.test(shape .. " G4a queued computations run oldest first, centering after the sheets", function()
        local world = control_world(shape, {1})
        require("gui.sheet").new(storage[1].sheet_section.sheet_pane)
        local order = {}
        local calculate, auto_center = async_calls[1], async_calls[2]
        async_calls[1] = function(compute_button, sheet_pane, sheet_index)
            order[#order + 1] = "sheet" .. tostring(sheet_index)
            return calculate(compute_button, sheet_pane, sheet_index)
        end
        async_calls[2] = function(player_index)
            order[#order + 1] = "center"
            return auto_center(player_index)
        end
        require("gui.calculator").recompute_everything(1)
        drain_ticks(world)
        H.equal(table.concat(order, " "), "sheet1 sheet2 center", "run order")
    end)

    H.test(shape .. " B6 a queued computation whose player data is gone is skipped", function()
        local world = control_world(shape, {1})
        local sheet_pane = storage[1].sheet_section.sheet_pane
        table.insert(storage.computation_stack, {player_index = 5, call_id = 1, parameters = {false, sheet_pane, 1}})
        drain_ticks(world)
        H.equal(storage.computation_stack[1], nil, "queue drained")
    end)
end

H.done("test_control")
