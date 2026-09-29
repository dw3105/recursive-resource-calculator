--Round 48 D2 + D5: the facts our fixtures and constants assume, compared with the live game.
--D2: every catalog leaf the fixtures of this profile carry (tests/fixtures/engine_facts/catalog_facts.tsv, lane 281)
--    against Catalog.build on the running game for the same names. A path the live catalog does not produce is
--    reported apart from a value that differs.
--D5: every hardcoded engine constant (constants.json) against its prototype field. expect "model" = a formula of
--    ours with no single prototype field; listed, never compared.
--Profile: player facts run only with the player's mods loaded (RRC_PROFILE=player), vanilla facts only without.
local Catalog = require "logic.catalog"
local ok_p, FACTS_PLAYER = pcall(require, "tests.game.fixtures.facts_player")
local ok_v, FACTS_VANILLA = pcall(require, "tests.game.fixtures.facts_vanilla")
local ok_c, CONSTANTS = pcall(require, "tests.game.fixtures.constants")

local function player_profile() return script.active_mods["Moshine"] ~= nil end

local function decode(text)
    local ok, t = pcall(helpers.json_to_table, "[" .. text .. "]")
    if ok and type(t) == "table" then return t[1], true end
    return text, false
end

local function same(a, b)
    if type(a) == "number" and type(b) == "number" then
        return math.abs(a - b) <= 1e-6 * math.max(1, math.abs(a), math.abs(b))
    end
    return a == b
end

local function flatten(value, prefix, out)
    if type(value) == "table" then
        for k, v in pairs(value) do flatten(v, prefix == "" and tostring(k) or (prefix .. "." .. tostring(k)), out) end
    else
        out[prefix] = value
    end
    return out
end

