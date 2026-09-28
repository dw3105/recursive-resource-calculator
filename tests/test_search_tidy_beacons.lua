--TB1 regression: fails on the base code because tidy obstacles omit live beacons after beacon sliding.
local H = require "tests.harness"

package.path = "./?.lua;./?/init.lua;" .. package.path
local Route = require "logic.bp.route"
local original_tidy_begin = Route.tidy_begin
local seen_beacons = false
Route.tidy_begin = function(done_state, options)
    for _, obstacle in ipairs(options and options.obstacles or {}) do
        if type(obstacle.owner) == "string" and obstacle.owner:sub(1, 7) == "beacon:" then
            seen_beacons = true
        end
    end
    return original_tidy_begin(done_state, options)
end

local old_arg, old_exit = arg, os.exit
arg = {[0] = "tools/first_stage.lua", "player-red-science-1s-foundry", "validate", "15"}
os.exit = function(code) error({first_stage_exit = code}) end
local ok, failure = pcall(dofile, "tools/first_stage.lua")
arg, os.exit = old_arg, old_exit
Route.tidy_begin = original_tidy_begin
H.equal(ok, false, "first-stage harness exits after its first validation verdict")
H.equal(type(failure), "table", "first-stage exit was intercepted")
H.equal(seen_beacons, true, "tidy obstacles include a live beacon rectangle")

H.done("test_search_tidy_beacons")
