--Late binding between modules that need each other.
--
--Factorio allows `require` only while control.lua is being parsed: calling it from a handler raises
--"Require can't be used outside of control.lua parsing". So a module that needs a second module which needs it
--back cannot ask for it lazily. Each module publishes itself here at load, and its partner reads the field when
--it runs. This file requires nothing, so it can never take part in a cycle.
--
--  logic/registry.lua      <- everyone
--  Registry.sheet          gui/sheet.lua
--  Registry.jobs           logic/jobs.lua
--  Registry.snapshot       logic/snapshot.lua
--  Registry.solver_steps   logic/solver_steps.lua
local Registry = {}

--Reads one entry and says which module is missing rather than indexing nil somewhere far away.
function Registry.need(name)
    local value = Registry[name]
    if value == nil then
        error("logic.registry has no '" .. tostring(name) .. "'; control.lua must require the module that publishes it", 2)
    end
    return value
end

return Registry
