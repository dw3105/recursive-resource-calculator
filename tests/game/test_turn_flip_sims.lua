-- Turn and Flip census sheets use the same lab protocol as tests/game/test_sheets.lua.
local Lab = require "tests.game.lib.lab"
local ok_index, INDEX = pcall(require, "tests.game.fixtures.turn_flip_index")
local SHEETS={}
if ok_index and type(INDEX)=="table" then
    for _,row in ipairs(INDEX) do SHEETS[#SHEETS+1]={case=row.case,turn=row.turn,flip=row.flip,data=require(row.data)} end
end
local has_flipped={}
for _,row in ipairs(SHEETS) do if row.turn==8 and row.flip==1 then has_flipped[row.case:gsub("_[0-9]+_[01]$","")]=true end end
local function present(sample, row)
    if not sample then return true end
    local case=row.case:gsub("_[0-9]+_[01]$","")
    return (row.turn==8 and row.flip==1) or (row.turn==8 and row.flip==0 and not has_flipped[case])
end
describe("Turn and Flip sheet sims", function()
    if not ok_index then
        it("lab loads offline",function() assert.is_true(type(Lab)=="table") end)
    else
        for index,sheet in ipairs(SHEETS) do
            if os.getenv("RRC_TURN_FLIP_FULL")=="1" or present(true,sheet) then
                it(sheet.case,function()
                    if RRC_OFFLINE then return end
                    local ports=helpers.json_to_table(sheet.data.ports)
                    assert.are_equal(0,#(ports.problems or {}),serpent.line(ports.problems))
                    local force=game.forces.player; local stack=Lab.research_stack(force)
                    if ports.force then
                        if ports.force.bulk_inserter_capacity_bonus then force.bulk_inserter_capacity_bonus=ports.force.bulk_inserter_capacity_bonus end
                        if ports.force.inserter_stack_size_bonus then force.inserter_stack_size_bonus=ports.force.inserter_stack_size_bonus end
                        for recipe,bonus in pairs(ports.force.research or {}) do if force.recipes[recipe] then force.recipes[recipe].productivity_bonus=bonus end end
                    end
                    local surface=Lab.surface(); local box=ports.bbox; local origin={index*512,0}
                    Lab.prepare(surface,{{origin[1]+box[1]-16,origin[2]+box[2]-16},{origin[1]+box[3]+16,origin[2]+box[4]+16}})
                    local imported,code=Lab.import_ok(sheet.data.bp); assert(imported,sheet.case.." engine refused blueprint "..tostring(code))
                    local built=Lab.build(surface,force,sheet.data.bp,origin)
                    assert.are_equal(0,#built.refused,sheet.case.." entities do not place")
                    assert(Lab.power(surface,force,built),sheet.case.." power failed")
                    local feeds,belts={},{}
                    for _,f in ipairs(ports.feeds) do local ent=Lab.at(surface,built,f.tile[1],f.tile[2]); assert(Lab.feed_shape_ok(ent,f.fluid),sheet.case.." feed port shape"); feeds[#feeds+1]={entity=ent,item=f.item,fluid=f.fluid}; if f.item then belts[#belts+1]=ent end end
                    local sinks={}; for _,s in ipairs(ports.sinks) do sinks[#sinks+1]={entity=Lab.at(surface,built,s.tile[1],s.tile[2]),got={},items=s.items} end
                    local speed=0.03125
                    for _,ent in pairs(built.entities) do if ent.valid and ent.type=="transport-belt" then speed=math.max(speed,ent.prototype.belt_speed) end end
                    local warm=math.max(3600,math.ceil(((box[3]-box[1])+(box[4]-box[2]))*2/speed)+600)
                    local t0=game.tick; local WINDOW=3600; local short,samples=0,0; local window_start=nil; game.speed=1000
                    on_tick(function()
                        local elapsed=game.tick-t0; Lab.feed_tick(feeds,stack)
                        local measuring=elapsed>=warm; if measuring and not window_start then window_start=elapsed end
                        Lab.sink_tick(sinks,measuring)
                        if measuring and elapsed%60==0 then
                            samples=samples+1
                            for _,belt in ipairs(belts) do for lane=1,2 do
                                local det=belt.get_transport_line(lane).get_detailed_contents(); local full=#det>=4
                                for _,d in pairs(det) do if d.stack.count~=stack then full=false end end
                                if not full then short=short+1 end
                            end end
                        end
                        if not window_start or elapsed-window_start<WINDOW then return end
                        local got,problems={},{}
                        if short>0 then problems[#problems+1]="FEED_SHORT "..short.." lane samples" end
                        for _,s in ipairs(sinks) do local allowed={}; for _,n in ipairs(s.items) do allowed[n]=true end; for n,count in pairs(s.got) do if not allowed[n] then problems[#problems+1]="foreign "..n end; got[n]=(got[n] or 0)+count end end
                        for name,rate in pairs(ports.targets) do local item=name:gsub("^item/",""); local actual=(got[item] or 0)/(WINDOW/60); if actual<.95*rate then problems[#problems+1]=item.." short "..actual.." < "..(.95*rate) end end
                        game.speed=1; assert(#problems==0,sheet.case..": "..table.concat(problems,"; ")); return false
                    end)
                end)
            end
        end
    end
end)
