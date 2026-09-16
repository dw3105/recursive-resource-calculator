--Quality loop stages that run no machines say why (round 6d U1): the item ingredients no supply of which reaches the stage, in a narrow wrapped label
local H = require "tests.harness"

local M = {} --modules loaded after each new world

--Three qualities. X is cast from molten (no items) at normal; above it X is made from O (X-O), C (X-C) or C, D and O (X-CDO). mine-P-O makes P with O
--as a byproduct on a miner rolling quality; mine-O, mine-C and mine-D make their item. X-recycling returns X itself.
local function idle_world(options)
    options = options or {}
    local world = H.new_world("2.0")
    world.set_quality_chain({{name = "normal", level = 0}, {name = "uncommon", level = 1}, {name = "rare", level = 2}})
    for _, name in ipairs({"X", "O", "C", "D", "P"}) do world.add_item(name) end
    world.add_fluid("molten")
    world.add_module("q", "quality", {quality = 0.25})
    world.add_machine({name = "caster", categories = {"metallurgy"}, speed = 1, module_slots = 4})
    world.add_machine({name = "assembler", categories = {"crafting"}, speed = 1, module_slots = 4})
    world.add_machine({name = "miner", categories = {"mining"}, speed = 1, module_slots = 0, base_quality = 1})
    world.add_machine({name = "recycler", type = "furnace", categories = {"recycling"}, speed = 1, module_slots = 4})
    world.add_recipe({name = "cast-X", category = "metallurgy", ingredients = {{type = "fluid", name = "molten", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "X-O", category = "crafting", ingredients = {{name = "O", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "X-C", category = "crafting", ingredients = {{name = "C", amount = 1}}, products = {{name = "X", amount = 1}}})
    world.add_recipe({name = "X-CDO", category = "crafting", ingredients = {{name = "O", amount = 1}, {name = "C", amount = 1}, {name = "D", amount = 1}},
        products = {{name = "X", amount = 1}}})
    if options.recycling then
        world.add_recipe({name = "X-recycling", category = "recycling", hidden = true, ingredients = {{name = "X", amount = 1}}, products = {{name = "X", amount = 1, p = 0.25}}})
    end
    world.add_recipe({name = "mine-P-O", category = "mining", ingredients = {}, products = {{name = "P", amount = 1}, {name = "O", amount = 1}}})
    world.add_recipe({name = "mine-O", category = "mining", ingredients = {}, products = {{name = "O", amount = 1}}})
    world.add_recipe({name = "mine-C", category = "mining", ingredients = {}, products = {{name = "C", amount = 1}}})
    world.add_recipe({name = "mine-D", category = "mining", ingredients = {}, products = {{name = "D", amount = 1}}})
    world.add_player(1)
    world.init()
    storage[1].calculator = {force_auto_center = function() end}
    world.bind("item/X", options.bind_x or "cast-X")
    world.bind("item/P", "mine-P-O")
    world.bind("item/O", "mine-O")
    world.bind("item/C", "mine-C")
    world.bind("item/D", "mine-D")
    M.QualityId = require "logic.quality_id"
    M.QualityLoops = require "logic.quality_loops"
    M.QualityLoop = require "logic.quality_loop"
    M.Solver = require "logic.solver"
    M.Sheet = require "gui.sheet"
    M.Report = require "gui.report"
    require "gui.calculator" --registers the report's handlers
    return world
end

--Stores the loop of X at a quality: uncommon and rare tier recipes, four q modules on every craft tier; options.start, options.assist (recipe name)
local function configure(quality, uncommon_recipe, rare_recipe, options)
    options = options or {}
    local key = M.QualityId.encode("X", quality)
    local parts = {type = "item", name = "X", quality = quality}
    local config = M.QualityLoops.normalized(1, key, parts)
    config.start_quality = options.start
    if config.crafts.uncommon then config.crafts.uncommon.recipe_name = uncommon_recipe end
    if config.crafts.rare then config.crafts.rare.recipe_name = rare_recipe end
    if options.assist then config.assist.recipe_name = options.assist end
    M.QualityLoops.store(1, key, config)
    config = M.QualityLoops.normalized(1, key, parts)
    M.QualityLoops.store(1, key, config)
    for _, settings in pairs(config.crafts) do
        settings.setup.modules = {{name = "q"}, {name = "q"}, {name = "q"}, {name = "q"}}
    end
    return key, parts
end

local function find_all(element, predicate, found)
    found = found or {}
    if predicate(element) then found[#found + 1] = element end
    for _, child in ipairs(element.children) do find_all(child, predicate, found) end
    return found
end

local function label_of(line)
    local buttons = find_all(line.machine_button.parent, function(element) return element.type == "label" end)
    return buttons[#buttons]
end

local function compute(sheet_flow)
    local button = find_all(sheet_flow, function(element) return element.name == "hxrrc_compute_button" end)[1]
    M.Sheet.calculate(button)
    return H.parse_report(sheet_flow.output_flow)
end

local function column_of(result, key)
    for _, column in ipairs(result.columns) do
        if column.product_full_name == key then return column end
    end
end

local function final_tiers(result, key)
    local by_quality = {}
    for _, tier in ipairs(column_of(result, key).quality_loop.tiers) do by_quality[tier.quality] = tier end
    return by_quality
end

H.test("2.0 U1a U1e an idle tier names the ingredient it lacks at its quality in a narrow wrapped label, and keeps its controls; round-up shows the same", function()
    idle_world()
    local key = configure("rare", "X-O", "X-C")
    for _, round_up in ipairs({false, true}) do
        local report, sheet_pane = H.run_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}}, 1, {round_up = round_up})
        local loop = report.loops[key]
        local label = round_up and "U1e " or "U1a "
        local uncommon = loop.tiers_by_quality.uncommon
        H.equal(uncommon.craft.reason, "hxrrc.quality_loop_stage_idle", label .. "uncommon tier idle")
        H.deep_equal(uncommon.craft.caption, {"hxrrc.quality_loop_stage_idle", {"quality-name.uncommon"}, {"", {"item-name.O"}}}, label .. "names uncommon O")
        H.deep_equal(uncommon.craft.tooltip, {"", {"", "", {"item-name.O"}}}, label .. "tooltip lists O")
        local text = label_of(uncommon.craft)
        H.equal(text.style.single_line, false, label .. "wraps")
        H.equal(text.style.maximal_width, 160, label .. "narrow")
        assert(uncommon.craft.machine_button, label .. "machine button kept")
        assert(#find_all(uncommon.module_flow, function(element) return element.name == "hxrrc_choose_module_button" end) > 0, label .. "module slots kept")
        H.equal(#find_all(sheet_pane, function(element)
            return element.name == "hxrrc_choose_tier_recipe_button" and element.tags.tier == "uncommon" end), 1, label .. "tier recipe button kept")
        H.equal(loop.tiers_by_quality.rare.craft.caption[3][2][1], "item-name.C", label .. "rare tier names rare C")
        assert(loop.tiers_by_quality.normal.craft.machines > 0, label .. "the start tier counts machines")
    end
end)

H.test("2.0 U1b a stage lacking three ingredients names two and says how many more; the tooltip lists all", function()
    idle_world()
    local key = configure("rare", "X-CDO", "X-C")
    local report = H.run_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}})
    local line = report.loops[key].tiers_by_quality.uncommon.craft
    H.deep_equal(line.caption, {"hxrrc.quality_loop_stage_idle", {"quality-name.uncommon"},
        {"", {"item-name.C"}, ", ", {"item-name.D"}, " ", {"hxrrc.and_more", 1}}}, "two names and one more")
    H.deep_equal(line.tooltip, {"", {"", "", {"item-name.C"}}, {"", "\n", {"item-name.D"}}, {"", "\n", {"item-name.O"}}}, "all three in the tooltip")
end)

