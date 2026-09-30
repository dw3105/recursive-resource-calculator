-- Headless engine measurement for recipe to fluid box bindings, 2026-09-30.
local Lab = require "tests.game.lib.lab"
local Binding = require "logic.bp.box_binding"

--2.0 LuaRecipePrototype.category; 2.1 has only categories. An engine object errors on a missing key (headless
--2.0.77, 2026-09-30), so both reads are guarded.
local function categories(recipe)
    local okc, cat = pcall(function() return recipe.category end)
    if okc and cat then return {cat} end
    local out = {}
    local okl, list = pcall(function() return recipe.categories end)
    for k, v in pairs(okl and list or {}) do out[#out + 1] = type(k) == "string" and k or (type(v) == "table" and v.name or v) end
    return out
end
local function surface_count()
    local n = 0
    for _ in pairs(game.surfaces) do n = n + 1 end
    return n
end

describe("box binding", function()
    it("records engine recipe fluid box bindings", function()
        if RRC_OFFLINE then return end
        local rows = {"# Box binding fixture, engine measured 2026-09-30", "# version " .. script.active_mods.base}
        local body = {}
        --Same fresh, ungenerated scratch surface generation.lua probes on in game.
        local surface = Binding.scratch_surface(game)
        assert.is_true(surface ~= nil, "scratch surface")
        for machine_name, machine in pairs(prototypes.entity) do
            if machine.crafting_categories then
                for recipe_name, recipe in pairs(prototypes.recipe) do
                    local fits = false
                    for _, category in ipairs(categories(recipe)) do
                        if machine.crafting_categories and machine.crafting_categories[category] then fits = true end
                    end
                    local has_fluid = false
                    for _, list in ipairs({recipe.ingredients or {}, recipe.products or {}}) do
                        for _, item in ipairs(list) do if item.type == "fluid" then has_fluid = true end end
                    end
                    if fits and has_fluid and #(machine.fluidbox_prototypes or {}) > 0 then
                        local binding = Binding.probe(surface, machine, recipe)
                        for fluid, entry in pairs(binding) do
                            --A merged runtime box binds one fluid to several prototype boxes: one line per box.
                            for _, box in ipairs(entry.boxes or {entry.box}) do
                                body[#body + 1] = string.format("BIND %s recipe=%s fluid=%s role=%s box=%d",
                                    machine_name, recipe_name, fluid, entry.role, box)
                            end
                        end
                    end
                end
            end
        end
        table.sort(body)
        for _, row in ipairs(body) do rows[#rows + 1] = row end
        game.delete_surface(surface)
        helpers.write_file("rrc_box_binding.txt", table.concat(rows, "\n") .. "\n")
        assert.is_true(#rows > 2, "measured bindings")
    end)
end)
