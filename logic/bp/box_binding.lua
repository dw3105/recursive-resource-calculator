--Box binding (CONTEXT.md): which fluid box of a machine each fluid of its recipe uses, as the engine decides it.
--Round 52 STEP 0 frozen contract (2026-09-30); lane 290 replaces the bodies, never the signatures.
local BoxBinding = {}

--Runtime only: create machine with recipe on scratch surface, read filter per box, map to prototype box index.
--Returns {[fluid_name] = {box = <prototype box index>, role = "input"|"output"}} or nil.
function BoxBinding.probe(surface, machine_proto, recipe_proto)
    return nil
end

--Prototype box index the engine binds fluid_name to, for machine_name running recipe_name, or nil when unknown.
function BoxBinding.box_for(catalog, machine_name, recipe_name, fluid_name, role)
    return nil
end

return BoxBinding