--Names and descriptors the fixtures referenced, read back from their own fact paths.
local function requests_from(rows)
    local sets = {entity = {}, item = {}, recipe = {}, fluid = {}, module = {}, quality = {}}
    local families = {}
    for _, row in ipairs(rows) do
        local head, name, rest = row.path:match("^([%w_]+)%.([^%.]+)%.?(.*)$")
        if head and sets[head] then sets[head][name] = true
        elseif head and (head == "belt" or head == "pipe" or head == "inserter" or head == "long_inserter" or head == "pole" or head == "robo") then
            families[head] = families[head] or {}
            if rest == "" then
                local value = decode(row.value)
                if type(value) ~= "table" then families[head][name] = value end
            end
        end
    end
    local function keys(t) local out = {}; for k in pairs(t) do out[#out + 1] = k end; table.sort(out); return out end
    local options = {entities = keys(sets.entity), item_names = keys(sets.item), recipe_names = keys(sets.recipe),
        fluid_names = keys(sets.fluid), module_names = keys(sets.module), quality_names = keys(sets.quality)}
    for family, descriptor in pairs(families) do options[family] = descriptor end
    return options
end

local function parse(text)
    local rows = {}
    for line in text:gmatch("[^\n]+") do
        local path, value = line:match("^([^\t]+)\t(.*)$")
        if path then rows[#rows + 1] = {path = path, value = value} end
    end
    return rows
end

describe("facts", function()
    it("catalog facts match the live game", function()
        if RRC_OFFLINE then return end
        local text = player_profile() and (ok_p and FACTS_PLAYER) or (ok_v and FACTS_VANILLA)
        assert(type(text) == "string", "no embedded facts for this profile")
        local rows = parse(text)
        local live = flatten(Catalog.build(1, requests_from(rows)), "", {})
        local expected = {}
        for _, row in ipairs(rows) do
            expected[row.path] = expected[row.path] or {}
            table.insert(expected[row.path], (decode(row.value)))
        end
        --Only catalog sections are compared. A fact about a prototype this game does not have (the harness's
        --invented "assembler", "ore-washer") describes a mock world: counted as FICTION, never compared.
        local SECTIONS = {entity = prototypes.entity, item = prototypes.item, recipe = prototypes.recipe, fluid = prototypes.fluid,
            module = prototypes.item, quality = prototypes.quality, beacon = prototypes.entity}
        local FAMILY = {belt = true, pipe = true, inserter = true, long_inserter = true, pole = true, robo = true}
        local absent, differ, fiction, checked = {}, {}, {}, 0
        for path, values in pairs(expected) do
            local head, name = path:match("^([%w_]+)%.([^%.]+)")
            local store = head and SECTIONS[head]
            --Family blocks (belt, inserter, pole ...) are per-sheet choices that differ between fixtures, and *_bonus
            --fields are the player's research state: neither is a prototype fact. The prototypes behind the choices are
            --compared through entity.* anyway.
            if not store or path:find("_bonus$") then goto continue end
            if store and store[name] == nil then fiction[head .. "." .. name] = true; goto continue end
            checked = checked + 1
            local got = live[path]
            if got == nil then absent[#absent + 1] = path
            else
                local match = false
                for _, v in ipairs(values) do if same(v, got) then match = true end end
                if not match then differ[#differ + 1] = path .. " fixture=" .. serpent.line(values) .. " live=" .. serpent.line(got) end
            end
            ::continue::
        end
        local fiction_list = {}
        for k in pairs(fiction) do fiction_list[#fiction_list + 1] = k end
        table.sort(fiction_list)
        log("FACTS-FICTION " .. #fiction_list .. " invented prototypes: " .. table.concat(fiction_list, ", "))
        table.sort(absent); table.sort(differ)
        log("FACTS profile=" .. (player_profile() and "player" or "vanilla") .. " checked=" .. checked .. " absent=" .. #absent .. " differ=" .. #differ)
        for i = 1, #differ do log("FACTS-DIFFER " .. differ[i]) end
        for i = 1, #absent do log("FACTS-ABSENT " .. absent[i]) end
        assert(#differ == 0 and #absent == 0, string.format("%d of %d fixture facts differ from the live game, %d absent (factorio-current.log FACTS-*); first: %s",
            #differ, checked, #absent, tostring(differ[1] or absent[1])))
    end)

    it("hardcoded constants match prototypes", function()
        if RRC_OFFLINE then return end
        assert(ok_c, "constants not embedded")
        local list = helpers.json_to_table(CONSTANTS)
        local bad, model = {}, {}
        for _, c in ipairs(list) do
            local p = c.probe
            if p.expect == "model" then model[#model + 1] = c.name
            elseif p.profile == "vanilla" and player_profile() then model[#model + 1] = c.name .. " (vanilla fallback, not compared in the player profile)"
            elseif p.kind == "entity" and prototypes.entity[p.name] == nil and not player_profile() then
                model[#model + 1] = c.name .. " (mod entity, player profile only)"
            else
                local proto = prototypes[p.kind] and prototypes[p.kind][p.name]
                local got
                if proto then
                    --2.0 moved some facts behind methods (supply_area_distance -> get_supply_area_distance()).
                    local ok, v = pcall(function() return proto[p.field] end)
                    if not ok or v == nil then ok, v = pcall(function() return proto["get_" .. p.field]() end) end
                    got = ok and v or nil
                end
                local pass
                if p.expect == "tile_size" then pass = got == c.value
                elseif p.expect == "offset_distance" then
                    pass = type(got) == "table" and same(math.max(math.abs(got.x or got[1] or 0), math.abs(got.y or got[2] or 0)), c.value)
                else pass = same(got, c.value) end
                if not pass then bad[#bad + 1] = c.name .. " (" .. c.file .. ":" .. c.line .. ") ours=" .. serpent.line(c.value) .. " engine " .. p.kind .. "." .. tostring(p.name) .. "." .. p.field .. "=" .. serpent.line(got) end
            end
        end
        table.sort(bad)
        for _, line in ipairs(bad) do log("CONST-DIFFER " .. line) end
        log("CONST model-only: " .. table.concat(model, ", "))
        assert(#bad == 0, #bad .. " constants differ from the engine: " .. table.concat(bad, " | "))
    end)
end)