H.test("2.0 U1c U1h a tier fed from another row counts machines and keeps no reason, while an idle tier of the same mixed loop still names what it lacks", function()
    idle_world()
    local key, parts = configure("rare", "X-O", "X-C")
    local result = M.Solver.solve_for({[key] = 1, ["item/P"] = 9}, 1, {[key] = parts})
    H.equal(result.status, "ok", "solved")
    local info = column_of(result, key).quality_loop
    assert(info.parts and info.parts[1].share > 0, "U1h: the loop is mixed with outside uncommon O")
    local tiers = final_tiers(result, key)
    assert(tiers.uncommon.crafts > 0, "U1h: uncommon tier crafts")
    H.equal(tiers.uncommon.missing, nil, "U1h: an active tier keeps no reason")
    H.deep_equal(tiers.rare.missing, {"C"}, "U1h: the idle rare tier keeps its reason through the mix")

    local report = H.run_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}, {item = "P", rate = 9, unit = "/s"}})
    local loop = report.loops[key]
    H.equal(loop.tiers_by_quality.uncommon.craft.reason, nil, "U1c: no idle text on the fed tier")
    assert(loop.tiers_by_quality.uncommon.craft.machines > 0, "U1c: the fed tier counts machines")
    H.equal(loop.tiers_by_quality.rare.craft.reason, "hxrrc.quality_loop_stage_idle", "U1h: rare tier idle in the report")
    H.equal(loop.tiers_by_quality.rare.craft.caption[3][2][1], "item-name.C", "U1h: names C")
    H.equal(loop.tiers_by_quality.rare.craft.tooltip[2][3][1], "item-name.C", "U1h: tooltip names C")
end)

