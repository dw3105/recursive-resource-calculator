--The progress bar and Cancel button on a sheet.
--
--Owned by lane W1-progress. The bar shows real work: a phase name a player can read and a fraction that stays
--below 1 until a complete result is committed. Nothing invents a countdown while the dependency graph is still
--growing.
--
--The calculator window is never disabled while work runs, because the controls that stop that work live inside
--it. Cancel stops within two ticks of its handler and leaves the previous report visible and marked stale.
local ProgressPanel = {}

function ProgressPanel.show(sheet_flow) end
function ProgressPanel.hide(sheet_flow) end
--progress: {phase = locale key suffix, done_units, total_units | nil}
function ProgressPanel.update(sheet_flow, progress) end
function ProgressPanel.on_cancel_clicked(event) end

return ProgressPanel
