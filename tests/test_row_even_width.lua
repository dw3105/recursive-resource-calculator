-- RW1 fails on round-41-base: a 4-wide row head puts the side feed on the plain hand.
local H=require "tests.harness"
local Groups=require "logic.bp.groups"
local Grid=require "logic.bp.grid"
local function build(width)
    local catalog={entity={machine={name="machine",tile_w=width,tile_h=width,etype="assembling-machine"},
        inserter={name="inserter",tile_w=1,tile_h=1,pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}},
        inserter={name="inserter",pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}},belt={items_per_second=15}}
    local inputs={{flow_id="item/a",rate_per_second=1},{flow_id="item/b",rate_per_second=1}}
    local plan={steps={{step_id="s",machine="machine",machine_count=3,recipe="r",inputs=inputs,outputs={{flow_id="item/c"}}}},
        flows={{flow_id="item/a"},{flow_id="item/b"},{flow_id="item/c"}}}
    local state=Groups.begin({catalog=catalog,plan=plan}); for _=1,100 do if state.done then break end; Groups.step(state,{ops=10}) end
    for _,c in ipairs(state.result.candidates) do for _,b in ipairs(c.blocks) do if b.row then return b end end end
end
local function key(x,y) return x..":"..y end
H.test("RW1 even width second feed avoids every plain hand and machine",function()
    local b=build(4); H.equal(b~=nil,true,"four-wide row exists"); if not b then return end
    local run; for _,r in ipairs(b.belt_runs) do if r.role=="in" then run=r; break end end
    H.equal(#run.feeds,2,"two feed tiles")
    local second=run.feeds[2].side_tile
    for _,h in ipairs(b.inserters) do if not h.long and h.role=="input" then
        H.equal(key(second.x,second.y)==key(h.x,h.y),false,"second side tile differs from plain hand")
    end end
    for _,m in ipairs(b.machines) do
        H.equal(second.x>=m.x and second.x<m.x+m.w and second.y>=m.y and second.y<m.y+m.h,false,"second side tile outside member")
    end
    H.equal(run.head.x,b.machines[1].x+math.floor((b.machines[1].w-1)/2)-1,"head uses even-width corrected center")
end)
H.test("RW2 odd width row keeps the existing head and feed coordinates",function()
    local b=build(3); H.equal(b~=nil,true,"three-wide row exists"); if not b then return end
    local run; for _,r in ipairs(b.belt_runs) do if r.role=="in" then run=r; break end end
    local x=b.machines[1].x+math.floor(b.machines[1].w/2)
    H.equal(run.head.x,x-1,"odd-width head unchanged")
    H.equal(run.feeds[1].side_tile.x,x-1,"first feed unchanged")
    H.equal(run.feeds[2].side_tile.x,x-1,"second feed unchanged")
end)
H.done("test_row_even_width")
