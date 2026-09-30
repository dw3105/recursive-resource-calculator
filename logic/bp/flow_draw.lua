-- Draw the candidate Flow graph before pack. State contains serializable data only.
local FlowDraw = {}

local function side(edge)
    return edge == "left" and 1 or edge == "top" and 2 or edge == "right" and 3 or 4
end
local function turn_side(value, turn) return ((value - 1 + turn / 4) % 4) + 1 end
local function choose_turn(input, node)
    local wanted = side(input.input_edge)
    local away = wanted % 4 + 1
    local best, best_score = 0, -1
    for _, turn in ipairs({0, 4, 8, 12}) do
        local score = 0
        for _, p in ipairs(node.ports or {}) do
            local s
            if p.attach_dx == -1 then s = 1 elseif p.attach_dx == node.w then s = 3
            elseif p.attach_dy == -1 then s = 2 elseif p.attach_dy == node.h then s = 4 end
            if s and p.role == "in" and turn_side(s, turn) == wanted then score = score + 1 end
            if s and p.role == "out" and turn_side(s, turn) == away then score = score + 1 end
        end
        if score > best_score then best, best_score = turn, score end
    end
    return best
end

-- This phase creates numeric node indexes and per-adjacent-layer segment lists.
local function prepare(input)
    local g = {nodes={}, ids={}, edges={}, seg={}, order={}, max_layer=0}
    local id_index, seen, source_index, output_index = {}, {}, {}, {}
    for _, n in ipairs(input.nodes or {}) do
        local ix = #g.nodes + 1
        g.nodes[ix] = {kind="block", id=n.id, layer=1, rank=0, input_order=ix, turn=choose_turn(input,n)}
        g.ids[ix], id_index[n.id] = n.id, ix
    end
    local function add_edge(a,b,link)
        if a and b then
            local k = a .. ":" .. b
            if not seen[k] then seen[k]=true; g.edges[#g.edges+1]={a=a,b=b,link=link} end
        end
    end
    for li, l in ipairs(input.links or {}) do
        local a = l.a and id_index[l.a.block_id]
        local b = l.b and id_index[l.b.block_id]
        if a and b then add_edge(a,b,li)
        elseif l.ext == "in" and l.flow_id ~= nil then
            local key = tostring(l.flow_id)
            local si = source_index[key]
            if not si then
                si=#g.nodes+1; source_index[key]=si
                g.nodes[si]={kind="source",flow_id=l.flow_id,layer=0,rank=0}
            end
            add_edge(si,b,li)
        elseif l.ext == "out" and l.flow_id ~= nil then
            local key=tostring(l.flow_id)
            if not output_index[key] then
                local oi=#g.nodes+1
                output_index[key]=oi
                g.nodes[oi]={kind="output",flow_id=l.flow_id,producer=a,layer=0,rank=0,pinned=true}
            end
        end
    end
    -- Longest-path layering, bounded to #Blocks passes for cyclic input.
    for i=1,#g.ids do g.nodes[i].layer=1 end
    for _=1,#g.ids do
        local changed=false
        for _,e in ipairs(g.edges) do
            local a,b=g.nodes[e.a],g.nodes[e.b]
            if a.kind=="block" and b.kind=="block" and b.layer<a.layer+1 then b.layer=a.layer+1; changed=true end
        end
        if not changed then break end
    end
    for _,e in ipairs(g.edges) do
        if g.nodes[e.a].kind=="source" and g.nodes[e.b].layer<1 then g.nodes[e.b].layer=1 end
    end
    local occupied={}
    for ix=#g.ids+1,#g.nodes do
        local n=g.nodes[ix]
        if n.kind=="output" then
            n.layer=(n.producer and g.nodes[n.producer].layer or 0)+1
            while occupied[n.layer] do n.layer=n.layer+1 end
            occupied[n.layer]=true
        end
    end
    for ix=#g.ids+1,#g.nodes do
        local n=g.nodes[ix]
        if n.kind=="output" and n.producer then g.edges[#g.edges+1]={a=n.producer,b=ix,link=0} end
    end
    for _,e in ipairs(g.edges) do
        local a,b=g.nodes[e.a],g.nodes[e.b]
        local prev=e.a
        e.path={e.a}
        for layer=a.layer+1,b.layer-1 do
            local di=#g.nodes+1
            g.nodes[di]={kind="dummy",layer=layer,rank=0,link=e.link,tail=prev}
            g.nodes[prev].next=di; e.path[#e.path+1]=di; prev=di
        end
        g.nodes[prev].next=e.b; e.path[#e.path+1]=e.b
    end
    for ix,n in ipairs(g.nodes) do
        g.max_layer=math.max(g.max_layer,n.layer)
        g.order[n.layer]=g.order[n.layer] or {}; g.order[n.layer][#g.order[n.layer]+1]=ix
    end
    local bottom=input.output_edge=="bottom" or input.output_edge=="right"
    for l=0,g.max_layer do
        local a=g.order[l] or {}; g.order[l]=a
        -- Stable deterministic starting order, with pinned Outputs at their edge.
        table.sort(a,function(x,y)
            local nx,ny=g.nodes[x],g.nodes[y]
            if nx.kind=="source" or ny.kind=="source" then return nx.kind=="source" and ny.kind~="source" end
            if nx.kind=="output" or ny.kind=="output" then
                if nx.kind==ny.kind then return x<y end
                return bottom and ny.kind=="output" or nx.kind=="output"
            end
            local kx=nx.kind=="block" and nx.input_order or (nx.tail or 0)+0.25
            local ky=ny.kind=="block" and ny.input_order or (ny.tail or 0)+0.25
            return kx==ky and x<y or kx<ky
        end)
        for rank,ix in ipairs(a) do g.nodes[ix].rank=rank end
    end
    -- Precompute segment endpoint node indexes, grouped by layer pair.
    g.neighbors={}
    for _,e in ipairs(g.edges) do
        for i=1,#e.path-1 do
            local x,y=e.path[i],e.path[i+1]
            local l=g.nodes[x].layer
            g.seg[l]=g.seg[l] or {}; g.seg[l][#g.seg[l]+1]={x,y}
            g.neighbors[x]=g.neighbors[x] or {}; g.neighbors[x][l+1]=g.neighbors[x][l+1] or {}
            g.neighbors[x][l+1][#g.neighbors[x][l+1]+1]=y
            g.neighbors[y]=g.neighbors[y] or {}; g.neighbors[y][l]=g.neighbors[y][l] or {}
            g.neighbors[y][l][#g.neighbors[y][l]+1]=x
        end
    end
    return g
end

local function rank_update(g,l)
    for i,ix in ipairs(g.order[l]) do g.nodes[ix].rank=i end
end
local function neighbours(g,ix,l)
    return (g.neighbors[ix] and g.neighbors[ix][l]) or {}
end
local function snapshot(g)
    local c={}; for l=0,g.max_layer do c[l]={}; for i,x in ipairs(g.order[l]) do c[l][i]=x end end; return c
end
local function restore(g,c)
    for l=0,g.max_layer do g.order[l]={}; for i,x in ipairs(c[l]) do g.order[l][i]=x end; rank_update(g,l) end
end
local function pair_cost(g,u,v)
    local cost=0
    for _,l in ipairs({g.nodes[u].layer-1,g.nodes[u].layer+1}) do
        if l>=0 and l<=g.max_layer then
            local nu=g.neighbors[u] and g.neighbors[u][l] or {}
            local nv=g.neighbors[v] and g.neighbors[v][l] or {}
            for _,a in ipairs(nu) do for _,b in ipairs(nv) do if g.nodes[a].rank>g.nodes[b].rank then cost=cost+1 end end end
        end
    end
    return cost
end

local function result(g,best,crossings)
    restore(g,best)
    local r={layer_of={},rank_of={},layers={},sources={},outputs={},dummies={},crossings=crossings,turn_of={}}
    for l=0,g.max_layer do
        r.layers[l+1]={}
        for _,ix in ipairs(g.order[l]) do
            local n=g.nodes[ix]
            if n.kind=="block" then r.layer_of[n.id]=l; r.rank_of[n.id]=n.rank; r.layers[l+1][#r.layers[l+1]+1]=n.id; r.turn_of[n.id]=n.turn
            elseif n.kind=="source" then r.sources[#r.sources+1]={flow_id=n.flow_id,rank=n.rank}
            elseif n.kind=="output" then r.outputs[#r.outputs+1]={flow_id=n.flow_id,producer=n.producer and g.nodes[n.producer].id,layer=l,rank=n.rank}
            elseif n.kind=="dummy" then r.dummies[#r.dummies+1]={link=n.link,layer=l,rank=n.rank} end
        end
    end
    return r
end

function FlowDraw.begin(input)
    return {input=input,done=false,result=nil,cursor={phase="build",restart=1,sweep=1,layer=0,pass=1,i=1}}
end

function FlowDraw.step(state,budget)
    if state.done then return true end
    budget=budget or {ops=1000000000}
    local allowance=budget.ops or 0
    while allowance>0 and not state.done do
        local c=state.cursor
        if c.phase=="build" then
            state.graph=prepare(state.input)
            local g=state.graph
            state.order=g.order
            state.initial=snapshot(g); state.best=snapshot(g); state.best_crossings=nil
            state.restarts=math.max(1,tonumber(state.input.restarts) or 30)
            state.sweeps=math.max(0,tonumber(state.input.sweeps) or 8)
            state.rng=tonumber(state.input.seed) or 1
            c.phase="restart"
        elseif c.phase=="restart" then
            local g=state.graph
            if c.restart>state.restarts then
                state.result=result(g,state.best,state.best_crossings or 0); state.graph=nil; state.done=true
            elseif c.restart>1 and c.shuffle_layer<=g.max_layer then
                if c.shuffle_layer==0 and c.shuffle_i==2 then restore(g,state.initial) end
                local l=c.shuffle_layer; local a=g.order[l]
                if c.shuffle_i>#a then
                    -- Keep pinned outputs in place by extracting them before reordering.
                    local moving,pinned={},{}
                    for _,ix in ipairs(a) do if g.nodes[ix].kind=="output" then pinned[#pinned+1]=ix else moving[#moving+1]=ix end end
                    for i=#moving,2,-1 do state.rng=(state.rng*1103515245+c.restart*12345)%2147483648; local j=math.floor(state.rng%i)+1; moving[i],moving[j]=moving[j],moving[i] end
                    if state.input.output_edge=="top" or state.input.output_edge=="left" then
                        for i=#pinned,1,-1 do table.insert(moving,1,pinned[i]) end
                    else for _,ix in ipairs(pinned) do moving[#moving+1]=ix end end
                    g.order[l]=moving; rank_update(g,l); c.shuffle_layer=l+1; c.shuffle_i=1
                else c.shuffle_i=c.shuffle_i+1; allowance=allowance-1 end
            else
                c.phase="bary"; c.down=true; c.layer=c.down and 1 or g.max_layer-1; c.node_pos=1; c.neighbor_pos=1; c.sum=0; c.count=0
            end
        elseif c.phase=="bary" then
            local g=state.graph
            local stop=c.down and g.max_layer or 0
            local step=c.down and 1 or -1
            if (c.down and c.layer>stop) or (not c.down and c.layer<stop) then
                c.phase="transpose"; c.layer=0; c.pass=1; c.i=1; c.changed=false
            else
                local a=g.order[c.layer]; local ix=a[c.node_pos]
                if not ix then c.layer=c.layer+step; c.node_pos=1; c.neighbor_pos=1; c.sum=0; c.count=0
                else
                    local n=g.nodes[ix]
                    if n.kind=="output" then c.node_pos=c.node_pos+1; c.neighbor_pos=1
                    else
                        if c.neighbor_node~=ix then c.neighbors=neighbours(g,ix,c.layer-step); c.neighbor_node=ix; c.neighbor_pos=1 end
                        local ns=c.neighbors or {}; local ni=ns[c.neighbor_pos]
                        if ni then c.sum=c.sum+g.nodes[ni].rank; c.count=c.count+1; c.neighbor_pos=c.neighbor_pos+1; allowance=allowance-1
                        else n.key=c.count>0 and c.sum/c.count or c.node_pos; c.node_pos=c.node_pos+1; c.neighbor_pos=1; c.neighbor_node=nil; c.neighbors=nil; c.sum=0; c.count=0 end
                    end
                    if c.node_pos>#a then
                        local moving,pinned={},{}
                        for _,j in ipairs(a) do if g.nodes[j].kind=="output" then pinned[#pinned+1]=j else moving[#moving+1]=j end end
                        table.sort(moving,function(x,y) local nx,ny=g.nodes[x],g.nodes[y]; local kx=nx.key or nx.rank; local ky=ny.key or ny.rank; return kx==ky and nx.rank<ny.rank or kx<ky end)
                        if state.input.output_edge=="top" or state.input.output_edge=="left" then
                            for j=#pinned,1,-1 do table.insert(moving,1,pinned[j]) end
                        else for _,j in ipairs(pinned) do moving[#moving+1]=j end end
                        g.order[c.layer]=moving; a=moving
                        for _,j in ipairs(a) do g.nodes[j].key=nil end; rank_update(g,c.layer); c.layer=c.layer+step; c.node_pos=1; c.neighbor_pos=1
                    end
                end
            end
        elseif c.phase=="transpose" then
            local g=state.graph
            if c.layer>g.max_layer then
                c.phase="count"; c.count_layer=0; c.pair_i=1; c.pair_j=2; c.crossings=0
            else
                local a=g.order[c.layer]
                if c.i>=#a then
                    c.layer=c.layer+1; c.i=1
                    if c.layer>g.max_layer and (not c.changed or c.pass>=10) then c.phase="count"; c.count_layer=0; c.pair_i=1; c.pair_j=2; c.crossings=0
                    elseif c.layer>g.max_layer then c.layer=0; c.pass=c.pass+1; c.changed=false end
                else
                    local u,v=a[c.i],a[c.i+1]
                    if g.nodes[u].kind~="output" and g.nodes[v].kind~="output" and pair_cost(g,v,u)<pair_cost(g,u,v) then a[c.i],a[c.i+1]=v,u; rank_update(g,c.layer); c.changed=true end
                    c.i=c.i+1; allowance=allowance-1
                end
            end
        elseif c.phase=="count" then
            local g=state.graph
            while c.count_layer<=g.max_layer and not g.seg[c.count_layer] do c.count_layer=c.count_layer+1; c.pair_i=1; c.pair_j=2 end
            if c.count_layer>g.max_layer then
                if state.best_crossings==nil or c.crossings<state.best_crossings then state.best_crossings=c.crossings; state.best=snapshot(g) end
                c.sweep=c.sweep+1
                if c.sweep>state.sweeps then c.restart=c.restart+1; c.sweep=1; c.shuffle_layer=0; c.shuffle_i=2; c.phase="restart"
                else c.phase="bary"; c.down=not c.down; c.layer=c.down and 1 or g.max_layer-1; c.node_pos=1; c.neighbor_pos=1; c.sum=0; c.count=0 end
            else
                local s=g.seg[c.count_layer]
                if c.pair_i>=#s then c.count_layer=c.count_layer+1; c.pair_i=1; c.pair_j=2
                elseif c.pair_j>#s then c.pair_i=c.pair_i+1; c.pair_j=c.pair_i+1
                else
                    local a,b=s[c.pair_i],s[c.pair_j]
                    local x1,x2=g.nodes[a[1]].rank,g.nodes[b[1]].rank; local y1,y2=g.nodes[a[2]].rank,g.nodes[b[2]].rank
                    if (x1-x2)*(y1-y2)<0 then c.crossings=c.crossings+1 end
                    c.pair_j=c.pair_j+1; allowance=allowance-1
                end
            end
        end
    end
    if budget.ops then budget.ops=math.max(0,budget.ops-allowance) end
    return state.done
end

return FlowDraw
