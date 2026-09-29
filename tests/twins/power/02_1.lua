local entities = {{id="r1",kind="roboport",name="roboport",x=1,y=1},{id="r2",kind="roboport",name="roboport",x=15,y=15}}
local validator = {catalog={entity={roboport={name="roboport",etype="roboport",logistic_radius=5}}}}
return {id = "T-280-V21", rule = "BP_V_ROBO_DISCONNECTED", class = "engine", from = "tests/test_validate.lua twin candidate", grid = {w=20,h=20}, entities = entities, validator = validator, stage = "validate", check = "network", truth = "defect", codes = {"BP_V_ROBO_DISCONNECTED"}, audit = {}}
