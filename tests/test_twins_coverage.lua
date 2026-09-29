local H = require "tests.harness"
local Twin = require "tests.twins.lib.twin"

--Round 48 D3: every code the mod can emit, and every auditor count, is covered by a clean twin and a breach
--twin, unless tests/twins/required.lua marks it player or contract. TWIN_OWNER=L279 checks one lane's rows only.
local owner = os.getenv("TWIN_OWNER")
local rows = dofile("tests/twins/required.lua")

local function emitted()
    local found = {}
    for _, cmd in ipairs({"grep -ohE '\"BP_(V|REJ)_[A-Z_]+\"' logic/bp/validate.lua logic/bp/preflight.lua logic/bp/reason_codes.lua"}) do
        local pipe = assert(io.popen(cmd))
        for line in pipe:lines() do found[line:sub(2, -2)] = true end
        pipe:close()
    end
    return found
end

local listed = {}
for _, row in ipairs(rows) do listed[row[1]] = row end

H.test("every emitted or registered code has a row", function()
    local missing = {}
    for code in pairs(emitted()) do if not listed[code] then missing[#missing + 1] = code end end
    table.sort(missing)
    H.deep_equal(missing, {}, "codes with no row in tests/twins/required.lua")
end)
H.test("every row names a code the mod still has", function()
    local codes, stale = emitted(), {}
    for _, row in ipairs(rows) do
        if not row[1]:match("^audit:") and not codes[row[1]] then stale[#stale + 1] = row[1] end
    end
    table.sort(stale)
    H.deep_equal(stale, {}, "rows whose code is gone")
end)

local clean, breach = {}, {}
for _, path in ipairs(Twin.list()) do
    local twin = Twin.load(path)
    local bucket = twin.truth == "ok" and clean or breach
    bucket[twin.rule] = (bucket[twin.rule] or 0) + 1
    for tool, keys in pairs(twin.audit or {}) do
        for key, value in pairs(keys) do
            local name = "audit:" .. tool .. ":" .. key
            local b = value > 0 and breach or clean
            b[name] = (b[name] or 0) + 1
        end
    end
end

for _, row in ipairs(rows) do
    local code, lane, class = row[1], row[2], row[3]
    if class == "twin" and (owner == nil or owner == lane) then
        H.test(lane .. " " .. code .. " has a clean and a breach twin", function()
            H.equal((clean[code] or 0) > 0, true, code .. " clean twin (truth ok, or audit key pinned 0)")
            H.equal((breach[code] or 0) > 0, true, code .. " breach twin (truth defect|waste, or audit key pinned > 0)")
        end)
    end
end
H.done("test_twins_coverage")
