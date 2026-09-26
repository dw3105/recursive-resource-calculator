--These cases fail on round-41-base: crowded fluid fronts collide, pipe branches miss connected networks, and underground pipe ends seed branches.
local H = require "tests.harness"
local Route = require "logic.bp.route"
local Grid = require "logic.bp.grid"

local function port(id, role, flow, dx, dy, x, y)
    return {port_id=id,role=role,kind="fluid",flow_id="fluid/"..flow,rate_per_second=1,x=x,y=y,
        attach_dx=dx,attach_dy=dy,normal_dir=Grid.EAST,travel_dir=Grid.EAST}
end
local function block(id, x, y, ports)
    return {block_id=id,machines={{step_id=id}},x=x,y=y,w=1,h=1,ports=ports}
end
local function input(blocks, flows, grid)
    return {grid=Grid.new(grid or 24,16),catalog={pipe={pipe="pipe",underground="underground-pipe",
        throughput_per_second=100,underground_max_distance=5}},blocks=blocks,flows=flows}
end
local function flow(id, source, sinks)
    local consumers={}
    for _, sink in ipairs(sinks) do consumers[#consumers+1]={step_id=sink,share_per_second=1} end
    return {flow_id="fluid/"..id,is_fluid=true,producers={{step_id=source,share_per_second=1}},consumers=consumers}
end
local function route(i)
    local s=Route.begin(i); local n=0
    while not s.done and n<20000 do n=n+1; Route.step(s,{ops=10000}) end
    H.equal(s.done,true,"route finishes")
    H.equal(s.ok,true,"route succeeds "..tostring(s.errors and s.errors[1] and s.errors[1].code))
    return s
end
local function pipe_at(state,x,y)
    for _,e in ipairs(state.result.entities or {}) do
        if e.name=="pipe" and math.floor(e.position.x)==x and math.floor(e.position.y)==y then return true end
    end
    return false
end

H.test("CF1 three fluid outputs from one crowded machine route",function()
    local machine=block("crowded",8,7,{port("out-a","out","a",1,0,10,5),port("out-b","out","b",0,1,10,7),port("out-c","out","c",-1,0,10,9)})
    local blocks={machine}
    local flows={}
    for _,v in ipairs({{"a", "sink-a",15,3},{"b", "sink-b",15,7},{"c", "sink-c",15,11}}) do
        blocks[#blocks+1]=block(v[2],v[3],v[4],{port(v[2].."-in","in",v[1],-1,0,v[3]-1,v[4])})
        flows[#flows+1]=flow(v[1],"crowded",{v[2]})
    end
    local s=route(input(blocks,flows))
    H.equal(#(s.result.shortfalls or {}),0,"no fluid shortfall")
end)

H.test("CF2 new branch joins an existing same flow network",function()
    local a=block("source-a",2,3,{port("a-out","out","a",1,0)})
    local b=block("source-b",2,10,{port("b-out","out","a",1,0)})
    local sink=block("sink",19,7,{port("sink-in","in","a",-1,0)})
    local s=route(input({a,b,sink},{flow("a","source-a",{"sink"}),flow("a","source-b",{"sink"})}))
    H.equal(#(s.result.shortfalls or {}),0,"no shortfall")
    H.equal(pipe_at(s,10,7),true,"branches join shared route")
end)

H.test("CF3 underground pipe ends are never branch seeds",function()
    local a=block("source",2,7,{port("out","out","a",1,0)})
    local b=block("sink",19,7,{port("in","in","a",-1,0)})
    local s=route(input({a,b},{flow("a","source",{"sink"})}))
    local buried={}
    for _,e in ipairs(s.result.entities or {}) do
        if e.ug_role then buried[math.floor(e.position.x)..":"..math.floor(e.position.y)]=true end
    end
    for _,binding in ipairs(s.result.bindings or {}) do
        local p=binding.path or {}
        if p[1] then H.equal(buried[math.floor(p[1].x)..":"..math.floor(p[1].y)] or false,false,"branch does not seed underground") end
    end
end)

H.test("CF4 single fluid port remains on its base route",function()
    local a=block("source",2,7,{port("out","out","a",1,0)})
    local b=block("sink",12,7,{port("in","in","a",-1,0)})
    local s=route(input({a,b},{flow("a","source",{"sink"})},16))
    local names={}
    for _,e in ipairs(s.result.entities or {}) do names[#names+1]=e.name..":"..e.position.x..":"..e.position.y..":"..tostring(e.dir) end
    H.equal(table.concat(names,"|"),"pipe:3.5:7.5:4|pipe:4.5:7.5:4|pipe:5.5:7.5:4|pipe:6.5:7.5:4|pipe:7.5:7.5:4|pipe:8.5:7.5:4|pipe:9.5:7.5:4|pipe:10.5:7.5:4|pipe:11.5:7.5:4","same entities as base")
end)
H.done("test_route_crowded_fluids")
