-- See the frozen contract above: this module draws the candidate Flow graph before pack.
local FlowDraw = {}

local function endpoint(end_)
    return end_ and end_.block_id
end

local function edge_side(edge)
    return edge == "left" and 1 or edge == "top" and 2 or edge == "right" and 3 or 4
end

local function turned(side, turns)
    return ((side - 1 + turns / 4) % 4) + 1
end

local function port_side(node, port)
    if port.attach_dx == -1 then return 1 end
    if port.attach_dx == node.w then return 3 end
    if port.attach_dy == -1 then return 2 end
    if port.attach_dy == node.h then return 4 end
end

local function turns(input, node)
    local best, score = 0, -1
    local wanted, away = edge_side(input.input_edge), edge_side(input.input_edge)
    away = ((away + 1) % 4) + 1
    for _, turn in ipairs({0, 4, 8, 12}) do
        local value = 0
        for _, port in ipairs(node.ports or {}) do
            local side = port_side(node, port)
            if side and port.role == "in" and turned(side, turn) == wanted then value = value + 1 end
            if side and port.role == "out" and turned(side, turn) == away then value = value + 1 end
        end
        if value > score then best, score = turn, value end
    end
    return best
end

local function build(input)
    local blocks, ids, known, order = {}, {}, {}, {}
    for _, node in ipairs(input.nodes or {}) do
        blocks[node.id], known[node.id] = node, true
        ids[#ids + 1] = node.id
        order[node.id] = #ids
    end
    local edges, edge_seen, source_ids, output_ids, source_seen, output_seen = {}, {}, {}, {}, {}, {}
    for li, link in ipairs(input.links or {}) do
        local a, b = endpoint(link.a), endpoint(link.b)
        if a and b and known[a] and known[b] then
            local key = "b|" .. tostring(a) .. "|" .. tostring(b)
            if not edge_seen[key] then edges[#edges + 1] = {a=a,b=b,link=li}; edge_seen[key] = true end
        elseif link.ext == "in" and link.flow_id ~= nil then
            local key = tostring(link.flow_id)
            if not source_seen[key] then source_seen[key]=true; source_ids[#source_ids+1]=link.flow_id end
            local ekey = "s|"..key.."|"..tostring(b)
            if b and known[b] and not edge_seen[ekey] then edges[#edges+1]={source=key,b=b,link=li}; edge_seen[ekey]=true end
        elseif link.ext == "out" and link.flow_id ~= nil then
            local key = tostring(link.flow_id)
            if not output_seen[key] then output_seen[key]=true; output_ids[#output_ids+1]={flow_id=link.flow_id,producer=a} end
        end
    end
    local layer, sources = {}, {}
    for _, fid in ipairs(source_ids) do sources[tostring(fid)] = {kind="source", flow_id=fid, layer=0, pinned=false} end
    for _, id in ipairs(ids) do layer[id] = 1 end
    for _=1,#ids do
        local changed=false
        for _, e in ipairs(edges) do
            if e.a and layer[e.a] and layer[e.b] and layer[e.b] < layer[e.a]+1 then layer[e.b]=layer[e.a]+1; changed=true end
        end
        if not changed then break end
    end
    for _,e in ipairs(edges) do if e.source then layer[e.b]=math.max(layer[e.b] or 1, 1) end end
    local outputs, occupied = {}, {}
    local out_at_end = input.output_edge == "bottom" or input.output_edge == "right"
    for _, output in ipairs(output_ids) do
        local producer = output.producer
        local l = (layer[producer] or 0)+1
        if occupied[l] then l=l+1 end
        occupied[l]=true
        local obj={kind="output",flow_id=output.flow_id,producer=producer,layer=l,pinned=true,at_end=out_at_end}
        outputs[#outputs+1]=obj
        if producer and known[producer] then edges[#edges+1]={a=producer, output=obj} end
    end
    local all, max_layer, drawable = {}, 0, {}
    for _,id in ipairs(ids) do
        local obj={kind="block",id=id,layer=layer[id],input_order=order[id]}
        all[#all+1]=obj; drawable[id]=obj; max_layer=math.max(max_layer,layer[id])
    end
    for _,s in ipairs(sources) do all[#all+1]=s end
    for _,o in ipairs(outputs) do all[#all+1]=o; max_layer=math.max(max_layer,o.layer) end
    local serial=0
    for _,e in ipairs(edges) do
        local from=e.source and sources[e.source] or e.a and drawable[e.a]
        local to=e.output or drawable[e.b]
        if from and to then
            local prev=from
            for l=from.layer+1,to.layer-1 do
                serial=serial+1
                local d={kind="dummy",link=e.link,layer=l,tail=prev}
                all[#all+1]=d; e.chain=e.chain or {}; e.chain[#e.chain+1]=d; prev=d; max_layer=math.max(max_layer,l)
            end
            e.from,e.to=from,to
        end
    end
    local adjacency={}
    local function add_adj(a,b)
        adjacency[a]=adjacency[a] or {}; adjacency[a][#adjacency[a]+1]=b
    end
    for _,e in ipairs(edges) do
        local path={e.from}; for _,d in ipairs(e.chain or {}) do path[#path+1]=d end; path[#path+1]=e.to
        for i=1,#path-1 do add_adj(path[i],path[i+1]); add_adj(path[i+1],path[i]) end
    end
    local layers={}
    for l=0,max_layer do layers[l]={} end
    for _,n in ipairs(all) do layers[n.layer][#layers[n.layer]+1]=n end
    local function initial_sort(l)
        table.sort(layers[l],function(a,b)
            if a.kind=="source" or b.kind=="source" then
                if a.kind==b.kind then return tostring(a.flow_id)<tostring(b.flow_id) end
                return a.kind=="source"
            end
            if a.kind=="output" or b.kind=="output" then
                if a.kind==b.kind then return tostring(a.flow_id)<tostring(b.flow_id) end
                return out_at_end and b.kind=="output" or a.kind=="output"
            end
            local ao=a.kind=="block" and a.input_order or (a.tail and a.tail.rank or 0)+0.25
            local bo=b.kind=="block" and b.input_order or (b.tail and b.tail.rank or 0)+0.25
            return ao<bo
        end)
        for i,n in ipairs(layers[l]) do n.rank=i end
    end
    for l=0,max_layer do initial_sort(l) end
    local function neighbors(node, other_layer)
        local found={}
        for _,n in ipairs(adjacency[node] or {}) do if n.layer==other_layer then found[#found+1]=n end end
        return found
    end
    local function update_ranks(l) for i,n in ipairs(layers[l]) do n.rank=i end end
    local function pair_cost(u,v)
        local cost=0
        for _,side in ipairs({-1,1}) do
            local ul,vl=u.layer+side,v.layer+side
            if ul>=0 and ul<=max_layer and vl==ul then
                for _,a in ipairs(neighbors(u,ul)) do for _,b in ipairs(neighbors(v,vl)) do if a.rank>b.rank then cost=cost+1 end end end
            end
        end
        return cost
    end
    local function transpose()
        for _=1,10 do
            local changed=false
            for l=0,max_layer do
                for i=1,#layers[l]-1 do
                    local u,v=layers[l][i],layers[l][i+1]
                    if not u.pinned and not v.pinned and pair_cost(v,u)<pair_cost(u,v) then
                        layers[l][i],layers[l][i+1]=v,u; update_ranks(l); changed=true
                    end
                end
            end
            if not changed then break end
        end
    end
    local function sweep(down)
        local first,last,step=down and 1 or max_layer-1,down and max_layer or 0,down and 1 or -1
        for l=first,last,step do
            local current=layers[l]
            local keys={}
            for i,n in ipairs(current) do
                local ns=neighbors(n,l-step)
                local sum=0; for _,x in ipairs(ns) do sum=sum+x.rank end
                keys[n]=#ns>0 and sum/#ns or i
            end
            table.sort(current,function(a,b)
                if a.pinned and b.pinned then
                    if a.at_end then return a.rank>b.rank end
                    return a.rank<b.rank
                end
                if a.pinned then return not a.at_end end
                if b.pinned then return b.at_end end
                if keys[a]==keys[b] then return a.rank<b.rank end
                return keys[a]<keys[b]
            end)
            update_ranks(l)
        end
    end
    local function count_crossings()
        local total=0
        for _,e1 in ipairs(edges) do for _,e2 in ipairs(edges) do
            if e1~=e2 then
                local p1={e1.from}; for _,d in ipairs(e1.chain or {}) do p1[#p1+1]=d end; p1[#p1+1]=e1.to
                local p2={e2.from}; for _,d in ipairs(e2.chain or {}) do p2[#p2+1]=d end; p2[#p2+1]=e2.to
                for i=1,#p1-1 do for j=1,#p2-1 do
                    if p1[i].layer==p2[j].layer and p1[i+1].layer==p2[j+1].layer and p1[i+1].layer==p1[i].layer+1
                        and (p1[i].rank-p2[j].rank)*(p1[i+1].rank-p2[j+1].rank)<0 then total=total+0.5 end
                end end
            end
        end end
        return total
    end
    local function snapshot()
        local copy={}; for l=0,max_layer do copy[l]={}; for i,n in ipairs(layers[l]) do copy[l][i]=n end end; return copy
    end
    local function restore(copy) for l=0,max_layer do layers[l]=copy[l]; update_ranks(l) end end
    local best=snapshot(); local best_count=count_crossings()
    local seed=tonumber(input.seed) or 1
    local restarts=math.max(1,tonumber(input.restarts) or 30)
    for r=1,restarts do
        if r>1 then
            for l=0,max_layer do
                local a=layers[l]
                for i=#a,2,-1 do
                    seed=(seed*1103515245+(r*12345))%2147483648
                    local j=math.floor(seed%i)+1
                    if not a[i].pinned and not a[j].pinned then a[i],a[j]=a[j],a[i] end
                end
                update_ranks(l)
                table.sort(a,function(x,y) if x.pinned then return out_at_end end if y.pinned then return not out_at_end end return x.rank<y.rank end)
                update_ranks(l)
            end
        end
        for _=1,math.max(0,tonumber(input.sweeps) or 8) do
            sweep(true); transpose(); sweep(false); transpose()
            local c=count_crossings(); if c<best_count then best_count=c; best=snapshot() end
        end
        restore(best)
    end
    restore(best)
    local result={layer_of={},rank_of={},layers={},sources={},outputs={},dummies={},crossings=best_count,turn_of={}}
    for l=0,max_layer do
        result.layers[l+1]={}
        for _,n in ipairs(layers[l]) do
            if n.kind=="block" then
                result.layer_of[n.id]=l; result.rank_of[n.id]=n.rank; result.layers[l+1][#result.layers[l+1]+1]=n.id
                result.turn_of[n.id]=turns(input,blocks[n.id])
            elseif n.kind=="source" then result.sources[#result.sources+1]={flow_id=n.flow_id,rank=n.rank}
            elseif n.kind=="output" then result.outputs[#result.outputs+1]={flow_id=n.flow_id,producer=n.producer,layer=l,rank=n.rank}
            elseif n.kind=="dummy" then result.dummies[#result.dummies+1]={link=n.link,layer=l,rank=n.rank} end
        end
    end
    return result, math.max(1,#edges*#edges)
end

function FlowDraw.begin(input) return {input=input, done=false, progress=0, result=nil} end

function FlowDraw.step(state,budget)
    if state.done then return true end
    if not state.prepared then state.prepared,state.work=build(state.input) end
    local allowance=budget and budget.ops or state.work
    allowance=math.max(0,allowance or 0)
    local used=math.min(allowance,state.work-state.progress)
    state.progress=state.progress+used
    if budget and budget.ops then budget.ops=math.max(0,budget.ops-used) end
    if state.progress>=state.work then state.result=state.prepared; state.prepared=nil; state.done=true; return true end
    return false
end

return FlowDraw
