-- FD10-FD15 red on base 9719cdd (2026-09-30). FD7 follows player grill Q5 (2026-09-30).
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
local function label(s) print(s) end

-- Count from the public layout and input links. Dummies are assigned to their
-- link and layer, so every long edge is expanded into adjacent-layer segments.
local function recount(input, layout, input_order)
    local layer, rank = {}, {}
    if not input_order then
        for id,l in pairs(layout.layer_of or {}) do layer[id]=l; rank[id]=layout.rank_of[id] end
        for _,s in ipairs(layout.sources or {}) do layer["@s:"..tostring(s.flow_id)]=0; rank["@s:"..tostring(s.flow_id)]=s.rank end
        for _,o in ipairs(layout.outputs or {}) do
            local key="@o:"..tostring(o.flow_id); layer[key]=o.layer; rank[key]=o.rank
        end
    else
        for i,n in ipairs(input.nodes or {}) do layer[n.id]=1; rank[n.id]=i end
        local source_rank, output_seen, occupied = 0, {}, {}
        for _,l in ipairs(input.links or {}) do
            if l.ext=="in" and l.flow_id~=nil then
                local key="@s:"..tostring(l.flow_id)
                if layer[key]==nil then source_rank=source_rank+1; layer[key]=0; rank[key]=source_rank end
            end
        end
        for _=1,#(input.nodes or {}) do
            local changed=false
            for _,l in ipairs(input.links or {}) do
                local a=l.a and l.a.block_id; local b=l.b and l.b.block_id
                if a and b and layer[a] and layer[b] and layer[b]<layer[a]+1 then layer[b]=layer[a]+1; changed=true end
            end
            if not changed then break end
        end
        for _,l in ipairs(input.links or {}) do
            if l.ext=="out" and l.flow_id~=nil then
                local key=tostring(l.flow_id)
                if not output_seen[key] then
                    output_seen[key]=true
                    local okey="@o:"..key; local at=(layer[l.a.block_id] or 0)+1
                    while occupied[at] do at=at+1 end
                    occupied[at]=true; layer[okey]=at
                end
            end
        end
        local counts={}
        for _,n in ipairs(input.nodes or {}) do local l=layer[n.id]; counts[l]=(counts[l] or 0)+1; rank[n.id]=counts[l] end
        for _,l in ipairs(input.links or {}) do
            if l.ext=="out" and l.flow_id~=nil then
                local key="@o:"..tostring(l.flow_id)
                if rank[key]==nil then local at=layer[key]; counts[at]=(counts[at] or 0)+1; rank[key]=counts[at] end
            end
        end
    end
    local dummy={}
    for _,d in ipairs(layout.dummies or {}) do dummy[d.link]=dummy[d.link] or {}; dummy[d.link][d.layer]=d.rank end
    local edges, edge_seen, output_producer={},{},{}
    for _,o in ipairs(layout.outputs or {}) do output_producer[tostring(o.flow_id)]=o.producer end
    for li,l in ipairs(input.links or {}) do
        local a=l.a and l.a.block_id; local b=l.b and l.b.block_id
        if l.ext=="in" and b then a="@s:"..tostring(l.flow_id)
        elseif l.ext=="out" and a then a=output_producer[tostring(l.flow_id)]; b="@o:"..tostring(l.flow_id) end
        local key=a and b and tostring(a)..">"..tostring(b)
        if a and b and layer[a]~=nil and layer[b]~=nil and not edge_seen[key] then
            edge_seen[key]=true
            local path={}
            for x=layer[a],layer[b] do
                local id
                if x==layer[a] then id=a elseif x==layer[b] then id=b
                elseif not input_order and dummy[li] then id="@d:"..li..":"..x; rank[id]=dummy[li][x]
                else id="@d:"..li..":"..x end
                if input_order and x>layer[a] and x<layer[b] then
                    -- Input baseline inserts each dummy immediately after its tail.
                    local tailrank=rank[path[#path]] or 0
                    rank[id]=tailrank+0.25
                end
                layer[id]=x; path[#path+1]=id
            end
            edges[#edges+1]=path
        end
    end
    local total=0
    for i=1,#edges do for j=i+1,#edges do
        for k=1,#edges[i]-1 do for m=1,#edges[j]-1 do
            local a,b=edges[i][k],edges[i][k+1]
            local c,d=edges[j][m],edges[j][m+1]
            if layer[a]==layer[c] and layer[b]==layer[d] and (rank[a]-rank[c])*(rank[b]-rank[d])<0 then total=total+1 end
        end end
    end end
    return total
end

H.test("FD1 chain layers Blocks, Source, and Output", function()
    local ns={node("a"),node("b"),node("c")}
    local ls={link("a","b"),link("b","c"),{a={block_id="a",port_id=1},b={edge="left"},flow_id="in",ext="in"},
        {a={block_id="c",port_id=1},b={edge="right"},flow_id="out",ext="out"}}
    local r=draw(ns,ls)
    H.equal(r.crossings,0); H.equal(r.layer_of.a,1); H.equal(r.layer_of.b,2); H.equal(r.layer_of.c,3)
    H.equal(r.outputs[1].layer,4)
    label("FD1")
end)

H.test("FD2 reduces K2,2 to one crossing", function()
    local ns={node("a"),node("b"),node("x"),node("y")}
    local r=draw(ns,{link("a","y"),link("a","x"),link("b","y"),link("b","x")})
    H.equal(r.crossings,1)
    label("FD2")
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
    label("FD3")
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
    label("FD4")
end)

H.test("FD5 every Block consumer is in a later Layer", function()
    for _,edge in ipairs({"left","top","right","bottom"}) do
        local r=draw({node("a"),node("b"),node("c")},{link("a","b"),link("b","c")},{input_edge=edge})
        H.equal(r.layer_of.b>r.layer_of.a,true); H.equal(r.layer_of.c>r.layer_of.b,true)
    end
    label("FD5")
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
    H.equal(recount({nodes=ns,links=ls},r,false),r.crossings)
    H.equal(r.crossings<=recount({nodes=ns,links=ls},r,true),true)
    label("FD6")
end)

H.test("FD7 Block keeps the zero-detour port orientation", function()
    local ports={{port_id=1,role="in",attach_dx=0,attach_dy=-1},{port_id=2,role="in",attach_dx=1,attach_dy=-1},
        {port_id=3,role="out",attach_dx=0,attach_dy=2}}
    local orientations={ ["0|0"]={w=3,h=2,ports={[1]={side=1,place=.5},[3]={side=3,place=.5}}} }
    local r=draw({{id="a",w=3,h=2,ports=ports,orients=orientations}},{},{input_edge="left"})
    H.equal(r.turn_of.a,0)
    label("FD7")
end)

H.test("FD10 Source and Output edges exist", function()
    local g=FlowDraw._test.prepare({nodes={node("a")},input_edge="left",links={
        {a={block_id="a",port_id=1},b={edge="left"},flow_id="in",ext="in"},
        {a={block_id="a",port_id=2},b={edge="right"},flow_id="out",ext="out"}}})
    H.equal(#g.edges,2); H.equal(g.nodes[g.edges[1].a].kind,"source")
    label("FD10")
end)
H.test("FD11 step returns remaining ops", function()
    local s=FlowDraw.begin({nodes={node("a")},links={},restarts=1,sweeps=0})
    local b={ops=5000}; FlowDraw.step(s,b); H.equal(b.ops>=4950,true); label("FD11")
end)
H.test("FD12 port places determine crossings", function()
    local function orient(place) return { ["0|0"]={w=2,h=2,ports={[1]={side=1,place=place},[2]={side=3,place=.5}}} } end
    local ns={{id="a",orients=orient(.5)},{id="x",orients=orient(.9)},{id="y",orients=orient(.1)}}
    local ls={link("a","x"),link("a","y")}; ls[1].b.port_id=1; ls[2].b.port_id=1
    local r=draw(ns,ls,{restarts=1,sweeps=0}); H.equal(r.crossings,0); label("FD12")
end)
H.test("FD13 wrong-side port has detour cost", function()
    local n={id="a",orients={
        ["0|0"]={w=3,h=2,ports={[1]={side=3,place=.5}}},
        ["4|0"]={w=2,h=3,ports={[1]={side=1,place=.5}}}}}
    local r=draw({n},{{a={block_id="a",port_id=1},b={edge="x"},flow_id="i",ext="in"}},{restarts=1,sweeps=0})
    H.equal(r.score,0); H.equal(r.turn_of.a,4); label("FD13")
end)
H.test("FD14 Flip can remove a crossing", function()
    local a={id="a",orients={
        ["0|0"]={w=2,h=2,ports={[1]={side=1,place=.1},[2]={side=1,place=.9}}},
        ["0|1"]={w=2,h=2,ports={[1]={side=3,place=.9},[2]={side=3,place=.1}}}}}
    local b={id="b",orients={["0|0"]={w=2,h=2,ports={[1]={side=1,place=.9},[2]={side=1,place=.1}}}}}
    local r=draw({a,b},{{a={block_id="a",port_id=1},b={block_id="b",port_id=1}},
        {a={block_id="a",port_id=2},b={block_id="b",port_id=2}}},{restarts=1,sweeps=0})
    H.equal(r.mirror_of.a,1); H.equal(r.crossings,0); label("FD14")
end)
H.test("FD15 custom material costs are applied", function()
    local ns={}
    for _,id in ipairs({"a","b"}) do ns[#ns+1]={id=id,orients={["0|0"]={w=2,h=2,ports={[1]={side=3,place=.5,kind="fluid"}}}}} end
    for _,id in ipairs({"x","y"}) do ns[#ns+1]={id=id,orients={["0|0"]={w=2,h=2,ports={[1]={side=1,place=.5,kind="fluid"}}}}} end
    local ls={link("a","x"),link("a","y"),link("b","x"),link("b","y")}
    local r=draw(ns,ls,{restarts=1,sweeps=0,costs={ug_pair=31,belt_tile=4,ptg_pair=29,pipe_tile=3}})
    H.equal(r.crossings>0,true); H.equal(r.score,r.crossings*29); H.equal(r.ug_pred,r.crossings); label("FD15")
end)

H.test("FD8 sliced 12 Block graph stays within its tick budget", function()
    local ns,ls={},{}
    for i=1,12 do
        local ports={[1]={side=1,place=.5,kind="item"}}; local orients={}
        for _,k in ipairs({"0|0","4|0","8|0","12|0","0|1","4|1","8|1","12|1"}) do
            orients[k]={w=3,h=2,ports=ports}
        end
        ns[i]={id="v"..i,w=3,h=2,orients=orients}
    end
    local seed=12345
    for a=1,11 do for b=a+1,12 do
        seed=(seed*1103515245+12345)%2147483648
        if seed%4==0 then ls[#ls+1]=link("v"..a,"v"..b) end
    end end
    for i=1,6 do ls[#ls+1]={a={block_id="v"..i,port_id=1},b={edge="left"},flow_id="src"..i,ext="in"} end
    ls[#ls+1]={a={block_id="v12",port_id=1},b={edge="right"},flow_id="product",ext="out"}
    local input={nodes=ns,links=ls,input_edge="left",output_edge="right",seed=12345,restarts=30,sweeps=8}
    local state=FlowDraw.begin(input); local started=os.clock()
    while not state.done do
        local t=os.clock(); FlowDraw.step(state,{ops=2000})
        H.equal(os.clock()-t<0.02,true)
        H.equal(os.clock()-started<3,true)
    end
    local full=FlowDraw.begin(input); FlowDraw.step(full,{ops=1000000000})
    H.deep_equal(state.result,full.result)
    label("FD8")
end)

H.test("FD9 pinned Output shuffle is valid when Output nodes meet", function()
    local ns={node("a")}; local ls={}
    for i=1,3 do ls[#ls+1]={a={block_id="a",port_id=i},b={edge="right"},flow_id="o"..i,ext="out"} end
    local r=draw(ns,ls,{restarts=30,sweeps=8,output_edge="right"})
    H.equal(#r.outputs,3)
    label("FD9")
end)

H.done("test_flow_draw")
