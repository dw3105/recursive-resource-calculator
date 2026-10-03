-- Stable text view of turn-trial search records; kept free of search/runtime dependencies.
local Rows = {}

local function value(v)
    if v == nil then return "-" end
    return tostring(v)
end

function Rows.format(case_id, trial)
    local lines = {}
    if type(trial) ~= "table" then return lines end
    for _, row in ipairs(trial.rows or {}) do
        lines[#lines + 1] = string.format("TRIAL case=%s block=%s rule=%s pose=%s result=%s code=%s material=%s area=%s",
            value(case_id), value(row.block), value(row.rule), value(row.pose), value(row.result), value(row.code),
            type(row.material) == "number" and string.format("%.1f", row.material) or "-", value(row.area))
    end
    lines[#lines + 1] = string.format("TRIALSUM case=%s tried=%s won=%s fails=%s ticks_before=%s ticks=%s",
        value(case_id), value(trial.tried), value(trial.won), value(trial.fails), value(trial.ticks_before), value(trial.ticks))
    return lines
end

if ... == "tools.turn_trial_rows" then return Rows end

local function read(path)
    local f = assert(io.open(path, "rb")); local text = f:read("*a"); f:close(); return text
end
local H = require "tests.harness"
H.new_world("2.0")
for i = 1, #arg do
    local path = arg[i]
    local ok, decoded = pcall(helpers.json_to_table, read(path))
    if not ok then error("cannot parse " .. path .. ": " .. tostring(decoded)) end
    local result = decoded and decoded.result
    local trial = result and result.search and result.search.trial
    local case_id = path:match("([^/]+)%.r%.json$") or path:match("([^/]+)%.json$") or path
    for _, line in ipairs(Rows.format(case_id, trial)) do print(line) end
end
