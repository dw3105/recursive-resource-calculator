-- FB1 fails on round-41-base: multiple recipe fluids all select the same role box.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"

local names = {"a", "b", "c", "d", "e"}
local function run(multiple)
    local boxes = {
        {index=1,production_type="input",connections={{position={x=-2,y=-2}}}},
        {index=2,production_type="input",connections={{position={x=2,y=-2}}}},
        {index=3,production_type="output",connections={{position={x=-2,y=2}}}},
        {index=4,production_type="output",connections={{position={x=0,y=2}}}},
        {index=5,production_type="output",connections={{position={x=2,y=2}}}},
    }
    local inputs, outputs, ingredients, results, flows, ports = {}, {}, {}, {}, {}, {}
    local ni, no = multiple and 2 or 1, multiple and 3 or 0
    for i=1,ni do
        local fid="fluid/"..names[i]; inputs[i]={flow_id=fid,kind="fluid",is_fluid=true,port_id="in"..i}
        ingredients[i]={name=names[i],type="fluid"}; flows[#flows+1]={flow_id=fid,kind="fluid",is_fluid=true}
        ports[#ports+1]={port_id="in"..i,role="in",kind="fluid",flow_id=fid,step_id="s"}
    end
    for i=1,no do
        local n=names[i+2]; local fid="fluid/"..n
        outputs[i]={flow_id=fid,kind="fluid",is_fluid=true,port_id="out"..i}
        results[i]={name=n,type="fluid"}; flows[#flows+1]={flow_id=fid,kind="fluid",is_fluid=true}
        ports[#ports+1]={port_id="out"..i,role="out",kind="fluid",flow_id=fid,step_id="s"}
    end
    if not multiple then
        inputs[2]={flow_id="item/x",port_id="item"}; flows[#flows+1]={flow_id="item/x"}
    end
    local catalog={entity={machine={name="machine",tile_w=5,tile_h=5,etype="assembling-machine",fluid_boxes=boxes}},
        recipe={r={ingredients=ingredients,results=results}}}
    local plan={steps={{step_id="s",machine="machine",recipe="r",machine_count=1,inputs=inputs,outputs=outputs}},flows=flows,ports=ports}
    local state=Groups.begin({catalog=catalog,plan=plan})
    for _=1,100 do if state.done then break end; Groups.step(state,{ops=10}) end
    local found={}
    for _,c in ipairs(state.result.candidates) do for _,b in ipairs(c.blocks) do for _,p in ipairs(b.ports) do
        if p.kind=="fluid" then found[p.flow_id]={box=p.fluidbox_index,x=p.connection.position.x,y=p.connection.position.y} end
    end end end
    return found
end

H.test("FB1 recipe fluids occupy their ordered distinct boxes",function()
    local found=run(true)
    for i=1,5 do
        local fid="fluid/"..names[i]
        H.equal(found[fid]~=nil,true,fid.." port exists")
        H.equal(found[fid].box,i,fid.." selects box "..i)
    end
    local tiles={}; for _,v in pairs(found) do tiles[v.x..":"..v.y]=true end
    local count=0; for _ in pairs(tiles) do count=count+1 end
    H.equal(count,5,"five fluid ports occupy five tiles")
end)

H.test("FB2 one fluid input keeps the current first-box choice beside an item",function()
    local found=run(false)
    H.equal(found["fluid/a"].box,1,"single input stays on box 1")
end)
H.test("FB3 a fluid bound to merged boxes takes the first box as an input and the last as an output",function()
    --Round 54 integrator: the engine binds a one-fluid recipe to every box of a role (chemical plant: water 1+2,
    --product 3+4). bound[1] for the product put a stacked plant's output pipe on the next plant's water tile.
    local boxes = {
        {index=1,production_type="input",connections={{position={x=-1,y=-2}}}},
        {index=2,production_type="input",connections={{position={x=1,y=-2}}}},
        {index=3,production_type="output",connections={{position={x=-1,y=2}}}},
        {index=4,production_type="output",connections={{position={x=1,y=2}}}},
    }
    local flows={{flow_id="fluid/a",kind="fluid",is_fluid=true},{flow_id="fluid/c",kind="fluid",is_fluid=true}}
    local catalog={entity={machine={name="machine",tile_w=3,tile_h=3,etype="assembling-machine",fluid_boxes=boxes}},
        recipe={r={ingredients={{name="a",type="fluid"}},results={{name="c",type="fluid"}},
            fluid_boxes={machine={a={box=1,boxes={1,2},role="input"},c={box=3,boxes={3,4},role="output"}}}}}}
    local plan={steps={{step_id="s",machine="machine",recipe="r",machine_count=1,
        inputs={{flow_id="fluid/a",name="a",kind="fluid",is_fluid=true,port_id="in1"}},
        outputs={{flow_id="fluid/c",name="c",kind="fluid",is_fluid=true,port_id="out1"}}}},flows=flows,
        ports={{port_id="in1",role="in",kind="fluid",flow_id="fluid/a",step_id="s"},
            {port_id="out1",role="out",kind="fluid",flow_id="fluid/c",step_id="s"}}}
    local state=Groups.begin({catalog=catalog,plan=plan})
    for _=1,100 do if state.done then break end; Groups.step(state,{ops=10}) end
    local found={}
    for _,c in ipairs(state.result.candidates) do for _,b in ipairs(c.blocks) do for _,p in ipairs(b.ports) do
        if p.kind=="fluid" then found[p.flow_id]=p.fluidbox_index end
    end end end
    H.equal(found["fluid/a"],1,"input takes the first bound box")
    H.equal(found["fluid/c"],4,"output takes the last bound box")
end)
H.done("test_groups_fluid_box_order")
