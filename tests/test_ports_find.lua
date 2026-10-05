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
local function run(case)
    local base="tests/fixtures/sheets/"..case
    local f=json(base..".entities.json"); local expected=json(base:gsub("/sheets/","/sheets/")..".ports.json")
    local recipes={}; local input,output={},{}; local sizes={}
    local prepared="tests/golden/cases/"..case.."/prepared_input.json"
    local file=io.open(prepared)
    if file then file:close(); local c=json(prepared).catalog.recipe
        for n,r in pairs(c) do recipes[n]=r.ingredients or {} end
        for n,v in pairs(json(prepared).catalog.entity or {}) do sizes[n]={v.tile_w or 1,v.tile_h or 1} end
    else
        recipes["automation-science-pack"]={{name="iron-plate",kind="item"},{name="copper-plate",kind="item"},{name="iron-gear-wheel",kind="item"}}
        recipes["iron-gear-wheel"]={{name="iron-plate",kind="item"}}; recipes["copper-plate"]={{name="copper-ore",kind="item"}}; recipes["iron-plate"]={{name="iron-ore",kind="item"}}
        recipes["logistic-science-pack"]={{name="inserter",kind="item"},{name="transport-belt",kind="item"},{name="automation-science-pack",kind="item"}}
        sizes["assembling-machine-1"]={3,3}; sizes["stone-furnace"]={2,2}; output["item/automation-science-pack"]=true; output["item/logistic-science-pack"]=true
    end
    for n in pairs(expected.inputs or {}) do input[n:gsub("^[^/]+/","")]=true end
    for _,v in ipairs(expected.sinks or {}) do for _,n in ipairs(v.items) do output["item/"..n]=true end end
    local function ingredients(n)
        local result={}; for _,x in ipairs(recipes[n] or {}) do result[#result+1]={name=x.name,kind=x.kind or x.type or "item"} end; return result
    end
    local found=Ports.find{entities=f.entities,bbox=f.bbox,ingredients=ingredients,inputs=input,outputs=output,hand_reach=function(n)return n:find("long%-handed") and 2 or 1 end,sizes=function(n)local s=sizes[n] or {1,1}; return s[1],s[2] end}
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
    for _,case in ipairs(cases) do local got,want=run(case); local ok,msg=same(set(got.feeds),set(want.feeds)); H.equal(ok,true,case.." feeds: "..msg) end
    print("PF1")
end)
H.test("PF2 geometry identifies every fixture sink", function()
    for _,case in ipairs(cases) do local got,want=run(case); local expected={}; for _,v in ipairs(want.sinks) do for _,n in ipairs(v.items) do expected[#expected+1]={tile=v.tile,item=n} end end; local ok,msg=same(set(got.sinks),set(expected)); H.equal(ok,true,case.." sinks: "..msg) end
    print("PF2")
end)
H.test("PF3 geometry identifies fluid feeds", function()
    for _,case in ipairs({"player-blue-science-10s","player-am2-chain-repaired"}) do local got=run(case); local fluid={}; for _,x in ipairs(got.feeds) do if x.fluid then fluid[x.fluid]=true end end
        if case=="player-blue-science-10s" then H.equal(fluid.water,true); H.equal(fluid["crude-oil"],true) else H.equal(fluid["molten-iron"],true) end
    end; print("PF3")
end)
H.test("PF4 reports an unnamed input feed", function()
    local got=run("player-red-science-1s"); H.equal(#got.problems>0,true,"unmatched feed is reported"); print("PF4")
end)
H.test("PF5 finder does not inspect port ids", function()
    local f=assert(io.open("tests/game/lib/ports.lua")); local s=f:read("*a"); f:close(); H.equal(s:find("port_id",1,true),nil); print("PF5")
end)
