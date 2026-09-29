local entities = {{id="m",kind="machine",name="assembling-machine-2",x=5,y=5,needs_power=true}}
local validator = {catalog={entity={ ["assembling-machine-2"]={name="assembling-machine-2",etype="assembling-machine",needs_power=true}}}}
return {id = "T-280-V61", rule = "BP_V_POWER_UNCOVERED", class = "engine", from = "tests/test_validate.lua twin candidate", grid = {w=20,h=20}, entities = entities, validator = validator, stage = "validate", check = "powered", truth = "defect", codes = {"BP_V_POWER_UNCOVERED"}, audit = {}}
