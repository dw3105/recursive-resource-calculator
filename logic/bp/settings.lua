--What the player picked to build with, kept per sheet.
--
--Owned by lane W3-infra. A belt choice carries its family: the matching underground belt and splitter at the same
--quality. A modded belt with no known family is refused rather than quietly replaced with a vanilla tier.
--
--  {roboport = {name, quality}, pole = {...}, belt = {...}, inserter = {...}, pipe = {...}, underground_pipe = {...},
--   input_edge = "left"|"right"|"top"|"bottom", output_edge = same, surface = string}
--
--Defaults: left in, top out, as in the reference layout. The two edges must differ. New sheets start from the
--player's last choices; changing one sheet never changes another.
local Settings = {}

Settings.EDGES = {"left", "right", "top", "bottom"}
Settings.DEFAULT_INPUT_EDGE = "left"
Settings.DEFAULT_OUTPUT_EDGE = "top"

function Settings.of_sheet(player_index, sheet_id)
    return {input_edge = Settings.DEFAULT_INPUT_EDGE, output_edge = Settings.DEFAULT_OUTPUT_EDGE}
end

function Settings.store(player_index, sheet_id, settings) end

--Checks one choice against the game: returns ok, reason code, subject
function Settings.validate(settings, catalog)
    return false, nil, nil
end

--The underground belt and splitter that belong to a chosen belt, at its quality; nil family when none is known
function Settings.belt_family(belt_name, quality)
    return nil
end

return Settings
