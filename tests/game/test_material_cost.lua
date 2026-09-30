-- Headless engine probe: reports raw material cost for the entities Catalog can place.
local Catalog = require "logic.catalog"

describe("material cost", function()
    it("prints measured catalog material costs", function()
        if RRC_OFFLINE then return end
        local catalog = Catalog.build(1, {
            belt = {base = "transport-belt", underground = "underground-belt", splitter = "splitter"},
            pipe = {base = "pipe", underground = "pipe-to-ground"},
        })
        local names = {}
        for name in pairs(catalog.material or {}) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do print(string.format("MATERIAL %s %.4f", name, catalog.material[name])) end
        assert.is_true((catalog.material["transport-belt"] or 0) > 0)
        assert.is_true((catalog.material["underground-belt"] or 0) > (catalog.material["transport-belt"] or 0))
        assert.is_true((catalog.material.splitter or 0) > (catalog.material["underground-belt"] or 0))
    end)
end)
