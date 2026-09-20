# Golden corpus coverage

GOLD-09 is represented explicitly below. A draft case is named so the missing
evidence is machine-visible, but it is an open gap and does not count as
coverage. Branches are the branches claimed by the required matrix.

| scope | GOLD-09 category or retained matrix row | case_id | branches | outcome kind | state | coverage |
| --- | --- | --- | --- | --- | --- | --- |
| GOLD-09 | provided assembler-chain example | assembler-chain-example | 2.0, 2.1 | production | captured | open gap: harness capture only; engine observation pending; not coverage |
| GOLD-09 | base-only crafting and smelting | base-only-crafting-smelting | 2.0, 2.1 | production | captured | open gap: harness capture only; engine observation pending; not coverage |
| GOLD-09 | shared-intermediate multi-target case | shared-intermediate-multi-target | 2.0, 2.1 | production | captured | open gap: harness capture only; engine observation pending; not coverage |
| GOLD-09 | mixed fluids with deterministic byproducts | fluid-byproduct-chain | 2.0, 2.1 | production | captured | open gap: harness capture only; engine observation pending; not coverage |
| GOLD-09 | shared beacons and competing beacon loadouts | shared-beacon-loadouts | 2.0, 2.1 | production | draft | open gap: capture pending; content arrives with capture; not coverage |
| GOLD-09 | 2x2-to-larger grid growth with a larger-grid beacon improvement | grid-growth-beacon-improvement | 2.0, 2.1 | production | draft | open gap: capture pending; content arrives with capture; not coverage |
| GOLD-09 | quality of machines and infrastructure | quality-machines-infrastructure | 2.0, 2.1 | production | draft | open gap: capture pending; content arrives with capture; not coverage |
| GOLD-09 | a standard modded machine or interface | modded-machine-interface | 2.0, 2.1 | production | draft | open gap: capture pending; content arrives with capture; not coverage |
| GOLD-09 | belt and inserter bottleneck handling | belt-inserter-bottleneck | 2.0, 2.1 | rejection | draft | open gap: capture pending; content arrives with capture; not coverage |
| GOLD-09 | connected multi-pole coverage | multi-pole-connectivity | 2.0, 2.1 | production | draft | open gap: capture pending; content arrives with capture; not coverage |
| GOLD-09 | repeatability | repeatability | 2.0, 2.1 | production | captured | open gap: harness capture only; engine observation pending; not coverage |
| GOLD-09 | unsupported cycles | unsupported-cycles | 2.0, 2.1 | rejection | draft | open gap: capture pending; content arrives with capture; not coverage |
| GOLD-09 | unsupported quality-changing behaviour | unsupported-quality-changing | 2.0, 2.1 | rejection | draft | open gap: capture pending; content arrives with capture; not coverage |
| GOLD-09 | unsupported spoilage | unsupported-spoilage | 2.0, 2.1 | rejection | draft | open gap: capture pending; content arrives with capture; not coverage |
| GOLD-09 | unsupported probabilistic behaviour | unsupported-probabilistic | 2.0, 2.1 | rejection | draft | open gap: capture pending; content arrives with capture; not coverage |
| GOLD-09 | unsupported custom behaviour | unsupported-custom-behaviour | 2.0, 2.1 | rejection | draft | open gap: capture pending; content arrives with capture; not coverage |
| GOLD-09 | known-feasible case at the 100-machine and 30-step boundary | boundary-100-machines-30-steps | 2.0, 2.1 | production | draft | open gap: capture pending; content arrives with capture; not coverage |
| matrix | retained baseline case | basic-canonical | 2.0 | production | accepted | accepted baseline corpus case |
| matrix | retained baseline case | import-build-round-trip | 2.0, 2.1 | production | draft | open gap: capture pending; content arrives with capture; not coverage |
| matrix | retained baseline case | export-decode | 2.0, 2.1 | export | draft | open gap: capture pending; content arrives with capture; not coverage |
| matrix | player's exported speed-module chain | player-speed-module-chain | 2.0 | production | draft | open gap: capture pending; content arrives with capture; not coverage |

The three retained baseline rows remain in the required matrix even where they
are not a separate GOLD-09 category. The accepted baseline is the only current
coverage; every other row still needs a captured PreparedInput from the real
preparation path before it can become coverage.
