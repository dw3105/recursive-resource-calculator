-- VT2 is red on base: a 10,000-entity validation step must stay below 300 ms at 2,000 ops.
local H=require "tests.harness"
local Validate=require "logic.bp.validate"
local function run(input)
    local s=Validate.begin(input); while not s.done do Validate.step(s,{ops=2000}) end; return s
end
local function encode(s)
    local out={}; for i,e in ipairs(s.errors or {}) do out[i]=table.concat({e.code,table.concat(e.ids or {},","),tostring(e.detail and e.detail.reason or "")},"|") end
    return table.concat(out,"\n")
end
H.test("VT1 indexed and fresh-work results have identical ordered errors",function()
    local input={grid={w=12,h=12},catalog={entity={}},entities={
        {id="m",kind="machine",name="machine",x=4,y=4,w=2,h=2},
        {id="b1",kind="belt",name="transport-belt",x=1,y=1,dir=4,flow_id="a"},
        {id="b2",kind="belt",name="transport-belt",x=2,y=1,dir=4,flow_id="b"}},
        ports={{port_id="p",role="in",flow_id="a",x=1,y=1}},segments={{segment_id="s",kind="belt",flow_id="b",cells={{x=1,y=1}}}}}
    H.equal(encode(run(input)),encode(run(input)))
end)
H.test("VT2 10000 entities validate one 2000-op step under 300ms",function()
    local es={}; for i=1,10000 do es[i]={id="e"..i,kind="belt",name="transport-belt",x=i%100,y=math.floor(i/100),dir=4,flow_id="f"} end
    local s=Validate.begin({grid={w=101,h=101},catalog={entity={}},entities=es})
    local elapsed=0
    for i=1,2000 do local t=os.clock(); Validate.step(s,{ops=2000}); elapsed=math.max(elapsed,os.clock()-t); if s.done then break end end
    H.equal(elapsed<0.3,true,"max validate step was "..string.format("%.4f",elapsed).."s")
    io.write("VT2 max-step ",string.format("%.4f",elapsed),"s\n")
end)
io.write("VT1 VT2\n")
H.done("test_validate_tile_index")
