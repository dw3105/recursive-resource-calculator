--The window that shows the debug string.
--
--Owned by lane W1-exportui. A scrollable, selectable, read-only text box with Select all and Close, an
--explanation that says the string is not a blueprint, and a message when encoding failed. It reads the sheet and
--changes nothing on it; opening or closing it leaves the report exactly as it was.
local ExportDialog = {}

ExportDialog.FRAME_NAME = "hxrrc_export_dialog"

function ExportDialog.open(player_index, sheet_flow) end
function ExportDialog.close(player_index) end
function ExportDialog.is_open(player_index) return false end

--What the export button does, kept here so gui/sheet.lua only delegates
function ExportDialog.on_export_clicked(event) end

return ExportDialog
