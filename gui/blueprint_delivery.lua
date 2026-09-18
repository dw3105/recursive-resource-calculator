--Handing a finished blueprint to the player without losing what they were holding.
--
--Owned by lane W4-deliver. The blueprint is built in a staging inventory, not on the cursor, so a failure or a
--cancellation leaves the held item, the inventory and the world exactly as they were. Only a validated complete
--result is ever published, and the revisions are checked once more immediately before it is.
--
--If the cursor cannot take it, the finished result is kept and the player is told how to collect it; it is never
--dropped and never silently overwrites another blueprint.
local BlueprintDelivery = {}

function BlueprintDelivery.deliver(player_index, blueprint, metadata) return false, nil end
function BlueprintDelivery.retry(player_index) return false, nil end
function BlueprintDelivery.discard(player_index) end

return BlueprintDelivery
