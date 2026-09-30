-- Headless engine measurement for recipe to fluid box bindings, 2026-09-30.
local Lab = require "tests.game.lib.lab"
local Binding = require "logic.bp.box_binding"

local function categories(recipe)
    local value = recipe.categories
    if value then
        local out = {}
        for k, v in pairs(value) do out[#out + 1] = type(k) == "string" and k or (type(v) == "table" and v.name or v) end
        return out
    end
    return {recipe.category}
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
        local surface = Lab.surface()
        local before = surface_count()
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
                            rows[#rows + 1] = string.format("BIND %s recipe=%s fluid=%s role=%s box=%d",
                                machine_name, recipe_name, fluid, entry.role, entry.box)
                        end
                    end
                end
            end
        end
        assert.are_equal(before, surface_count(), "probe leaked an engine surface")
        helpers.write_file("rrc_box_binding.txt", table.concat(rows, "\n") .. "\n")
        assert.is_true(#rows > 2, "measured bindings")
    end)
end)
