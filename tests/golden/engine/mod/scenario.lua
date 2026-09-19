--Tick-driven engine evidence controller.
--
--This file is loaded by control.lua while the mod is parsed.  It deliberately
--contains no require call in a runtime callback: Factorio rejects that after
--control.lua parsing has finished.  The controller is data-only apart from its
--short-lived runtime adapter, so the offline test can drive the same state
--machine without pretending to measure a factory.
local Scenario = {}

Scenario.RUNNER_REVISION = "engine-scenario-v1"
Scenario.TICKS_PER_SECOND = 60
Scenario.MAX_TIMEOUT_SECONDS = 3600

--The only branch-dependent facts owned by the companion live here.  The
--packaging lane may select the matching info.json branch from branch-manifest.json;
--the controller itself uses the same names on both supported branches.
Scenario.BRANCH_FACTS = {
    ["2.0"] = {
        factorio_version = "2.0",
        source_chest = "wooden-chest",
        drain_chest = "iron-chest",
        inserter = "inserter",
        pipe = "pipe",
        fluid_buffer = "storage-tank",
        power_source = "electric-energy-interface",
    },
    ["2.1"] = {
        factorio_version = "2.1",
        source_chest = "wooden-chest",
        drain_chest = "iron-chest",
        inserter = "inserter",
        pipe = "pipe",
        fluid_buffer = "storage-tank",
        power_source = "electric-energy-interface",
    },
}

Scenario.STATES = {
    ENVIRONMENT = "environment",
    EXPORT = "export",
    GENERATION = "generation",
    BUILD = "build",
    SUPPLY_SETUP = "supply_setup",
    POWER = "power",
    DRAIN_SETUP = "drain_setup",
    WARMING = "warming",
    SAMPLING = "sampling",
    DONE = "done",
    REFUSED = "refused",
}

local function finite(value, fallback)
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return fallback
end

local function integer(value, fallback)
    value = finite(value, fallback)
    if value == nil then return nil end
    return math.floor(value)
end

local function copy(value, seen)
    local value_type = type(value)
    if value == nil or value_type == "boolean" or value_type == "string" or value_type == "number" then
        return value
    end
    if value_type ~= "table" then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            local copied = copy(child, seen)
            if copied ~= nil then result[key] = copied end
        end
    end
    seen[value] = nil
    return result
end

