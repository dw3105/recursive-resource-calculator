local H = require "tests.harness"
local Hands = require "logic.bp.hands"
H.test("slide moves the hand, port and pickup/drop points", function()
    local hand = {id="m:hand", name="inserter", kind="inserter", x=3, y=1, machine_id="machine",
        pickup_position={x=4.5,y=1.5}, drop_position={x=2.5,y=1.5}, position={x=3.5,y=1.5}}
    local port = {port_id="p", inserter_id="hand", flow_id="iron", x=4, y=1}
    local m = {entities={hand, {id="machine",kind="machine",x=1,y=1,w=2,h=2}}, ports={port},
        blocks={{belt_runs={{role="in",flows={"iron"},tiles={{x=4,y=2}}}}}}}
    H.equal(Hands.free_cell(m, 3, 1), true)
    H.equal(hand.y, 2)
    H.equal(port.y, 2)
    H.equal(hand.pickup_position.y, 2.5)
    H.equal(hand.drop_position.y, 2.5)
end)
H.test("free_cell refuses when pickup leaves its belt run", function()
    local hand = {id="m:hand", name="inserter", x=3, y=1, machine_id="machine",
        pickup_position={x=4.5,y=1.5}, drop_position={x=2.5,y=1.5}}
    local port = {inserter_id="hand", flow_id="iron", x=4,y=1}
    local m = {entities={hand,{id="machine",x=1,y=1,w=2,h=2}},ports={port},blocks={{belt_runs={{flows={"iron"},tiles={}}}}}}
    H.equal(Hands.free_cell(m,3,1),false)
end)
H.done("test_hands")
