--RI1 is red on round-47-base: port-id lookup resolves both duplicate row ids to the last block.
local H=require "tests.harness"
local Route=require "logic.bp.route"
H.test("RI1 bindings retain row block identity",function()
    local lookup=Route._test.ep_lookup
    H.equal(type(lookup),"function","block aware endpoint lookup is exposed")
    local a={port_id="row:in:f",block_id="a",flow_id="f",role="in",x=1,y=0}
    local b={port_id="row:in:f",block_id="b",flow_id="f",role="in",x=2,y=0}
    local src={port_id="source",block_id="p",flow_id="f",role="out",x=0,y=0}
    local work={endpoint_by_id={["row:in:f"]=b,source=src},endpoint_index={f={ ["in"]={a,b},out={src}}},
        segments_by_cell={ ["0:0"]={flow_id="f",direction=4},["1:0"]={flow_id="f",direction=4}}}
    local path=Route._test.binding_path
    local pa=path(work,{source_port_id="source",source_block_id="p",sink_port_id="row:in:f",sink_block_id="a",flow_id="f"})
    local pb=path(work,{source_port_id="source",source_block_id="p",sink_port_id="row:in:f",sink_block_id="b",flow_id="f"})
    H.equal(pa[1],"1:0","first binding reaches its own block sink")
    H.equal(pb[1],"2:0","second binding reaches its own block sink")
    io.write("RI1\n")
end)
H.test("RI2 endpoint lookup falls back without block id",function()
    local lookup=Route._test.ep_lookup
    local endpoint={port_id="x"}; local got=lookup({endpoint_by_id={x=endpoint}},"x",nil,"f","in")
    H.equal(got,endpoint,"missing block id falls back to endpoint_by_id")
    io.write("RI2\n")
end)
H.done("test_route_row_ids")
