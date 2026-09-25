# 220: Blueprint string and delivery fallback

Blueprint strings are built as Factorio blueprint objects with a version prefix, filtered entity fields, typed
underground ends, recipe-machine icons, and valid captured wires. Offline pole placeholder wires are omitted so
the poles can reconnect automatically.

If cursor delivery fails, the staged blueprint is offered to the clipboard and paste is activated. The delivery
diagnostics retain the cursor error text, and the staging inventory is destroyed after each attempt.
