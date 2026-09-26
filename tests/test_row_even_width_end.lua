-- RE1 fails on round-41-base: the near belt extends one tile past the final plain hand on a 4-wide row.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"

local function build(width)
    local catalog={entity={machine={name="machine",tile_w=width,tile_h=width,etype="assembling-machine"},
        inserter={name="inserter",tile_w=1,tile_h=1,pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}}},
        inserter={name="inserter",pickup_offset={x=0,y=1},drop_offset={x=0,y=-1}},belt={items_per_second=15}}
    local plan={steps={{step_id="s",machine="machine",machine_count=3,recipe="r",
        inputs={{flow_id="item/a",rate_per_second=1},{flow_id="item/b",rate_per_second=1}},outputs={{flow_id="item/c"}}}},
        flows={{flow_id="item/a"},{flow_id="item/b"},{flow_id="item/c"}}}
    local state=Groups.begin({catalog=catalog,plan=plan})
    for _=1,100 do if state.done then break end; Groups.step(state,{ops=10}) end
    for _,candidate in ipairs(state.result.candidates) do for _,block in ipairs(candidate.blocks) do if block.row then return block end end end
end

H.test("RE1 four-wide near belt ends at the last plain hand column",function()
    local block=build(4); H.equal(block~=nil,true); if not block then return end
    local run; for _,r in ipairs(block.belt_runs) do if r.role=="in" and not r.far then run=r; break end end
    local last_hand
    for _,hand in ipairs(block.inserters) do if hand.role=="input" and not hand.long and (not last_hand or hand.x>last_hand.x) then last_hand=hand end end
    H.equal(run.tiles[#run.tiles].x,last_hand.x,"near belt terminates at last plain hand")
end)
H.test("RE2 three-wide row keeps its near belt end",function()
    local block=build(3); H.equal(block~=nil,true); if not block then return end
    local run; for _,r in ipairs(block.belt_runs) do if r.role=="in" and not r.far then run=r; break end end
    local last_machine=block.machines[#block.machines]
    local old_x=last_machine.x+math.floor(last_machine.w/2)
    H.equal(run.tiles[#run.tiles].x,old_x,"odd-width endpoint unchanged")
end)
H.done("test_row_even_width_end")
