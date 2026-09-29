--Twin: one tiny factory written once as data, judged twice (docs/twins.md). This module is the offline half:
--load and check a twin file, turn it into the validator's input, read the validator's verdict, and publish the
--blueprint string the python auditors and the headless builder read.
local Grid = require "logic.bp.grid"

local Twin = {}

Twin.DIRS = {north = Grid.NORTH, east = Grid.EAST, south = Grid.SOUTH, west = Grid.WEST}
Twin.CLASSES = {engine = true, waste = true}
Twin.TRUTHS = {ok = true, defect = true, waste = true}
Twin.CHECKS = {flow_purity = true, rate = true, pickup_drop = true, placeable = true, powered = true, network = true,
    beacon_effect = true, underground_pair = true, fluid_system = true, prototype = true, artifact = true}
Twin.STAGES = {validate = true, preflight = true, artifact = true}
Twin.ROOT = "tests/twins"

--Every twin file under tests/twins, sorted, lib/ and required.lua excluded.
function Twin.list(root)
    root = root or Twin.ROOT
    local pipe = assert(io.popen("find " .. root .. " -name '*.lua' -not -path '*/lib/*' -not -name required.lua | LC_ALL=C sort"))
    local paths = {}
    for line in pipe:lines() do paths[#paths + 1] = line end
    pipe:close()
    return paths
end

local function problem(list, path, text) list[#list + 1] = path .. ": " .. text end

--Schema check. Returns a list of problems; empty means the twin is well formed.
function Twin.check(twin, path)
    local p = {}
    path = path or "?"
    if type(twin) ~= "table" then problem(p, path, "file must return a table"); return p end
    if type(twin.id) ~= "string" or twin.id == "" then problem(p, path, "id missing") end
    if type(twin.rule) ~= "string" then problem(p, path, "rule missing") end
    if not Twin.CLASSES[twin.class] then problem(p, path, "class must be engine|waste, got " .. tostring(twin.class)) end
    if not Twin.TRUTHS[twin.truth] then problem(p, path, "truth must be ok|defect|waste, got " .. tostring(twin.truth)) end
    if not Twin.CHECKS[twin.check] then problem(p, path, "unknown check " .. tostring(twin.check)) end
    if twin.stage ~= nil and not Twin.STAGES[twin.stage] then problem(p, path, "stage must be validate|preflight|artifact") end
    local stage = twin.stage or "validate"
    if stage == "preflight" and type(twin.preflight) ~= "table" then problem(p, path, "preflight stage needs preflight = {snapshot, solver_result, catalog, options}") end
    if stage == "artifact" and type(twin.artifact) ~= "table" then problem(p, path, "artifact stage needs artifact = {artifact, plan, catalog}") end
    if type(twin.codes) ~= "table" then problem(p, path, "codes missing (use {} when clean)") end
    if twin.truth == "ok" and type(twin.codes) == "table" and #twin.codes > 0 then problem(p, path, "truth ok needs codes {}") end
    if twin.truth ~= "ok" and type(twin.codes) == "table" and #twin.codes == 0 then
        problem(p, path, "truth " .. tostring(twin.truth) .. " needs its code in codes") end
    if type(twin.grid) ~= "table" or type(twin.grid.w) ~= "number" or type(twin.grid.h) ~= "number" then problem(p, path, "grid {w,h} missing") end
    if stage == "validate" and (type(twin.entities) ~= "table" or #twin.entities == 0) then problem(p, path, "entities missing") end
    local ids = {}
    for i, e in ipairs(twin.entities or {}) do
        local where = "entity " .. i
        if type(e.id) ~= "string" then problem(p, path, where .. " id missing") elseif ids[e.id] then problem(p, path, where .. " duplicate id " .. e.id) end
        ids[e.id or i] = true
        if type(e.name) ~= "string" then problem(p, path, where .. " name missing") end
        if type(e.kind) ~= "string" then problem(p, path, where .. " kind missing") end
        if type(e.x) ~= "number" or type(e.y) ~= "number" then problem(p, path, where .. " x,y missing") end
        if e.dir ~= nil and Twin.DIRS[e.dir] == nil then problem(p, path, where .. " dir must be north|east|south|west") end
    end
    for i, f in ipairs(twin.feeds or {}) do
        local t = f.tile
        if type(t) ~= "table" then problem(p, path, "feed " .. i .. " tile missing")
        elseif twin.grid and not (t[1] == 0 or t[2] == 0 or t[1] == twin.grid.w - 1 or t[2] == twin.grid.h - 1) then
            problem(p, path, "feed " .. i .. " must sit on grid edge (validator port rule, validate.lua:1655)") end
    end
    return p
end

function Twin.load(path)
    local chunk, err = loadfile(path)
    if not chunk then error("twin " .. path .. ": " .. tostring(err)) end
    local twin = chunk()
    local p = Twin.check(twin, path)
    if #p > 0 then error(table.concat(p, "\n")) end
    twin._path = path
    return twin
end

local function flow_id(name)
    if name:find("/", 1, true) then return name end
    return "item/" .. name
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

--Twin -> Validate.begin input. Validator-native entities: x,y top-left tile, w,h (default 1), dir as Grid value.
function Twin.to_candidate(twin)
    local entities = {}
    for _, e in ipairs(twin.entities or {}) do
        local out = copy(e)
        out.w, out.h = e.w or 1, e.h or 1
        out.dir = e.dir and Twin.DIRS[e.dir] or nil
        out.flows = nil
        if e.flows then
            out.flow_ids = {}
            for i, f in ipairs(e.flows) do out.flow_ids[i] = flow_id(f) end
        end
        entities[#entities + 1] = out
    end
    local input = copy(twin.validator or {})
    input.grid = {w = twin.grid.w, h = twin.grid.h}
    input.entities = entities
    input.catalog = input.catalog or {entity = {}, belt = {items_per_second = 15, lane_items_per_second = 7.5}}
    return input
end

local function unique_sorted(records)
    local seen, codes = {}, {}
    for _, e in ipairs(records or {}) do
        if not seen[e.code] then seen[e.code] = true; codes[#codes + 1] = e.code end
    end
    table.sort(codes)
    return codes
end

--Verdict: sorted unique code list (G2: the exact set is compared). Stage picks the judge:
--validate = Validate.begin/step, preflight = Preflight.check, artifact = Validate.reconcile_artifact.
function Twin.verdict(twin)
    local stage = twin.stage or "validate"
    if stage == "preflight" then
        local Preflight = require "logic.bp.preflight"
        local q = twin.preflight
        return unique_sorted(Preflight.check(copy(q.snapshot), copy(q.solver_result), copy(q.catalog), copy(q.options)))
    end
    local Validate = require "logic.bp.validate"
    if stage == "artifact" then
        local result = Validate.reconcile_artifact(copy(twin.artifact))
        return unique_sorted(result.errors), result
    end
    local state = Validate.begin(Twin.to_candidate(twin))
    local guard = 0
    while not state.done do
        Validate.step(state, {ops = 1000})
        guard = guard + 1
        if guard > 100000 then error("twin " .. tostring(twin.id) .. ": validator did not finish") end
    end
    return unique_sorted(state.errors), state
end

--Blueprint string through the pipeline's own publish path: Serialize (flips inserter dir to pickup,
--logic/bp/serialize.lua:406) then BlueprintString.build. Needs global `helpers` (engine or tests/harness.lua).
function Twin.to_bp(twin)
    local Serialize = require "logic.bp.serialize"
    local BlueprintString = require "logic.bp.blueprint_string"
    local cand = Twin.to_candidate(twin)
    local state = Serialize.begin({entities = cand.entities, catalog = cand.catalog, wires = cand.wires})
    while not state.done do Serialize.step(state, {ops = 1000}) end
    return BlueprintString.build(state.result, "twin " .. tostring(twin.id))
end

function Twin.sorted(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    table.sort(out)
    return out
end

return Twin
