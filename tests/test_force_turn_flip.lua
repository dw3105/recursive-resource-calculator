-- TF1-TF7 red on round-54-base (2026-09-30): forced Turn and Flip are not available.
local H = require 'tests.harness'
local Grid = require 'logic.bp.grid'
local Pack = require 'logic.bp.pack'
local ReasonCodes = require 'logic.bp.reason_codes'
local Search = require 'logic.bp.search'
local D = require 'tests.fixtures.search_doubles'
local Groups = require 'logic.bp.groups'

local function pack(mode, dirs, forced_dir)
    local drawing = {layer_of={b=1}, rank_of={b=1}, turn_of={}}
    local state = Pack.begin{area=Grid.rect(0,0,20,20), blocks={{id='b',w=2,h=2,allowed_dirs=dirs}},
        mode=mode, drawing=drawing, forced_dir=forced_dir}
    while not state.done do Pack.step(state,{ops=10000}) end
    return state
end

H.test('TF1 forced Turn reaches layered and drawn pack', function()
    local layered, drawn = pack(nil,{8},8), pack('sugiyama',{8},8)
    H.equal(layered.result.placements[1].dir,8)
    H.equal(drawn.result.placements[1].dir,8)
    print('TF1')
end)
H.test('TF2 forced Flip is a registered failure contract', function()
    local state, log = D.run({}, function()
        local old_step, old_reorient, old_pack = Groups.step, Groups.reorient, Pack.begin
        local saw_mirror, saw_turn = false, false
        Pack.begin=function(input)
            saw_turn=input.forced_dir==8
            for _, block in ipairs(input.blocks) do
                for _, machine in ipairs(block.machines or {}) do if machine.mirror==true then saw_mirror=true end end
            end
            return old_pack(input)
        end
        Groups.step = function(s,budget)
            if budget.ops > 0 then
                budget.ops=budget.ops-1
                s.result={candidates={{id='c',blocks={{id='b',block_id='b',w=1,h=1,
                    machines={{id='m',name='assembler'}},ports={}}}}}}
                s.done,s.ok=true,true
            end
            return s
        end
        Groups.reorient = function(_,block,turn_flip)
            H.equal(turn_flip.dir,0); H.equal(turn_flip.mirror,true)
            local rebuilt={}; for k,v in pairs(block) do rebuilt[k]=v end
            rebuilt.machines={{id='m',name='assembler',mirror=true}}
            return rebuilt
        end
        local input=D.input({settings={force_turn_flip={turn=8,flip=true}},catalog={entity={assembler={can_flip=true}}}})
        local result=D.finish(Search,Search.begin(input))
        Groups.step,Groups.reorient,Pack.begin=old_step,old_reorient,old_pack
        result._tf={mirror=saw_mirror,turn=saw_turn}
        return result
    end)
    H.equal(state.ok,true); H.equal(log.pack[1].area ~= nil,true)
    H.equal(state._tf.mirror,true); H.equal(state._tf.turn,true)
    H.equal(ReasonCodes.all().BP_FAIL_FLIP_REBUILD,true)
    print('TF2')
end)
H.test('TF3 forbidden Flip is a registered failure contract', function()
    local state = D.run({},function()
        local old=Groups.step
        Groups.step=function(s,budget)
            if budget.ops>0 then
                budget.ops=budget.ops-1
                s.result={candidates={{id='c',blocks={{id='b',block_id='b',w=1,h=1,
                    machines={{id='m',name='assembler'}},ports={}}}}}}
                s.done,s.ok=true,true
            end
            return s
        end
        local r=D.finish(Search,Search.begin(D.input({settings={force_turn_flip={turn=0,flip=true}},
            catalog={entity={assembler={use_mirroring=false}}}})))
        Groups.step=old; return r
    end)
    H.equal(state.ok,false); H.equal(state.errors[1].code,'BP_FAIL_FLIP_FORBIDDEN')
    H.equal(state.errors[1].subject,'assembler'); print('TF3')
end)
H.test('TF4 Flip on a Block without can_flip leaves member data untouched', function()
    local reoriented=false
    local state, log=D.run({},function()
        local old_step,old_reorient=Groups.step,Groups.reorient
        Groups.step=function(s,budget)
            if budget.ops>0 then
                budget.ops=budget.ops-1
                s.result={candidates={{id='c',blocks={{id='b',block_id='b',w=1,h=1,
                    machines={{id='m',name='assembler',mirror=false}},ports={}}}}}}
                s.done,s.ok=true,true
            end
            return s
        end
        Groups.reorient=function(...) reoriented=true; return old_reorient(...) end
        local r=D.finish(Search,Search.begin(D.input({settings={force_turn_flip={turn=4,flip=true}},
            catalog={entity={assembler={}}}})))
        Groups.step,Groups.reorient=old_step,old_reorient
        return r
    end)
    H.equal(state.ok,true); H.equal(#log.pack,1); H.equal(reoriented,false)
    print('TF4')
end)
H.test('TF5 absent switch keeps the known player blueprint bytes', function()
    local command = "lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output /tmp/rrc-298-tf5.json"
    local pipe = assert(io.popen(command .. ' 2>&1'))
    local output = pipe:read('*a'); local ok = pipe:close()
    H.equal(ok == true or ok == 0,true,output)
    local converted = io.popen('python3 tools/blueprint_string.py /tmp/rrc-298-tf5.json -o /tmp/rrc-298-tf5.bp && sha256sum /tmp/rrc-298-tf5.bp')
    local digest = converted:read('*l'); converted:close()
    H.equal(digest:sub(1,8), '6fea7eb3')
    print('TF5')
end)
H.test('TF6 forced pack must keep its one allowed Turn', function()
    local state=D.run({},function()
        local old_step,old_pack_step=Groups.step,Pack.step
        Groups.step=function(s,budget)
            if budget.ops>0 then
                budget.ops=budget.ops-1
                s.result={candidates={{id='c',blocks={{id='b',block_id='b',w=1,h=1,ports={}}}}}}
                s.done,s.ok=true,true
            end
            return s
        end
        Pack.step=function(s,budget)
            if budget.ops>0 then budget.ops=budget.ops-1;s.errors={{code='BP_P_NO_FIT'}};s.done,s.ok=true,false end
            return s
        end
        local r=D.finish(Search,Search.begin(D.input({settings={force_turn_flip={turn=8,flip=false}}})))
        Groups.step,Pack.step=old_step,old_pack_step
        return r
    end)
    H.equal(state.ok,false); H.equal(state.work.fell_back==true,false)
    print('TF6')
end)
H.test('TF7 catalog exposes engine mirroring restriction', function()
    for _, shape in ipairs(H.shapes()) do
        local world=H.new_world(shape)
        world.add_machine({name='locked-assembler',categories={'crafting'},speed=1,module_slots=0})
        world.add_machine({name='open-assembler',categories={'crafting'},speed=1,module_slots=0})
        local prototype=prototypes.entity['locked-assembler']
        prototypes.entity['locked-assembler']=setmetatable({use_mirroring=false},{__index=prototype})
        world.add_default_infrastructure(); world.init()
        local Catalog=require 'logic.catalog'
        local catalog=Catalog.build(1,{entities={'locked-assembler','open-assembler'}})
        H.equal(catalog.entity['locked-assembler'].use_mirroring,false,shape .. ' retains engine restriction')
        H.equal(catalog.entity['open-assembler'].use_mirroring,nil,shape .. ' leaves absent property nil')
    end
    print('TF7')
end)
H.done('test_force_turn_flip')
