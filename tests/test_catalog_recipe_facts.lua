--The catalog is the plain-data boundary for recipe and effect-receiver facts.
local H = require "tests.harness"

local Catalog

local function recipe_world(shape)
    local world = H.new_world(shape)
    world.add_item("ore")
    world.add_item("plate")
    world.add_item("spoiled-plate")
    world.add_item("fresh-plate", nil, {result = "spoiled-plate", ticks = 600,
        ticks_by_quality = {normal = 600, legendary = 1200}})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, base_quality = 0,
        quality_limits = {min = 0}})
    world.add_machine({name = "uncaptured", categories = {"crafting"}, speed = 1, no_effect_receiver = true})
    world.add_recipe({name = "plate", category = "crafting", energy = 2,
        ingredients = {{name = "ore", amount = 2}, {name = "fresh-plate", amount = 1}},
        products = {{name = "plate", amount = 1, min = 1, max = 2, p = 0.75, e = 0.25, percent_spoiled = 0.1}}})
    world.add_recipe({name = "plain", category = "crafting", energy = 1,
        ingredients = {}, products = {{name = "plate", amount = 1}}})
    world.add_player(1)
    world.init()
    Catalog = require "logic.catalog"
    return world
end

local function recipe_options(names)
    return {quality = "normal", recipes = names}
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " FP1 the catalog projects every active recipe with its energy, ingredients and products", function()
        recipe_world(shape)
        local catalog = Catalog.build(1, recipe_options({"plate", "plain"}))
        H.equal(catalog.recipe ~= nil and catalog.recipe.plate ~= nil, true, "active recipe is projected")
        local recipe = catalog.recipe.plate
        H.equal(recipe.name, "plate", "recipe name")
        H.equal(recipe.category, "crafting", "recipe category")
        H.near(recipe.energy, 2, "recipe energy")
        H.equal(#recipe.ingredients, 2, "all ingredients are projected")
        H.equal(recipe.ingredients[1].type, "item", "ingredient type")
        H.equal(recipe.ingredients[1].name, "ore", "ingredient name")
        H.near(recipe.ingredients[1].amount, 2, "ingredient amount")
        H.equal(#recipe.products, 1, "all products are projected")
        H.equal(recipe.products[1].type, "item", "product type")
        H.equal(recipe.products[1].name, "plate", "product name")
        H.equal(recipe.products[1].full_name, "item/plate", "product full name")
        H.near(recipe.products[1].amount_min, 1, "product minimum")
        H.near(recipe.products[1].amount_max, 2, "product maximum")
        H.equal(recipe.facts.missing[1], nil, "complete recipe has no missing fact")
    end)

    H.test(shape .. " FP2 a product's probability survives on 2.0 and independent_probability on 2.1", function()
        recipe_world(shape)
        local catalog = Catalog.build(1, recipe_options({"plate"}))
        local product = catalog.recipe.plate.products[1]
        if shape == "2.0" then
            H.near(product.probability, 0.75, "2.0 probability")
            H.equal(product.independent_probability, nil, "2.0 has no 2.1 probability")
        else
            H.near(product.independent_probability, 0.75, "2.1 independent probability")
            H.equal(product.probability, nil, "2.1 has no 2.0 probability")
        end
    end)

    H.test(shape .. " FP3 facts.missing names a field the prototype could not supply, and is empty when nothing is missing", function()
        recipe_world(shape)
        prototypes.recipe.plain.energy = nil
        local catalog = Catalog.build(1, recipe_options({"plate", "plain"}))
        local missing = catalog.recipe.plain.facts.missing
        H.equal(missing[1], "energy", "missing energy is declared")
        H.equal(#catalog.recipe.plate.facts.missing, 0, "complete recipe declares no missing fields")
    end)

    H.test(shape .. " FP4 recipe_coverage.state is partial when an active recipe is absent, complete only when every active name is present", function()
        recipe_world(shape)
        local partial = Catalog.build(1, recipe_options({"plate", "gone"}))
        H.equal(partial.recipe_coverage.state, "partial", "absent active recipe makes coverage partial")
        H.equal(partial.recipe_coverage.missing.gone ~= nil, true, "coverage names absent recipe")
        local complete = Catalog.build(1, recipe_options({"plate", "plain"}))
        H.equal(complete.recipe_coverage.state, "complete", "all active recipes make coverage complete")
        H.equal(next(complete.recipe_coverage.missing), nil, "complete coverage has no missing recipe")
    end)

    H.test(shape .. " FP5 a machine's receiver record carries a status, a source and its branch", function()
        recipe_world(shape)
        local catalog = Catalog.build(1, {entities = {"assembler"}})
        local receiver = catalog.entity.assembler.effect_receiver
        H.equal(receiver.status == "verified_default" or receiver.status == "verified_supported", true,
            "captured receiver is verified")
        H.equal(receiver.source, "prototype", "receiver source")
        H.equal(receiver.branch, shape, "receiver branch")
    end)

    H.test(shape .. " FP6 a 2.0 machine is never unsupported for lacking quality_limits", function()
        recipe_world(shape)
        local catalog = Catalog.build(1, {entities = {"assembler"}})
        local receiver = catalog.entity.assembler.effect_receiver
        if shape == "2.0" then
            H.equal(receiver.quality_limits, nil, "2.0 has no quality limits field")
            H.equal(receiver.status == "unsupported", false, "2.0 missing 2.1 field is not unsupported")
        else
            H.equal(receiver.status == "unsupported", false, "supported 2.1 limits are not unsupported")
        end
    end)

    H.test(shape .. " FP7 a receiver nobody captured is missing, never verified_default", function()
        recipe_world(shape)
        local catalog = Catalog.build(1, {entities = {"uncaptured"}})
        local receiver = catalog.entity.uncaptured.effect_receiver
        H.equal(receiver.status, "missing", "uncaptured receiver is missing")
        H.equal(receiver.status == "verified_default", false, "uncaptured receiver is never a default")
        H.equal(type(receiver.reason), "string", "missing receiver has a reason")
    end)

    H.test(shape .. " FP8 a spoiling item projects spoil_result", function()
        recipe_world(shape)
        local catalog = Catalog.build(1, {items = {"fresh-plate"}})
        H.equal(catalog.item["fresh-plate"].spoil_result, "spoiled-plate", "spoil result is projected")
    end)
end

H.done("test_catalog_recipe_facts")
