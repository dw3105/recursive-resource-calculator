--Where the player picks what the blueprint is built out of, and which edges carry inputs and outputs.
--
--Owned by lane W3-infra. A thin shell over logic/bp/settings.lua: it shows the choices, keeps overrides per
--sheet, and refuses a choice the game cannot honour with the reason why.
local BlueprintDialog = {}

BlueprintDialog.FRAME_NAME = "hxrrc_blueprint_dialog"

function BlueprintDialog.open(player_index, sheet_flow) end
function BlueprintDialog.close(player_index) end
function BlueprintDialog.is_open(player_index) return false end
function BlueprintDialog.on_generate_clicked(event) end

return BlueprintDialog
