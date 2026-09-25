# 216: route slow hands

Four output hands at 2.31 items/s can serve one 10/s flow. Their drops are separate machine tiles, so route must let a
same-flow run pass each drop instead of requiring every hand to leave in its fixed inserter heading. When the first
heading search fails, the route retry allows the source belt to face the useful direction.

Underground pairs must satisfy the same geometry the validator walks. A surface tile carrying the pair's flow cannot
sit between its endpoints, and a route improvement cannot create a side-fed entrance that blocks its approach lane.
`tests/test_route_slow_hands.lua` and `tests/test_route_tidy_shapes.lua` replay captured route inputs for these cases.
