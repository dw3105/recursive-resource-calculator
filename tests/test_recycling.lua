--Excess products consumed by a recipe the player picks: consumer bindings, their checks, and results that cannot be solved or are infeasible
local H = require "tests.harness"

local function reconfigure()
    require("logic.indexer").run()
    require("logic.player_data_updater").reinitialize(1)
end

--make: raw -> target + x; burn consumes x and makes nothing; cast makes x from ore
local function consumer_world(shape)
    local world = H.new_world(shape)
    for _, item in ipairs({"raw", "target", "x", "ore", "y"}) do world.add_item(item) end
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1})
    world.add_recipe({name = "make", category = "crafting", ingredients = {{name = "raw", amount = 1}},
        products = {{name = "target", amount = 1}, {name = "x", amount = 1}}})
    world.add_recipe({name = "burn", category = "crafting", ingredients = {{name = "x", amount = 1}}, products = {}})
    world.add_recipe({name = "cast", category = "crafting", ingredients = {{name = "ore", amount = 1}}, products = {{name = "x", amount = 1}}})
    world.add_player(1)
    world.init()
    world.bind("item/target", "make")
    return world
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " R4-7 configuration change keeps a consumer binding while its recipe consumes the product", function()
        local world = consumer_world(shape)
        world.bind_consumer("item/x", "burn")
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"].name, "burn", "binding kept")
        H.equal(storage[1].consumer_product_full_names["item/x"], true, "flag kept")
        H.equal(storage[1].product_full_names_by_recipe_name.burn, "item/x", "inverse binding kept")
    end)

    H.test(shape .. " R4-7 a consumer binding goes with its flag once the recipe stops consuming the product", function()
        local world = consumer_world(shape)
        world.bind_consumer("item/x", "burn")
        --a mod changes burn to take ore, so x is neither its product nor its ingredient
        prototypes.recipe.burn.ingredients = {{type = "item", name = "ore", amount = 1}}
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"], nil, "binding dropped")
        H.equal(storage[1].consumer_product_full_names["item/x"], nil, "flag dropped")
        H.equal(storage[1].product_full_names_by_recipe_name.burn, nil, "inverse binding dropped")
    end)

    H.test(shape .. " R4-7 a consumer binding whose recipe now makes the product but no longer eats it is dropped", function()
        local world = consumer_world(shape)
        world.bind_consumer("item/x", "burn")
        prototypes.recipe.burn.ingredients = {{type = "item", name = "ore", amount = 1}}
        prototypes.recipe.burn.products = {H.product(shape, {name = "x", amount = 1})}
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"], nil, "binding dropped although burn produces x")
        H.equal(storage[1].consumer_product_full_names["item/x"], nil, "flag dropped")
    end)

    H.test(shape .. " R4-7 a consumer binding of a removed recipe goes with its flag", function()
        local world = consumer_world(shape)
        world.bind_consumer("item/x", "burn")
        world.remove_recipe("burn")
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"], nil, "binding dropped")
        H.equal(storage[1].consumer_product_full_names["item/x"], nil, "flag dropped")
    end)

    H.test(shape .. " R4-7 a producer binding still needs the product among the recipe's products", function()
        local world = consumer_world(shape)
        world.bind("item/x", "cast")
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"].name, "cast", "producer binding kept")
        prototypes.recipe.cast.products = {H.product(shape, {name = "y", amount = 1})}
        prototypes.recipe.cast.ingredients = {{type = "item", name = "x", amount = 1}}
        reconfigure()
        H.equal(storage[1].recipes_by_product_full_name["item/x"], nil, "producer binding dropped although cast now eats x")
    end)

    H.test(shape .. " R4-7 saves from before consumer bindings get an empty flag table and keep their bindings", function()
        local world = consumer_world(shape)
        world.bind("item/x", "cast")
        storage[1].consumer_product_full_names = nil
        reconfigure()
        H.equal(next(storage[1].consumer_product_full_names), nil, "empty flag table")
        H.equal(storage[1].recipes_by_product_full_name["item/x"].name, "cast", "binding kept as a producer")
    end)
end

H.done("test_recycling")
