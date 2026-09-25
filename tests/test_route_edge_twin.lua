--This regression fails before the edge-twin tidy: replaying the frozen candidate publishes two map-edge
--terminals for one flow instead of one terminal and a splitter covering the first inside column.
local H = require "tests.harness"
H.test("one edge terminal and a splitter replace neighbouring twins",function()
H.new_world(H.shapes()[1])
local f=assert(io.open("tests/fixtures/route_red10s_final.json","r"))
local input=helpers.json_to_table(f:read("*a")); f:close()
local Route=require "logic.bp.route"
input.tidy=false
local state=Route.begin(input)
while not state.done do Route.step(state,{ops=100000}) end
H.equal(state.ok,true,"fixture route completes")
local tidy=Route.tidy_begin(state,{})
while not tidy.done do Route.tidy_step(tidy,{ops=100000}) end
H.equal(tidy.ok,true,"tidy completes")

--Find the flow from the fixture's pair at x=0, y=37/38; do not encode a product or flow name.
local candidate
for _,flow in ipairs(input.flows) do
    local n=0
    for _,e in ipairs(tidy.result.entities) do
        local seg
        for _,s in ipairs(tidy.result.segments) do if s.segment_id==e.segment_id then seg=s; break end end
        if e.name and math.floor(e.position.x)==0 and (math.floor(e.position.y)==37 or math.floor(e.position.y)==38) then
            for _,a in ipairs(seg and seg.allocations or {}) do if a.flow_id==flow.flow_id then n=n+1 end end
        end
    end
    if n==2 then candidate=flow.flow_id; break end
end
H.equal(candidate~=nil,true,"fixture identifies the twin terminal flow")
local edge,splitter=0,0
for _,e in ipairs(tidy.result.entities) do
    local seg
    for _,s in ipairs(tidy.result.segments) do if s.segment_id==e.segment_id then seg=s; break end end
    local has=false; for _,a in ipairs(seg and seg.allocations or {}) do if a.flow_id==candidate then has=true end end
    if has and math.floor(e.position.x)==0 and (math.floor(e.position.y)==37 or math.floor(e.position.y)==38) then edge=edge+1 end
    if has and e.name==input.catalog.belt.splitter and math.floor(e.position.x)==1 and math.floor(e.position.y)==38 then splitter=splitter+1 end
end
H.equal(edge,1,"one edge terminal remains")
H.equal(splitter,1,"splitter occupies the two first inside tiles")
local sinks={}
for _,b in ipairs(tidy.result.bindings) do if b.flow_id==candidate then sinks[b.sink]=b.rate_per_second end end
local source_flow
for _,flow in ipairs(input.flows) do if flow.flow_id==candidate then source_flow=flow; break end end
H.equal(#source_flow.consumers,2,"both fixture sinks are covered")
for _,consumer in ipairs(source_flow.consumers) do
    local sink="step:"..consumer.step_id
    H.equal(sinks[sink],consumer.share_per_second,"sink keeps its full rate: "..sink)
end
end)
H.done("test_route_edge_twin")