local function sorted_unique(values)
    local seen, result = {}, {}
    for _, value in ipairs(values or {}) do
        value = tostring(value)
        if not seen[value] then seen[value] = true; result[#result + 1] = value end
    end
    table.sort(result)
    return result
end

local function mods_list(value)
    if type(value) ~= "table" then return {} end
    if #value > 0 then return copy(value) or {} end
    local result = {}
    for name, version in pairs(value) do
        result[#result + 1] = {name = tostring(name), version = tostring(version)}
    end
    table.sort(result, function(left, right) return left.name < right.name end)
    return result
end

local function scenario_of(case)
    return (type(case.engine_scenario) == "table" and case.engine_scenario)
        or (type(case.scenario) == "table" and case.scenario) or {}
end

local function expected_sha(case)
    if type(case) ~= "table" then return nil end
    return case.expected_candidate_sha or case.expected_candidate or case.expected_sha or case.candidate_sha_expected
        or case.candidate_sha
        or (type(case.expected) == "table" and case.expected.candidate_sha) or nil
end

local function case_id_of(case)
    return tostring(case.case_id or case.id or "unnamed-case")
end

local function add_counts(target, source)
    if type(source) ~= "table" then return end
    if type(source.accepted) == "table" then source = source.accepted
    elseif type(source.drained) == "table" then source = source.drained
    elseif type(source.counts) == "table" then source = source.counts end
    for key, value in pairs(source) do
        if type(key) == "string" then
            if type(value) == "number" then
                target[key] = (target[key] or 0) + math.max(0, value)
            elseif type(value) == "table" then
                local count = finite(value.count or value.amount, 0)
                target[key] = (target[key] or 0) + math.max(0, count)
            elseif type(value) == "string" then
                target[value] = (target[value] or 0) + 1
            end
        elseif type(value) == "string" then
            target[value] = (target[value] or 0) + 1
        end
    end
end

local function subtract_counts(after, before)
    local result = {}
    for key, value in pairs(after or {}) do result[key] = math.max(0, value - (before and before[key] or 0)) end
    return result
end

local function map_rates(counts, ticks)
    local result = {}
    for key, value in pairs(counts or {}) do result[key] = Scenario.rate_per_second(value, ticks) end
    return result
end

function Scenario.rate_per_second(count, ticks)
    count, ticks = finite(count, 0), finite(ticks, 0)
    if ticks <= 0 then return 0 end
    return count * Scenario.TICKS_PER_SECOND / ticks
end

--The export outcome needs a host-checkable digest too.  Keep this copy local
--to the companion because runtime require is forbidden and the candidate's
--digest helper is intentionally private to its interface module.
local function sha256(text)
    local bit = rawget(_G, "bit32")
    local band, bor, bxor, rshift, rrotate
    if bit then
        band, bor, bxor = bit.band, bit.bor, bit.bxor
        rshift, rrotate = bit.rshift, bit.rrotate
    else
        --Lua 5.4 has integer operators but Factorio's Lua 5.2 has bit32.  Keep
        --the digest available in both offline interpreters without requiring a
        --runtime module or relying on an engine helper that does not exist.
        local MOD32 = 4294967296
        local function unsigned(value) return value % MOD32 end
        local function binary(op, values)
            local result = 0
            for place = 0, 31 do
                local bit_value = 2 ^ place
                local count = 0
                for index = 1, #values do
                    if math.floor(unsigned(values[index]) / bit_value) % 2 == 1 then count = count + 1 end
                end
                local set = op(count, #values)
                if set then result = result + bit_value end
            end
            return result
        end
        band = function(first, ...) return binary(function(count, width) return count == width end, {first, ...}) end
        bor = function(first, ...) return binary(function(count) return count > 0 end, {first, ...}) end
        bxor = function(first, ...) return binary(function(count) return count % 2 == 1 end, {first, ...}) end
        rshift = function(value, amount) return math.floor(unsigned(value) / 2 ^ amount) end
        rrotate = function(value, amount)
            amount = amount % 32
            local low = unsigned(value) % 2 ^ amount
            return math.floor(unsigned(value) / 2 ^ amount) + low * 2 ^ (32 - amount) % MOD32
        end
    end
    local k = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    }
    local h = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19}
    local bit_length = #text * 8
    text = text .. string.char(128)
    while (#text + 8) % 64 ~= 0 do text = text .. string.char(0) end
    local high = math.floor(bit_length / 4294967296)
    local low = bit_length % 4294967296
    text = text .. string.char(
        band(rshift(high, 24), 255), band(rshift(high, 16), 255), band(rshift(high, 8), 255), band(high, 255),
        band(rshift(low, 24), 255), band(rshift(low, 16), 255), band(rshift(low, 8), 255), band(low, 255))
    local function word(offset)
        return band(text:byte(offset) * 16777216 + text:byte(offset + 1) * 65536
            + text:byte(offset + 2) * 256 + text:byte(offset + 3), 0xffffffff)
    end
    local function add(a, b, c, d, e)
        return band((a or 0) + (b or 0) + (c or 0) + (d or 0) + (e or 0), 0xffffffff)
    end
    for offset = 1, #text, 64 do
        local w = {}
        for index = 0, 15 do w[index] = word(offset + index * 4) end
        for index = 16, 63 do
            local x, y = w[index - 15], w[index - 2]
            local s0 = bxor(rrotate(x, 7), rrotate(x, 18), rshift(x, 3))
            local s1 = bxor(rrotate(y, 17), rrotate(y, 19), rshift(y, 10))
            w[index] = add(w[index - 16], s0, w[index - 7], s1)
        end
        local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
        for index = 0, 63 do
            local s1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
            local choose = bxor(band(e, f), band(bxor(e, 0xffffffff), g))
            local temp1 = add(hh, s1, choose, k[index + 1], w[index])
            local s0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
            local majority = bxor(band(a, b), band(a, c), band(b, c))
            local temp2 = add(s0, majority)
            hh, g, f, e, d, c, b, a = g, f, e, add(d, temp1), c, b, a, add(temp1, temp2)
        end
        h[1], h[2], h[3], h[4] = add(h[1], a), add(h[2], b), add(h[3], c), add(h[4], d)
        h[5], h[6], h[7], h[8] = add(h[5], e), add(h[6], f), add(h[7], g), add(h[8], hh)
    end
    local result = {}
    for _, value in ipairs(h) do result[#result + 1] = string.format("%08x", value) end
    return table.concat(result)
end

local Controller = {}
Controller.__index = Controller

local function safe_call(object, name, ...)
    local method = object and object[name]
    if type(method) ~= "function" then return false, "missing adapter method " .. tostring(name) end
    return pcall(method, ...)
end

function Scenario.new(dependencies)
    dependencies = dependencies or {}
    return setmetatable({
        candidate = dependencies.candidate or Scenario.remote_candidate("rrc-engine-test"),
        adapter = dependencies.adapter or Scenario.runtime_adapter(),
        active = nil,
        last = nil,
    }, Controller)
end

function Controller:_now(tick)
    if type(tick) == "number" then return tick end
    local ok, value = safe_call(self.adapter, "tick")
    return ok and finite(value, 0) or 0
end

function Controller:_metadata(state)
    local result = {}
    local ok, metadata = safe_call(self.adapter, "metadata", state.case, state.environment, state.build)
    if ok and type(metadata) == "table" then result = copy(metadata) or {} end
    local initial = scenario_of(state.case).initial_state or state.case.initial_state or {}
    local branch = result.factorio_branch or state.build.factorio_branch
        or (state.environment and state.environment.branch) or "unknown"
    return {
        schema_version = 1,
        case_id = case_id_of(state.case),
        candidate_sha = tostring(state.build.candidate_sha or "unknown"),
        runner_revision = Scenario.RUNNER_REVISION,
        factorio_version = result.factorio_version or state.build.factorio_version or branch,
        factorio_branch = branch,
        mods = mods_list(result.mods or result.active_mods),
        force = result.force or (state.environment and state.environment.force_name)
            or initial.force or "player",
        surface = result.surface or (state.environment and state.environment.surface_name)
            or initial.surface or "nauvis",
    }
end

function Controller:_write(state, observation)
    state.observation = observation
    safe_call(self.adapter, "write_observation", observation, state.case)
end

function Controller:_cleanup(state)
    if state.cleaned then return end
    state.cleaned = true
    if not state.environment and not state.built and not state.supply and not state.drain then return end
    safe_call(self.adapter, "cleanup", state.built, state.perimeter, state.environment, state.case)
end

function Controller:_finish(state, observation, final_state)
    self:_write(state, observation)
    self:_cleanup(state)
    state.state = final_state or Scenario.STATES.DONE
    state.finished = true
    self.last = state
    self.active = nil
    safe_call(self.adapter, "announce", observation, state)
    return self:status()
end

function Controller:_rejection(state, stage, codes, detail, final_state)
    local base = self:_metadata(state)
    local rejection = {stage = stage, reason_codes = sorted_unique(codes)}
    if detail ~= nil then rejection.detail = tostring(detail) end
    base.outcome_kind = "rejection"
    base.rejection = rejection
    return self:_finish(state, base, final_state or Scenario.STATES.REFUSED)
end

function Controller:_timings(state)
    local ticks = state.ticks or {}
    local function delta(a, b) return math.max(0, integer(ticks[b], ticks[a] or 0) - integer(ticks[a], 0)) end
    return {
        setup_ticks = delta("submitted", "setup"),
        generation_ticks = delta("generation_start", "generation_end"),
        build_ticks = delta("generation_end", "build_end"),
        warm_up_ticks = state.warm_up_ticks or 0,
        sampling_ticks = state.sample_ticks or 0,
    }
end

function Controller:_finish_production(state)
    local status = state.generation_status or {}
    local canonical_sha, canonical_version = status.canonical_sha256, status.canonical_version
    if not canonical_sha and type(self.candidate.canonical) == "function" then
        local ok, canonical = pcall(self.candidate.canonical, state.blueprint_string)
        if ok and type(canonical) == "table" then
            canonical_sha, canonical_version = canonical.canonical_sha256, canonical.canonical_version
        end
    end
    local drained = subtract_counts(state.counts.drained, state.sample_baseline)
    local accepted = subtract_counts(state.counts.accepted, state.accepted_baseline)
    local production = {
        canonical_sha256 = canonical_sha,
        canonical_version = canonical_version,
        blueprint_string = state.blueprint_string,
        blueprint_string_sha256 = sha256(state.blueprint_string),
        rates = map_rates(drained, state.sample_ticks),
        accepted_supply = {counts = accepted, rates = map_rates(accepted, state.sample_ticks)},
        drained_outputs = {counts = drained, rates = map_rates(drained, state.sample_ticks)},
        warm_up = {ticks = state.warm_up_ticks, start_tick = state.warmup_start_tick,
            end_tick = state.warmup_end_tick},
        window = {ticks = state.sample_ticks, start_tick = state.sample_start_tick,
            end_tick = state.sample_end_tick},
        timings = self:_timings(state),
    }
    local observation = self:_metadata(state)
    observation.outcome_kind = "production"
    observation.production = production
    return self:_finish(state, observation, Scenario.STATES.DONE)
end

function Controller:_service_perimeter(state)
    local ok, accepted = safe_call(self.adapter, "supply", state.supply, state.case, state.environment)
    if not ok then return false, "supply: " .. tostring(accepted) end
    add_counts(state.counts.accepted, accepted)
    ok, accepted = safe_call(self.adapter, "drain", state.drain, state.case, state.environment)
    if not ok then return false, "drain: " .. tostring(accepted) end
    add_counts(state.counts.drained, accepted)
    return true
end

function Controller:_enter_sampling(state, tick)
    state.state = Scenario.STATES.SAMPLING
    state.sample_start_tick = tick
    state.sample_end_tick = tick + state.sample_ticks - 1
    state.sample_baseline = copy(state.counts.drained) or {}
    state.accepted_baseline = copy(state.counts.accepted) or {}
end

function Controller:_enter_warmup(state, tick)
    local scenario = scenario_of(state.case)
    state.warm_up_ticks = math.max(0, integer(scenario.warm_up_ticks, 0))
    state.sample_ticks = math.max(1, integer(scenario.sampling_window_ticks, 1))
    state.warmup_start_tick = tick
    state.warmup_end_tick = tick + state.warm_up_ticks
    if state.warm_up_ticks == 0 then
        self:_enter_sampling(state, tick)
    else
        state.state = Scenario.STATES.WARMING
    end
end

function Controller:_setup_environment(state, tick)
    local ok, environment = safe_call(self.adapter, "setup_environment", state.case, state.build)
    if not ok or type(environment) ~= "table" then
        return self:_rejection(state, "environment", {"RRC_ENVIRONMENT_SETUP_FAILED"}, environment)
    end
    state.environment = environment
    state.ticks.setup = tick
    local context_ok, context = safe_call(self.adapter, "generation_context", state.case, environment, state.build)
    if not context_ok or type(context) ~= "table" then
        return self:_rejection(state, "environment", {"RRC_SHEET_SETUP_FAILED"}, context)
    end
    state.context = context
    if scenario_of(state.case).outcome_kind == "export" or state.case.expected_outcome == "export" then
        state.state = Scenario.STATES.EXPORT
        return self:status()
    end
    local started, job_id = pcall(self.candidate.start_generation, context)
    if not started or job_id == nil then
        return self:_rejection(state, "generation", {"RRC_GENERATION_START_FAILED"}, job_id)
    end
    state.job_id = job_id
    state.ticks.generation_start = tick
    state.state = Scenario.STATES.GENERATION
    return self:status()
end

function Controller:_export(state)
    local ok, envelope = pcall(self.candidate.export, state.context.sheet_id or state.case.sheet_id)
    if not ok or envelope == nil then
        return self:_rejection(state, "export", {"RRC_EXPORT_FAILED"}, envelope)
    end
    local digest = type(envelope) == "table" and (envelope.content_sha256 or envelope.digest or envelope.sha256 or envelope.canonical_sha256)
        or (type(envelope) == "string" and sha256(envelope))
        or state.case.export_digest
    local decoded = envelope
    if type(envelope) == "string" and rawget(_G, "helpers") then
        local encoded = envelope:sub(1, 1) == "0" and envelope:sub(2) or envelope
        local ok_text, text = pcall(helpers.decode_string, encoded)
        if ok_text and type(text) == "string" then
            local ok_table, value = pcall(helpers.json_to_table, text)
            if ok_table and type(value) == "table" then decoded = value end
        end
    end
    local observation = self:_metadata(state)
    observation.outcome_kind = "export"
    if type(decoded) == "table" then
        observation.export = copy(decoded) or {}
        observation.export.content_sha256 = observation.export.content_sha256 or digest
    else
        observation.export = {envelope = decoded, content_sha256 = digest}
    end
    return self:_finish(state, observation, Scenario.STATES.DONE)
end

function Controller:_poll_generation(state, tick)
    local scenario = scenario_of(state.case)
    local timeout = math.max(1, math.min(Scenario.MAX_TIMEOUT_SECONDS,
        finite(scenario.timeout_seconds, 60))) * Scenario.TICKS_PER_SECOND
    state.timeout_ticks = math.floor(timeout)
    if tick - state.ticks.generation_start >= state.timeout_ticks then
        pcall(self.candidate.cancel_generation, state.job_id)
        return self:_rejection(state, "generation-timeout", {"RRC_GENERATION_TIMEOUT"})
    end
    local ok, status = pcall(self.candidate.generation_status, state.job_id)
    if not ok or type(status) ~= "table" then
        return self:_rejection(state, "generation", {"RRC_GENERATION_STATUS_FAILED"}, status)
    end
    state.generation_status = status
    if status.state == "pending" then return self:status() end
    state.ticks.generation_end = tick
    if status.state == "failure" then
        return self:_rejection(state, "generation", status.reason_codes or {"RRC_GENERATION_FAILED"}, status.stage)
    elseif status.state == "cancelled" then
        return self:_rejection(state, "cancelled", {"RRC_GENERATION_CANCELLED"})
    elseif status.state ~= "success" or type(status.blueprint_string) ~= "string" then
        return self:_rejection(state, "generation", {"RRC_GENERATION_INVALID_RESULT"})
    end
    state.blueprint_string = status.blueprint_string
    state.state = Scenario.STATES.BUILD
    return self:status()
end

function Controller:_build(state, tick)
    local ok, built, detail = pcall(self.adapter.build_blueprint, state.blueprint_string, state.context,
        state.environment, state.case)
    if not ok or built == nil or built == false then
        return self:_rejection(state, "build", {"RRC_BUILD_FAILED"}, detail or built)
    end
    state.built = built
    state.ticks.build_end = tick
    state.state = Scenario.STATES.SUPPLY_SETUP
    return self:status()
end

function Controller:_prepare_supply(state)
    local ok, supply = safe_call(self.adapter, "prepare_supply", state.built, state.case, state.environment)
    if not ok or supply == nil or supply == false then
        return self:_rejection(state, "supply", {"RRC_SUPPLY_SETUP_FAILED"}, supply)
    end
    state.supply = supply
    state.state = Scenario.STATES.POWER
    return self:status()
end

function Controller:_provide_power(state)
    local ok, result = safe_call(self.adapter, "provide_power", state.built, state.case, state.environment)
    if not ok or result == false then
        return self:_rejection(state, "power", {"RRC_POWER_SETUP_FAILED"}, result)
    end
    state.state = Scenario.STATES.DRAIN_SETUP
    return self:status()
end

function Controller:_prepare_drain(state, tick)
    local ok, drain = safe_call(self.adapter, "prepare_drain", state.built, state.case, state.environment)
    if not ok or drain == nil or drain == false then
        return self:_rejection(state, "drain", {"RRC_DRAIN_SETUP_FAILED"}, drain)
    end
    state.drain = drain
    state.counts = {accepted = {}, drained = {}}
    state.ticks.drain_setup = tick
    self:_enter_warmup(state, tick)
    return self:status()
end

function Controller:tick(tick)
    local state = self.active
    if not state then return self:status() end
    tick = self:_now(tick)
    if state.state == Scenario.STATES.ENVIRONMENT then
        return self:_setup_environment(state, tick)
    elseif state.state == Scenario.STATES.EXPORT then
        return self:_export(state)
    elseif state.state == Scenario.STATES.GENERATION then
        return self:_poll_generation(state, tick)
    elseif state.state == Scenario.STATES.BUILD then
        return self:_build(state, tick)
    elseif state.state == Scenario.STATES.SUPPLY_SETUP then
        return self:_prepare_supply(state)
    elseif state.state == Scenario.STATES.POWER then
        return self:_provide_power(state)
    elseif state.state == Scenario.STATES.DRAIN_SETUP then
        return self:_prepare_drain(state, tick)
    elseif state.state == Scenario.STATES.WARMING then
        local serviced, detail = self:_service_perimeter(state)
        if not serviced then return self:_rejection(state, "perimeter", {"RRC_PERIMETER_TICK_FAILED"}, detail) end
        if tick >= state.warmup_end_tick then self:_enter_sampling(state, tick + 1) end
        return self:status()
    elseif state.state == Scenario.STATES.SAMPLING then
        if tick < state.sample_start_tick then return self:status() end
        local serviced, detail = self:_service_perimeter(state)
        if not serviced then return self:_rejection(state, "perimeter", {"RRC_PERIMETER_TICK_FAILED"}, detail) end
        if tick >= state.sample_end_tick then return self:_finish_production(state) end
    end
    return self:status()
end

function Controller:submit(input_case)
    if self.active then return false, self:status() end
    local case = copy(input_case or {}) or {}
    local ok, build = pcall(self.candidate.build_id)
    if not ok or type(build) ~= "table" then
        local state = {case = case, build = {candidate_sha = "unknown"}, ticks = {submitted = self:_now()}}
        return false, self:_rejection(state, "identity", {"RRC_BUILD_ID_UNAVAILABLE"}, build)
    end
    local state = {case = case, build = copy(build) or {candidate_sha = "unknown"}, ticks = {submitted = self:_now()}}
    if build.packaged ~= true then
        return false, self:_rejection(state, "identity", {"RRC_DEVELOPMENT_BUILD"})
    end
    local expected = expected_sha(case)
    if expected ~= nil and tostring(build.candidate_sha) ~= tostring(expected) then
        return false, self:_rejection(state, "identity", {"RRC_CANDIDATE_IDENTITY_MISMATCH"})
    end
    self.active = state
    state.state = Scenario.STATES.ENVIRONMENT
    return true, self:status()
end

function Controller:cancel()
    local state = self.active
    if not state then return self:status() end
    if state.state == Scenario.STATES.GENERATION and state.job_id ~= nil then
        pcall(self.candidate.cancel_generation, state.job_id)
    end
    return self:_rejection(state, "cancelled", {"RRC_SCENARIO_CANCELLED"}, nil, "cancelled")
end

function Controller:status()
    local state = self.active or self.last
    if not state then return {state = "idle"} end
    local result = {state = state.state, case_id = case_id_of(state.case), job_id = state.job_id,
        phase = state.generation_status and state.generation_status.phase or state.state}
    if state.observation then result.observation = state.observation end
    return result
end

--Remote-call adapter.  It is created while control.lua is parsed, but all
--Factorio globals are read only when a method is called by the controller.
function Scenario.remote_candidate(interface_name)
    local candidate = {}
    local function call(name, ...)
        local remote = rawget(_G, "remote")
        if not remote or not remote.interfaces or not remote.interfaces[interface_name]
            or not remote.interfaces[interface_name][name] then
            error("RRC-Golden-Companion: candidate has no " .. name, 2)
        end
        return remote.call(interface_name, name, ...)
    end
    candidate.build_id = function() return call("build_id") end
    candidate.start_generation = function(context) return call("start_generation", context) end
    candidate.generation_status = function(job_id) return call("generation_status", job_id) end
    candidate.cancel_generation = function(job_id) return call("cancel_generation", job_id) end
    candidate.export = function(sheet_id) return call("export", sheet_id) end
    candidate.canonical = function(blueprint_string) return call("canonical", blueprint_string) end
    return candidate
end

local function direction_vector(direction)
    direction = integer(direction, 0) % 16
    if direction == 0 then return 0, -1 end
    if direction == 4 then return 1, 0 end
    if direction == 8 then return 0, 1 end
    return -1, 0
end

local function opposite_direction(direction)
    return (integer(direction, 0) + 8) % 16
end

local function position_of(value, fallback)
    if type(value) == "table" then
        local x, y = finite(value.x or value[1]), finite(value.y or value[2])
        if x ~= nil and y ~= nil then return {x = x, y = y} end
    end
    return {x = fallback.x, y = fallback.y}
end

local function full_name_parts(full_name)
    local kind, name = tostring(full_name or ""):match("^([^/]+)/(.+)$")
    return kind or "item", name or tostring(full_name or "")
end

local function scenario_ports(case, side)
    local scenario = scenario_of(case)
    local source = scenario[side] or {}
    local declared = scenario.ports or scenario.perimeter_ports or case.ports or {}
    local result = {}
    for index, entry in ipairs(source) do
        local port = {}
        for _, candidate in ipairs(declared) do
            local candidate_role = candidate.role or candidate.direction
            local wanted_role = side == "supply" and (candidate_role == "in" or candidate_role == "input")
                or (candidate_role == "out" or candidate_role == "output")
            local same_id = entry.port_id ~= nil and candidate.port_id == entry.port_id
            local same_flow = entry.full_name ~= nil and candidate.full_name == entry.full_name
            if wanted_role and (same_id or same_flow) then
                port = copy(candidate) or {}
                break
            end
        end
        for key, value in pairs(entry) do port[key] = copy(value) end
        port.port_id = port.port_id or port.id or side .. ":" .. tostring(index) .. ":" .. tostring(port.full_name)
        result[#result + 1] = port
    end
    return result
end

function Scenario.runtime_adapter()
    local adapter = {}
    local function game_object()
        local object = rawget(_G, "game")
        if not object then error("RRC-Golden-Companion: game is unavailable", 3) end
        return object
    end
    local function branch_facts(build, case)
        local branch = build and build.factorio_branch or case.factorio_branch or "2.0"
        branch = tostring(branch):match("^(2%.[01])") or "2.0"
        return Scenario.BRANCH_FACTS[branch], branch
    end
    adapter.tick = function() return game_object().tick or 0 end
    adapter.setup_environment = function(case, build)
        local game = game_object()
        local scenario = scenario_of(case)
        local initial = scenario.initial_state or case.initial_state or {}
        local surface_name = tostring(initial.surface or scenario.surface or "nauvis")
        local force_name = tostring(initial.force or scenario.force or "player")
        local surface = game.surfaces[surface_name]
        local created_surface = surface == nil
        if not surface then surface = game.create_surface(surface_name) end
        local force = game.forces[force_name]
        if not force then force = game.create_force(force_name) end
        if initial.game_speed ~= nil then game.speed = finite(initial.game_speed, game.speed or 1) end
        local research_before = {}
        for _, research in ipairs(initial.research or scenario.force_research or case.force_research or {}) do
            local name = type(research) == "table" and (research.name or research.technology) or research
            local technology = force.technologies and force.technologies[name]
            if technology then
                research_before[name] = technology.researched
                technology.researched = true
            end
        end
        local facts, branch = branch_facts(build, case)
        return {surface = surface, force = force, surface_name = surface_name, force_name = force_name,
            branch = branch, facts = facts, previous_game_speed = game.speed,
            research_before = research_before, created_surface = created_surface}
    end
    adapter.generation_context = function(case, environment, build)
        local setup = type(case.setup) == "table" and case.setup or {}
        local prepared = case.prepared_input or setup.prepared_input or scenario_of(case).prepared_input
        local prepared_input = copy(prepared or {}) or {}
        local settings = setup.settings
        if type(settings) == "table" and type(settings.current) == "table" then settings = settings.current end
        local context = {
            schema_version = 1,
            player_index = case.player_index or 1,
            sheet_id = case.sheet_id or case_id_of(case),
            revisions = copy(case.revisions or prepared_input.revisions or {sheet = 0, config = 0})
                or {sheet = 0, config = 0},
            settings = copy(settings or prepared_input.settings or {}) or {},
            options = copy(setup.options or prepared_input.options or {}) or {},
            prepared_input = prepared_input,
        }
        context.surface = environment.surface_name
        context.force = environment.force_name
        context.deliver = false
        if not context.prepared_input.snapshot then
            context.prepared_input.snapshot = {schema_version = 1, sheet_id = context.sheet_id,
                player_index = context.player_index, targets = copy(case.targets or {}) or {},
                selection = copy(setup.selection or {}) or {}, options = copy(setup.options or {}) or {},
                state = "current", revisions = context.revisions}
        end
        return context
    end

    local function build_position(case)
        local scenario = scenario_of(case)
        return position_of(scenario.build_position, {x = 0, y = 0})
    end

    adapter.build_blueprint = function(blueprint_string, context, environment, case)
        local position = build_position(case)
        local created = environment.surface.create_entities_from_blueprint_string{
            string = blueprint_string, position = position, force = environment.force,
            raise_built = true, create_build_effect_smoke = false,
        }
        if type(created) ~= "table" or #created == 0 then error("blueprint created no entities", 2) end
        for index, entity in ipairs(created) do
            if entity.type == "entity-ghost" then
                local _, revived = entity.revive{raise_revive = true}
                if not revived then error("blueprint entity ghost could not be revived", 2) end
                created[index] = revived
            end
        end
        local port_positions = {}
        local ok_decoded, decoded_text = pcall(helpers.decode_string,
            blueprint_string:sub(1, 1) == "0" and blueprint_string:sub(2) or blueprint_string)
        if ok_decoded then
            local ok_blueprint, decoded = pcall(helpers.json_to_table, decoded_text)
            if ok_blueprint and type(decoded) == "table" then
                local root = type(decoded.blueprint) == "table" and decoded.blueprint or decoded
                for _, entity in ipairs(root.entities or {}) do
                    local id = entity.port_id or (entity.tags and entity.tags.port_id)
                    if id and entity.position then
                        port_positions[id] = {x = entity.position.x + position.x, y = entity.position.y + position.y}
                    end
                end
            end
        end
        return {entities = created, surface = environment.surface, force = environment.force, position = position,
            port_positions = port_positions, perimeter = {}, power = nil}
    end

    local function endpoint_position(entry, built)
        local explicit = entry.position or entry.attach_position
        if explicit then
            local position = position_of(explicit, built.position)
            if entry.absolute ~= true then
                position.x = position.x + built.position.x
                position.y = position.y + built.position.y
            end
            return position
        end
        local by_id = built.port_positions or {}
        local position = by_id[entry.port_id]
        if position then return position_of(position, built.position) end
        error("port " .. tostring(entry.port_id) .. " has no perimeter position", 3)
    end

    local function make_entity(surface, spec)
        local entity = surface.create_entity(spec)
        if not entity then error("could not create perimeter entity " .. tostring(spec.name), 3) end
        return entity
    end

    local function make_perimeter_entry(entry, side, built, environment)
        local kind, name = full_name_parts(entry.full_name)
        local position = endpoint_position(entry, built)
        local dx, dy = direction_vector(entry.travel_dir or entry.direction or 0)
        local far = {x = position.x + dx * (side == "supply" and -2 or 2), y = position.y + dy * (side == "supply" and -2 or 2)}
        local near = {x = position.x + dx * (side == "supply" and -1 or 1), y = position.y + dy * (side == "supply" and -1 or 1)}
        local facts = environment.facts
        local result = {entry = entry, kind = kind, name = name, accumulator = 0, branch = environment.branch}
        if kind == "fluid" then
            result.buffer = make_entity(environment.surface, {name = facts.fluid_buffer, position = far, force = environment.force})
            result.pipe = make_entity(environment.surface, {name = facts.pipe, position = near, force = environment.force})
        else
            result.buffer = make_entity(environment.surface, {name = side == "supply" and facts.source_chest or facts.drain_chest,
                position = far, force = environment.force})
            result.inserter = make_entity(environment.surface, {name = facts.inserter, position = near,
                direction = opposite_direction(entry.direction or entry.travel_dir or 0), force = environment.force})
        end
        built.perimeter[#built.perimeter + 1] = result
        return result
    end

    adapter.prepare_supply = function(built, case, environment)
        local result = {}
        for _, entry in ipairs(scenario_ports(case, "supply")) do
            result[#result + 1] = make_perimeter_entry(entry, "supply", built, environment)
        end
        return result
    end

    adapter.provide_power = function(built, case, environment)
        local poles = {}
        for _, entity in ipairs(built.entities or {}) do
            if entity.valid ~= false and entity.type == "electric-pole" then poles[#poles + 1] = entity end
        end
        if #poles == 0 then error("blueprint has no electric pole", 2) end
        local pole_position = poles[1].position
        local position = {x = pole_position.x + 1, y = pole_position.y}
        local source = make_entity(environment.surface, {name = environment.facts.power_source,
            position = position, force = environment.force})
        source.power_production = "100MW"
        local connector_id = defines.wire_connector_id.pole_copper
        local source_connector = source.get_wire_connector(connector_id, true)
        local pole_connector = poles[1].get_wire_connector(connector_id, true)
        if not source_connector or not pole_connector then error("power entities have no copper connector", 2) end
        source_connector.connect_to(pole_connector)
        built.power = source
        return true
    end

    adapter.prepare_drain = function(built, case, environment)
        local result = {}
        for _, entry in ipairs(scenario_ports(case, "drain")) do
            result[#result + 1] = make_perimeter_entry(entry, "drain", built, environment)
        end
        return result
    end

    local function inventory(entity)
        local defines_global = rawget(_G, "defines")
        local inventory_id = defines_global and defines_global.inventory and defines_global.inventory.chest
        return entity.get_inventory(inventory_id)
    end

    local function fluid_at(port)
        if port.branch == "2.0" then
            return port.buffer.fluidbox[1]
        end
        return port.buffer.get_fluid(1)
    end

    local function add_fluid(port, name, amount, existing)
        if port.branch == "2.0" then
            port.buffer.fluidbox[1] = {name = name, amount = existing + amount}
            return amount
        end
        return port.buffer.add_fluid(1, {name = name, amount = amount})
    end

    local function remove_fluid(port, amount)
        if port.branch == "2.0" then
            local current = port.buffer.fluidbox[1]
            local removed = math.min(current and current.amount or 0, amount)
            if removed > 0 then
                local remaining = current.amount - removed
                port.buffer.fluidbox[1] = remaining > 0
                    and {name = current.name, amount = remaining} or nil
            end
            return removed
        end
        local removed = port.buffer.remove_fluid(1, amount)
        return removed and removed.amount or 0
    end

    local function stack_for(port, count)
        local stack = {name = port.name, count = count}
        if port.quality and port.quality ~= "normal" then stack.quality = port.quality end
        return stack
    end

    adapter.supply = function(supplies)
        local accepted = {}
        for _, port in ipairs(supplies or {}) do
            local rate = math.max(0, finite(port.entry.rate_per_second or port.entry.rate, 0))
            port.accumulator = port.accumulator + rate / Scenario.TICKS_PER_SECOND
            local whole = math.floor(port.accumulator)
            port.accumulator = port.accumulator - whole
            if port.kind == "fluid" then
                local current = fluid_at(port)
                local amount = whole + port.accumulator
                if amount > 0 then
                    local existing = current and current.name == port.name and current.amount or 0
                    local added = math.max(0, amount)
                    if added > 0 then
                        local accepted_amount = add_fluid(port, port.name, added, existing)
                        accepted_amount = math.max(0, math.min(added, accepted_amount or 0))
                        port.accumulator = math.max(0, amount - accepted_amount)
                        accepted[port.entry.full_name] = (accepted[port.entry.full_name] or 0) + accepted_amount
                    end
                end
            elseif whole > 0 then
                local added = inventory(port.buffer).insert(stack_for(port, whole))
                accepted[port.entry.full_name] = (accepted[port.entry.full_name] or 0) + added
            end
        end
        return accepted
    end

    adapter.drain = function(drains)
        local drained = {}
        for _, port in ipairs(drains or {}) do
            local rate = math.max(0, finite(port.entry.rate_per_second or port.entry.rate, 0))
            port.accumulator = port.accumulator + rate / Scenario.TICKS_PER_SECOND
            local whole = math.floor(port.accumulator)
            port.accumulator = port.accumulator - whole
            if port.kind == "fluid" then
                local current = fluid_at(port)
                local amount = current and current.name == port.name and current.amount or 0
                local removed = remove_fluid(port, math.min(amount, whole + port.accumulator))
                if removed > 0 then
                    port.accumulator = math.max(0, whole + port.accumulator - removed)
                    drained[port.entry.full_name] = (drained[port.entry.full_name] or 0) + removed
                end
            elseif whole > 0 then
                local removed = inventory(port.buffer).remove(stack_for(port, whole))
                drained[port.entry.full_name] = (drained[port.entry.full_name] or 0) + removed
            end
        end
        return drained
    end

    adapter.metadata = function(case, environment, build)
        game_object()
        local active_mods = (rawget(_G, "script") and script.active_mods) or {}
        local branch = build and build.factorio_branch or environment and environment.branch
            or case.factorio_branch or "unknown"
        local facts = environment and environment.facts or Scenario.BRANCH_FACTS[branch]
        return {
            factorio_version = build and build.factorio_version or facts and facts.factorio_version or branch,
            factorio_branch = branch,
            mods = mods_list(active_mods),
            force = environment and environment.force_name
                or scenario_of(case).force or case.force or "player",
            surface = environment and environment.surface_name
                or scenario_of(case).surface or (case.initial_state and case.initial_state.surface) or "nauvis",
        }
    end

    adapter.write_observation = function(observation, case)
        game_object()
        local case_id = case_id_of(case):gsub("[^%w_.-]", "_")
        local path = "rrc-engine-evidence/" .. case_id .. ".observation.json"
        helpers.write_file(path, helpers.table_to_json(observation), false)
    end

    adapter.announce = function(observation)
        local line = "[RRC engine evidence] " .. tostring(observation.case_id) .. " " .. tostring(observation.outcome_kind)
        local game = rawget(_G, "game")
        if game then game.print(line) end
        local rcon = rawget(_G, "rcon")
        if rcon and rcon.print then rcon.print(line) end
    end

    adapter.cleanup = function(built, perimeter, environment)
        if environment then
            local game = game_object()
            if environment.previous_game_speed ~= nil then game.speed = environment.previous_game_speed end
            for name, researched in pairs(environment.research_before or {}) do
                local technology = environment.force.technologies and environment.force.technologies[name]
                if technology then technology.researched = researched end
            end
            if environment.created_surface and environment.surface and environment.surface.valid ~= false
                then
                game.delete_surface(environment.surface_name)
            end
        end
        if not built then return end
        for _, port in ipairs(built.perimeter or {}) do
            if port.inserter and port.inserter.valid ~= false then port.inserter.destroy() end
            if port.pipe and port.pipe.valid ~= false then port.pipe.destroy() end
            if port.buffer and port.buffer.valid ~= false then port.buffer.destroy() end
        end
        if built.power and built.power.valid ~= false then built.power.destroy() end
        for _, entity in ipairs(built.entities or {}) do
            if entity.valid ~= false then entity.destroy() end
        end
    end
    return adapter
end

return Scenario
