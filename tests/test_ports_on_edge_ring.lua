--Round 54 integrator: a fluid port is its pipe tile; a Block may keep that tile on its own border ring. The Flip of
--a chemical plant moved its pipe tile from (1,0) to (3,0) on the same ring and the rebuild was refused.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"

local function block(ax, ay, kind)
    return {w = 5, h = 4, members = {{kind = "machine", x = 1, y = 1, w = 3, h = 3},
        {kind = "inserter", x = 0, y = 1, w = 1, h = 1}},
        ports = {{port_id = "p", kind = kind or "fluid", attach_dx = ax, attach_dy = ay}}}
end

H.test("PR1 fluid port on a free border tile of the Block counts as on the edge", function()
    assert(Groups.ports_on_edge(block(1, 0), true), "original pipe tile (1,0)")
    assert(Groups.ports_on_edge(block(3, 0), true), "flipped pipe tile (3,0)")
    assert(Groups.ports_on_edge(block(1, -1), true), "outside edge still fine")
    print("PR1 ok")
end)

H.test("PR2 a border tile under a member, an interior tile, or an item port inside stays refused", function()
    assert(not Groups.ports_on_edge(block(0, 1), true), "inserter covers (0,1)")
    assert(not Groups.ports_on_edge(block(2, 2), true), "interior tile")
    assert(not Groups.ports_on_edge(block(3, 0, "item"), true), "item port inside envelope")
    print("PR2 ok")
end)

H.test("PR4 a fluid port in an open gap column between machines counts; a walled-in gap does not", function()
    local open = {w = 9, h = 5, members = {{kind = "machine", x = 0, y = 1, w = 4, h = 4},
        {kind = "machine", x = 5, y = 1, w = 4, h = 4}},
        ports = {{port_id = "p", kind = "fluid", attach_dx = 4, attach_dy = 3}}}
    assert(Groups.ports_on_edge(open, true), "gap column x=4 is open to the top")
    local closed = {w = 9, h = 5, members = {{kind = "machine", x = 0, y = 1, w = 4, h = 4},
        {kind = "machine", x = 5, y = 1, w = 4, h = 4}, {kind = "inserter", x = 4, y = 0, w = 1, h = 1},
        {kind = "inserter", x = 4, y = 4, w = 1, h = 1}},
        ports = {{port_id = "p", kind = "fluid", attach_dx = 4, attach_dy = 2}}}
    assert(not Groups.ports_on_edge(closed, true), "gap walled at both ends")
    print("PR4 ok")
end)

H.test("PR3 without the forced ring (drawn) a border tile inside the Block stays refused", function()
    assert(not Groups.ports_on_edge(block(3, 0)), "drawn keeps the round 53 rule")
    print("PR3 ok")
end)

H.test("PR5 a fluid port walled in by machines is a Blocked fluid port; belts or inserters around it are not", function()
    local walled = {w = 9, h = 5, members = {{kind = "machine", x = 0, y = 0, w = 4, h = 5},
        {kind = "machine", x = 5, y = 0, w = 4, h = 5}, {kind = "machine", x = 4, y = 0, w = 1, h = 2},
        {kind = "machine", x = 4, y = 3, w = 1, h = 2}},
        ports = {{port_id = "p", kind = "fluid", attach_dx = 4, attach_dy = 2}}}
    assert(Groups.fluid_port_walled(walled), "machines on all four sides")
    local soft = {w = 9, h = 5, members = {{kind = "machine", x = 0, y = 0, w = 4, h = 5},
        {kind = "machine", x = 5, y = 0, w = 4, h = 5}, {kind = "inserter", x = 4, y = 0, w = 1, h = 1},
        {kind = "inserter", x = 4, y = 4, w = 1, h = 1}},
        belt_runs = {{tiles = {{x = 4, y = 1}}}},
        ports = {{port_id = "p", kind = "fluid", attach_dx = 4, attach_dy = 2}}}
    assert(not Groups.ports_on_edge(soft, true), "inserters and a belt still refuse the rebuild")
    assert(not Groups.fluid_port_walled(soft), "but they can move: not a Blocked fluid port")
    local item = {w = 9, h = 5, members = walled.members,
        ports = {{port_id = "p", kind = "item", attach_dx = 4, attach_dy = 2}}}
    assert(not Groups.fluid_port_walled(item), "item ports never count")
    print("PR5 ok")
end)

H.done("test_ports_on_edge_ring")
