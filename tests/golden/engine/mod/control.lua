--The companion only drives the candidate's public interface. It never creates a blueprint or stores executable data.
local CANDIDATE = "rrc-engine-test"
local COMPANION = "rrc-golden-companion"

local function candidate_build_id()
    if not remote.interfaces[CANDIDATE] or not remote.interfaces[CANDIDATE].build_id then
        error("RRC-Golden-Companion: candidate interface is unavailable", 2)
    end
    return remote.call(CANDIDATE, "build_id")
end

local function packaged()
    local build = candidate_build_id()
    if type(build) ~= "table" or build.packaged ~= true then
        error("RRC-Golden-Companion: development checkout cannot produce evidence", 2)
    end
    return build
end

local function candidate_call(name, ...)
    packaged()
    if not remote.interfaces[CANDIDATE] or not remote.interfaces[CANDIDATE][name] then
        error("RRC-Golden-Companion: candidate has no " .. name, 2)
    end
    return remote.call(CANDIDATE, name, ...)
end

remote.add_interface(COMPANION, {
    build_id = candidate_build_id,
    start_generation = function(context) return candidate_call("start_generation", context) end,
    generation_status = function(job_id) return candidate_call("generation_status", job_id) end,
    cancel_generation = function(job_id) return candidate_call("cancel_generation", job_id) end,
    preflight = function(case) return candidate_call("preflight", case) end,
    export = function(sheet_id) return candidate_call("export", sheet_id) end,
    canonical = function(blueprint_string) return candidate_call("canonical", blueprint_string) end,
    --The host supplies the measured outcome after polling. The companion adds
    --the candidate identity from the same running game and returns plain data.
    observation = function(observation)
        local build = packaged()
        local result = {}
        for key, value in pairs(observation or {}) do result[key] = value end
        result.build_id = build
        result.candidate_sha = build.candidate_sha
        result.packaged = true
        return result
    end,
})
