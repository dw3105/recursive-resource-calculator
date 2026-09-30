-- Plain contract data and fixture checks shared by the Turn and Flip probe.
local M = {}
M.CASES = {
    {machine = "assembling-machine-1", recipe = "electronic-circuit"},
    {machine = "assembling-machine-2", recipe = "empty-water-barrel"},
    {machine = "chemical-plant", recipe = "plastic-bar"},
    {machine = "chemical-plant", recipe = "sulfuric-acid"},
    {machine = "oil-refinery", recipe = "advanced-oil-processing"},
    {machine = "foundry", recipe = "casting-iron"},
    {machine = "foundry", recipe = "iron-ore-melting"},
    {machine = "electromagnetic-plant", recipe = "electrolyte"},
    {machine = "cryogenic-plant", recipe = "fluoroketone"},
    {machine = "biochamber", recipe = "rocket-fuel"},
}
function M.ids()
    local ids = {}
    for _, row in ipairs(M.CASES) do
        for _, n in ipairs({1, 4}) do ids[#ids + 1] = row.machine .. "-" .. row.recipe .. "-" .. n end
    end
    table.sort(ids)
    return ids
end
function M.target_rate(one_machine_rate, n) return n * one_machine_rate * 0.999 end
function M.check_fixture(value)
    if type(value) ~= "table" or type(value.version) ~= "string" or value.version == ""
        or type(value.cases) ~= "table" then return false end
    for _, prepared in pairs(value.cases) do
        if type(prepared) ~= "table" or type(prepared.catalog) ~= "table"
            or type(prepared.settings) ~= "table" or prepared.settings.input_edge ~= "left"
            or prepared.settings.output_edge ~= "top" then return false end
    end
    return true
end
return M
