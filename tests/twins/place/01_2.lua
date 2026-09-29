local entities = {{id="p",kind="pole",name="medium-electric-pole",x=5,y=5}}
local validator = {}
return {id = "T-280-V12", rule = "BP_V_COLLISION", class = "engine", from = "tests/test_validate.lua twin candidate", grid = {w=20,h=20}, entities = entities, validator = validator, stage = "validate", check = "placeable", truth = "ok", codes = {}, --AUDITOR-DOUBT: redundant beacon count stays zero because the audit runner provides no beacon config.
audit = {blueprint_audit={invalid_inserters=0,backward_hands=0,redundant_beacons=0}}}
