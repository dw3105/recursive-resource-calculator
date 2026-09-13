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
end

H.done("test_control")
