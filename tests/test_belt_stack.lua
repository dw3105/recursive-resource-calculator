-- ST1, ST3, and ST4 are regressions: they fail on round-47-w1 because external belt input is counted at one item per belt slot.
local H = require "tests.harness"
local Belt = require "logic.bp.belt"
local Validate = require "logic.bp.validate"

io.write("ST0\n")
H.test("ST0 stacked input capacities", function()
    local ext = {producers={{step_id="$external"}}}
    H.equal(Belt.capacity({belt={items_per_second=60}}, ext, "belt"), 240, "default stack")
    H.equal(Belt.capacity({belt={items_per_second=60}}, {}, "belt"), 60, "internal")
    H.equal(Belt.capacity({belt={items_per_second=60}}, {is_fluid=true, producers={{step_id="$external"}}}, "belt"), 60, "fluid")
    H.equal(Belt.capacity({belt={items_per_second=60, stack_max=2}}, ext, "belt"), 120, "catalog stack")
    H.equal(Belt.capacity({belt={items_per_second=60, lane_items_per_second=30}}, ext, "lane"), 120, "lane stack")
    H.equal(Belt.stack_max({}), 4, "missing stack defaults")
end)

io.write("ST1\n")
H.test("ST1 external 99/s input does not force belt chunks", function()
    local Groups = require "logic.bp.groups"
    local plan = {steps={{step_id="s",recipe="r",machine="assembler",machine_count=4,
        inputs={{flow_id="item/ore",rate_per_second=99}},outputs={{flow_id="item/product",rate_per_second=1}}}},
        flows={{flow_id="item/ore",producers={{step_id="$external",share_per_second=99}},consumers={{step_id="s",share_per_second=99}}},
            {flow_id="item/product",producers={{step_id="s",share_per_second=1}},consumers={{step_id="$external",share_per_second=1}}}},ports={}}
    local catalog={entity={assembler={name="assembler",tile_w=3,tile_h=3},inserter={name="inserter",tile_w=1,tile_h=1}},
        inserter={items_per_second=100},belt={items_per_second=60,stack_max=4}}
    local state=Groups.begin({plan=plan,catalog=catalog})
    for _=1,100 do if state.done then break end; Groups.step(state,{ops=10}) end
    local machines=0; for _,b in ipairs(state.result.candidates[1].blocks) do for _,m in ipairs(b.machines) do if m.step_id=="s" then machines=machines+1 end end end
    H.equal(machines,4,"all machines grouped without external input chunking")
end)
io.write("ST2\n")
H.test("ST2 internal capacity stays unstacked", function()
    H.equal(Belt.capacity({belt={items_per_second=60}}, {}, "belt"), 60, "internal capacity")
end)
io.write("ST3\n")
H.test("ST3 external twins fit stacked belt", function()
    H.equal(Belt.capacity({belt={items_per_second=60}}, {producers={{step_id="$external"}}}, "belt") >= 99, true, "edge capacity")
end)
io.write("ST4\n")
H.test("ST4 external segment capacity exceeds unstacked rate", function()
    local function has_capacity_error(external)
        local flow={flow_id="item/x",producers=external and {{step_id="$external",share_per_second=99}} or {{step_id="s",share_per_second=99}},
            consumers={{step_id="$external",share_per_second=99}}}
        local v=Validate.begin({grid={w=3,h=3},catalog={entity={},belt={items_per_second=60}},entities={},segments={{segment_id="b",kind="belt",flow_id="item/x",
            allocations={{flow_id="item/x",sink="port:out",rate_per_second=99}}}},flows={flow},ports={}})
        for _=1,500 do if v.done then break end; Validate.step(v,{ops=100}) end
        for _,e in ipairs(v.errors or {}) do if e.code=="BP_V_TRANSFER_CAPACITY" then return true end end
        return false
    end
    H.equal(has_capacity_error(true),false,"external segment accepted")
    H.equal(has_capacity_error(false),true,"internal segment remains bounded")
end)
H.done("test_belt_stack")
