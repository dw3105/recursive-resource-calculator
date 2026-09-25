--Player, 2026-09-25: "calcite is not unique! there must be no hardcoding!" Layout and GUI code must never name a
--game item or fluid: a rule written for one flow is wrong for every other one. This scans every code line (comments
--excluded) of logic/, gui/ and control.lua for the item and fluid names the golden sheets use.
local H = require "tests.harness"

local NAMES = {"calcite", "iron-ore", "copper-ore", "iron-plate", "copper-plate", "iron-gear-wheel", "copper-cable",
    "electronic-circuit", "molten-iron", "molten-copper", "automation-science-pack", "logistic-science-pack", "steel-plate",
    "stone", "coal", "water", "crude-oil", "petroleum-gas", "sulfuric-acid", "lava"}

local function lua_files()
    local list = {"control.lua"}
    local pipe = io.popen("find logic gui -name '*.lua' | sort")
    for path in pipe:lines() do list[#list + 1] = path end
    pipe:close()
    return list
end

local function code_part(line)
    local code = line:gsub("%-%-.*$", "")
    return (code:gsub('"[^"]*[Cc]omment[^"]*"', ""))
end

H.test("NI1 no code line names a game item or fluid", function()
    local found = {}
    for _, path in ipairs(lua_files()) do
        local number = 0
        for line in io.lines(path) do
            number = number + 1
            local code = code_part(line)
            for _, name in ipairs(NAMES) do
                if code:find('["\'/]' .. name:gsub("%-", "%%-") .. '["\']') then
                    found[#found + 1] = path .. ":" .. number .. " " .. name
                end
            end
        end
    end
    H.equal(table.concat(found, "; "), "", "item and fluid names stay in data, never in code")
end)

H.done("test_no_item_names")
