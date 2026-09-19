--Frozen Route.begin input: first candidate of docs/tasks/058_reproducer.lua.
--source_kind = "harness"; captured on host legalcopilot-dev, 2026-09-19.
--source_sha = "30a7540d9bbfe7431d279f1043f2832f336714e9"
--Expected supported outcome: a route for every demand. Preserve as a positive case; it is not a rejection.
return {
    blocks = {
        {
            block_id = "block:cable+circuit",
            dir = 4,
            h = 11,
            id = "block:cable+circuit",
            ports = {
                {
                    _block_h = 10,
                    _block_w = 11,
                    _occupied = {
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 7,
                            y = 9
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 5
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 6
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 9
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 10
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 13
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 14
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 0,
                            y = 15
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 5
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 9
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 13
                        }
                    },
                    attach_dx = 0,
                    attach_dy = -1,
                    dir = 12,
                    flow_id = "item/cable",
                    kind = "item",
                    member_id = "m:machine:circuit:1",
                    normal_dir = 12,
                    port_id = "in:item/cable",
                    rate_per_second = 7.1999999999999993,
                    role = "in",
                    step_id = "circuit",
                    travel_dir = 12,
                    x = 10,
                    y = 5
                },
                {
                    _block_h = 10,
                    _block_w = 11,
                    _occupied = {
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 7,
                            y = 9
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 5
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 6
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 9
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 10
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 13
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 14
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 0,
                            y = 15
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 5
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 9
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 13
                        }
                    },
                    attach_dx = 1,
                    attach_dy = -1,
                    dir = 12,
                    flow_id = "item/plate",
                    kind = "item",
                    member_id = "m:machine:circuit:1",
                    normal_dir = 12,
                    port_id = "in:item/plate",
                    rate_per_second = 2.3999999999999999,
                    role = "in",
                    step_id = "circuit",
                    travel_dir = 12,
                    x = 10,
                    y = 6
                },
                {
                    _block_h = 10,
                    _block_w = 11,
                    _occupied = {
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 7,
                            y = 9
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 5
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 6
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 9
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 10
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 13
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 14
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 0,
                            y = 15
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 5
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 9
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 13
                        }
                    },
                    attach_dx = 2,
                    attach_dy = -1,
                    dir = 12,
                    flow_id = "item/plate",
                    kind = "item",
                    member_id = "m:machine:cable:1",
                    normal_dir = 12,
                    port_id = "in:item/plate",
                    rate_per_second = 2.8799999999999999,
                    role = "in",
                    step_id = "cable",
                    travel_dir = 12,
                    x = 10,
                    y = 7
                },
                {
                    _block_h = 10,
                    _block_w = 11,
                    _occupied = {
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 7,
                            y = 9
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 5
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 6
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 9
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 10
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 13
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 14
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 0,
                            y = 15
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 5
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 9
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 13
                        }
                    },
                    attach_dx = 3,
                    attach_dy = -1,
                    dir = 12,
                    flow_id = "item/cable",
                    kind = "item",
                    member_id = "m:machine:cable:1",
                    normal_dir = 12,
                    port_id = "out:item/cable",
                    rate_per_second = 7.1999999999999993,
                    role = "out",
                    step_id = "cable",
                    travel_dir = 4,
                    x = 10,
                    y = 8
                },
                {
                    _block_h = 10,
                    _block_w = 11,
                    _occupied = {
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 7,
                            y = 9
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 5
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 6
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 9
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 10
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 2,
                            y = 13
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 1,
                            y = 14
                        },
                        {
                            h = 1,
                            owner = "machine:block:cable+circuit",
                            w = 1,
                            x = 0,
                            y = 15
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 5
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 9
                        },
                        {
                            h = 3,
                            owner = "machine:block:cable+circuit",
                            w = 3,
                            x = 3,
                            y = 13
                        }
                    },
                    attach_dx = 4,
                    attach_dy = -1,
                    dir = 12,
                    flow_id = "item/circuit",
                    kind = "item",
                    member_id = "m:machine:circuit:1",
                    normal_dir = 12,
                    port_id = "out:item/circuit",
                    rate_per_second = 3,
                    role = "out",
                    step_id = "circuit",
                    travel_dir = 4,
                    x = 10,
                    y = 9
                }
            },
            w = 10,
            x = 0,
            y = 5
        },
        {
            block_id = "block:machine",
            dir = 4,
            h = 3,
            id = "block:machine",
            ports = {
                {
                    _block_h = 7,
                    _block_w = 3,
                    _occupied = {
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 8,
                            y = 0
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 7,
                            y = 1
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 6,
                            y = 2
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 5,
                            y = 2
                        },
                        {
                            h = 3,
                            owner = "machine:block:machine",
                            w = 3,
                            x = 9,
                            y = 0
                        }
                    },
                    attach_dx = 0,
                    attach_dy = -1,
                    dir = 12,
                    flow_id = "item/circuit",
                    kind = "item",
                    member_id = "m:machine:machine:1",
                    normal_dir = 12,
                    port_id = "in:item/circuit",
                    rate_per_second = 3,
                    role = "in",
                    step_id = "machine",
                    travel_dir = 12,
                    x = 12,
                    y = 0
                },
                {
                    _block_h = 7,
                    _block_w = 3,
                    _occupied = {
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 8,
                            y = 0
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 7,
                            y = 1
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 6,
                            y = 2
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 5,
                            y = 2
                        },
                        {
                            h = 3,
                            owner = "machine:block:machine",
                            w = 3,
                            x = 9,
                            y = 0
                        }
                    },
                    attach_dx = 1,
                    attach_dy = -1,
                    dir = 12,
                    flow_id = "item/gear",
                    kind = "item",
                    member_id = "m:machine:machine:1",
                    normal_dir = 12,
                    port_id = "in:item/gear",
                    rate_per_second = 5,
                    role = "in",
                    step_id = "machine",
                    travel_dir = 12,
                    x = 12,
                    y = 1
                },
                {
                    _block_h = 7,
                    _block_w = 3,
                    _occupied = {
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 8,
                            y = 0
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 7,
                            y = 1
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 6,
                            y = 2
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 5,
                            y = 2
                        },
                        {
                            h = 3,
                            owner = "machine:block:machine",
                            w = 3,
                            x = 9,
                            y = 0
                        }
                    },
                    attach_dx = 2,
                    attach_dy = -1,
                    dir = 12,
                    flow_id = "item/plate",
                    kind = "item",
                    member_id = "m:machine:machine:1",
                    normal_dir = 12,
                    port_id = "in:item/plate",
                    rate_per_second = 9,
                    role = "in",
                    step_id = "machine",
                    travel_dir = 12,
                    x = 12,
                    y = 2
                },
                {
                    _block_h = 7,
                    _block_w = 3,
                    _occupied = {
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 8,
                            y = 0
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 7,
                            y = 1
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 6,
                            y = 2
                        },
                        {
                            h = 1,
                            owner = "machine:block:machine",
                            w = 1,
                            x = 5,
                            y = 2
                        },
                        {
                            h = 3,
                            owner = "machine:block:machine",
                            w = 3,
                            x = 9,
                            y = 0
                        }
                    },
                    attach_dx = 3,
                    attach_dy = 0,
                    dir = 0,
                    flow_id = "item/machine",
                    kind = "item",
                    member_id = "m:machine:machine:1",
                    normal_dir = 0,
                    port_id = "out:item/machine",
                    rate_per_second = 1,
                    role = "out",
                    step_id = "machine",
                    travel_dir = 8,
                    x = 11,
                    y = 3
                }
            },
            w = 7,
            x = 5,
            y = 0
        }
    },
    catalog = {
        beacon = {
            beacon = {
                counter = "same_type",
                distribution_effectivity = 1.5
            }
        },
        belt = {
            belt = "transport-belt",
            items_per_second = 15,
            lane_items_per_second = 7.5,
            quality = "normal",
            splitter = "splitter",
            underground = "underground-belt",
            underground_max_distance = 5
        },
        entity = {
            assembler = {
                crafting_speed = 1,
                energy_usage_w = 210000,
                etype = "assembling-machine",
                fluid_boxes = {},
                module_slots = 4,
                name = "assembler",
                needs_power = true,
                pollution_per_min = 0.066666666666666666,
                quality = "normal"
            },
            beacon = {
                beacon = {
                    counter = "same_type",
                    distribution_effectivity = 1.5
                },
                energy_usage_w = 480000,
                etype = "beacon",
                fluid_boxes = {},
                module_slots = 2,
                name = "beacon",
                needs_power = true,
                pollution_per_min = 0,
                quality = "normal"
            },
            inserter = {
                collision_box = {
                    left_top = {
                        x = -0.45000000000000001,
                        y = -0.45000000000000001
                    },
                    right_bottom = {
                        x = 0.45000000000000001,
                        y = 0.45000000000000001
                    }
                },
                collision_mask = {
                    layers = {
                        object = true,
                        player = true,
                        water_tile = true
                    }
                },
                energy_usage_w = 13000,
                etype = "inserter",
                flags = {
                    ["player-creation"] = true
                },
                fluid_boxes = {},
                name = "inserter",
                needs_power = true,
                pollution_per_min = 0,
                quality = "normal",
                tile_h = 1,
                tile_w = 1
            },
            ["medium-electric-pole"] = {
                collision_box = {
                    left_top = {
                        x = -0.45000000000000001,
                        y = -0.45000000000000001
                    },
                    right_bottom = {
                        x = 0.45000000000000001,
                        y = 0.45000000000000001
                    }
                },
                collision_mask = {
                    layers = {
                        object = true,
                        player = true,
                        water_tile = true
                    }
                },
                energy_usage_w = 0,
                etype = "electric-pole",
                flags = {
                    ["player-creation"] = true
                },
                fluid_boxes = {},
                name = "medium-electric-pole",
                needs_power = false,
                pollution_per_min = 0,
                quality = "normal",
                tile_h = 1,
                tile_w = 1
            },
            pipe = {
                collision_box = {
                    left_top = {
                        x = -0.45000000000000001,
                        y = -0.45000000000000001
                    },
                    right_bottom = {
                        x = 0.45000000000000001,
                        y = 0.45000000000000001
                    }
                },
                collision_mask = {
                    layers = {
                        object = true,
                        player = true,
                        water_tile = true
                    }
                },
                energy_usage_w = 0,
                etype = "pipe",
                flags = {
                    ["player-creation"] = true
                },
                fluid_boxes = {
                    {
                        connections = {
                            {
                                connection_type = "normal",
                                direction = 0,
                                flow_direction = "input-output",
                                positions = {
                                    {
                                        x = 0,
                                        y = -1
                                    },
                                    {
                                        x = 1,
                                        y = 0
                                    },
                                    {
                                        x = 0,
                                        y = 1
                                    },
                                    {
                                        x = -1,
                                        y = 0
                                    }
                                }
                            },
                            {
                                connection_type = "normal",
                                direction = 4,
                                flow_direction = "input-output",
                                positions = {
                                    {
                                        x = 1,
                                        y = 0
                                    },
                                    {
                                        x = 0,
                                        y = 1
                                    },
                                    {
                                        x = -1,
                                        y = 0
                                    },
                                    {
                                        x = 0,
                                        y = -1
                                    }
                                }
                            },
                            {
                                connection_type = "normal",
                                direction = 8,
                                flow_direction = "input-output",
                                positions = {
                                    {
                                        x = 0,
                                        y = 1
                                    },
                                    {
                                        x = -1,
                                        y = 0
                                    },
                                    {
                                        x = 0,
                                        y = -1
                                    },
                                    {
                                        x = 1,
                                        y = 0
                                    }
                                }
                            },
                            {
                                connection_type = "normal",
                                direction = 12,
                                flow_direction = "input-output",
                                positions = {
                                    {
                                        x = -1,
                                        y = 0
                                    },
                                    {
                                        x = 0,
                                        y = -1
                                    },
                                    {
                                        x = 1,
                                        y = 0
                                    },
                                    {
                                        x = 0,
                                        y = 1
                                    }
                                }
                            }
                        },
                        index = 1,
                        production_type = "input-output",
                        volume = 100
                    }
                },
                name = "pipe",
                needs_power = false,
                pollution_per_min = 0,
                quality = "normal",
                tile_h = 1,
                tile_w = 1
            },
            ["pipe-to-ground"] = {
                collision_box = {
                    left_top = {
                        x = -0.45000000000000001,
                        y = -0.45000000000000001
                    },
                    right_bottom = {
                        x = 0.45000000000000001,
                        y = 0.45000000000000001
                    }
                },
                collision_mask = {
                    layers = {
                        object = true,
                        player = true,
                        water_tile = true
                    }
                },
                energy_usage_w = 0,
                etype = "pipe-to-ground",
                flags = {
                    ["player-creation"] = true
                },
                fluid_boxes = {
                    {
                        connections = {
                            {
                                connection_type = "normal",
                                direction = 0,
                                flow_direction = "input-output",
                                positions = {
                                    {
                                        x = 0,
                                        y = -1
                                    },
                                    {
                                        x = 1,
                                        y = 0
                                    },
                                    {
                                        x = 0,
                                        y = 1
                                    },
                                    {
                                        x = -1,
                                        y = 0
                                    }
                                }
                            },
                            {
                                connection_type = "underground",
                                direction = 8,
                                flow_direction = "input-output",
                                max_underground_distance = 10,
                                positions = {
                                    {
                                        x = 0,
                                        y = 1
                                    },
                                    {
                                        x = -1,
                                        y = 0
                                    },
                                    {
                                        x = 0,
                                        y = -1
                                    },
                                    {
                                        x = 1,
                                        y = 0
                                    }
                                }
                            }
                        },
                        index = 1,
                        production_type = "input-output",
                        volume = 100
                    }
                },
                name = "pipe-to-ground",
                needs_power = false,
                pollution_per_min = 0,
                quality = "normal",
                tile_h = 1,
                tile_w = 1
            },
            plant = {
                crafting_speed = 1,
                energy_usage_w = 210000,
                etype = "assembling-machine",
                fluid_boxes = {},
                module_slots = 2,
                name = "plant",
                needs_power = true,
                pollution_per_min = 0.066666666666666666,
                quality = "normal"
            },
            roboport = {
                collision_box = {
                    left_top = {
                        x = -1.95,
                        y = -1.95
                    },
                    right_bottom = {
                        x = 1.95,
                        y = 1.95
                    }
                },
                collision_mask = {
                    layers = {
                        object = true,
                        player = true,
                        water_tile = true
                    }
                },
                energy_usage_w = 50000,
                etype = "roboport",
                flags = {
                    ["player-creation"] = true
                },
                fluid_boxes = {},
                name = "roboport",
                needs_power = true,
                pollution_per_min = 0,
                quality = "normal",
                tile_h = 4,
                tile_w = 4
            },
            splitter = {
                collision_box = {
                    left_top = {
                        x = -0.94999999999999996,
                        y = -0.45000000000000001
                    },
                    right_bottom = {
                        x = 0.94999999999999996,
                        y = 0.45000000000000001
                    }
                },
                collision_mask = {
                    layers = {
                        object = true,
                        player = true,
                        water_tile = true
                    }
                },
                energy_usage_w = 0,
                etype = "splitter",
                flags = {
                    ["player-creation"] = true
                },
                fluid_boxes = {},
                name = "splitter",
                needs_power = false,
                pollution_per_min = 0,
                quality = "normal",
                tile_h = 1,
                tile_w = 2
            },
            ["transport-belt"] = {
                collision_box = {
                    left_top = {
                        x = -0.45000000000000001,
                        y = -0.45000000000000001
                    },
                    right_bottom = {
                        x = 0.45000000000000001,
                        y = 0.45000000000000001
                    }
                },
                collision_mask = {
                    layers = {
                        object = true,
                        player = true,
                        water_tile = true
                    }
                },
                energy_usage_w = 0,
                etype = "transport-belt",
                flags = {
                    ["player-creation"] = true
                },
                fluid_boxes = {},
                name = "transport-belt",
                needs_power = false,
                pollution_per_min = 0,
                quality = "normal",
                tile_h = 1,
                tile_w = 1
            },
            ["underground-belt"] = {
                collision_box = {
                    left_top = {
                        x = -0.45000000000000001,
                        y = -0.45000000000000001
                    },
                    right_bottom = {
                        x = 0.45000000000000001,
                        y = 0.45000000000000001
                    }
                },
                collision_mask = {
                    layers = {
                        object = true,
                        player = true,
                        water_tile = true
                    }
                },
                energy_usage_w = 0,
                etype = "underground-belt",
                flags = {
                    ["player-creation"] = true
                },
                fluid_boxes = {},
                name = "underground-belt",
                needs_power = false,
                pollution_per_min = 0,
                quality = "normal",
                tile_h = 1,
                tile_w = 1
            }
        },
        fluid = {},
        inserter = {
            drop_offset = {
                x = 0,
                y = -1.203125
            },
            drop_position = {
                x = 0,
                y = -1.203125
            },
            items_per_second = 4.6200000000000001,
            name = "inserter",
            pickup_offset = {
                x = 0,
                y = 1
            },
            quality = "normal"
        },
        item = {
            cable = {
                fuel_emissions_multiplier = 1,
                fuel_value = 0,
                name = "cable",
                quality = "normal",
                type = "item"
            },
            circuit = {
                fuel_emissions_multiplier = 1,
                fuel_value = 0,
                name = "circuit",
                quality = "normal",
                type = "item"
            },
            gear = {
                fuel_emissions_multiplier = 1,
                fuel_value = 0,
                name = "gear",
                quality = "normal",
                type = "item"
            },
            machine = {
                fuel_emissions_multiplier = 1,
                fuel_value = 0,
                name = "machine",
                quality = "normal",
                type = "item"
            },
            plate = {
                fuel_emissions_multiplier = 1,
                fuel_value = 0,
                name = "plate",
                quality = "normal",
                type = "item"
            },
            prod = {
                module = true,
                module_effects = {
                    productivity = 0.25
                },
                name = "prod",
                quality = "normal",
                type = "module"
            },
            speed = {
                module = true,
                module_effects = {
                    speed = 0.5
                },
                name = "speed",
                quality = "normal",
                type = "module"
            }
        },
        module = {
            prod = {
                category = "productivity",
                effects = {
                    productivity = 0.25
                },
                name = "prod",
                quality = "normal"
            },
            speed = {
                category = "speed",
                effects = {
                    speed = 0.5
                },
                name = "speed",
                quality = "normal"
            }
        },
        pipe = {
            pipe = "pipe",
            quality = "normal",
            throughput_per_second = 1200,
            underground = "pipe-to-ground",
            underground_max_distance = 10
        },
        pole = {
            name = "medium-electric-pole",
            quality = "normal",
            supply_h = 3.5,
            supply_w = 3.5,
            tile_h = 1,
            tile_w = 1,
            wire_reach = 9
        },
        quality = {
            normal = {
                level = 0,
                name = "normal"
            }
        },
        quality_level = {
            normal = 0
        },
        robo = {
            connection_distance = 50,
            construction_radius = 55,
            logistic_radius = 25,
            name = "roboport",
            quality = "normal",
            tile_h = 4,
            tile_w = 4
        },
        schema_version = 1
    },
    catalog_diagnostics = {},
    flows = {
        {
            consumers = {
                {
                    share_per_second = 7.1999999999999993,
                    step_id = "circuit"
                }
            },
            flow_id = "item/cable",
            full_name = "item/cable",
            is_fluid = false,
            item_name = "cable",
            producers = {
                {
                    share_per_second = 7.1999999999999993,
                    step_id = "cable"
                }
            },
            quality = "normal",
            rate_per_second = 7.1999999999999993
        },
        {
            consumers = {
                {
                    share_per_second = 3,
                    step_id = "machine"
                }
            },
            flow_id = "item/circuit",
            full_name = "item/circuit",
            is_fluid = false,
            item_name = "circuit",
            producers = {
                {
                    share_per_second = 3,
                    step_id = "circuit"
                }
            },
            quality = "normal",
            rate_per_second = 3
        },
        {
            consumers = {
                {
                    share_per_second = 5,
                    step_id = "machine"
                }
            },
            flow_id = "item/gear",
            full_name = "item/gear",
            is_fluid = false,
            item_name = "gear",
            producers = {
                {
                    share_per_second = 5,
                    step_id = "$external"
                }
            },
            quality = "normal",
            rate_per_second = 5
        },
        {
            consumers = {
                {
                    share_per_second = 1,
                    step_id = "$external"
                }
            },
            flow_id = "item/machine",
            full_name = "item/machine",
            is_fluid = false,
            item_name = "machine",
            producers = {
                {
                    share_per_second = 1,
                    step_id = "machine"
                }
            },
            quality = "normal",
            rate_per_second = 1
        },
        {
            consumers = {
                {
                    share_per_second = 2.8799999999999999,
                    step_id = "cable"
                },
                {
                    share_per_second = 2.3999999999999999,
                    step_id = "circuit"
                },
                {
                    share_per_second = 9,
                    step_id = "machine"
                }
            },
            flow_id = "item/plate",
            full_name = "item/plate",
            is_fluid = false,
            item_name = "plate",
            producers = {
                {
                    share_per_second = 14.279999999999999,
                    step_id = "$external"
                }
            },
            quality = "normal",
            rate_per_second = 14.279999999999999
        }
    },
    force = "player",
    grid = {
        h = 54,
        w = 54
    },
    input_edge = "left",
    obstacles = {
        {
            owner = "k:1",
            rect = {
                h = 4,
                w = 4,
                x = 0,
                y = 0
            }
        },
        {
            owner = "k:2",
            rect = {
                h = 4,
                w = 4,
                x = 50,
                y = 0
            }
        },
        {
            owner = "k:3",
            rect = {
                h = 4,
                w = 4,
                x = 0,
                y = 50
            }
        },
        {
            owner = "k:4",
            rect = {
                h = 4,
                w = 4,
                x = 50,
                y = 50
            }
        }
    },
    options = {
        catalog_diagnostics = {},
        force = "player",
        input_edge = "left",
        output_edge = "top",
        round_up = false,
        settings = {
            belt = {
                name = "transport-belt",
                quality = "normal",
                splitter = "splitter",
                underground = "underground-belt"
            },
            input_edge = "left",
            inserter = {
                name = "inserter",
                quality = "normal"
            },
            output_edge = "top",
            pipe = {
                name = "pipe",
                quality = "normal"
            },
            pole = {
                name = "medium-electric-pole",
                quality = "normal"
            },
            roboport = {
                name = "roboport",
                quality = "normal"
            },
            underground_pipe = {
                name = "pipe-to-ground",
                quality = "normal"
            }
        },
        start_leftovers = "byproduct"
    },
    output_edge = "top",
    perimeter_ports = {
        {
            full_name = "item/gear",
            is_fluid = false,
            kind = "item",
            min_lanes = 1,
            port_id = "in:item/gear",
            rate_per_second = 5,
            role = "in",
            travel_dir = 4,
            x = 0,
            y = 4
        },
        {
            full_name = "item/plate",
            is_fluid = false,
            kind = "item",
            min_lanes = 2,
            port_id = "in:item/plate",
            rate_per_second = 14.279999999999999,
            role = "in",
            travel_dir = 4,
            x = 0,
            y = 16
        },
        {
            full_name = "item/machine",
            is_fluid = false,
            kind = "item",
            min_lanes = 1,
            port_id = "out:item/machine",
            rate_per_second = 1,
            role = "out",
            travel_dir = 0,
            x = 4,
            y = 0
        }
    },
    player_index = 1,
    ports = {
        {
            _block_h = 10,
            _block_w = 11,
            _occupied = {
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 7,
                    y = 9
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 5
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 6
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 9
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 10
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 13
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 14
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 0,
                    y = 15
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 5
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 9
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 13
                }
            },
            attach_dx = 0,
            attach_dy = -1,
            dir = 12,
            flow_id = "item/cable",
            kind = "item",
            member_id = "m:machine:circuit:1",
            normal_dir = 12,
            port_id = "in:item/cable",
            rate_per_second = 7.1999999999999993,
            role = "in",
            step_id = "circuit",
            travel_dir = 12,
            x = 10,
            y = 5
        },
        {
            _block_h = 10,
            _block_w = 11,
            _occupied = {
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 7,
                    y = 9
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 5
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 6
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 9
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 10
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 13
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 14
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 0,
                    y = 15
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 5
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 9
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 13
                }
            },
            attach_dx = 1,
            attach_dy = -1,
            dir = 12,
            flow_id = "item/plate",
            kind = "item",
            member_id = "m:machine:circuit:1",
            normal_dir = 12,
            port_id = "in:item/plate",
            rate_per_second = 2.3999999999999999,
            role = "in",
            step_id = "circuit",
            travel_dir = 12,
            x = 10,
            y = 6
        },
        {
            _block_h = 10,
            _block_w = 11,
            _occupied = {
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 7,
                    y = 9
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 5
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 6
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 9
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 10
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 13
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 14
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 0,
                    y = 15
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 5
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 9
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 13
                }
            },
            attach_dx = 2,
            attach_dy = -1,
            dir = 12,
            flow_id = "item/plate",
            kind = "item",
            member_id = "m:machine:cable:1",
            normal_dir = 12,
            port_id = "in:item/plate",
            rate_per_second = 2.8799999999999999,
            role = "in",
            step_id = "cable",
            travel_dir = 12,
            x = 10,
            y = 7
        },
        {
            _block_h = 10,
            _block_w = 11,
            _occupied = {
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 7,
                    y = 9
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 5
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 6
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 9
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 10
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 13
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 14
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 0,
                    y = 15
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 5
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 9
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 13
                }
            },
            attach_dx = 3,
            attach_dy = -1,
            dir = 12,
            flow_id = "item/cable",
            kind = "item",
            member_id = "m:machine:cable:1",
            normal_dir = 12,
            port_id = "out:item/cable",
            rate_per_second = 7.1999999999999993,
            role = "out",
            step_id = "cable",
            travel_dir = 4,
            x = 10,
            y = 8
        },
        {
            _block_h = 10,
            _block_w = 11,
            _occupied = {
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 7,
                    y = 9
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 5
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 6
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 9
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 10
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 2,
                    y = 13
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 1,
                    y = 14
                },
                {
                    h = 1,
                    owner = "machine:block:cable+circuit",
                    w = 1,
                    x = 0,
                    y = 15
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 5
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 9
                },
                {
                    h = 3,
                    owner = "machine:block:cable+circuit",
                    w = 3,
                    x = 3,
                    y = 13
                }
            },
            attach_dx = 4,
            attach_dy = -1,
            dir = 12,
            flow_id = "item/circuit",
            kind = "item",
            member_id = "m:machine:circuit:1",
            normal_dir = 12,
            port_id = "out:item/circuit",
            rate_per_second = 3,
            role = "out",
            step_id = "circuit",
            travel_dir = 4,
            x = 10,
            y = 9
        },
        {
            _block_h = 7,
            _block_w = 3,
            _occupied = {
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 8,
                    y = 0
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 7,
                    y = 1
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 6,
                    y = 2
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 5,
                    y = 2
                },
                {
                    h = 3,
                    owner = "machine:block:machine",
                    w = 3,
                    x = 9,
                    y = 0
                }
            },
            attach_dx = 0,
            attach_dy = -1,
            dir = 12,
            flow_id = "item/circuit",
            kind = "item",
            member_id = "m:machine:machine:1",
            normal_dir = 12,
            port_id = "in:item/circuit",
            rate_per_second = 3,
            role = "in",
            step_id = "machine",
            travel_dir = 12,
            x = 12,
            y = 0
        },
        {
            _block_h = 7,
            _block_w = 3,
            _occupied = {
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 8,
                    y = 0
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 7,
                    y = 1
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 6,
                    y = 2
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 5,
                    y = 2
                },
                {
                    h = 3,
                    owner = "machine:block:machine",
                    w = 3,
                    x = 9,
                    y = 0
                }
            },
            attach_dx = 1,
            attach_dy = -1,
            dir = 12,
            flow_id = "item/gear",
            kind = "item",
            member_id = "m:machine:machine:1",
            normal_dir = 12,
            port_id = "in:item/gear",
            rate_per_second = 5,
            role = "in",
            step_id = "machine",
            travel_dir = 12,
            x = 12,
            y = 1
        },
        {
            _block_h = 7,
            _block_w = 3,
            _occupied = {
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 8,
                    y = 0
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 7,
                    y = 1
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 6,
                    y = 2
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 5,
                    y = 2
                },
                {
                    h = 3,
                    owner = "machine:block:machine",
                    w = 3,
                    x = 9,
                    y = 0
                }
            },
            attach_dx = 2,
            attach_dy = -1,
            dir = 12,
            flow_id = "item/plate",
            kind = "item",
            member_id = "m:machine:machine:1",
            normal_dir = 12,
            port_id = "in:item/plate",
            rate_per_second = 9,
            role = "in",
            step_id = "machine",
            travel_dir = 12,
            x = 12,
            y = 2
        },
        {
            _block_h = 7,
            _block_w = 3,
            _occupied = {
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 8,
                    y = 0
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 7,
                    y = 1
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 6,
                    y = 2
                },
                {
                    h = 1,
                    owner = "machine:block:machine",
                    w = 1,
                    x = 5,
                    y = 2
                },
                {
                    h = 3,
                    owner = "machine:block:machine",
                    w = 3,
                    x = 9,
                    y = 0
                }
            },
            attach_dx = 3,
            attach_dy = 0,
            dir = 0,
            flow_id = "item/machine",
            kind = "item",
            member_id = "m:machine:machine:1",
            normal_dir = 0,
            port_id = "out:item/machine",
            rate_per_second = 1,
            role = "out",
            step_id = "machine",
            travel_dir = 8,
            x = 11,
            y = 3
        }
    },
    revisions = {
        config = 0,
        sheet = 0
    },
    round_up = false,
    settings = {
        belt = {
            name = "transport-belt",
            quality = "normal",
            splitter = "splitter",
            underground = "underground-belt"
        },
        input_edge = "left",
        inserter = {
            name = "inserter",
            quality = "normal"
        },
        output_edge = "top",
        pipe = {
            name = "pipe",
            quality = "normal"
        },
        pole = {
            name = "medium-electric-pole",
            quality = "normal"
        },
        roboport = {
            name = "roboport",
            quality = "normal"
        },
        underground_pipe = {
            name = "pipe-to-ground",
            quality = "normal"
        }
    },
    sheet_id = "sheet-2",
    snapshot = {
        fingerprint = {
            input = "rrc-snapshot-1:t1:310:s7:options61:t1:219:s15:start_leftovers12:s9:byproduct11:s8:round_up4:b1:010:s7:targets218:t1:14:d1:1204:t1:919:s15:rate_per_second4:d1:17:s4:name10:s7:machine7:s4:type7:s4:item8:s5:index4:d1:18:s5:valid4:b1:110:s7:quality9:s6:normal11:s8:raw_text4:s1:112:s9:full_name16:s12:item/machine12:s9:time_unit5:s2:/s12:s9:selection1751:t1:54:d1:1673:t2:1014:s10:unselected4:b1:015:s11:recipe_name8:s5:cable21:s17:product_full_name14:s10:item/cable9:s6:status11:s8:selected10:s7:beacons250:t1:14:d1:1236:t1:67:s4:name9:s6:beacon7:s4:type9:s6:beacon8:s5:count4:d1:110:s7:modules116:t1:24:d1:147:t1:27:s4:name8:s5:speed10:s7:quality9:s6:normal4:d1:247:t1:27:s4:name8:s5:speed10:s7:quality9:s6:normal10:s7:quality9:s6:normal10:s7:sharing4:d1:110:s7:machine47:t1:27:s4:name8:s5:plant10:s7:quality9:s6:normal10:s7:modules59:t1:14:d1:146:t1:27:s4:name7:s4:prod10:s7:quality9:s6:normal11:s8:consumer4:b1:011:s8:selected4:b1:112:s9:signature88:s84:M5:plant-S1;4:prod6:normalB1;G6:beacon6:normal1:11:12;5:speed6:normal5:speed6:normal4:d1:2678:t2:1014:s10:unselected4:b1:015:s11:recipe_name10:s7:circuit21:s17:product_full_name16:s12:item/circuit9:s6:status11:s8:selected10:s7:beacons250:t1:14:d1:1236:t1:67:s4:name9:s6:beacon7:s4:type9:s6:beacon8:s5:count4:d1:110:s7:modules116:t1:24:d1:147:t1:27:s4:name8:s5:speed10:s7:quality9:s6:normal4:d1:247:t1:27:s4:name8:s5:speed10:s7:quality9:s6:normal10:s7:quality9:s6:normal10:s7:sharing4:d1:110:s7:machine47:t1:27:s4:name8:s5:plant10:s7:quality9:s6:normal10:s7:modules59:t1:14:d1:146:t1:27:s4:name7:s4:prod10:s7:quality9:s6:normal11:s8:consumer4:b1:011:s8:selected4:b1:112:s9:signature88:s84:M5:plant-S1;4:prod6:normalB1;G6:beacon6:normal1:11:12;5:speed6:normal5:speed6:normal4:d1:3321:t2:1014:s10:unselected4:b1:015:s11:recipe_name10:s7:machine21:s17:product_full_name16:s12:item/machine9:s6:status11:s8:selected10:s7:beacons4:t1:010:s7:machine52:t1:27:s4:name12:s9:assembler10:s7:quality9:s6:normal10:s7:modules4:t1:011:s8:consumer4:b1:011:s8:selected4:b1:112:s9:signature30:s26:M9:assembler6:normalS0;B0;17:s13:quality_loops4:t1:010:s7:burners4:t1:0",
            result = "rrc-snapshot-1:t1:310:s7:options61:t1:219:s15:start_leftovers12:s9:byproduct11:s8:round_up4:b1:010:s7:targets218:t1:14:d1:1204:t1:919:s15:rate_per_second4:d1:17:s4:name10:s7:machine7:s4:type7:s4:item8:s5:index4:d1:18:s5:valid4:b1:110:s7:quality9:s6:normal11:s8:raw_text4:s1:112:s9:full_name16:s12:item/machine12:s9:time_unit5:s2:/s12:s9:selection1751:t1:54:d1:1673:t2:1014:s10:unselected4:b1:015:s11:recipe_name8:s5:cable21:s17:product_full_name14:s10:item/cable9:s6:status11:s8:selected10:s7:beacons250:t1:14:d1:1236:t1:67:s4:name9:s6:beacon7:s4:type9:s6:beacon8:s5:count4:d1:110:s7:modules116:t1:24:d1:147:t1:27:s4:name8:s5:speed10:s7:quality9:s6:normal4:d1:247:t1:27:s4:name8:s5:speed10:s7:quality9:s6:normal10:s7:quality9:s6:normal10:s7:sharing4:d1:110:s7:machine47:t1:27:s4:name8:s5:plant10:s7:quality9:s6:normal10:s7:modules59:t1:14:d1:146:t1:27:s4:name7:s4:prod10:s7:quality9:s6:normal11:s8:consumer4:b1:011:s8:selected4:b1:112:s9:signature88:s84:M5:plant-S1;4:prod6:normalB1;G6:beacon6:normal1:11:12;5:speed6:normal5:speed6:normal4:d1:2678:t2:1014:s10:unselected4:b1:015:s11:recipe_name10:s7:circuit21:s17:product_full_name16:s12:item/circuit9:s6:status11:s8:selected10:s7:beacons250:t1:14:d1:1236:t1:67:s4:name9:s6:beacon7:s4:type9:s6:beacon8:s5:count4:d1:110:s7:modules116:t1:24:d1:147:t1:27:s4:name8:s5:speed10:s7:quality9:s6:normal4:d1:247:t1:27:s4:name8:s5:speed10:s7:quality9:s6:normal10:s7:quality9:s6:normal10:s7:sharing4:d1:110:s7:machine47:t1:27:s4:name8:s5:plant10:s7:quality9:s6:normal10:s7:modules59:t1:14:d1:146:t1:27:s4:name7:s4:prod10:s7:quality9:s6:normal11:s8:consumer4:b1:011:s8:selected4:b1:112:s9:signature88:s84:M5:plant-S1;4:prod6:normalB1;G6:beacon6:normal1:11:12;5:speed6:normal5:speed6:normal4:d1:3321:t2:1014:s10:unselected4:b1:015:s11:recipe_name10:s7:machine21:s17:product_full_name16:s12:item/machine9:s6:status11:s8:selected10:s7:beacons4:t1:010:s7:machine52:t1:27:s4:name12:s9:assembler10:s7:quality9:s6:normal10:s7:modules4:t1:011:s8:consumer4:b1:011:s8:selected4:b1:112:s9:signature30:s26:M9:assembler6:normalS0;B0;17:s13:quality_loops4:t1:010:s7:burners4:t1:0"
        },
        options = {
            round_up = false,
            start_leftovers = "byproduct"
        },
        player_index = 1,
        revisions = {
            config = 0,
            sheet = 0
        },
        schema_version = 1,
        selection = {
            [1] = {
                beacons = {
                    {
                        count = 1,
                        modules = {
                            {
                                name = "speed",
                                quality = "normal"
                            },
                            {
                                name = "speed",
                                quality = "normal"
                            }
                        },
                        name = "beacon",
                        quality = "normal",
                        sharing = 1,
                        type = "beacon"
                    }
                },
                consumer = false,
                machine = {
                    name = "plant",
                    quality = "normal"
                },
                modules = {
                    {
                        name = "prod",
                        quality = "normal"
                    }
                },
                product_full_name = "item/cable",
                recipe_name = "cable",
                selected = true,
                signature = "M5:plant-S1;4:prod6:normalB1;G6:beacon6:normal1:11:12;5:speed6:normal5:speed6:normal",
                status = "selected",
                unselected = false
            },
            [2] = {
                beacons = {
                    {
                        count = 1,
                        modules = {
                            {
                                name = "speed",
                                quality = "normal"
                            },
                            {
                                name = "speed",
                                quality = "normal"
                            }
                        },
                        name = "beacon",
                        quality = "normal",
                        sharing = 1,
                        type = "beacon"
                    }
                },
                consumer = false,
                machine = {
                    name = "plant",
                    quality = "normal"
                },
                modules = {
                    {
                        name = "prod",
                        quality = "normal"
                    }
                },
                product_full_name = "item/circuit",
                recipe_name = "circuit",
                selected = true,
                signature = "M5:plant-S1;4:prod6:normalB1;G6:beacon6:normal1:11:12;5:speed6:normal5:speed6:normal",
                status = "selected",
                unselected = false
            },
            [3] = {
                beacons = {},
                consumer = false,
                machine = {
                    name = "assembler",
                    quality = "normal"
                },
                modules = {},
                product_full_name = "item/machine",
                recipe_name = "machine",
                selected = true,
                signature = "M9:assembler6:normalS0;B0;",
                status = "selected",
                unselected = false
            },
            burners = {},
            quality_loops = {}
        },
        sheet_id = "sheet-2",
        state = "current",
        targets = {
            {
                full_name = "item/machine",
                index = 1,
                name = "machine",
                quality = "normal",
                rate_per_second = 1,
                raw_text = "1",
                time_unit = "/s",
                type = "item",
                valid = true
            }
        }
    },
    solver_result = {
        columns = {
            {
                consumer = false,
                machine = {
                    name = "assembler",
                    quality = "normal"
                },
                net_amounts = {
                    ["item/circuit"] = -3,
                    ["item/gear"] = -5,
                    ["item/machine"] = 1,
                    ["item/plate"] = -9
                },
                product_full_name = "item/machine",
                recipe_name = "machine",
                setup = {
                    beacons = {},
                    modules = {}
                }
            },
            {
                consumer = false,
                machine = {
                    name = "plant"
                },
                net_amounts = {
                    ["item/cable"] = -3,
                    ["item/circuit"] = 1.25,
                    ["item/plate"] = -1
                },
                product_full_name = "item/circuit",
                recipe_name = "circuit",
                setup = {
                    beacons = {
                        {
                            count = 1,
                            modules = {
                                {
                                    name = "speed",
                                    quality = "normal"
                                },
                                {
                                    name = "speed",
                                    quality = "normal"
                                }
                            },
                            name = "beacon",
                            quality = "normal"
                        }
                    },
                    modules = {
                        {
                            name = "prod",
                            quality = "normal"
                        }
                    }
                }
            },
            {
                consumer = false,
                machine = {
                    name = "plant"
                },
                net_amounts = {
                    ["item/cable"] = 2.5,
                    ["item/plate"] = -1
                },
                product_full_name = "item/cable",
                recipe_name = "cable",
                setup = {
                    beacons = {
                        {
                            count = 1,
                            modules = {
                                {
                                    name = "speed",
                                    quality = "normal"
                                },
                                {
                                    name = "speed",
                                    quality = "normal"
                                }
                            },
                            name = "beacon",
                            quality = "normal"
                        }
                    },
                    modules = {
                        {
                            name = "prod",
                            quality = "normal"
                        }
                    }
                }
            }
        },
        product_parts = {},
        reasons_by_column = {},
        recipe_rates = {
            cable = 2.8799999999999999,
            circuit = 2.3999999999999999,
            machine = 1
        },
        solved_rates = {
            ["item/cable"] = 7.1999999999999993,
            ["item/circuit"] = 3,
            ["item/machine"] = 1
        },
        status = "ok",
        unsolved_rates = {
            ["item/gear"] = 5,
            ["item/plate"] = 14.280000000000001
        }
    },
    start_leftovers = "byproduct"
}
