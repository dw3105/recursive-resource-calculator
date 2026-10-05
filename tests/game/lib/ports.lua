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
local function hands(e) return (e.name or ""):find("long%-handed") and 2 or 1 end

function Ports.find(args)
    local cells, split, hands_list, machines, pipe_cells = {}, {}, {}, {}, {}
    local b=args.bbox; b={l=b.l or b[1],t=b.t or b[2],r=b.r or b[3],b=b.b or b[4]}
    for _,e in ipairs(args.entities or {}) do
        local t=tile(e); local n=e.name or ""
        if n:find("inserter") then hands_list[#hands_list+1]=e
        elseif n:match("assembling%-machine") or n:match("furnace$") or n:match("foundry$") or n:match("chemical%-plant") or n:match("smelting%-plant") or n:match("machining%-assembler") or n:match("biochamber") or n:match("oil%-refinery") then machines[#machines+1]=e
        elseif pipe(e) then pipe_cells[key(t[1],t[2])]={e=e,t=t}
        elseif transport(e) then
            local c={e=e,t=t}; cells[key(t[1],t[2])]=c
            if n:match("splitter$") then
                local d=e.direction or 0; local dx,dy=(d==0 or d==8) and 1 or 0,(d==0 or d==8) and 0 or 1
                local other={t[1]+dx,t[2]+dy}; cells[key(other[1],other[2])]={e=e,t=other}
                split[#split+1]={key(t[1],t[2]),key(other[1],other[2])}
            end
        end
    end
    local function successors(k,c)
        local d=V[c.e.direction or 0]; if not d then return {} end
        if c.e.name:match("underground%-belt$") and c.e.type=="input" then
            for _,u in pairs(cells) do if u.e.name==c.e.name and u.e.type=="output" and u.e.direction==c.e.direction then return {key(u.t[1],u.t[2])} end end
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
    local function recipe_items(m,kind)
        local out={}; if not m.recipe then return out end
        for _,x in ipairs(args.ingredients(m.recipe) or {}) do
            if x.kind==kind then out[x.name]=true end
        end
        return out
    end
    local function machine_at(t)
        for _,m in ipairs(machines) do
            local mt=tile(m); local w,h=args.sizes(m.name); w=w or 1; h=h or 1
            if (m.direction or 0)%8==4 then w,h=h,w end
            if math.abs(t[1]-m.position.x)<=(w+1)/2 and math.abs(t[2]-m.position.y)<=(h+1)/2 then return m end
        end
    end
    for _,h in ipairs(hands_list) do
        local d=V[h.direction or 0]
        if d then
            local ht=tile(h); local reach=hands(h)
            local pick={ht[1]+d[1]*reach,ht[2]+d[2]*reach}; local drop={ht[1]-d[1]*reach,ht[2]-d[2]*reach}
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
                local c=cells[k]; local product=dm.recipe
                if product and not args.outputs["item/"..product] then
                    local only; for name in pairs(args.outputs) do if name:match("^item/") then if only then only=nil; break else only=name:sub(6) end end end
                    product=only or product
                end
                if c and edge(c.t,b) and product and args.outputs["item/"..product] then sinks[#sinks+1]={tile={x=c.t[1],y=c.t[2]},item=product} end
            end
        end
    end
    -- Pipe component edges and nearby recipe fluid ingredients.
    local visited={}
    for k,c in pairs(pipe_cells) do if not visited[k] then
        local comp={}; local todo={k}; visited[k]=true
        while #todo>0 do local q=table.remove(todo); comp[#comp+1]=pipe_cells[q]; local t=pipe_cells[q].t
            for _,d in pairs(V) do local nk=key(t[1]+d[1],t[2]+d[2]); if pipe_cells[nk] and not visited[nk] then visited[nk]=true; todo[#todo+1]=nk end end
        end
        local edgepipe; for _,p in ipairs(comp) do if edge(p.t,b) then edgepipe=p; break end end
        if edgepipe then local found={}; local nearest,dist
            for _,m in ipairs(machines) do for item in pairs(recipe_items(m,"fluid")) do
                local mt=tile(m); local d=math.abs(mt[1]-edgepipe.t[1])+math.abs(mt[2]-edgepipe.t[2])
                if (args.inputs["fluid/"..item] or args.inputs[item]) and (not dist or d<dist) then nearest,dist=item,d end
            end end
            if nearest then found[nearest]=true end
            local names={}; for n in pairs(found) do names[#names+1]=n end; table.sort(names); if #names==1 then feeds[#feeds+1]={tile={x=edgepipe.t[1],y=edgepipe.t[2]},fluid=names[1]} end
        end
    end end
    table.sort(feeds,function(a,b) if a.tile.y~=b.tile.y then return a.tile.y<b.tile.y end if a.tile.x~=b.tile.x then return a.tile.x<b.tile.x end return (a.item or a.fluid)<(b.item or b.fluid) end)
    table.sort(sinks,function(a,b) if a.tile.y~=b.tile.y then return a.tile.y<b.tile.y end return a.tile.x<b.tile.x end)
    return {feeds=feeds,sinks=sinks,problems=problems}
end

return Ports
