data:extend({
    {
        type = "custom-input",
        name = "hxrrc_toggle_calculator",
        localised_name = {"hxrrc.toggle_calculator"},
        key_sequence = "ALT + X",
    },
    {
        --Enter, whatever the player bound it to: confirms the module picker when it is open with a module selected; Enter keeps its own job everywhere
        type = "custom-input",
        name = "hxrrc_confirm_module_picker",
        localised_name = {"hxrrc.confirm_module_picker"},
        key_sequence = "",
        linked_game_control = "confirm-gui",
        consuming = "none",
    },
})

--Factorio 2.0 ships the recycling arrows in the quality mod; 2.1 moved them to the recycler mod. Neither present: no sprite, and the report shows text.
--With layers, every property but name and type is read from the layers only.
local recycling_icons = (mods["recycler"] and "__recycler__/graphics/icons/") or (mods["quality"] and "__quality__/graphics/icons/")
if recycling_icons then
    data:extend({
        {
            type = "sprite",
            name = "hxrrc_recycling",
            layers = {
                {filename = recycling_icons .. "recycling.png", size = 64, scale = 0.5, flags = {"gui-icon"}},
                {filename = recycling_icons .. "recycling-top.png", size = 64, scale = 0.5, flags = {"gui-icon"}},
            },
        },
    })
end
