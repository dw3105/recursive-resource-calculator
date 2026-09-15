--Identity of an item at a quality above normal. Normal items keep their "item/<name>" full name; these live in a namespace without "/", so they
--never equal one, and both names are length-prefixed, so two different pairs never share an identity whatever characters the names hold.
--Nothing decodes an identity: whoever creates one records its parts next to it.
local QualityId = {}

function QualityId.encode(item_name, quality_name)
    return "item-quality:" .. #item_name .. ":" .. item_name .. #quality_name .. ":" .. quality_name
end

return QualityId
