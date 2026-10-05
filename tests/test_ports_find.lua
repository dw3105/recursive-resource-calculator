-- PF1-PF5 red on player-run-base (2026-10-05): geometry-only feed and sink discovery.
local H = require "tests.harness"
local Ports = require "tests.game.lib.ports"
local function json(path)
    local f=assert(io.open(path)); local s=f:read("*a"); f:close()
    local g=assert(io.open("tests/golden/generate.lua")); local src=g:read("*a"); g:close()
    local a=assert(src:find("local JSON = {}",1,true)); local b=assert(src:find("local input_path,",a,true))
    return assert(load(src:sub(a,b-1).."\nreturn JSON"))().decode(s)
end
local cases={"player-am2-chain-repaired","player-blue-science-10s","player-green-science-1s","player-inserter-10s",
"player-inserter-10s-bulk","player-inserter-10s-stack1","player-red-green-science-10s","player-red-science-10s",
"player-red-science-10s-bulk","player-red-science-10s-stack1","player-red-science-1s","player-red-science-1s-bulk",
"player-red-science-1s-foundry","vanilla-2.1-red-science-1s","vanilla-2.1-green-science-1s"}
local function run(case,edit)
    local base="tests/fixtures/sheets/"..case
    local f=json(base..".entities.json"); local expected=json(base:gsub("/sheets/","/sheets/")..".ports.json")
    for _,e in ipairs(f.entities) do e.position={x=e.x,y=e.y} end
    if edit then f.entities=edit(f.entities) or f.entities end
    local recipes, products, entity_catalog, input, output, sizes={}, {}, {}, {}, {}, {}
    local prepared="tests/golden/cases/"..case.."/prepared_input.json"
    local file=io.open(prepared)
    if file then
        file:close(); local catalog=json(prepared).catalog
        recipes=catalog.recipe or {}; entity_catalog=catalog.entity or {}
        for n,v in pairs(entity_catalog) do sizes[n]={v.tile_w or 1,v.tile_h or 1} end
        for n,r in pairs(recipes) do products[n]=r.products or {} end
    else
        recipes={
            ["automation-science-pack"]={{name="iron-plate",kind="item"},{name="copper-plate",kind="item"},{name="iron-gear-wheel",kind="item"}},
            ["iron-gear-wheel"]={{name="iron-plate",kind="item"}},["copper-plate"]={{name="copper-ore",kind="item"}},
            ["iron-plate"]={{name="iron-ore",kind="item"}},
            ["logistic-science-pack"]={{name="inserter",kind="item"},{name="transport-belt",kind="item"},{name="automation-science-pack",kind="item"}}
        }
        products={ ["automation-science-pack"]={{name="automation-science-pack",kind="item"}},["logistic-science-pack"]={{name="logistic-science-pack",kind="item"}},["iron-plate"]={{name="iron-plate",kind="item"}},["copper-plate"]={{name="copper-plate",kind="item"}},["iron-gear-wheel"]={{name="iron-gear-wheel",kind="item"}} }
        entity_catalog["assembling-machine-1"]={crafting_categories={crafting=true},fluid_boxes={},tile_w=3,tile_h=3}
        entity_catalog["stone-furnace"]={crafting_categories={smelting=true},fluid_boxes={},tile_w=2,tile_h=2}
        for n in pairs(recipes) do recipes[n].category=(n=="iron-plate" or n=="copper-plate") and "smelting" or "crafting" end
    end
    for n in pairs(expected.inputs or {}) do input[n:gsub("^[^/]+/","")]=true end
    for _,v in ipairs(expected.sinks or {}) do for _,n in ipairs(v.items) do output["item/"..n]=true end end
    local function normalize(list)
        local result={}; for _,x in ipairs(list or {}) do result[#result+1]={name=x.name,kind=x.kind or x.type or "item"} end; return result
    end
    local function ingredients(n) return normalize((recipes[n] or {}).ingredients or recipes[n]) end
    local function product_list(n) return normalize((products[n] or {})) end
    local function recipes_for(machine)
        local spec=entity_catalog[machine] or {}; local out={}
        for n,r in pairs(recipes) do if spec.crafting_categories and spec.crafting_categories[r.category] then out[#out+1]=n end end
        table.sort(out); return out
    end
    local function fluid_boxes(machine,direction,mirror)
        local spec=entity_catalog[machine] or {}; local out={}
        for _,box in ipairs(spec.fluid_boxes or {}) do
            for _,conn in ipairs(box.connections or {}) do
                local pos=(conn.positions or {})[math.floor((direction or 0)/4)+1]
                if pos then
                    local x,y=pos.x,pos.y
                    local d=((conn.direction or 0)+(direction or 0))%16
                    if mirror then x=-x; d=(16-d)%16 end
                    local turns=math.floor((direction or 0)/4)
                    for _=1,turns do x,y=-y,x end
                    local vectors={[0]={0,-1},[4]={1,0},[8]={0,1},[12]={-1,0}}
                    local v=vectors[d]
                    if v then out[#out+1]={tile_offset={x=math.floor(x+v[1]),y=math.floor(y+v[2])},fluid_index=box.index} end
                end
            end
        end
        return out
    end
    local found=Ports.find{entities=f.entities,bbox=f.bbox,ingredients=ingredients,products=product_list,recipes_for=recipes_for,fluid_boxes=fluid_boxes,inputs=input,outputs=output,hand_reach=function(n)return n:find("long%-handed") and 2 or 1 end,sizes=function(n)local z=sizes[n] or {1,1}; return z[1],z[2] end}
    return found,expected
end
local function set(rows,key)
    local out={}; for _,v in ipairs(rows) do out[table.concat({v.tile[1] or v.tile.x,v.tile[2] or v.tile.y,v.item or v.fluid or ""},":")]=true end; return out
end
local function same(a,b)
    local function sig(t) local keys={}; for k in pairs(t) do keys[#keys+1]=k end; table.sort(keys); return table.concat(keys,"|") end
    return sig(a)==sig(b), "actual="..sig(a).." expected="..sig(b)
end

H.test("PF1 geometry identifies every fixture feed", function()
    local failures={}; for _,case in ipairs(cases) do local got,want=run(case); local ok,msg=same(set(got.feeds),set(want.feeds)); if not ok then failures[#failures+1]=case.." "..msg end end
    H.equal(#failures,0,table.concat(failures,"\n"))
    print("PF1")
end)
H.test("PF2 geometry identifies every fixture sink", function()
    local failures={}; for _,case in ipairs(cases) do local got,want=run(case); local expected={}; for _,v in ipairs(want.sinks) do for _,n in ipairs(v.items) do expected[#expected+1]={tile=v.tile,item=n} end end; local ok,msg=same(set(got.sinks),set(expected)); if not ok then failures[#failures+1]=case.." "..msg end end
    H.equal(#failures,0,table.concat(failures,"\n"))
    print("PF2")
end)
H.test("PF3 geometry identifies fluid feeds", function()
    for _,case in ipairs({"player-blue-science-10s","player-am2-chain-repaired"}) do local got=run(case); local fluid={}; for _,x in ipairs(got.feeds) do if x.fluid then fluid[x.fluid]=true end end
        if case=="player-blue-science-10s" then H.equal(fluid.water,true); H.equal(fluid["crude-oil"],true) else H.equal(fluid["molten-iron"],true) end
    end; print("PF3")
end)
H.test("PF4 reports an unnamed input feed", function()
    local function prepared(entities,remove)
        local out={}
        for _,e in ipairs(entities) do
            if e.name=="electric-furnace" and e.x==4.5 and e.y==8.5 then e.recipe="copper-plate" end
            if not (remove and e.name=="inserter" and e.x==4.5 and e.y==6.5) then out[#out+1]=e end
        end
        return out
    end
    local complete=run("player-red-science-1s",function(es)return prepared(es,false)end)
    local missing=run("player-red-science-1s",function(es)return prepared(es,true)end)
    H.equal(set(complete.feeds)["0:5:copper-ore"],true,"the selected hand names the copper feed")
    H.equal(set(missing.feeds)["0:5:copper-ore"],nil,"removing its hand removes the feed name")
    H.equal(#missing.problems>0,true,"the unnamed edge feed is reported"); print("PF4")
end)
H.test("PF5 finder does not inspect port ids", function()
    local f=assert(io.open("tests/game/lib/ports.lua")); local s=f:read("*a"); f:close(); H.equal(s:find("port_id",1,true),nil); print("PF5")
end)
