local entities = {{id="p",kind="pole",name="medium-electric-pole",x=5,y=5}}
local validator = {plan={steps={{step_id="s",machine="assembling-machine-2",machine_count=1}}}}
return {id = "T-280-V171", rule = "BP_V_MACHINE_COUNT_MISMATCH", class = "engine", from = "tests/test_validate.lua twin candidate", grid = {w=20,h=20}, entities = entities, validator = validator, stage = "validate", check = "rate", truth = "defect", codes = {"BP_V_MACHINE_COUNT_MISMATCH"}, audit = {}}
