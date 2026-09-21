# Lane 112 findings

The empty `pickup_offset`, `drop_offset`, and `drop_position` values in
`tests/golden/cases/player-am2-chain/prepared_input.json` originate at the
catalog projection boundary. The file is a stored `PreparedInput`; its
`catalog.inserter` is built during generation preparation, before
`ExportPayload.build` or JSON encoding runs. The old `logic/catalog.lua`
`copy_position` read only keyed `position.x` and `position.y`, so an
array-shaped vector entered through that API boundary as `{}` without a
diagnostic. The fixture cannot establish whether the runtime source itself
returned the array shape or whether an API adapter supplied it, but it does
establish that the stored empties predate the export boundary.

There was a second publication leak: `logic/export_payload.lua` carried the
already-empty prepared catalog through `capture_projection`, and the generic
JSON copy encoded those fields as empty objects. The export boundary now
normalizes supported keyed and array vectors and marks malformed or empty
geometry as `BP_CAP_INCOMPLETE`, omitting it from replay rather than filling
or publishing an empty vector. The original stored capture remains unchanged
and is treated as incomplete history.

The catalog boundary now checks every component of the inserter offsets and
fluid connection positions. It accepts keyed `{x, y}` and array `{x, y}`
representations, rejects empty or unsupported representations with a
diagnostic naming the entity and field, and does not publish the incomplete
entity or inserter geometry.
