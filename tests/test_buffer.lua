--The buffer-zone rule from the player's screenshots, 2026-09-23 (logic/bp/buffer.lua).
local H = require "tests.harness"
local Buffer = require "logic.bp.buffer"

local catalog = {recipe = {
    one = {ingredients = {{name = "a"}}},
    two = {ingredients = {{name = "a"}, {name = "b"}}},
    three = {ingredients = {{name = "a"}, {name = "b"}, {name = "c"}}},
    five = {ingredients = {{name = "a"}, {name = "b"}, {name = "c"}, {name = "d"}, {name = "e"}}},
}}

local function machine(x, y, recipe, name)
    name = name or "assembling-machine-3"
    return {rect = {x = x, y = y, w = 3, h = 3}, ring = Buffer.ring(catalog, recipe), key = Buffer.key(name, recipe)}
end

H.test("BZ1 ring width follows the ingredient count: 1-2 -> 2, 3 -> 3, 4+ -> 4, unknown -> 2", function()
    H.equal(Buffer.ring(catalog, "one"), 2, "one ingredient")
    H.equal(Buffer.ring(catalog, "two"), 2, "two ingredients")
    H.equal(Buffer.ring(catalog, "three"), 3, "three ingredients")
    H.equal(Buffer.ring(catalog, "five"), 4, "five ingredients")
    H.equal(Buffer.ring(catalog, "nope"), 2, "unknown recipe")
end)

H.test("BZ2 the zone is the footprint grown by the ring on every side", function()
    local zone = Buffer.zone({x = 10, y = 20, w = 3, h = 3}, 3)
    H.equal(zone.x, 7, "x"); H.equal(zone.y, 17, "y"); H.equal(zone.w, 9, "w"); H.equal(zone.h, 9, "h")
end)

H.test("BZ3 different recipes need both rings between them", function()
    --Ring 2 + ring 3 = 5 empty tiles between footprints.
    H.equal(Buffer.conflict(machine(0, 0, "two"), machine(3 + 4, 0, "three")), true, "4 tiles apart conflicts")
    H.equal(Buffer.conflict(machine(0, 0, "two"), machine(3 + 5, 0, "three")), false, "5 tiles apart is clear")
end)

H.test("BZ4 same recipe in one column or one row may share the ring", function()
    H.equal(Buffer.conflict(machine(0, 0, "two"), machine(0, 4, "two")), false, "vertical pair, same column")
    H.equal(Buffer.conflict(machine(0, 0, "two"), machine(5, 0, "two")), false, "horizontal pair, same row")
end)

H.test("BZ5 same recipe but shifted, or another machine type, keeps full rings", function()
    H.equal(Buffer.conflict(machine(0, 0, "two"), machine(2, 5, "two")), true, "diagonal shift conflicts")
    H.equal(Buffer.conflict(machine(0, 0, "two"), machine(0, 4, "two", "assembling-machine-2")), true,
        "same recipe, other machine conflicts")
end)

H.done("test_buffer")
