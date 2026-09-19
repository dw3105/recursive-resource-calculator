--The companion loads all code while control.lua is parsed. The controller's
--on_tick work never calls require: Factorio rejects runtime require calls.
local Scenario = require "scenario"

local CANDIDATE = "rrc-engine-test"
local COMPANION = "rrc-golden-companion"
local controller = Scenario.new({candidate = Scenario.remote_candidate(CANDIDATE)})

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
    --These six calls remain thin, packaged-only access to the frozen §17 API.
    build_id = candidate_build_id,
    start_generation = function(context) return candidate_call("start_generation", context) end,
    generation_status = function(job_id) return candidate_call("generation_status", job_id) end,
    cancel_generation = function(job_id) return candidate_call("cancel_generation", job_id) end,
    preflight = function(case) return candidate_call("preflight", case) end,
    export = function(sheet_id) return candidate_call("export", sheet_id) end,
    canonical = function(blueprint_string) return candidate_call("canonical", blueprint_string) end,

    --One remote command starts the real tick-driven scenario. It returns a
    --small status immediately; terminal status is printed and written by the
    --on_tick controller.
    run = function(case)
        local accepted, status = controller:submit(case)
        status.accepted = accepted
        if accepted and game and game.print then
            local line = "[RRC engine evidence] queued " .. tostring(status.case_id or "case")
            game.print(line)
            local rcon = rawget(_G, "rcon")
            if rcon and rcon.print then pcall(rcon.print, line) end
        end
        return status
    end,
    status = function() return controller:status() end,
    cancel = function() return controller:cancel() end,
})

script.on_event(defines.events.on_tick, function(event)
    controller:tick(event.tick)
end)
