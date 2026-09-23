local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"
local Fixture = require "tests.fixtures.row_block"

local copper, gear, pack = Fixture.COPPER, Fixture.GEAR, Fixture.PACK
local catalog = {entity={assembler={name="assembler",tile_w=3,tile_h=3,etype="assembling-machine"},
    inserter={name="inserter",tile_w=1,tile_h=1,pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}},
    inserter={name="inserter",pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}, belt={items_per_second=15}}
local function plan(count, three)
    local ins = {{flow_id=copper,rate_per_second=count,pickup_cell={x=1,y=0}},{flow_id=gear,rate_per_second=count,pickup_cell={x=1,y=0}}}
    if three then ins[#ins+1]={flow_id="item/extra",rate_per_second=count} end
    local steps={{step_id="science",machine="assembler",machine_count=count,recipe="automation-science-pack",inputs=ins,
        outputs={{flow_id=pack,rate_per_second=count}}}}
    local flows={{flow_id=copper},{flow_id=gear},{flow_id=pack}}
    if three then flows[#flows+1]={flow_id="item/extra"} end
    return {steps=steps,flows=flows,ports={}}
end
local function grouped(input)
    input._force_multi_flow_hands = true
    local s=Groups.begin(input)
    for _=1,8 do if s.done then break end; Groups.step(s,{ops=1}) end
    return s.result and s.result.candidates or {}
end
local function row_block(input)
    for _,c in ipairs(grouped(input)) do for _,b in ipairs(c.blocks) do if b.row then return b end end end
end
H.test("GR1 eligible multi-machine recipe is one touching row",function()
    local b=row_block({plan=plan(4),catalog=catalog})
    H.equal(b~=nil,true,"row block exists")
    if not b then return end
    H.equal(b.row.machines,4,"row machine count")
    H.equal(#b.machines,4,"four machines")
    for i=2,#b.machines do H.equal(b.machines[i].x,b.machines[i-1].x+b.machines[i-1].w,"machines touch") end
    local ni,no=0,0
    for _,h in ipairs(b.inserters) do if h.role=="input" then ni=ni+1 else no=no+1 end end
    H.equal(ni,4,"one paired input hand per machine"); H.equal(no,4,"one output hand per machine")
    H.equal(b.allowed_dirs[2],Grid.EAST,"row turns east")
end)
H.test("GR2 row exposes shared belt runs and one port per flow",function()
    local b=row_block({plan=plan(4),catalog=catalog}); H.equal(b~=nil,true,"row exists")
    if not b then return end
    H.equal(#b.belt_runs,2,"one input and output run")
    H.equal(#b.belt_runs[1].tiles,12,"input run spans pickups and head")
    H.equal(#b.ports,3,"one port per item flow")
    H.equal(#b.belt_runs[1].feeds,2,"two head feeds")
end)
H.test("GR3 materialized row exposes rotated runs",function()
    local b=row_block({plan=plan(4),catalog=catalog}); H.equal(b~=nil,true,"row exists")
    if not b then return end
    for _,dir in ipairs({Grid.NORTH,Grid.EAST}) do
        local placed=Groups.materialize(b,{x=10,y=20,dir=dir})
        H.equal(#placed.belt_runs,2,"placed runs")
        H.equal(placed.belt_runs[1].dir,dir==Grid.NORTH and Grid.EAST or Grid.SOUTH,"run direction rotated")
    end
end)
H.test("GR4 one-machine and three-input paths are not row blocks",function()
    H.equal(row_block({plan=plan(1),catalog=catalog})==nil,true,"single machine is legacy")
    H.equal(row_block({plan=plan(4,true),catalog=catalog})==nil,true,"three inputs do not form a row")
end)
H.done("test_groups_rows")
