--Electrical demand: which placed entities ask for a pole, and which never do.
--Ordinary belts and pipes carry no energy source. Counting them as consumers inflates the pole problem by the
--whole length of every route, so this file pins the rule the validator already uses: explicit entity field,
--then catalog field, then entity kind.
local H = require "tests.harness"
local Search = require "logic.bp.search"

local function catalog()
    return {entity = {
        ["assembling-machine-2"] = {kind = "machine", needs_power = true, tile_w = 3, tile_h = 3},
        ["beacon"] = {kind = "beacon", needs_power = true, tile_w = 3, tile_h = 3},
        ["inserter"] = {kind = "inserter", needs_power = true, tile_w = 1, tile_h = 1},
        ["transport-belt"] = {kind = "transport", needs_power = false, tile_w = 1, tile_h = 1},
        ["underground-belt"] = {kind = "transport", needs_power = false, tile_w = 1, tile_h = 1},
        ["splitter"] = {kind = "transport", needs_power = false, tile_w = 2, tile_h = 1},
        ["pipe"] = {kind = "transport", needs_power = false, tile_w = 1, tile_h = 1},
        ["roboport"] = {kind = "roboport", needs_power = true, tile_w = 4, tile_h = 4},
        ["powered-belt"] = {kind = "transport", needs_power = true, tile_w = 1, tile_h = 1},
        ["mystery-belt"] = {kind = "transport", tile_w = 1, tile_h = 1},
    }}
end

local function plan()
    return {steps = {{step_id = "make", power_w = 150000}}}
end

local function ids(consumers)
    local result = {}
    for _, consumer in ipairs(consumers) do result[#result + 1] = consumer.id end
    table.sort(result)
    return result
end

local function belts(count, name)
    local result = {}
    for index = 1, count do
        result[#result + 1] = {id = "r:" .. index, name = name or "transport-belt", x = index, y = 0, w = 1, h = 1}
    end
    return result
end

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " PW1 ordinary transport is no electrical consumer", function()
        local entities = {
            {id = "m:1", name = "assembling-machine-2", step_id = "make", x = 0, y = 0, w = 3, h = 3},
            {id = "r:belt", name = "transport-belt", x = 4, y = 0, w = 1, h = 1},
            {id = "r:ug", name = "underground-belt", x = 5, y = 0, w = 1, h = 1, type = "input"},
            {id = "r:split", name = "splitter", x = 6, y = 0, w = 2, h = 1},
            {id = "r:pipe", name = "pipe", x = 8, y = 0, w = 1, h = 1},
        }
        H.deep_equal(ids(Search.power_consumers(entities, plan(), catalog())), {"m:1"},
            "only the machine asks for power")
    end)

    H.test(shape .. " PW2 a hundred belt segments add no consumer", function()
        local entities = belts(100)
        entities[#entities + 1] = {id = "m:1", name = "assembling-machine-2", step_id = "make",
            x = 0, y = 4, w = 3, h = 3}
        H.equal(#Search.power_consumers(entities, plan(), catalog()), 1,
            "a hundred belts leave the consumer count at one")
    end)

    H.test(shape .. " PW3 declared powered transport is a consumer", function()
        local entities = {
            {id = "r:powered", name = "powered-belt", x = 1, y = 0, w = 1, h = 1},
            {id = "r:plain", name = "transport-belt", x = 2, y = 0, w = 1, h = 1},
        }
        H.deep_equal(ids(Search.power_consumers(entities, plan(), catalog())), {"r:powered"},
            "the modded powered belt asks for power and the plain belt does not")
    end)

    H.test(shape .. " PW4 an entity field overrides its catalog entry", function()
        local entities = {
            {id = "r:on", name = "transport-belt", x = 1, y = 0, w = 1, h = 1, needs_power = true},
            {id = "m:off", name = "assembling-machine-2", step_id = "make", x = 4, y = 0, w = 3, h = 3,
                needs_power = false},
        }
        H.deep_equal(ids(Search.power_consumers(entities, plan(), catalog())), {"r:on"},
            "the explicit entity field decides both ways")
    end)

    H.test(shape .. " PW5 machines, beacons and inserters stay consumers and roboports stay out", function()
        local entities = {
            {id = "m:1", name = "assembling-machine-2", step_id = "make", x = 0, y = 0, w = 3, h = 3},
            {id = "m:beacon", name = "beacon", x = 4, y = 0, w = 3, h = 3},
            {id = "m:ins", name = "inserter", x = 8, y = 0, w = 1, h = 1},
            {id = "k:1", name = "roboport", x = 10, y = 0, w = 4, h = 4},
        }
        H.deep_equal(ids(Search.power_consumers(entities, plan(), catalog())), {"m:1", "m:beacon", "m:ins"},
            "the roboport is excluded and the three powered kinds are kept")
    end)

    H.test(shape .. " PW6 transport of unknown power behaviour asks for no pole", function()
        local entities = {{id = "r:mystery", name = "mystery-belt", x = 1, y = 0, w = 1, h = 1}}
        H.equal(#Search.power_consumers(entities, plan(), catalog()), 0,
            "transport without declared power is left out rather than assumed powered")
    end)
end

H.done("test_power_demand")
