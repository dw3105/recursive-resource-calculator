--One twin's published blueprint string (round 48, docs/twins.md).
--  lua5.2 tools/twin_bp.lua <twin.lua>           blueprint string on stdout
--  lua5.2 tools/twin_bp.lua --audit <twin.lua>   the twin's pinned auditor counts, "<tool> <key> <value>" per line
--  lua5.2 tools/twin_bp.lua --catalog <twin.lua> {"catalog": ...} JSON for lane_sim.py --input (recipes, sizes)
--Published through the pipeline's own path (Serialize + BlueprintString), so the auditors read what a sheet ships.
package.path = "./?.lua;" .. package.path
local mode = (arg[1] == "--audit" or arg[1] == "--catalog") and arg[1] or nil
local audit = mode == "--audit"
local path = assert(mode and arg[2] or arg[1], "usage: lua5.2 tools/twin_bp.lua [--audit|--catalog] <twin.lua>")
local Twin = require "tests.twins.lib.twin"
local twin = Twin.load(path)
if audit then
    for tool, keys in pairs(twin.audit or {}) do
        for key, value in pairs(keys) do print(tool .. " " .. key .. " " .. tostring(value)) end
    end
    return
end
if mode == "--catalog" then
    local H = require "tests.harness"
    if rawget(_G, "helpers") == nil then H.new_world() end
    io.write(helpers.table_to_json({catalog = Twin.to_candidate(twin).catalog}), "\n")
    return
end
if (twin.stage or "validate") ~= "validate" then print("NO-BP " .. twin.stage); return end
local H = require "tests.harness"
if rawget(_G, "helpers") == nil then H.new_world() end
io.write(Twin.to_bp(twin), "\n")
