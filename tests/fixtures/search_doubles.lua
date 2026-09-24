--Stage doubles for the one-pass pipeline (contract docs/contracts/pipeline_r29.md C9). Every double records what it
--was given, so a test can read the order of stages and the fields the search passed to each.
local Groups = require "logic.bp.groups"
local Pack = require "logic.bp.pack"
local Power = require "logic.bp.power"
local Route = require "logic.bp.route"
local Validate = require "logic.bp.validate"

local M = {}

local function stage() return {done = false, ok = nil, result = nil, cursor = {}, progress = {}} end
local function finish_one(state, budget)
    if budget.ops > 0 then budget.ops = budget.ops - 1; state.done = true; if state.ok == nil then state.ok = true end end
    return state
end

--options.validate_fails = number of validate runs that fail before one passes (nil = never fails)
--options.pack_no_fit = number of pack runs that fail with BP_P_NO_FIT first
function M.run(options, callback)
    local log = {calls = {}, groups = {}, pack = {}, route = {}, tidy = {}, power = {}, validate = {}}
    local function call(name) log.calls[#log.calls + 1] = name end
    local saved = {}
    local function swap(module, key, fn) saved[#saved + 1] = {module, key, module[key]}; module[key] = fn end
    local validate_runs, pack_runs = 0, 0
    swap(Groups, "begin", function(input) call("groups"); log.groups[#log.groups + 1] = {ring_bump = input.ring_bump}; return stage() end)
    swap(Groups, "step", function(state, budget)
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            state.result = {candidates = {{id = "one", blocks = {{id = "b", block_id = "b", w = 1, h = 1,
                ports = {{port_id = "p", step_id = "one", flow_id = "f", role = "in"}}}}}}}
            state.done, state.ok = true, true
        end
        return state
    end)
    swap(Groups, "materialize", function(block, placement)
        return {envelope = {x = placement.x, y = placement.y, w = block.w, h = block.h, dir = 0},
            entities = {{id = "m:" .. block.id, name = "assembler", x = placement.x, y = placement.y, w = 1, h = 1}}, ports = {}}
    end)
    swap(Pack, "begin", function(input)
        call("pack"); pack_runs = pack_runs + 1
        log.pack[#log.pack + 1] = {zone_blockers = input.zone_blockers, links = input.links, area = input.area}
        local s = stage(); s.block = input.blocks[1]
        if options.pack_no_fit and pack_runs <= options.pack_no_fit then s.no_fit = true end
        return s
    end)
    swap(Pack, "step", function(state, budget)
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            if state.no_fit then state.done, state.ok, state.errors = true, false, {{code = "BP_P_NO_FIT"}}
            else
                state.result = {placements = {{block_id = state.block.id, x = 0, y = 0, w = 1, h = 1}}}
                state.done, state.ok = true, true
            end
        end
        return state
    end)
    local function empty() local s = stage(); s.result = {entities = {}, wires = {}, segments = {}, bindings = {}}; return s end
    swap(Route, "begin", function(input) call("route"); log.route[#log.route + 1] = {tidy = input.tidy}; return empty() end)
    swap(Route, "step", finish_one)
    swap(Route, "tidy_begin", function(done_state, opts) call("tidy"); log.tidy[#log.tidy + 1] = opts or {}; return empty() end)
    swap(Route, "tidy_step", finish_one)
    swap(Power, "begin", function(input) call("power"); log.power[#log.power + 1] = {make_room = input.make_room}; return empty() end)
    swap(Power, "step", finish_one)
    swap(Validate, "begin", function(input)
        call("validate"); validate_runs = validate_runs + 1
        log.validate[#log.validate + 1] = {ring_bump = input.ring_bump}
        local s = stage(); s.fail = options.validate_fails ~= nil and (options.validate_fails < 0 or validate_runs <= options.validate_fails)
        return s
    end)
    swap(Validate, "step", function(state, budget)
        if budget.ops > 0 then
            budget.ops = budget.ops - 1
            state.done = true
            if state.fail then state.ok, state.errors = false, {{code = "BP_V_BUFFER_ZONE"}}
            else state.ok, state.result = true, {score = {beacon_count = 0}, metrics = {}} end
        end
        return state
    end)
    local ok, result = pcall(callback, log)
    for i = #saved, 1, -1 do saved[i][1][saved[i][2]] = saved[i][3] end
    if not ok then error(result, 0) end
    return result, log
end

function M.input(extra)
    local input = {plan_result = {steps = {{step_id = "one", machine = "assembler", machine_count = 1}},
        flows = {{flow_id = "f", producers = {{step_id = "$external"}}, consumers = {{step_id = "one"}}}}, ports = {}},
        grids = {{w = 8, h = 8}, {w = 10, h = 10}}, include_roboports = false,
        perimeter_ports = {}}
    for k, v in pairs(extra or {}) do input[k] = v end
    return input
end

function M.finish(Search, state)
    local ticks = 0
    while not state.done and ticks < 10000 do ticks = ticks + 1; Search.step(state, {ops = 1000}) end
    return state
end

return M
