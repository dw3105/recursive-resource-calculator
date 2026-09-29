local entities = {{id="p",kind="pole",name="medium-electric-pole",x=5,y=5}}
local validator = {}
return {id = "T-280-V42", rule = "BP_V_BEACON_REDUNDANT", class = "engine", from = "tests/test_validate.lua twin candidate", grid = {w=20,h=20}, entities = entities, validator = validator, stage = "validate", check = "beacon_effect", truth = "ok", codes = {}, audit = {}}
