local H = require "tests.harness"
local ReasonCodes = require "logic.bp.reason_codes"

local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

H.test("validator violation registry exactly matches emitted validator codes", function()
    local source = read("logic/bp/validate.lua")
    local emitted = {}
    for code in source:gmatch('"(BP_V_[A-Z_]+)"') do emitted[code] = true end
    local registered = {}
    for _, code in ipairs(ReasonCodes.VIOLATION) do registered[code] = true end
    local missing, stale = {}, {}
    for code in pairs(emitted) do if not registered[code] then missing[#missing + 1] = code end end
    for code in pairs(registered) do if not emitted[code] then stale[#stale + 1] = code end end
    table.sort(missing); table.sort(stale)
    H.deep_equal(missing, {}, "validator codes missing from ReasonCodes.VIOLATION")
    H.deep_equal(stale, {}, "registered violations never emitted by validate.lua")
end)

H.done("test_reason_codes_registry")
