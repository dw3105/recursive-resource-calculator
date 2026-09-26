--Hand seating: after pack, before route, an item input hand moves to the machine-face tile nearest where its flow
--enters. Round 39 base: identity stubs, filled by lane 227.
local Seat = {}

--Moves hands through Hands.place hops; returns the number of hands moved.
function Seat.run(materialized, grid, flows, input_edge)
    return 0
end

--May an edge terminal of a flow stand on the approach tile reserved for that same flow's port?
function Seat.approach_open(state)
    return state.work.edge_split_flows ~= nil
end

return Seat
