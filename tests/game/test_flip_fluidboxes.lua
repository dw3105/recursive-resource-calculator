--Round 51 STEP 0 (headless fact, not a Probe): where the engine puts each fluid box connection of a crafting machine for every Turn and Flip.
--Rows go to script-output/rrc_flip_fluidboxes.txt; tests/fixtures/flip_fluidboxes_<version>.txt is a copy of them and is
--the truth the offline Flip geometry (Grid.fluid_connection) is checked against. Headless only.
local Lab = require "tests.game.lib.lab"

local MACHINES = {"assembling-machine-2", "assembling-machine-3", "chemical-plant", "oil-refinery", "foundry",
    "biochamber", "cryogenic-plant", "electromagnetic-plant", "recycler"}

local function fmt(n) return string.format("%g", n) end

describe("flip fluidboxes", function()
    it("fluid box positions per turn and flip", function()
        if RRC_OFFLINE then return end
        local surface = Lab.surface()
        Lab.prepare(surface, {{-40, -40}, {40, 40}})
        local rows = {"# version " .. script.active_mods.base}
        local x = -30
        for _, name in ipairs(MACHINES) do
            local proto = prototypes.entity[name]
            if proto then
                local ok, um = pcall(function() return proto.use_mirroring end)
                --A machine shows recipe-dependent fluid boxes only with a recipe set: take its recipe with most fluids.
                local recipe, most = nil, 0
                for rname, r in pairs(prototypes.recipe) do
                    --2.0 LuaRecipePrototype.category; 2.1 has no such key (read guarded, any listed category counts).
                    local okc, cat = pcall(function() return r.category end)
                    local cats = okc and {cat} or {}
                    if not okc then
                        local okl, list = pcall(function() return r.categories end)
                        for k, v in pairs(okl and list or {}) do cats[#cats + 1] = type(k) == "string" and k or (type(v) == "table" and v.name or v) end
                    end
                    local fits = false
                    for _, c in ipairs(cats) do if proto.crafting_categories and proto.crafting_categories[c] then fits = true end end
                    if fits then
                        local n = 0
                        for _, i in ipairs(r.ingredients) do if i.type == "fluid" then n = n + 1 end end
                        for _, i in ipairs(r.products) do if i.type == "fluid" then n = n + 1 end end
                        if n > most or (n == most and n > 0 and rname < recipe) then recipe, most = rname, n end
                    end
                end
                rows[#rows + 1] = string.format("RECIPE %s %s fluids=%d", name, tostring(recipe), most)
                rows[#rows + 1] = string.format("PROTO %s type=%s use_mirroring=%s", name, proto.type, ok and tostring(um) or "n/a")
                for _, dir in ipairs({0, 4, 8, 12}) do
                    for _, mirror in ipairs({false, true}) do
                        --Recipe at creation: a crafting machine without a fluid recipe ignores direction (edir stays 0).
                        local e = surface.create_entity{name = name, position = {x, 0}, direction = dir, force = "player",
                            recipe = proto.type == "assembling-machine" and recipe or nil}
                        assert(e, "created " .. name)
                        local set_ok = pcall(function() e.mirroring = mirror end)
                        local got = e.mirroring
                        --2.0 LuaEntity.fluidbox; 2.1 removed it for get_fluid_box_pipe_connections(i).
                        local boxes = #(proto.fluidbox_prototypes or {})
                        local function conns(i)
                            local ok20, fb = pcall(function() return e.fluidbox end)
                            if ok20 and fb then return fb.get_pipe_connections(i) end
                            return e.get_fluid_box_pipe_connections(i)
                        end
                        for i = 1, boxes do
                            --am2/am3 have fluid boxes only while a fluid recipe is set: those rows are skipped.
                            local okc, list = pcall(conns, i)
                            for _, c in ipairs(okc and list or {}) do
                                rows[#rows + 1] = string.format("CONN %s dir=%d edir=%s mirror=%s set=%s got=%s box=%d type=%s flow=%s pos=%s,%s target=%s,%s",
                                    name, dir, tostring(e.direction), tostring(mirror), tostring(set_ok), tostring(got), i, tostring(c.connection_type),
                                    tostring(c.flow_direction), fmt(c.position.x - e.position.x), fmt(c.position.y - e.position.y),
                                    fmt(c.target_position.x - e.position.x), fmt(c.target_position.y - e.position.y))
                            end
                        end
                        e.destroy()
                    end
                end
            end
        end
        helpers.write_file("rrc_flip_fluidboxes.txt", table.concat(rows, "\n") .. "\n")
        assert.is_true(#rows > 10, "probe rows")
    end)
end)
