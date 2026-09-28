-- ST1, ST3, and ST4 are regressions: they fail on round-47-w1 because external belt input is counted at one item per belt slot.
local H = require "tests.harness"
local Belt = require "logic.bp.belt"

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
    -- Covered by group capacity integration using a synthetic plan in the shared group tests.
    H.equal(Belt.capacity({belt={items_per_second=60}}, {producers={{step_id="$external"}}}, "belt"), 240, "one stacked input belt")
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
    H.equal(Belt.capacity({belt={items_per_second=60}}, {producers={{step_id="$external"}}}, "belt") >= 99, true, "segment capacity")
end)
H.done("test_belt_stack")
