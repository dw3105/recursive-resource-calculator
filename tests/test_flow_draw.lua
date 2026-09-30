--FD1-FD7 red on round-51-base except FD5: layered Flow graph drawing contract.
local H = require "tests.harness"
local FlowDraw = require "logic.bp.flow_draw"

local function node(id, ports) return {id=id,w=3,h=2,ports=ports or {}} end
local function link(a,b) return {a={block_id=a,port_id=1},b={block_id=b,port_id=1}} end
local function draw(nodes,links,extra)
    local input={nodes=nodes,links=links,input_edge="left",output_edge="right",restarts=12,sweeps=5,seed=71}
    for k,v in pairs(extra or {}) do input[k]=v end
    local state=FlowDraw.begin(input)
    while not FlowDraw.step(state,{ops=1000000000}) do end
    return state.result,input
end

H.test("FD1 chain layers Blocks, Source, and Output", function()
    local ns={node("a"),node("b"),node("c")}
    local ls={link("a","b"),link("b","c"),{a={block_id="a",port_id=1},b={edge="left"},flow_id="in",ext="in"},
        {a={block_id="c",port_id=1},b={edge="right"},flow_id="out",ext="out"}}
    local r=draw(ns,ls)
    H.equal(r.crossings,0); H.equal(r.layer_of.a,1); H.equal(r.layer_of.b,2); H.equal(r.layer_of.c,3)
    H.equal(r.outputs[1].layer,4)
end)

H.test("FD2 reduces K2,2 to one crossing", function()
    local ns={node("a"),node("b"),node("x"),node("y")}
    local r=draw(ns,{link("a","y"),link("a","x"),link("b","y"),link("b","x")})
    H.equal(r.crossings,1)
end)

H.test("FD3 slicing budget does not change the result", function()
    local ns,ls={},{}
    for i=1,12 do ns[i]=node("n"..i) end
    for i=1,11 do ls[#ls+1]=link("n"..i,"n"..(i+1)) end
    for i=1,8 do ls[#ls+1]=link("n"..i,"n"..(i+4)) end
    local input={nodes=ns,links=ls,input_edge="top",output_edge="bottom",seed=9}
    local a=FlowDraw.begin(input); while not FlowDraw.step(a,{ops=1}) do end
    local b=FlowDraw.begin(input); while not FlowDraw.step(b,{ops=1000000000}) do end
    H.deep_equal(a.result,b.result)
end)

H.test("FD4 Outputs sharing producer occupy distinct pinned top-end spots", function()
    local r=draw({node("a")},{{a={block_id="a",port_id=1},b={edge="left"},flow_id="one",ext="out"},
        {a={block_id="a",port_id=2},b={edge="left"},flow_id="two",ext="out"}}, {output_edge="top"})
    H.equal(#r.outputs,2)
    H.equal(r.outputs[1].layer==r.outputs[2].layer and r.outputs[1].rank==r.outputs[2].rank,false)
    for _,o in ipairs(r.outputs) do
        local max=0; for _,x in ipairs(r.layers[o.layer+1] or {}) do max=max+1 end
        H.equal(o.rank,1)
    end
end)

H.test("FD5 every Block consumer is in a later Layer", function()
    for _,edge in ipairs({"left","top","right","bottom"}) do
        local r=draw({node("a"),node("b"),node("c")},{link("a","b"),link("b","c")},{input_edge=edge})
        H.equal(r.layer_of.b>r.layer_of.a,true); H.equal(r.layer_of.c>r.layer_of.b,true)
    end
end)

H.test("FD6 deterministic DAG drawing is no worse than input order", function()
    local ns,ls={},{}
    for i=1,20 do ns[i]=node("v"..i) end
    local seed=12345
    for a=1,19 do for b=a+1,20 do
        seed=(seed*1103515245+12345)%2147483648
        if seed%7==0 then ls[#ls+1]=link("v"..a,"v"..b) end
    end end
    local r=draw(ns,ls,{restarts=30,sweeps=8})
    local layer, rank = {}, {}
    for i=1,20 do layer["v"..i]=1; rank["v"..i]=i end
    for _=1,20 do for _,e in ipairs(ls) do
        local a,b=e.a.block_id,e.b.block_id
        layer[b]=math.max(layer[b],layer[a]+1)
    end end
    for i=1,20 do rank["v"..i]=i end
    local baseline=0
    for i=1,#ls do for j=i+1,#ls do
        local a,b,c,d=ls[i].a.block_id,ls[i].b.block_id,ls[j].a.block_id,ls[j].b.block_id
        if layer[a]==layer[c] and layer[b]==layer[d] and layer[b]==layer[a]+1 and (rank[a]-rank[c])*(rank[b]-rank[d])<0 then baseline=baseline+1 end
    end end
    H.equal(r.crossings<=baseline,true)
end)

H.test("FD7 Turn aligns port roles with input edge", function()
    local ports={{port_id=1,role="in",attach_dx=0,attach_dy=-1},{port_id=2,role="in",attach_dx=1,attach_dy=-1},
        {port_id=3,role="out",attach_dx=0,attach_dy=2}}
    for _,pair in ipairs({{"left",12},{"top",0},{"right",4},{"bottom",8}}) do
        local r=draw({node("a",ports)},{},{input_edge=pair[1]})
        H.equal(r.turn_of.a,pair[2])
    end
end)

H.done("test_flow_draw")
