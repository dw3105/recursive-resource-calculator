-- IP1/IP3 fail on round-41-base: a free interior item port is not marked or accepted.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"
local Validate = require "logic.bp.validate"

local function build()
    local catalog={entity={machine={name="machine",tile_w=3,tile_h=3,etype="assembling-machine"},
        beacon={name="beacon",tile_w=3,tile_h=3,beacon={supply_w=8,supply_h=8}},
        inserter={name="inserter",tile_w=1,tile_h=1}}}
    local plan={steps={{step_id="s",machine="machine",machine_count=1,recipe="r",
        beacon_groups={{signature="b",name="beacon",count_per_machine=2}},
        inputs={{flow_id="item/a",rate_per_second=1}},outputs={{flow_id="item/b",rate_per_second=1,drop_cell={x=3,y=3}}}}},
        flows={{flow_id="item/a"},{flow_id="item/b"}}}
    local state=Groups.begin({catalog=catalog,plan=plan})
    for _=1,100 do if state.done then break end; Groups.step(state,{ops=10}) end
    for _,candidate in ipairs(state.result.candidates) do for _,block in ipairs(candidate.blocks) do return block end end
end
local function validate(port)
    local state=Validate.begin({candidate={grid_w=12,grid_h=12,entities={},blocks={{block_id="b",w=5,h=5,
        ports={port}}}},plan={steps={}},catalog={entity={}}})
    while not state.done do Validate.step(state,{ops=100}) end
    for _,err in ipairs(state.errors or {}) do if err.code=="BP_V_PORT_EDGE_WRONG" then return false end end
    return true
end

H.test("IP1 free item hand port inside a beaconed machine envelope is marked",function()
    local block=build(); H.equal(block~=nil,true); if not block then return end
    local right
    for _,port in ipairs(block.ports or {}) do if port.role=="out" and port.kind=="item" then right=port; break end end
    H.equal(right~=nil,true,"output port exists")
    if right then H.equal(right.interior_free,true,"free interior output attach tile is recorded") end
end)
H.test("IP2 a port on the envelope ring is not marked interior free",function()
    local block=build(); H.equal(block~=nil,true); if not block then return end
    local ring
    for _,port in ipairs(block.ports or {}) do if port.attach_dx==block.w or port.attach_dx==-1 or port.attach_dy==-1 or port.attach_dy==block.h then ring=port; break end end
    H.equal(ring~=nil,true); if ring then H.equal(ring.interior_free == true,false,"ring port stays unmarked") end
end)
H.test("IP3 validator accepts marked interior ports and rejects unmarked ones",function()
    local base={port_id="p",role="out",kind="item",attach_dx=2,attach_dy=2,normal_dir=0}
    local marked={}; for k,v in pairs(base) do marked[k]=v end; marked.interior_free=true
    H.equal(validate(marked),true,"marked inside attach accepted")
    H.equal(validate(base),false,"unmarked inside attach rejected")
end)
H.done("test_groups_interior_port")
