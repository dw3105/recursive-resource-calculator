--Row run direction (docs/contracts/row_block.md §Reversal). After pack, a row's in or out run may be mirrored so
--its port sits at the run end nearest the flow's partner. Round 39 base: identity stub, filled by lane 226.
local RunDir = {}

--Returns the block to materialize: `block` itself, or a reversed copy. Never mutates `block`.
function RunDir.choose(block, placement, blocks, placements, grid, flows, input_edge, output_edge)
    return block
end

return RunDir
