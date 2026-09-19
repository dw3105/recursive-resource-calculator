# Debug export format

The sheet export is a versioned diagnostic envelope, not a blueprint and not a
release expectation. Its outer shape is:

```json
{
  "format": "rrc-sheet-debug",
  "schema_version": 1,
  "encoding": "zlib+base64",
  "rrc_version": "1.1.36",
  "environment": {"base_game_version": "2.0", "active_mods": {}},
  "sheet": {"sheet_id": "...", "state": "current", "targets": []},
  "selection": [],
  "settings": {"current": {}, "result": {}},
  "state": "current",
  "calculation": {},
  "prototypes": {},
  "diagnostics": {}
}
```

The displayed export string is the result of
`helpers.encode_string(helpers.table_to_json(payload))`: Base64 of a zlib
stream, with no blueprint `0` prefix. Empty lists remain lists in the game
payload. `state` is one of `not_computed`, `current`, `pending`, `stale` or
`failed`; current settings and the settings that produced the saved result are
kept separately.

## Offline decoder

This works with Python 3 and the string copied from the game. It also accepts a
file containing the string:

```python
import base64, json, pathlib, zlib

text = pathlib.Path("export.txt").read_text()  # or paste the string here
text = "".join(text.split())
if text.startswith("0"):
    text = text[1:]
payload = json.loads(zlib.decompress(base64.b64decode(text)).decode("utf-8"))
assert payload["format"] == "rrc-sheet-debug"
print(json.dumps(payload, indent=2, sort_keys=True))
```

`tests/golden/add_case` uses the same decoder and writes `export.json` beside
the original `export.txt`. A decoded export is input evidence only: capturing
it never writes an accepted golden expectation.
