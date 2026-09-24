local H = require "tests.harness"
local Grid = require "logic.bp.grid"
local Hands = require "logic.bp.hands"

local function offers()
    local hand = {id="m:h", kind="inserter", name="inserter", x=1, y=3, w=1, h=1,
        machine_id="m", dir=Grid.WEST, pickup_position={x=0.5,y=3.5},drop_position={x=1.5,y=3.5},position={x=1.5,y=3.5}}
    local port = {port_id="p",inserter_id="h",role="in",x=0,y=3,attach_dx=0,attach_dy=3,
        normal_dir=Grid.EAST,travel_dir=Grid.EAST}
    local m = {entities={hand,{id="m",kind="machine",x=2,y=2,w=3,h=3}},ports={port}}
    local grid = Grid.new(10,10)
    Grid.fill(grid,{x=2,y=2,w=3,h=3},1)
    Grid.fill(grid,{x=6,y=3,w=1,h=1},2)
    return m,port,hand,grid
end

H.test("hop options cover other faces, skip corners and occupied cells, and sort nearest first", function()
    local m,port,_,grid = offers()
    Hands.offer_slides(m,grid)
    H.equal(type(port.hop_options),"table")
    H.equal(#port.hop_options <= 16,true)
    local faces, previous = {}, nil
    for _,o in ipairs(port.hop_options) do
        H.equal(math.abs(o.hand_x-o.port_x)+math.abs(o.hand_y-o.port_y),1,"port adjacent")
        local d = math.abs(o.hand_x-1)+math.abs(o.hand_y-3)
        local key = {d,o.hand_y,o.hand_x}
        if previous then
            H.equal((d > previous[1]) or (d == previous[1] and (o.hand_y > previous[2] or
                (o.hand_y == previous[2] and o.hand_x >= previous[3]))),true,"nearest, then y, then x")
        end
        previous=key
        H.equal((o.hand_x==2 or o.hand_x==4) and (o.hand_y==2 or o.hand_y==4) and
            (o.hand_x==2 or o.hand_x==4) and (o.hand_y==2 or o.hand_y==4),false,"not corners")
        H.equal(o.hand_x==6 and o.hand_y==3,false,"blocked hand tile excluded")
        H.equal(o.port_x==6 and o.port_y==3,false,"blocked port tile excluded")
        H.equal(Grid.get(grid,o.hand_x,o.hand_y),nil,"hand tile free")
        H.equal(Grid.get(grid,o.port_x,o.port_y),nil,"port tile free")
        local turns = o.hand_x < 2 and 0 or o.hand_y < 2 and 1 or o.hand_y > 4 and 3 or 2
        H.equal(o.turns,turns,"outward normal rotation")
        faces[o.hand_x..":"..o.hand_y]=true
    end
    H.equal(faces["3:1"]~=nil,true,"north face offered")
    H.equal(faces["3:5"]~=nil,true,"south face offered")
    H.equal(faces["5:2"]~=nil or faces["5:4"]~=nil,true,"east face offered")
    H.equal(port.hand_x,1); H.equal(port.hand_y,3)
end)

H.test("row ports receive no hops", function()
    local m,port,_,grid=offers(); port.row_port=true
    Hands.offer_slides(m,grid)
    H.equal(port.hop_options,nil)
end)

local function placement(role)
    local hand={id="m:h",kind="inserter",name="inserter",x=1,y=3,w=1,h=1,machine_id="m",dir=Grid.WEST,
        position={x=1.5,y=3.5},pickup_position={x=.5,y=3.5},drop_position={x=1.5,y=3.5}}
    local port={port_id="p",inserter_id="h",role=role,x=0,y=3,attach_dx=0,attach_dy=3,
        normal_dir=Grid.WEST,travel_dir=Grid.WEST,_occupied={{x=1,y=3,w=1,h=1}}}
    local m={entities={hand,{id="m",kind="machine",x=2,y=2,w=3,h=3}},ports={port}}
    Hands.place(m,{port_slides={{port_id="p",hop={hand_x=3,hand_y=1,port_x=3,port_y=0,turns=1}}}})
    return hand,port,m
end

H.test("input hop updates hand and port geometry and recomputes transfer points", function()
    local hand,port,m=placement("in")
    H.equal(port.x,3); H.equal(port.y,0); H.equal(port.attach_dx,3); H.equal(port.attach_dy,0)
    H.equal(port.normal_dir,Grid.NORTH); H.equal(port.travel_dir,Grid.NORTH)
    H.equal(hand.x,3); H.equal(hand.y,1); H.equal(hand.dir,Grid.NORTH)
    H.equal(hand.position.x,3.5); H.equal(hand.position.y,1.5)
    H.equal(hand.pickup_position.x,3.5); H.equal(hand.pickup_position.y,.5)
    H.equal(hand.drop_position.x,3.5); H.equal(hand.drop_position.y,2.5)
    H.equal(port._occupied[1].x,3); H.equal(port._occupied[1].y,1)
end)

H.test("output hop reverses pickup and drop", function()
    local hand=placement("out")
    H.equal(hand.pickup_position.x,3.5); H.equal(hand.pickup_position.y,2.5)
    H.equal(hand.drop_position.x,3.5); H.equal(hand.drop_position.y,.5)
end)


H.test("hops are offered on the search's roboport grid, which has no cells (Grid.robo_grid)", function()
    local m,port = offers()
    Hands.offer_slides(m,{w=10,h=10})
    H.equal(type(port.hop_options),"table","hop options exist")
    H.equal(#port.hop_options > 0,true,"at least one hop on a cell-less grid")
end)
H.done("test_hands_hop")
