--MaxRects with Best Short Side Fit: put opaque rectangles into a rectangle that already has holes in it.
--
--Owned by lane W3-pack. It never learns what a block contains, which flow it carries or why it is that size;
--that ignorance is what keeps it small and testable. Insertion order is decided by the search, not here.
--
--  Pack.begin{area = TileRect, obstacles = {TileRect}, blocks = {{block_id, w, h, allowed_dirs}},
--             limits = {max_free_regions = int}} -> state
--  Pack.step(state, budget) -> state          budget = {ops = int}, decremented inside the region scan
--  state.result = {placements = {{block_id, x, y, dir, w, h}}, free_regions = {TileRect},
--                  stats = {peak_free_regions, scans}}
--  state.errors = {{code = "BP_P_NO_FIT", block_id}} | {{code = "BP_P_REGION_LIMIT"}}
--
--Yielding happens inside the scan over free regions, not between blocks: one block against many regions is
--already enough work to hold a tick.
local Pack = {}

function Pack.begin(input)
    return {done = false, ok = nil, cursor = {block_index = 1, region_index = 1}, progress = {phase = "packing", done_units = 0}}
end

function Pack.step(state, budget)
    return state
end

--Best Short Side Fit: the smaller leftover side decides, the larger breaks the tie, coordinates break that tie
function Pack.bssf_score(free, w, h)
    return nil, nil
end

return Pack
