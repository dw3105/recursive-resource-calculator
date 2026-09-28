-- Route-only replay of a frozen route input. Env: RIN=<route input json>, PATCHES=a.lua,b.lua, LIMIT=<cpu s>, TIDY=1.
-- Last line: ROUTE ok=<bool> code=<code> cpu=<s> ticks=<n> restarts=<n> expansions=<n> entities=<n> shortfalls=<n> digest=<sha256 16>
package.path = "./?.lua;./?/init.lua;" .. package.path
local fns = {}
for path in (os.getenv("PATCHES") or ""):gmatch("[^,]+") do fns[#fns + 1] = assert(loadfile(path))() end
for _, name in ipairs({"logic.bp.grid", "logic.bp.route"}) do
    package.preload[name] = function()
        local f = assert(io.open((name:gsub("%.", "/")) .. ".lua")); local src = f:read("*a"); f:close()
        for _, fn in ipairs(fns) do src = assert(fn(name, src)) end
        return assert(load(src, "@" .. name:gsub("%.", "/") .. ".lua"))()
    end
end
local H = require "tests.harness"
H.new_world("2.0")
local f = assert(io.open(os.getenv("RIN"))); local input = assert(helpers.json_to_table(f:read("*a"))); f:close()
local Route = require "logic.bp.route"
local limit = tonumber(os.getenv("LIMIT") or "1800")
local t0, ticks = os.clock(), 0
local st = Route.begin(input)
local last_report = t0
while not st.done do
    Route.step(st, {ops = 2000})
    ticks = ticks + 1
    local now = os.clock()
    if now - last_report > 30 then
        last_report = now
        io.stdout:write(string.format("PROGRESS cpu=%.0f ticks=%d restarts=%s demand=%s/%s\n", now - t0, ticks,
            tostring(st.counters and st.counters.restarts), tostring(st.cursor and st.cursor.demand_index),
            tostring(st.work and st.work.demands and #st.work.demands))); io.stdout:flush()
    end
    if now - t0 > limit then print(string.format("STUCK cpu=%.0f ticks=%d restarts=%s", now - t0, ticks, tostring(st.counters and st.counters.restarts))); os.exit(0) end
end
local entities = st.result and st.result.entities or {}
local rows = {}
for _, e in ipairs(entities) do
    rows[#rows + 1] = string.format("%s|%.1f|%.1f|%s|%s", tostring(e.name), e.position.x, e.position.y, tostring(e.direction), tostring(e.type))
end
table.sort(rows)
local tmp = os.tmpname()
local out = assert(io.open(tmp, "w")); out:write(table.concat(rows, "\n")); out:close()
local p = assert(io.popen("sha256sum " .. tmp)); local digest = p:read("*l"):sub(1, 16); p:close(); os.remove(tmp)
print(string.format("ROUTE ok=%s code=%s cpu=%.1f ticks=%d restarts=%s expansions=%s entities=%d shortfalls=%d digest=%s",
    tostring(st.ok), tostring(st.errors and st.errors[1] and st.errors[1].code), os.clock() - t0, ticks,
    tostring(st.counters and st.counters.restarts), tostring(st.counters and st.counters.expansions), #entities,
    #(st.result and st.result.shortfalls or {}), digest))
