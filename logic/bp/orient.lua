--Choose the one Turn and Flip every machine of a Block shares, so its fluid boxes face their pipe partners (round 51,
--drawn pack; CONTEXT.md: Turn, Flip). Engine truth: tests/fixtures/flip_fluidboxes_<version>.txt — a Flip mirrors
--x in the machine's own frame, then the Turn rotates; every fluid box keeps its index (2.0.77 and 2.1.20 agree).
--
--Contract (frozen round 51 STEP 0; lane 287 fills the body, never the signature):
--  Orient.choose{block, catalog, turn = 0|4|8|12, partner_dir = {[port_id] = 0|4|8|12}} -> {dir = 0|4|8|12, mirror = bool}
--
--STEP 0 skeleton: machines keep today's orientation.
local Orient = {}

function Orient.choose(_)
    return {dir = 0, mirror = false}
end

return Orient