H.test("2.0 U1d an idle recycler pool, and an idle tier recycle line, say there is nothing to recycle", function()
    idle_world({recycling = true, bind_x = "X-O"})
    storage[1].identifiers_of_chosen_crafting_machines_by_recipe_name["mine-O"] = {name = "miner"}
    local key = configure("uncommon", nil, nil, {start = "uncommon"})
    local report = H.run_sheet({{item = "X", quality = "uncommon", rate = 1, unit = "/s"}})
    local pool = report.loops[key].pool.recycle
    H.equal(pool.reason, "hxrrc.quality_loop_recycler_idle", "pool idle")
    H.equal(label_of(pool).style.maximal_width, 160, "pool text narrow")

    --a solve whose lower tier recycles nothing, drawn by the report
    idle_world({recycling = true})
    local rare_key, rare_parts = configure("rare", "X-O", "X-C")
    local result = M.Solver.solve_for({[rare_key] = 1}, 1, {[rare_key] = rare_parts})
    H.equal(result.status, "ok", "solved")
    local column = column_of(result, rare_key)
    column.quality_loop.tiers[2].recycle_crafts = 0
    local output_flow = H.gui_root({type = "flow", name = "output_flow"}, 1)
    M.Report.new(output_flow, result)
    local tier = H.parse_report(output_flow).loops[rare_key].tiers_by_quality.uncommon
    H.equal(tier.recycle.reason, "hxrrc.quality_loop_recycler_idle", "tier recycle line idle")
end)

H.test("2.0 U1f the tier step names only the ingredients whose missing supply bounds it", function()
    idle_world()
    local step = M.QualityLoop._tier_step({first = false, recycling = false, items = {"C", "O"}, amounts = {C = 1, O = 1}, supply = {C = 1, O = 0},
        feed = 0, own = 1, returns = {}, self_return = 0})
    H.equal(step.crafts, 0, "idle")
    H.deep_equal(step.missing, {"O"}, "only O lacks supply")
    step = M.QualityLoop._tier_step({first = false, recycling = false, items = {"C", "O"}, amounts = {C = 1, O = 1}, supply = {C = 1, O = 2},
        feed = 0, own = 1, returns = {}, self_return = 0})
    H.equal(step.crafts, 1, "crafts")
    H.equal(step.missing, nil, "no reason when it crafts")
end)

H.test("2.0 U1g an ingredient another target makes, but not available to the stage, is named as unavailable to this stage", function()
    idle_world()
    local key, parts = configure("rare", "X-O", "X-C")
    local c_key = M.QualityId.encode("C", "rare")
    local report = H.run_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}, {item = "C", quality = "rare", rate = 1, unit = "/s"}})
    local result = M.Solver.solve_for({[key] = 1, [c_key] = 1}, 1, {[key] = parts, [c_key] = {type = "item", name = "C", quality = "rare"}})
    local c_column = column_of(result, c_key)
    H.near(result.recipe_rates[c_column.recipe_name], 1, "the rare C target is made at 1 /s")
    H.equal(report.loops[key].tiers_by_quality.rare.craft.reason, "hxrrc.quality_loop_stage_idle", "rare X tier idle")
    H.equal(report.loops[key].tiers_by_quality.rare.craft.caption[3][2][1], "item-name.C", "names C")
    local locale = io.open("locale/en/locale.cfg"):read("*a")
    local line = locale:match("\nquality_loop_stage_idle=([^\n]*)")
    assert(line:find("available to this stage", 1, true), "wording is about the stage")
    assert(not line:find("sheet makes", 1, true), "never claims the sheet makes none")
end)

H.test("2.0 U1i an idle assist stage in a mixed loop names what it lacks", function()
    idle_world()
    local key, parts = configure("rare", "X-O", "X-C", {assist = "X-C"})
    local result = M.Solver.solve_for({[key] = 1, ["item/P"] = 9}, 1, {[key] = parts}, {start_leftovers = "craft"})
    H.equal(result.status, "ok", "solved")
    assert(column_of(result, key).quality_loop.parts, "mixed")
    local tiers = final_tiers(result, key)
    H.equal(tiers.normal.assist_crafts, 0, "assist idle")
    H.deep_equal(tiers.normal.assist_missing, {"C"}, "assist lacks C through the mix")
    local sheet_pane, sheet_flow = H.fill_sheet({{item = "X", quality = "rare", rate = 1, unit = "/s"}, {item = "P", rate = 9, unit = "/s"}})
    local dropdown = find_all(sheet_flow, function(element) return element.name == "hxrrc_start_leftovers_dropdown" end)[1]
    dropdown.selected_index = 2 --crafted by another recipe
    local assist = compute(sheet_flow).loops[key].assist
    H.equal(assist.reason, "hxrrc.quality_loop_stage_idle", "assist line idle")
    H.deep_equal(assist.caption, {"hxrrc.quality_loop_stage_idle", {"quality-name.normal"}, {"", {"item-name.C"}}}, "names normal C")
    local _ = sheet_pane
end)

H.done("test_idle_stages")
