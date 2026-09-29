--Round 48 D6: every member the offline mock (tests/harness.lua) exposes on the vanilla-named world
--(tests/game/lib/vanilla_world.lua) exists on the real object with the same type; for prototypes, scalar values equal
--the live ones too (the mock claims vanilla facts: assembling-machine-1 crafting_speed 0.5, ...).
--Manifest: tests/fixtures/engine_facts/mock_members.json (tools/fixture_facts.lua --mock), embedded by game_stage.
local ok_m, MEMBERS = pcall(require, "tests.game.fixtures.mock_members")

local function version()
    local v = script.active_mods.base or "2.0"
    return v:match("^(%d+%.%d+)")
end

local GETTERS = {
    LuaEntityPrototype = function(name) return prototypes.entity[name] end,
    LuaItemPrototype = function(name) return prototypes.item[name] end,
    LuaRecipePrototype = function(name) return prototypes.recipe[name] end,
    LuaQualityPrototype = function(name) return prototypes.quality[name] end,
    LuaRecipe = function(name) return game.forces.player.recipes[name] end,
    LuaBootstrap = function() return script end,
    LuaHelpers = function() return helpers end,
    LuaForce = function(name) return game.forces[name ~= "" and name or "player"] end,
}

describe("mock_parity", function()
    it("every mocked member exists on the real object with the same type", function()
        if RRC_OFFLINE then return end
        assert(ok_m, "mock_members not embedded")
        local rows = helpers.json_to_table(MEMBERS)
        local fv = version()
        local missing, wrong_type, wrong_value, skipped, checked = {}, {}, {}, {}, 0
        for _, r in ipairs(rows) do
            local in_shape = false
            for _, s in ipairs(r.shapes or {}) do if s == fv then in_shape = true end end
            local get = GETTERS[r.class]
            if not in_shape then
            elseif not get then skipped[r.class] = (skipped[r.class] or 0) + 1
            else
                local obj = get(r.name)
                local label = r.class .. "[" .. r.name .. "]." .. r.member
                if obj == nil then missing[#missing + 1] = label .. " (no such object)"
                else
                    checked = checked + 1
                    local ok, v = pcall(function() return obj[r.member] end)
                    if not ok then missing[#missing + 1] = label
                    elseif r.type ~= "nil" and v ~= nil and type(v) ~= r.type then
                        wrong_type[#wrong_type + 1] = label .. " mock " .. r.type .. " engine " .. type(v)
                    elseif r.value ~= "" and r.class:find("Prototype$") and v ~= nil and type(v) ~= "table" and type(v) ~= "userdata" then
                        local same = tostring(v) == r.value
                        if type(v) == "number" and tonumber(r.value) then same = math.abs(v - tonumber(r.value)) <= 1e-6 * math.max(1, math.abs(v)) end
                        if not same then wrong_value[#wrong_value + 1] = label .. " mock " .. r.value .. " engine " .. tostring(v) end
                    end
                end
            end
        end
        table.sort(missing); table.sort(wrong_type); table.sort(wrong_value)
        for _, l in ipairs(missing) do log("MOCK-MISSING " .. l) end
        for _, l in ipairs(wrong_type) do log("MOCK-TYPE " .. l) end
        for _, l in ipairs(wrong_value) do log("MOCK-VALUE " .. l) end
        log("MOCK-PARITY checked=" .. checked .. " missing=" .. #missing .. " type=" .. #wrong_type .. " value=" .. #wrong_value .. " skipped=" .. serpent.line(skipped))
        assert(#missing + #wrong_type + #wrong_value == 0, string.format("mock parity: %d missing, %d wrong type, %d wrong value (factorio-current.log MOCK-*); first: %s",
            #missing, #wrong_type, #wrong_value, tostring(missing[1] or wrong_type[1] or wrong_value[1])))
    end)
end)
