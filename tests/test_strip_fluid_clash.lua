--Round 54 integrator: EM plant x3 strip put holmium solution (4,2) over heavy oil (4,3) in one gap column; plain
--pipes join every neighbour, so no route fed either. The strip moves the next machine while pipe tiles of different
--fluids sit within 2 tiles, or their front tiles within 1.
local H = require "tests.harness"
local Groups = require "logic.bp.groups"

local function t(x, y, flow, front) return {x = x, y = y, flow = flow, front = front} end

H.test("SC1 different fluids within two tiles clash; same fluid never", function()
    assert(Groups._strip_fluid_clash({t(4, 2, "h")}, {t(4, 3, "o")}), "adjacent")
    assert(Groups._strip_fluid_clash({t(4, 2, "h")}, {t(5, 3, "o")}), "diagonal, columns touch")
    assert(not Groups._strip_fluid_clash({t(4, 2, "h")}, {t(6, 3, "o")}), "three apart")
    assert(not Groups._strip_fluid_clash({t(4, 2, "h")}, {t(4, 3, "h")}), "same fluid")
    print("SC1 ok")
end)

H.test("SC2 front tiles of different fluids clash only when touching", function()
    assert(Groups._strip_fluid_clash({t(10, 26, "h", true)}, {t(10, 27, "o", true)}), "fronts touch")
    assert(not Groups._strip_fluid_clash({t(10, 26, "h", true)}, {t(10, 28, "o", true)}), "fronts two apart")
    print("SC2 ok")
end)

H.done("test_strip_fluid_clash")
