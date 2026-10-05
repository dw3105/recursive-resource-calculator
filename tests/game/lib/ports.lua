-- Geometry-only port discovery shared by offline fixtures and live LuaEntities.
local Ports = {}
local V = {[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}}
local BELT, PIPE = {}, {}

local function tile(e) return {math.floor(e.position.x), math.floor(e.position.y)} end
local function key(x,y) return x .. "," .. y end
local function transport(e)
    local n=e.name or ""
    return n:match("transport%-belt$") or n:match("underground%-belt$") or n:match("splitter$")
end
local function pipe(e) return e.name == "pipe" or e.name:match("pipe%-to%-ground$") end
local function edge(t,b) return t[1]==b.l or t[1]==b.r or t[2]==b.t or t[2]==b.b end
local function reach(args,e) return args.hand_reach and args.hand_reach(e.name) or ((e.name or ""):find("long%-handed") and 2 or 1) end
local function ug_type(e) return e.belt_to_ground_type or e.type end

function Ports.find(args)
    local cells, hands_list, machines, pipe_cells = {}, {}, {}, {}
    local b=args.bbox; b={l=b.l or b[1],t=b.t or b[2],r=b.r or b[3],b=b.b or b[4]}
    for _,e in ipairs(args.entities or {}) do
        local t=tile(e); local n=e.name or ""
        if n:find("inserter") then hands_list[#hands_list+1]=e
        elseif e.recipe or n:match("assembling%-machine") or n:match("furnace$") or n:match("foundry$") or n:match("chemical%-plant") or n:match("smelting%-plant") or n:match("machining%-assembler") or n:match("biochamber") or n:match("oil%-refinery") then machines[#machines+1]=e
        elseif pipe(e) then pipe_cells[key(t[1],t[2])]={e=e,t=t}
        elseif transport(e) then
            local c={e=e,t=t}; cells[key(t[1],t[2])]=c
            if n:match("splitter$") then
                local d=e.direction or 0; local dx,dy=(d==0 or d==8) and 0.5 or 0,(d==0 or d==8) and 0 or 0.5
                local a={math.floor(e.position.x-dx),math.floor(e.position.y-dy)}
                local z={math.floor(e.position.x+dx),math.floor(e.position.y+dy)}
                cells[key(a[1],a[2])]={e=e,t=a}; cells[key(z[1],z[2])]={e=e,t=z}
            end
        end
    end
    local function successors(k,c)
        local d=V[c.e.direction or 0]; if not d then return {} end
        if c.e.name:match("underground%-belt$") and ug_type(c.e)=="input" then
            for _,u in pairs(cells) do if u.e.name==c.e.name and ug_type(u.e)=="output" and u.e.direction==c.e.direction then return {key(u.t[1],u.t[2])} end end
        end
        local nk=key(c.t[1]+d[1],c.t[2]+d[2]); local nc=cells[nk]
        if nc and nc ~= c then
            local nd=V[nc.e.direction or 0]
            if nd and nd[1]*d[1]+nd[2]*d[2] >= 0 then return {nk} end
        end
        return {}
    end
    local pred={}; for k,c in pairs(cells) do for _,n in ipairs(successors(k,c)) do pred[n]=pred[n] or {}; pred[n][#pred[n]+1]=k end end
    local feeds,sinks,problems={}, {}, {}
    local machine_at
    local function recipe_items(m,kind)
        local out,seen={},{}
        local recipe=m.recipe
        if not recipe and args.recipes_for then
            -- Recipe-less furnaces are labeled from the unique product used by a downstream recipe.
            local required={}
            for _,h in ipairs(hands_list) do
                local d=V[h.direction or 0]
                if d then
                    local ht=tile(h); local r=reach(args,h)
                    local pick={ht[1]+d[1]*r,ht[2]+d[2]*r}
                    local drop={ht[1]-d[1]*r,ht[2]-d[2]*r}
                    -- A hand taking from this machine has its pickup adjacent to its footprint.
                    local mt=tile(m)
                    if machine_at({x=pick[1],y=pick[2]})==m and cells[key(drop[1],drop[2])] then
                        local k=key(drop[1],drop[2]); local seen_chain={}
                        while cells[k] and not seen_chain[k] do seen_chain[k]=true; local nexts=successors(k,cells[k]); if #nexts==0 then break end; k=nexts[1] end
                        for _,down in ipairs(hands_list) do
                            local dd=V[down.direction or 0]
                            if dd then local dt=tile(down); local rr=reach(args,down); local take={dt[1]+dd[1]*rr,dt[2]+dd[2]*rr}
                                if k==key(take[1],take[2]) then
                                    local consumer=machine_at({dt[1]-dd[1]*rr,dt[2]-dd[2]*rr})
                                    if consumer then
                                        local choices=consumer.recipe and {consumer.recipe} or (args.recipes_for(consumer.name) or {})
                                        for _,rn in ipairs(choices) do for _,x in ipairs(args.ingredients(rn) or {}) do if x.kind==kind then required[x.name]=true end end end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            local candidates={}
            for _,name in ipairs(args.recipes_for(m.name) or {}) do
                for _,p in ipairs(args.products and args.products(name) or {}) do
                    if required[p.name] or (args.outputs[kind.."/"..p.name] or args.outputs[p.name]) then candidates[#candidates+1]=name; break end
                end
            end
            table.sort(candidates); if #candidates==1 then recipe=candidates[1] end
        end
        if recipe then for _,x in ipairs(args.ingredients(recipe) or {}) do if x.kind==kind and (args.inputs[kind.."/"..x.name] or args.inputs[x.name]) then out[x.name]=true end end end
        return out
    end
    machine_at = function(t)
        if t.x then t={t.x,t.y} end
        local nearest,near_d
        for _,m in ipairs(machines) do
            local mt=tile(m); local w,h=args.sizes(m.name); w=w or 1; h=h or 1
            if (m.direction or 0)%8==4 then w,h=h,w end
            if math.abs(t[1]-m.position.x)<=(w+1)/2 and math.abs(t[2]-m.position.y)<=(h+1)/2 then return m end
            local d=math.abs(t[1]-mt[1])+math.abs(t[2]-mt[2]); if not near_d or d<near_d then nearest,near_d=m,d end
        end
        if near_d and near_d<=7 then return nearest end
    end
    for _,h in ipairs(hands_list) do
        local d=V[h.direction or 0]
        if d then
            local ht=tile(h); local hand_reach=reach(args,h)
            local pick={ht[1]+d[1]*hand_reach,ht[2]+d[2]*hand_reach}; local drop={ht[1]-d[1]*hand_reach,ht[2]-d[2]*hand_reach}
            local pm=machine_at(drop)
            local dm=machine_at(pick)
            if cells[key(pick[1],pick[2])] and pm then
                local todo={key(pick[1],pick[2])}; local seen={}
                while #todo>0 do local k=table.remove(todo); if not seen[k] and cells[k] then
                    seen[k]=true; local ups=pred[k] or {}
                    if #ups==0 then local c=cells[k]; if edge(c.t,b) then
                        local matching={}; for item in pairs(recipe_items(pm,"item")) do if args.inputs["item/"..item] or args.inputs[item] then matching[#matching+1]=item end end
                        table.sort(matching); if #matching==1 then feeds[#feeds+1]={tile={x=c.t[1],y=c.t[2]},item=matching[1]} elseif #matching>1 then problems[#problems+1]="TWO_ITEMS "..k else problems[#problems+1]="NO_ITEM "..k.." recipe="..tostring(pm.recipe) end
                    end else for _,u in ipairs(ups) do todo[#todo+1]=u end end
                end end
            elseif cells[key(drop[1],drop[2])] and dm then
                local k=key(drop[1],drop[2]); local seen={}
                while cells[k] and not seen[k] do seen[k]=true; local nxt=successors(k,cells[k]); if #nxt==0 then break end; k=nxt[1] end
                local c=cells[k]; local product
                if dm.recipe then for _,p in ipairs(args.products and args.products(dm.recipe) or {}) do if p.kind=="item" and (args.outputs["item/"..p.name] or args.outputs[p.name]) then product=p.name; break end end end
                if c and edge(c.t,b) and product and args.outputs["item/"..product] then sinks[#sinks+1]={tile={x=c.t[1],y=c.t[2]},item=product} end
            end
        end
    end
    -- Pipe component edges and nearby recipe fluid ingredients.
    local visited,pipe_root={},{}
    local ptg={}; for k,c in pairs(pipe_cells) do if c.e.name:match("pipe%-to%-ground$") then ptg[#ptg+1]={k=k,c=c} end end
    local ptg_pair={}
    for _,a in ipairs(ptg) do local d=V[a.c.e.direction or 0]; local best,dist
        if d then for _,z in ipairs(ptg) do if z~=a and (z.c.e.direction or 0)==((a.c.e.direction or 0)+8)%16 then
            local dx,dy=z.c.t[1]-a.c.t[1],z.c.t[2]-a.c.t[2]
            if dx*d[1]+dy*d[2]>0 and dx*d[2]==dy*d[1] then local n=math.abs(dx)+math.abs(dy); if not dist or n<dist then best,dist=z.k,n end end
        end end end
        if best then ptg_pair[a.k]=best end
    end
    for k,c in pairs(pipe_cells) do if not visited[k] then
        local comp={}; local todo={k}; visited[k]=true
        while #todo>0 do local q=table.remove(todo); comp[#comp+1]=pipe_cells[q]; local t=pipe_cells[q].t
            for _,d in pairs(V) do local nk=key(t[1]+d[1],t[2]+d[2]); if pipe_cells[nk] and not visited[nk] then visited[nk]=true; todo[#todo+1]=nk end end
            local pair=ptg_pair[q]; if pair and not visited[pair] then visited[pair]=true; todo[#todo+1]=pair end
        end
        local root=k; for _,p in ipairs(comp) do pipe_root[key(p.t[1],p.t[2])]=root end
        local edgepipe; for _,p in ipairs(comp) do if edge(p.t,b) then edgepipe=p; break end end
        if edgepipe then local found={}
            for _,m in ipairs(machines) do
                if m.recipe and args.fluid_boxes then
                    local wants={}; for _,x in ipairs(args.ingredients(m.recipe) or {}) do if x.kind=="fluid" then wants[#wants+1]=x.name end end
                    local boxes=args.fluid_boxes(m.name,m.direction or 0,m.mirror) or {}
                    for _,box in ipairs(boxes) do
                        local off=box.tile_offset or box
                        local q=tile(m); local ck=key(math.floor(m.position.x+off.x),math.floor(m.position.y+off.y))
                        if pipe_root[ck] and pipe_root[ck]==pipe_root[key(edgepipe.t[1],edgepipe.t[2])] then
                            local item=wants[box.fluid_index or box.index or 1]
                            if item and (args.inputs["fluid/"..item] or args.inputs[item]) then found[item]=true end
                        end
                    end
                end
            end
            if next(found)==nil then
                for _,m in ipairs(machines) do for item in pairs(recipe_items(m,"fluid")) do
                    local mt=tile(m); local d=math.abs(mt[1]-edgepipe.t[1])+math.abs(mt[2]-edgepipe.t[2])
                    if d<=4 and (args.inputs["fluid/"..item] or args.inputs[item]) then found[item]=true end
                end end
            end
            local names={}; for n in pairs(found) do names[#names+1]=n end; table.sort(names); if #names==1 then feeds[#feeds+1]={tile={x=edgepipe.t[1],y=edgepipe.t[2]},fluid=names[1]} end
        end
    end end
    for k,c in pairs(cells) do
        if edge(c.t,b) and not pred[k] then
            local named=false
            for _,f in ipairs(feeds) do if f.tile.x==c.t[1] and f.tile.y==c.t[2] then named=true; break end end
            if not named then problems[#problems+1]="UNNAMED_FEED "..k end
        end
    end
    local function unique(rows,field)
        local seen,out={},{}
        for _,v in ipairs(rows) do local id=key(v.tile.x,v.tile.y)..":"..(v[field] or v.item or v.fluid); if not seen[id] then seen[id]=true; out[#out+1]=v end end
        return out
    end
    feeds=unique(feeds)
    table.sort(feeds,function(a,b) if a.tile.y~=b.tile.y then return a.tile.y<b.tile.y end if a.tile.x~=b.tile.x then return a.tile.x<b.tile.x end return (a.item or a.fluid)<(b.item or b.fluid) end)
    sinks=unique(sinks,"item")
    table.sort(sinks,function(a,b) if a.tile.y~=b.tile.y then return a.tile.y<b.tile.y end return a.tile.x<b.tile.x end)
    return {feeds=feeds,sinks=sinks,problems=problems}
end

return Ports
