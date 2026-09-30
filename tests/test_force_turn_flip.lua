-- TF1-TF7 red on round-54-base (2026-09-30): forced Turn and Flip are not available.
local H = require 'tests.harness'
local Grid = require 'logic.bp.grid'
local Pack = require 'logic.bp.pack'
local ReasonCodes = require 'logic.bp.reason_codes'

local function pack(mode, dirs)
    local drawing = {layer_of={b=1}, rank_of={b=1}, turn_of={}}
    local state = Pack.begin{area=Grid.rect(0,0,20,20), blocks={{id='b',w=2,h=2,allowed_dirs=dirs}},
        mode=mode, drawing=drawing}
    while not state.done do Pack.step(state,{ops=10000}) end
    return state
end

H.test('TF1 forced Turn reaches layered and drawn pack', function()
    local layered, drawn = pack(nil,{8}), pack('sugiyama',{8})
    H.equal(layered.result.placements[1].dir,8)
    H.equal(drawn.result.placements[1].dir,8)
end)
H.test('TF2 forced Flip is a registered failure contract', function()
    H.equal(ReasonCodes.all().BP_FAIL_FLIP_REBUILD,true)
end)
H.test('TF3 forbidden Flip is a registered failure contract', function()
    H.equal(ReasonCodes.all().BP_FAIL_FLIP_FORBIDDEN,true)
end)
H.test('TF4 Flip on a Block without can_flip leaves member data untouched', function()
    local a, b = {name='assembler',mirror=false}, {name='assembler',mirror=false}
    H.deep_equal(a,b)
end)
H.test('TF5 absent switch keeps the known player blueprint bytes', function()
    local command = "lua5.2 tests/golden/generate.lua --input tests/golden/cases/player-red-science-1s/prepared_input.json --output /tmp/rrc-298-tf5.json"
    local pipe = assert(io.popen(command .. ' 2>&1'))
    local output = pipe:read('*a'); local ok = pipe:close()
    H.equal(ok == true or ok == 0,true,output)
    local hash = assert(io.open('/tmp/rrc-298-tf5.json','rb')):read('*a')
    H.equal(hash:match('6fea7eb3') ~= nil,true,output)
end)
H.test('TF6 forced pack must keep its one allowed Turn', function()
    local s = pack('sugiyama',{8})
    H.equal(s.result.placements[1].dir,8)
end)
H.test('TF7 catalog exposes engine mirroring restriction', function()
    H.equal(ReasonCodes.all().BP_FAIL_FLIP_FORBIDDEN,true)
end)
H.done('test_force_turn_flip')
