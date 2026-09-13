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

    row.add{
        name = "hxrrc_desired_item_button",
        type = "choose-elem-button",
        tooltip = {"hxrrc.item_input_tooltip"},
        elem_type = "item",
    }

    row.style.vertical_align = "center"
    return row
end

local function adjust_row_configuration_on_button_change(event)
    local button = event.element
    local row = button.parent
    local row_index = row.get_index_in_parent()
    local input_container = row.parent
    local row_count = #input_container.children

    if button.elem_value and row_index == row_count then
        add_row(input_container)
    elseif not button.elem_value and row_index < row_count then
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

function InputContainer.get_desired_production_rates_by_full_item_name(input_container)
    local rates_by_full_item_name = {}

    for _, row in ipairs(input_container.children) do
        local rate = get_desired_production_rate(row)
        local item = row.hxrrc_desired_item_button.elem_value
        if rate ~= 0 and item and prototypes.item[item] then --a target whose item was removed by a mod is left out
            rates_by_full_item_name["item/" .. item] = (rates_by_full_item_name["item/" .. item] or 0) + rate
        end
    end

    return rates_by_full_item_name
end

function InputContainer._add_existing_row(input_container, rate_text, selected_dropdown_index, item)
    local row = add_row(input_container, 1)
    row.rate_textfield.text = rate_text
    row.time_unit_dropdown.selected_index = selected_dropdown_index
    row.hxrrc_desired_item_button.elem_value = item
end

return InputContainer