-- NR1/NR2 are expected to fail on base code: blocked floods replay in later direction orders.
local passed, failed = 0, 0
local function check(ok, label) if ok then passed = passed + 1 else failed = failed + 1; io.write("FAIL ", label, "\n") end end
local function run(cmd)
    local p = assert(io.popen(cmd .. " 2>&1", "r")); local s = p:read("*a"); p:close(); return s
end
local patch_path = os.tmpname() .. ".lua"
local f = assert(io.open(patch_path, "w"))
f:write([[return function(name, src)
 if name ~= "logic.bp.route" then return src end
 local needle = "local function begin_search(work, demand, amount, order_index)"
 local a,b = assert(src:find(needle,1,true))
 src = src:sub(1,b) .. " if order_index > 1 then _G.__nr_orders = (_G.__nr_orders or 0) + 1; io.stderr:write('NR_ORDERS 1\\n') end" .. src:sub(b+1)
 return src
end]])
f:close()
local snap = "tests/fixtures/route_snaps/stack1_restart27.lua.gz"
local out = run("lua5.2 tools/ckpt.lua resume " .. snap .. " --until kind=route-restart --patch " .. patch_path)
os.remove(patch_path)
local count = select(2, out:gsub("NR_ORDERS 1", ""))
io.write("NR1\n")
check(count == 0, "no begin_search calls with order_index > 1; got " .. tostring(count) .. "\n" .. out)

local Grid = require "logic.bp.grid"
package.preload["logic.bp.route"] = function()
    local f = assert(io.open("logic/bp/route.lua", "r")); local src = f:read("*a"); f:close()
    local head = "local function begin_search(work, demand, amount, order_index)"
    local _, finish = assert(src:find(head, 1, true))
    src = src:sub(1, finish) .. " if order_index > 1 then _G.__nr_unit_orders = (_G.__nr_unit_orders or 0) + 1 end\n" .. src:sub(finish + 1)
    return assert(load(src, "@logic/bp/route.lua"))()
end
local Route = require "logic.bp.route"
local input = {
    grid = Grid.new(12, 5), max_expansions = 500,
    catalog = {belt = {belt = "basic-belt", items_per_second = 10}},
    obstacles = {{x = 5, y = 0, w = 1, h = 5, owner = "wall"}},
    blocks = {
        {block_id = "source", machines = {{step_id = "source"}}, x = 1, y = 2, w = 1, h = 1, ports = {{
            port_id = "source-out", role = "out", kind = "item", flow_id = "item/wall", rate_per_second = 1,
            attach_dx = 1, attach_dy = 0, normal_dir = Grid.WEST, travel_dir = Grid.EAST}}},
        {block_id = "sink", machines = {{step_id = "sink"}}, x = 8, y = 2, w = 1, h = 1, ports = {{
            port_id = "sink-in", role = "in", kind = "item", flow_id = "item/wall", rate_per_second = 1,
            attach_dx = -1, attach_dy = 0, normal_dir = Grid.EAST, travel_dir = Grid.EAST}}},
    },
    flows = {{flow_id = "item/wall", producers = {{step_id = "source", share_per_second = 1}},
        consumers = {{step_id = "sink", share_per_second = 1}}}},
}
local state = Route.begin(input); local ticks = 0
while not state.done and ticks < 50000 do Route.step(state, {ops = 2000}); ticks = ticks + 1 end
io.write("NR2\n")
check(state.done, "blocked route reaches next candidate/fail path without looping")
check((_G.__nr_unit_orders or 0) == 0, "blocked route did not begin a second direction-order search")
io.write("test_route_no_replay: " .. passed .. " passed, " .. failed .. " failed\n")
