--The debug export's contents and its encoding.
--
--Owned by lane W2-payload. The envelope decodes offline with python3 base64.b64decode + zlib.decompress, which is
--why encoding goes through helpers.encode_string(helpers.table_to_json(payload)) and carries no blueprint prefix.
--
--  {format = "rrc-sheet-debug", schema_version = 1, encoding = "zlib+base64", rrc_version = string,
--   environment = {...}, sheet = <snapshot>, selection = {...}, calculation = {...}, prototypes = {...},
--   diagnostics = {...}}
--
--Two states are kept apart on purpose: the settings as they are now, and the result with the settings it was
--actually computed from. An old result is never labelled current, and reading the sheet never repairs it.
--Full precision, no display rounding; a value JSON cannot hold (NaN, infinity) is tagged rather than written as
--a broken number; an empty list and an empty object stay distinguishable.
local ExportPayload = {}

ExportPayload.FORMAT = "rrc-sheet-debug"
ExportPayload.SCHEMA_VERSION = 1

function ExportPayload.build(player_index, sheet_flow)
    return {format = ExportPayload.FORMAT, schema_version = ExportPayload.SCHEMA_VERSION, encoding = "zlib+base64"}
end

--Returns the string, or nil plus a reason: a failed encode says so instead of handing back a short string
function ExportPayload.encode(payload)
    return nil, "not implemented"
end

return ExportPayload
