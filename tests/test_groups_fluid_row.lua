local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Grid = require "logic.bp.grid"

for _, shape in ipairs(H.shapes()) do
    H.test(shape .. " fluid-fed two-machine step retains a bindable fluid port", function()
        local catalog = {entity = {
            assembler = {name="assembler", tile_w=3, tile_h=3, etype="assembling-machine",
                fluid_boxes={{production_type="input", index=1, pipe_connections={{position={x=-2,y=0},direction=Grid.WEST}}}}},
            inserter={name="inserter",tile_w=1,tile_h=1}},
            inserter={name="inserter",pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}}
        local plan = {steps={{step_id="cast",machine="assembler",machine_count=2,recipe="cast",
            inputs={{port_id="fluid:molten",flow_id="fluid/molten-iron",kind="fluid",is_fluid=true,rate_per_second=10}},
            outputs={{port_id="item:plate",flow_id="item/iron-plate",rate_per_second=1}}}},
            flows={{flow_id="fluid/molten-iron",kind="fluid",is_fluid=true},{flow_id="item/iron-plate"}},
            ports={{port_id="fluid:molten",role="in",kind="fluid",flow_id="fluid/molten-iron",step_id="cast",rate_per_second=10}}}
        local state=Groups.begin({catalog=catalog,plan=plan})
        for _=1,100 do if state.done then break end; Groups.step(state,{ops=10}) end
        H.equal(state.done,true,"grouping finishes")
        local found=false
        for _,c in ipairs(state.result.candidates or {}) do for _,b in ipairs(c.blocks) do
            for _,p in ipairs(b.ports or {}) do if p.kind=="fluid" and p.flow_id=="fluid/molten-iron" then
                found=true; H.equal(p.connection~=nil,true,"fluid port has pipe connection")
            end end
        end end
        H.equal(found,true,"route can bind the molten iron fluid input")
    end)
end
H.done("test_groups_fluid_row")
