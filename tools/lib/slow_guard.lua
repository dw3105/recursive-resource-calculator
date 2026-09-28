local M = {}
local slots = {profile=true, bytes=true, suite=true, headless=true, ["ckpt-save"]=true, release=true, test=true}
local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close(); return s
end
local function tool_info(tool)
    if tool == "golden generate" or tool == "golden_profile" or tool == "first_stage" then return "profile", "ckpt.lua resume <checkpoint> | one-stage replay" end
    if tool == "bytes_hash" or tool == "gate_sheet" or tool == "measure_sheet" then return "bytes", "merge gate only (RRC_SLOW=bytes:...)" end
    if tool == "tests/run.sh" then return "suite", "single test file (lua5.2 tests/<file>.lua)" end
    if tool == "game_test.sh" then return "headless", "offline Lua test" end
    if tool == "ckpt save" then return "ckpt-save", "reuse an existing checkpoint in tests/fixtures/route_snaps" end
    if tool == "ckpt list" or tool == "ckpt uninterrupted" then return "profile", "ckpt.lua resume <checkpoint> | one-stage replay" end
    if tool == "speed_probe" then return "profile", "one-stage replay" end
    return "profile", "fast rung: one-stage replay"
end
local function refuse(tool, hint)
    io.stderr:write("SLOW-REFUSED " .. tool .. " -> fast rung: " .. hint .. "\n")
    os.exit(7)
end
function M.check(tool, input)
    if _G.__rrc_slow_guard_checked then return true end
    local default, hint = tool_info(tool)
    local spec = os.getenv("RRC_SLOW") or ""
    local slot, reason = spec:match("^([^:]+):(.*)$")
    if not slot or not slots[slot] or #reason < (slot == "test" and 3 or 20) then refuse(tool, hint) end
    if input then
        input = input:gsub("\\", "/")
        if not input:match("/") and (tool == "first_stage" or tool == "golden_profile" or tool:match("^ckpt ")) then
            input = "tests/golden/cases/" .. input .. "/prepared_input.json"
        end
    end
    if slot == "test" and input and input:match("^tests/golden/cases/") then refuse(tool, hint) end
    local wave_path = os.getenv("RRC_WAVE_FILE") or ((os.getenv("HOME") or ".") .. "/.cache/rrc/wave")
    local wave = read(wave_path); wave = wave and wave:gsub("[%s]+$", "") or "unset"
    local budget_text = read("tools/slow_budget.json") or "{}"
    local budgets = {}; for k,v in budget_text:gmatch('"([^"]+)"%s*:%s*(-?%d+)') do budgets[k] = tonumber(v) end
    local budget = budgets[slot]
    if budget == nil then budget = budgets[default] end
    local ledger_path = os.getenv("RRC_SLOW_LEDGER") or ((os.getenv("HOME") or ".") .. "/.cache/rrc/slow_ledger.tsv")
    local previous = read(ledger_path) or ""
    local count = 0
    for line in previous:gmatch("[^\n]+") do
        local _, old_wave, old_slot = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)")
        if old_wave == wave and old_slot == slot then count = count + 1 end
    end
    if budget and budget >= 0 and count >= budget then refuse(tool, "budget used") end
    local dir = ledger_path:match("^(.*)/[^/]+$")
    if dir then os.execute("mkdir -p " .. string.format("%q", dir)) end
    local f = assert(io.open(ledger_path, "a"))
    f:write(os.date("!%Y-%m-%dT%H:%M:%SZ"), "\t", wave, "\t", slot, "\t", tool, "\t", reason, "\t", os.getenv("HOSTNAME") or "unknown", "\n"); f:close()
    _G.__rrc_slow_guard_checked = true
    return true
end
return M
