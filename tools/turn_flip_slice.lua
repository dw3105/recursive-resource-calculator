-- Shared Turn/Flip suite selector. Case order is supplied by the caller and must already be stable.
local Slice = {}
Slice.POSES = {
    {turn = 0, flip = 0}, {turn = 0, flip = 1},
    {turn = 4, flip = 0}, {turn = 4, flip = 1},
    {turn = 8, flip = 0}, {turn = 8, flip = 1},
    {turn = 12, flip = 0}, {turn = 12, flip = 1},
}

function Slice.pick(cases, round_id, full)
    assert(type(cases) == "table", "cases must be an ordered list")
    round_id = tonumber(round_id) or 56
    local picked = {}
    for case_index, name in ipairs(cases) do
        local first, last = 1, #Slice.POSES
        if not full then
            first = ((case_index - 1 + round_id) % #Slice.POSES) + 1
            last = first
        end
        for pose_index = first, last do
            local pose = Slice.POSES[pose_index]
            picked[#picked + 1] = {case = name, turn = pose.turn, flip = pose.flip}
        end
    end
    return picked
end

return Slice
