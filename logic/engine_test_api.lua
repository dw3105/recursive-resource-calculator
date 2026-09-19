--The interface the in-game test companion drives, and the build identity it checks first.
--
--Owned by lane W4-golden. Engine evidence has to exercise this candidate's own generation, rejection and export
--paths; a companion that builds a blueprint out of its own fixture would prove nothing about the mod under test.
--
--remote interface "rrc-engine-test":
--  build_id()                  -> {candidate_sha, mod_version, factorio_branch, packaged}
--  start_generation(context)   -> job_id
--  generation_status(job_id)   -> {state = "pending"|"success"|"failure", progress, phase,
--                                  blueprint_string?, canonical_sha256?, canonical_version?, reason_codes?}
--  cancel_generation(job_id)   -> {state = "cancelled"}
--  preflight(case)             -> reason codes        (a cheap pre-check, never a substitute for a real run)
--  export(sheet_id)            -> debug string
--  canonical(blueprint_string) -> {canonical_sha256, canonical_version}
--
--Generation is a job, not a function call: remote.call returns inside the tick it was made, while the search
--runs across ticks under the same budget and cancellation the player's own button uses. The companion polls, so
--what it measures is the path a player takes.
--
--logic/build_id.lua exists only in a packaged copy, written by generate_release.sh. In a source checkout it is
--absent and this module reports {candidate_sha = "dev", packaged = false}, which the companion refuses to write
--evidence for: a development checkout can never be mistaken for a release candidate.
local EngineTestApi = {}

--Read while control.lua is parsed: require is refused later, and a missing file is not an error here.
local ok_build, packaged_build = pcall(require, "logic.build_id")

function EngineTestApi.build_id()
    local ok, build = ok_build, packaged_build
    if ok and type(build) == "table" and build.packaged then return build end
    return {candidate_sha = "dev", mod_version = "dev", factorio_branch = "dev", packaged = false}
end

function EngineTestApi.register() end

return EngineTestApi
