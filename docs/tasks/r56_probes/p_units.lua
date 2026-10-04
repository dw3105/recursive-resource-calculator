-- LOCAL PROBE ticket 06 tail: ckpt --patch that wraps unit functions with instruction / tostring counters (tt.lua __ttu*).
-- behaviour neutral: wrapper passes all args and returns through.
local targets = {
  ["logic.bp.groups"] = {"build_block", "candidate_inserter", "append_inserters", "place_row", "redundant", "make_candidates_once"},
  ["logic.bp.pack"] = {"layered_legal"},
  ["logic.bp.route"] = {"search_step", "trial_finish", "result_for", "append_normal_path"},
  ["logic.bp.search"] = {"stage_input"},
  ["logic.bp.validate"] = {"check_geometry", "check_buffer_zones", "check_robo", "check_beacons", "check_power_coverage", "check_wire_legality",
    "check_wire_connectivity", "check_segments", "check_underground", "check_transport_shapes", "check_physical_transfers",
    "check_port_approaches", "check_fluid_mix", "check_ports", "check_machines", "finish"},
  ["logic.bp.plan"] = {},
}
return function(name, src)
  for _, fn in ipairs(targets[name] or {}) do
    local pat = "local function " .. fn .. "("
    local a, b = src:find(pat, 1, true)
    if a then
      local tag = name:match("[^.]+$") .. ":" .. fn
      local q = string.format("%q", tag)
      local rep = "local function " .. fn .. "(...) local f0, t0 = __ttu0(); return __ttu1(" .. q .. ", f0, t0, __TTR[" .. q ..
        "](...)) end; __TTR[" .. q .. "] = function("
      src = src:sub(1, a - 1) .. rep .. src:sub(b + 1)
    else
      io.stderr:write("p_units: no " .. pat .. " in " .. name .. "\n")
    end
  end
  if name == "logic.bp.power" then
    local pat = "        if not consume(budget, cost) then break end\n"
    local a, b = src:find(pat, 1, true); assert(a, "p_units: power consume line")
    src = src:sub(1, b) .. "        __ttm(\"power:\" .. state.cursor.phase)\n" .. src:sub(b + 1)
  end
  return src
end
