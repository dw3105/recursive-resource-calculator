local QualityId = require "logic.quality_id"

--value: {name, quality} or nil
local function add_item_button(row, index, value)
    row.add{
        name = "hxrrc_desired_item_button",
        type = "choose-elem-button",
        tooltip = {"hxrrc.item_input_tooltip"},
        elem_type = "item-with-quality",
        ["item-with-quality"] = value,
        index = index,
    }
end

local function add_fluid_button(row, index)
    row.add{
        name = "hxrrc_desired_fluid_button",
        type = "choose-elem-button",
        tooltip = {"hxrrc.fluid_input_tooltip"},
        elem_type = "fluid",
        index = index,
    }
end

local function add_row(input_container, index)
    local row = input_container.add{
        type = "flow",
        direction = "horizontal",
        index = index,
    }

    row.add{
        name = "rate_textfield",
        type = "textfield",
        tooltip = {"hxrrc.production_rate_input_tooltip"},
        numeric = true,
        allow_decimal = true,
        allow_negative = false,
        lose_focus_on_confirm = true,
    }

    row.add{
        name = "time_unit_dropdown",
        type = "drop-down",
        selected_index = 1,
        items = {"/m", "/s"},
    }

    add_item_button(row)
    add_fluid_button(row)

    row.style.vertical_align = "center"
    return row
end

--Shared by the item and fluid buttons: a row targets an item or a fluid, never both
local function adjust_row_configuration_on_button_change(event)
    local button = event.element
    local row = button.parent
    local other_button = button.name == "hxrrc_desired_item_button" and row.hxrrc_desired_fluid_button or row.hxrrc_desired_item_button
    if button.elem_value and other_button.elem_value then
        other_button.elem_value = nil --if this raises the handler again, the row is still filled and stays
    end

    --counted after clearing, since a re-raised handler may already have added the next row
    local row_index = row.get_index_in_parent()
    local input_container = row.parent
    local row_count = #input_container.children
    local filled = row.hxrrc_desired_item_button.elem_value or row.hxrrc_desired_fluid_button.elem_value

    if filled and row_index == row_count then
        add_row(input_container)
    elseif not filled and row_index < row_count then
        row.destroy()
    end
end

local function get_desired_production_rate(row)
    local rate = tonumber(row.rate_textfield.text) or 0

    local dropdown = row.time_unit_dropdown
    if dropdown.selected_index == 1 then
        rate = rate / 60
    end

    return rate
end

event_handlers.on_gui_elem_changed["hxrrc_desired_item_button"] = adjust_row_configuration_on_button_change
event_handlers.on_gui_elem_changed["hxrrc_desired_fluid_button"] = adjust_row_configuration_on_button_change

local InputContainer = {}
function InputContainer.build_and_add_to(parent)
    local input_container = parent.add{
        type = "flow",
        name = "input_container",
        direction = "vertical"
    }
    input_container.style.horizontal_align = "center"

    add_row(input_container)

    return input_container
end

--A quality's name, whether the engine gives a name or a prototype; nil for normal, so normal targets keep their plain full name
local function quality_name_of(quality)
    local name = type(quality) == "string" and quality or (quality and quality.name)
    return name ~= "normal" and name or nil
end

--The full name a row targets and, for an item above normal quality, its parts; nil when the row is empty or its item, fluid or quality was removed by a mod
local function target_of(row)
    local item = row.hxrrc_desired_item_button.elem_value
    local fluid = row.hxrrc_desired_fluid_button.elem_value
    if item and prototypes.item[item.name] then
        local quality_name = quality_name_of(item.quality)
        if not quality_name then
            return "item/" .. item.name
        elseif prototypes.quality[quality_name] then
            return QualityId.encode(item.name, quality_name), {type = "item", name = item.name, quality = quality_name}
        end
    elseif fluid and prototypes.fluid[fluid] then
        return "fluid/" .. fluid
    end
end

--Returns the rates by full name, and the parts of every full name of an item above normal quality
function InputContainer.get_desired_production_rates_by_full_item_name(input_container)
    local rates_by_full_item_name = {}
    local parts_by_full_name = {}

    for _, row in ipairs(input_container.children) do
        local rate = get_desired_production_rate(row)
        local full_name, parts = target_of(row)
        if rate ~= 0 and full_name then
            rates_by_full_item_name[full_name] = (rates_by_full_item_name[full_name] or 0) + rate
            parts_by_full_name[full_name] = parts
        end
    end

    return rates_by_full_item_name, parts_by_full_name
end

--Rows saved by older versions: before fluid targets they had no fluid button, and before quality targets their item button had elem_type "item",
--which cannot be changed, so that button is replaced at its place with its item kept. The engine returns nil for a missing child, so children are scanned by name.
function InputContainer.repair_rows(input_container)
    for _, row in ipairs(input_container.children) do
        local item_button_index, item_button, has_fluid_button
        for index, child in ipairs(row.children) do
            if child.name == "hxrrc_desired_item_button" then item_button_index, item_button = index, child end
            if child.name == "hxrrc_desired_fluid_button" then has_fluid_button = true end
        end
        if item_button and item_button.elem_type == "item" then
            local item_name = item_button.elem_value
            item_button.destroy() --first, since two children of one row may not share a name
            add_item_button(row, item_button_index, item_name and prototypes.item[item_name] and {name = item_name} or nil)
        end
        if item_button_index and not has_fluid_button then
            add_fluid_button(row, item_button_index + 1)
        end
    end
end

function InputContainer._add_existing_row(input_container, rate_text, selected_dropdown_index, item)
    local row = add_row(input_container, 1)
    row.rate_textfield.text = rate_text
    row.time_unit_dropdown.selected_index = selected_dropdown_index
    row.hxrrc_desired_item_button.elem_value = item and {name = item}
end

return InputContainer