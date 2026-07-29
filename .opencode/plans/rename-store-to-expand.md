# Rename store_gui to expand_gui

## Changes needed

### File rename
- `scripts/store_gui.lua` → `scripts/expand_gui.lua` (already done: `mv`)

### `scripts/expand_gui.lua` — replace all `otc_store_` → `otc_expand_`:
- `otc_store_frame` → `otc_expand_frame` (9x)
- `otc_store_close` → `otc_expand_close` (1x)
- `otc_store_inner` → `otc_expand_inner` (4x)
- `otc_store_list` → `otc_expand_list` (3x)
- `otc_store_buy_row` → `otc_expand_buy_row` (3x)
- `otc_store_buy_button` → `otc_expand_buy_button` (5x)
- `create_store_gui` → `create_expand_gui` (2x)
- `caption = "Shop"` → `caption = "Expand"`
- `"Platform Expansion"` → `"Hub"`

### `control.lua`:
- `local store_gui = require("scripts.store_gui")` → `local expand_gui = require("scripts.expand_gui")`
- `store_gui.` → `expand_gui.` (7x)
- `otc_store_frame` → `otc_expand_frame` (1x)
- `otc_store_close` → `otc_expand_close` (1x)
- `otc_store_buy_button` → `otc_expand_buy_button` (1x)

### `scripts/platform_gates.lua`:
- `store_gui_ref` → `expand_gui_ref` (1x)

After all changes, run `./validate.sh` to verify.
