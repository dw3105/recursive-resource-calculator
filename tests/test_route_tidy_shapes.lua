--Red on round-36-int3: tidy retained pairs over their own surface flow and a side-fed pair on a blocked lane.
local H = require "tests.harness"
local function replay()
    H.new_world(H.shapes()[1])
    local f=assert(io.open("tests/fixtures/route_red10s_stack1_call2.json"))
    local input=helpers.json_to_table(f:read("*a")); f:close()
    local Route=require "logic.bp.route"
    local state=Route.begin(input)
    while not state.done do Route.step(state,{ops=100000}) end
    if state.ok then
        state=Route.tidy_begin(state)
        while not state.done do Route.tidy_step(state,{ops=100000}) end
    end
    return state
end
H.test("TS1 tidy underground middles never carry their own flow",function()
    local state=replay(); H.equal(state.ok,true,"route and tidy complete")
    local work=state.work or state._work
    local checked=0
    for _,s in ipairs(work.segments or {}) do if s.underground and s.kind=="belt" then
        local dx,dy=require("logic.bp.grid").dir_vector(s.direction)
        local distance=math.abs(s.underground_exit_x-s.underground_entry_x)+math.abs(s.underground_exit_y-s.underground_entry_y)
        for i=1,distance-1 do
            local middle=work.segments_by_cell[tostring(s.underground_entry_x+dx*i)..":"..tostring(s.underground_entry_y+dy*i)]
            H.equal(middle and middle.flow_id==s.flow_id or false,false,"middle tile is clear of the pair's flow")
        end
        checked=checked+1
    end end
    H.equal(checked>0,true,"fixture exercises underground routing")
end)
H.test("TS2 underground entrances have a straight feeder",function()
    local state=replay(); H.equal(state.ok,true,"route and tidy complete")
    local work=state.work or state._work
    local Grid=require "logic.bp.grid"
    for _,s in ipairs(work.segments or {}) do if s.underground and s.kind=="belt" then
        local dx,dy=Grid.dir_vector(s.direction)
        local x,y=s.underground_entry_x-dx,s.underground_entry_y-dy
        if x>=0 and y>=0 and x<(work.grid.w or 0) and y<(work.grid.h or 0) then
            local feeder=work.segments_by_cell[tostring(x)..":"..tostring(y)]
            H.equal(feeder and feeder.direction==s.direction or false,true,"non-edge entrance is fed from behind")
        end
    end end
end)
H.done("test_route_tidy_shapes")
