-- Headless engine probe: raw material cost (CONTEXT.md Material cost) for every entity kind a blueprint places.
-- Integrator (round 53, 2026-09-30) runs it on 2.0.77 + 2.1.20 and copies the MATERIAL lines into
-- tests/fixtures/material_cost_<version>.txt; offline tools score delivered bytes with those tables.
local Catalog = require "logic.catalog"

local KINDS = {"transport-belt", "underground-belt", "splitter", "pipe", "pipe-to-ground", "assembling-machine",
    "furnace", "rocket-silo", "beacon", "inserter", "electric-pole"}

describe("material cost", function()
    it("prints measured catalog material costs", function()
        if RRC_OFFLINE then return end
        local entity = {}
        for _, kind in ipairs(KINDS) do
            for name in pairs(prototypes.get_entity_filtered({{filter = "type", type = kind}})) do
                entity[name] = {etype = kind}
            end
        end
        local catalog = {entity = entity}
        Catalog.fill_material(catalog)
        local names = {}
        for name in pairs(catalog.material or {}) do names[#names + 1] = name end
        table.sort(names)
        local lines = {}
        for _, name in ipairs(names) do lines[#lines + 1] = string.format("MATERIAL %s %.4f", name, catalog.material[name]) end
        helpers.write_file("rrc_material_cost.txt", table.concat(lines, "\n") .. "\n")
        assert.is_true((catalog.material["transport-belt"] or 0) == 1.5)
        assert.is_true((catalog.material["underground-belt"] or 0) == 8.75)
        assert.is_true((catalog.material["pipe"] or 0) == 1)
    end)
end)
