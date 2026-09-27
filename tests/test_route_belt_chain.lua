--BC1 and BC2 fail on round-44-wave3: a belt chain dive is discontinuous, then the retry can turn
--sideways off a source belt without a splitter on the frozen gray + magenta fixture (2026-09-27).
local H = require "tests.harness"
local Route = require "logic.bp.route"

local placed
local function route_fixture_once()
    if placed then return placed end
    H.new_world("2.0")
    local file=assert(io.open("tests/fixtures/route_gray_magenta_154.json","r"))
    local input=assert(helpers.json_to_table(file:read("*a"))); file:close()
    local s=Route.begin(input)
    local wanted={
        ["in:item/coal:inserter:plastic-bar:2:input:1"]="BC1",
        ["in:item/coal:inserter:plastic-bar:1:input:1"]="BC2",
    }
    placed={}
    local deadline=os.clock()+120
    repeat
        for _,b in ipairs(s.work.bindings or {}) do
            if wanted[b.sink_port_id] then placed[b.sink_port_id]=true end
        end
        if placed["in:item/coal:inserter:plastic-bar:2:input:1"]
            and placed["in:item/coal:inserter:plastic-bar:1:input:1"] then break end
        if s.done or os.clock()>=deadline then break end
        Route.step(s,{ops=2000})
    until false
    return placed
end

H.test("BC1 frozen gray and magenta chain dive demand is placed",function()
    io.write("BC1\n")
    H.equal(route_fixture_once()["in:item/coal:inserter:plastic-bar:2:input:1"],true,"chain dive demand is placed")
end)
H.test("BC2 frozen gray and magenta source branch demand is placed",function()
    io.write("BC2\n")
    H.equal(route_fixture_once()["in:item/coal:inserter:plastic-bar:1:input:1"],true,"source branch demand is placed")
end)

H.done("test_route_belt_chain")
