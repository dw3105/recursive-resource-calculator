--Proves the mocks behave like the engine in both directions before any mod test trusts them
local H = require "tests.harness"

H.test("LuaObject mock errors on a non-member read", function()
    local recipe = H.lua_object("LuaRecipePrototype", {name = "r"}, {"name", "category"})
    H.errors(function() return recipe.categories end, "LuaRecipePrototype doesn't contain key categories", "unknown member read")
end)

H.test("LuaObject mock returns nil for an unset member", function()
    local recipe = H.lua_object("LuaRecipePrototype", {name = "r"}, {"name", "category"})
    H.equal(recipe.category, nil, "unset member")
    H.equal(recipe.name, "r", "set member")
end)

H.test("LuaObject mock errors on a non-member write", function()
    local recipe = H.lua_object("LuaRecipePrototype", {name = "r"}, {"name"})
    H.errors(function() recipe.categories = {} end, "doesn't contain key categories", "unknown member write")
end)

H.test("product concept tables return nil for absent optional keys", function()
    local product = H.product("2.0", {name = "x", amount = 1})
    H.equal(product.extra_count_fraction, nil, "absent optional key")
    H.equal(product.probability, 1, "2.0 probability")
    local product_2_1 = H.product("2.1", {name = "x", amount = 1, p = 0.5, no_shared = true})
    H.equal(product_2_1.probability, nil, "2.1 has no probability")
    H.equal(product_2_1.shared_probability, nil, "2.1.7 shape without shared_probability")
    H.equal(product_2_1.independent_probability, 0.5, "2.1 independent_probability")
end)

H.test("recipe shapes expose only their version's category members", function()
    for _, case in ipairs({{"2.0", "category", "categories"}, {"2.1", "categories", "category"}}) do
        local world = H.new_world(case[1])
        world.add_recipe({name = "r", category = "crafting", ingredients = {}, products = {{name = "x", amount = 1}}})
        local recipe = prototypes.recipe.r
        assert(recipe[case[2]] ~= nil, case[1] .. " recipe lacks " .. case[2])
        H.errors(function() return recipe[case[3]] end, "doesn't contain key " .. case[3], case[1] .. " recipe exposes " .. case[3])
    end
end)

H.test("GUI mock resolves children by name and rejects unknown keys", function()
    local root = H.gui_root({type = "flow"})
    local child = root.add{type = "label", name = "hello", caption = "hi"}
    H.equal(root.hello, child, "child by name")
    H.equal(child.player_index, 1, "inherited player_index")
    H.errors(function() return root.nonexistent end, "LuaGuiElement doesn't contain key nonexistent", "unknown key")
end)

H.done("test_harness")
