--Long-hand acceptance probe (round 29, docs/contracts/pipeline_r29.md C4): the player's red-science sheet with
--EXTRA raw item inputs added to the 4-machine science step, so its row needs far belts and long-handed hands.
--  lua5.2 tests/golden/long_hand_probe.lua <extra 1..4> <out.json>
--extra 1 -> 3 inputs (far belt above), 2 -> 4 inputs, 3 -> 5 inputs (far belt below the output belt too).
package.path = "./?.lua;" .. package.path
EXTRA = tonumber(arg[1]) or 1
local OUT = arg[2] or "long_hand_probe.json"
local Plan = require "logic.bp.plan"
local step = Plan.step
Plan.step = function(st, b) local r = step(st, b)
  if st.done and st.ok and not st._inj then st._inj = true
    local extras = {"stone", "wood", "coal", "sulfur"}
    for i = 1, EXTRA do
      local item = extras[i]
      for _, s in ipairs(st.result.steps) do
        if s.recipe == "automation-science-pack" then s.inputs[#s.inputs + 1] = {flow_id = "item/" .. item, rate_per_second = 1} end
      end
      st.result.flows[#st.result.flows + 1] = {item_name = item, is_fluid = false, flow_id = "item/" .. item,
        full_name = "item/" .. item, quality = "normal", rate_per_second = 1,
        producers = {{share_per_second = 1, step_id = "$external"}},
        consumers = {{share_per_second = 1, step_id = "automation-science-pack"}}}
      st.result.ports = st.result.ports or {}
      st.result.ports[#st.result.ports + 1] = {is_fluid = false, role = "in", kind = "item", min_lanes = 1,
        full_name = "item/" .. item, port_id = "in:item/" .. item, rate_per_second = 1}
    end
  end return r end
arg = {[0] = "tests/golden/generate.lua", "--input", "tests/golden/cases/player-red-science-1s/prepared_input.json", "--output", OUT}
dofile("tests/golden/generate.lua")
