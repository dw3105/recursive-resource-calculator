-- Convert the generator's internal result to the blueprint schema accepted by Factorio.
local BlueprintString = {}

local KEEP = {"name", "position", "direction", "recipe", "recipe_quality", "items", "quality",
    "orientation", "bar", "filters", "filter_mode", "override_stack_size", "control_behavior",
    "use_filters", "request_filters", "mirror", "tags"}
local TYPED = {['underground-belt']=true, ['fast-underground-belt']=true, ['express-underground-belt']=true,
    ['turbo-underground-belt']=true, loader=true, ['loader-1x1']=true, ['fast-loader']=true,
    ['express-loader']=true, ['turbo-loader']=true}
local POLES = {['small-electric-pole']=true, ['medium-electric-pole']=true, ['big-electric-pole']=true, substation=true}

local function version()
    local s = rawget(_G, "script")
    local v = s and s.active_mods and s.active_mods.base
    local a,b,c
    if type(v)=="string" then a,b,c=v:match("^(%d+)%.(%d+)%.(%d+)") end
    a,b,c = tonumber(a), tonumber(b), tonumber(c)
    if not a then a,b,c=2,0,77 end
    return a*281474976710656 + b*4294967296 + c*65536
end

function BlueprintString.build(result, label)
    local source = result.entities or {}
    if #source == 0 then error("blueprint result has no entities") end
    local entities, by_number, icons = {}, {}, {}
    for i, entity in ipairs(source) do
        local p = entity.position
        if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" then error("entity has no usable position") end
        local out = {entity_number=i}
        for _, key in ipairs(KEEP) do if entity[key] ~= nil then out[key]=entity[key] end end
        if out.direction == 0 then out.direction=nil end
        if TYPED[entity.name] and (entity.type=="input" or entity.type=="output") then out.type=entity.type end
        entities[i], by_number[i] = out, out
        if entity.recipe then
            local found=false
            for _, icon in ipairs(icons) do if icon.signal.name==entity.name then found=true end end
            if not found and #icons < 4 then icons[#icons+1]={signal={type="item",name=entity.name},index=#icons+1} end
        end
    end
    local bp={item="blueprint",version=version(),label=label or "Recursive Resource Calculator",entities=entities}
    if #icons>0 then bp.icons=icons end
    local wires={}
    for _, w in ipairs(result.wires or {}) do
        if type(w)~="table" or #w~=4 or not by_number[w[1]] or not by_number[w[3]] then error("invalid blueprint wire") end
        if w[2]==0 or w[4]==0 then
            if not (w[2]==0 or w[4]==0) or not POLES[by_number[w[1]].name] or not POLES[by_number[w[3]].name] then error("wire has placeholder connector") end
        else wires[#wires+1]=w end
    end
    if #wires>0 then bp.wires=wires end
    local json=helpers.table_to_json({blueprint=bp})
    local encoded=helpers.encode_string(json)
    if type(encoded)~="string" or encoded=="" then error("blueprint encoding failed") end
    return "0"..encoded
end

return BlueprintString
