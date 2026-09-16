--Reason and error text in the report wraps inside a fixed width instead of stretching its table column; numbers never wrap
local H = require "tests.harness"

--Every label under an element, depth first
local function labels_under(element, found)
    found = found or {}
    for _, child in ipairs(element.children) do
        if child.type == "label" then found[#found + 1] = child end
        labels_under(child, found)
    end
    return found
end

--The labels whose localised caption is the key
local function labels_with_key(element, key)
    local found = {}
    for _, label in ipairs(labels_under(element)) do
        if type(label.caption) == "table" and label.caption[1] == key then found[#found + 1] = label end
    end
    return found
end

local function assert_wrapped(label, what)
    H.equal(label.style.single_line, false, what .. " wraps")
    H.equal(label.style.maximal_width, 320, what .. " width")
end

--X crafted from A in an assembler; Y only by hand (no machine has its category); quality module q for loops; X recycles into A
local function wrap_world(shape)
    local world = H.new_world(shape)
    world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}})
    world.add_item("A")
    world.add_item("X")
    world.add_item("Y")
    world.add_module("q", "quality", {quality = 0.25})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, energy_kw = 100, module_slots = 4})
    world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, energy_kw = 50, module_slots = 4})
    world.add_recipe({name = "X", category = "crafting", energy = 1, ingredients = {{name = "A", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "X-recycling", category = "recycling", energy = 0.5, hidden = true, ingredients = {{name = "X", amount = 1}},
        products = {{name = "A", amount = 1, p = 0.25}}})
    world.add_recipe({name = "Y", category = "by-hand", energy = 1, ingredients = {{name = "A", amount = 1}}, products = {{name = "Y", amount = 1}}})
    world.add_recipe({name = "A-mining", category = "mining", ingredients = {}, products = {{name = "A", amount = 1}}})
    world.add_player(1)
    world.init()
    world.bind("item/X", "X")
    world.bind("item/Y", "Y")
    world.bind("item/A", "A-mining")
    require "gui.calculator"
    return world
end

H.test("2.0 N2a N2d a diagnostic report wraps the header error, the unavailable totals, a machine row's reason and a hand-crafted row's reason", function()
    wrap_world("2.0")
    local Report = require "gui.report"
    local output_flow = H.gui_root({type = "flow", name = "output_flow"}, 1)
    Report.new_diagnostic(output_flow, {status = "unsolvable", product_parts = {}, reasons_by_column = {X = "no_rate", Y = "no_rate"},
        columns = {{recipe_name = "X", product_full_name = "item/X"}, {recipe_name = "Y", product_full_name = "item/Y"}}})
    local header = labels_with_key(output_flow, "hxrrc.system_with_no_solution_error")
    H.equal(#header, 1, "header error shown")
    assert_wrapped(header[1], "header error")
    local totals = labels_with_key(output_flow, "hxrrc.totals_unavailable")
    H.equal(#totals, 1, "pollution totals unavailable")
    assert_wrapped(totals[1], "unavailable pollution")
    local reasons = labels_with_key(output_flow, "hxrrc.no_rate")
    H.equal(#reasons, 2, "machine row and hand-crafted row")
    for index, label in ipairs(reasons) do assert_wrapped(label, "reason " .. index) end
    local report = H.parse_report(output_flow)
    H.equal(report.rows["item/X"].kind, "solved", "machine row")
    H.equal(report.rows["item/X"].reason, "hxrrc.no_rate", "its reason")
end)

H.test("2.0 N2b a quality loop's first-tier reason wraps", function()
    wrap_world("2.0")
    local key = require("logic.quality_id").encode("X", "uncommon")
    local report, sheet_pane = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    local reason = report.loops[key].reason
    assert(reason, "the loop without quality modules has a reason")
    local found = labels_with_key(sheet_pane.tabs[1].content.output_flow, reason)
    assert(#found >= 1, "reason label found")
    for index, label in ipairs(found) do assert_wrapped(label, "loop reason " .. index) end
end)

H.test("2.1 N2b the 2.1 loop reason wraps", function()
    wrap_world("2.1")
    local _, sheet_pane = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    local found = labels_with_key(sheet_pane.tabs[1].content.output_flow, "hxrrc.quality_loop_unavailable")
    H.equal(#found, 1, "unavailable reason shown")
    assert_wrapped(found[1], "2.1 loop reason")
end)

H.test("2.0 N2c counts, rates and totals stay single-line and uncapped", function()
    wrap_world("2.0")
    local report, sheet_pane = H.run_sheet({{item = "X", rate = 1, unit = "/s"}})
    H.near(report.rows["item/X"].machines, 1, "one assembler")
    local numbers = 0
    for _, label in ipairs(labels_under(sheet_pane.tabs[1].content.output_flow)) do
        if type(label.caption) == "string" and label.caption:match("%d") then
            numbers = numbers + 1
            H.equal(label.style.single_line, nil, "number label " .. label.caption .. " single-line")
            H.equal(label.style.maximal_width, nil, "number label " .. label.caption .. " uncapped")
        end
    end
    assert(numbers >= 3, "energy, pollution, rate and count labels checked, got " .. numbers)
end)

H.done("test_report_wrap")
