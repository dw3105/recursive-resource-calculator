--Choose the one Turn and Flip every machine of a Block shares, so its fluid boxes face their pipe partners (round 51,
--drawn pack; CONTEXT.md: Turn, Flip). Engine truth: tests/fixtures/flip_fluidboxes_<version>.txt — a Flip mirrors
--x in the machine's own frame, then the Turn rotates; every fluid box keeps its index (2.0.77 and 2.1.20 agree).
--
--Contract (frozen round 51 STEP 0; lane 287 fills the body, never the signature):
--  Orient.choose{block, catalog, turn = 0|4|8|12, partner_dir = {[port_id] = 0|4|8|12}} -> {dir = 0|4|8|12, mirror = bool}
--
--STEP 0 skeleton: machines keep today's orientation.
local Orient = {}
local Grid = require "logic.bp.grid"

function Orient.choose(args)
    args = args or {}
    local block, catalog = args.block or {}, args.catalog or {}
    local partner_dir, turn = args.partner_dir or {}, args.turn or 0
    local ports, candidates, has_fluid = block.ports or {}, {}, false
    for _, port in ipairs(ports) do if port.kind == "fluid" or port.is_fluid then has_fluid = true end end
    if not has_fluid then return {dir = 0, mirror = false} end
    local flip_ok = true
    for _, machine in ipairs(block.machines or {}) do
        local spec = catalog.entity and catalog.entity[machine.name or machine.entity]
        if not machine.can_flip and not (spec and spec.can_flip) then flip_ok = false end
    end
    for _, dir in ipairs({0, 4, 8, 12}) do
        candidates[#candidates + 1] = {dir = dir, mirror = false}
        if flip_ok then candidates[#candidates + 1] = {dir = dir, mirror = true} end
    end
    local best, best_score
    for _, candidate in ipairs(candidates) do
        local score = 0
        for _, port in ipairs(ports) do
            local target = partner_dir[port.port_id]
            if target ~= nil and (port.kind == "fluid" or port.is_fluid) then
                local connection = port.connection
                if not connection then
                    local entity = catalog.entity and catalog.entity[port.machine]
                    local boxes = entity and (entity.fluid_boxes or entity.fluidbox_prototypes) or {}
                    for bi, box in ipairs(boxes) do
                        if port.fluidbox_index == nil or port.fluidbox_index == box.index or port.fluidbox_index == bi then
                            for ci, value in ipairs(box.connections or box.pipe_connections or {}) do
                                if port.connection_index == nil or port.connection_index == ci then connection = value; break end
                            end
                        end
                        if connection then break end
                    end
                end
                if connection then
                    local _, _, facing = Grid.fluid_connection(connection, candidate.dir, candidate.mirror)
                    facing = Grid.rotate_dir(facing, turn)
                    local delta = (facing - target) % 16
                    score = score + (delta == 0 and 2 or (delta == 4 or delta == 12) and 1 or 0)
                end
            end
        end
        if best_score == nil or score > best_score then best, best_score = candidate, score end
    end
    return best or {dir = 0, mirror = false}
end

return Orient
