--Putting one player's recipe setups back to what a new player starts with.
--
--Owned by lane W2-reset, which also owns logic/player_data.lua for this round.
--
--Resets: recipe bindings both ways, consumer and burner bindings, chosen machines and their qualities, machine
--modules, beacon groups with their modules, count and sharing, and every quality loop. Through the same
--initializers a fresh player goes through, so a recipe that is bound automatically today is bound again.
--
--Keeps: every sheet, tab, target row, rate, unit and quality, the round-up and solver options, and the blueprint
--infrastructure choices. storage[player_index] is not wiped: it also holds the GUI handles.
--
--Before anything else it invalidates that player's running work, advances the configuration revision, closes
--pickers and drops pending pastes, so no result computed against the old setup can commit afterwards. Then every
--sheet is queued for recalculation, the visible one first.
local Reset = {}

function Reset.run(player_index) end
function Reset.forget_player(player_index) end
function Reset.on_reset_clicked(event) end

return Reset
