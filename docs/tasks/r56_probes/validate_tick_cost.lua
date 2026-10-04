local H = require "tests.harness"
H.new_world("2.0")
local Validate = require "logic.bp.validate"
for _, path in ipairs(arg) do
  local f = assert(io.open(path, "rb")); local input = helpers.json_to_table(f:read("*a")); f:close()
  local st = Validate.begin(input); local worst, wph = 0, ""
  local nt = tostring
  while not st.done do
    local ph = st.cursor.phase; local instr, ts = 0, 0
    _G.tostring = function(v) ts = ts + 1; return nt(v) end
    debug.sethook(function() instr = instr + 1000 end, "", 1000)
    Validate.step(st, {ops = 4000})
    debug.sethook(); _G.tostring = nt
    local w = instr + 78 * ts
    if w > worst then worst, wph = w, ph end
  end
  print(string.format("%s worst=%.2fM weighted (%.1f ms model) phase=%s", path:match("[^/]+$"), worst/1e6, 20.28*worst/1e6+0.51, wph))
end
