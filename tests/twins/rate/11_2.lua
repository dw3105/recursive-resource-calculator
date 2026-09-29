local entities = {{id="p",kind="pole",name="medium-electric-pole",x=5,y=5}}
local validator = {}
return {id = "T-280-V112", rule = "BP_V_TRANSFER_CAPACITY", class = "engine", from = "tests/test_validate.lua twin candidate", grid = {w=20,h=20}, entities = entities, validator = validator, stage = "validate", check = "rate", truth = "ok", codes = {}, audit = {}}
