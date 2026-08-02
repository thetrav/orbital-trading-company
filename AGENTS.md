# Agent instructions

## Validation

After every batch of changes, run `./validate.sh` and verify all 6 checks pass before reporting done. The script runs `luacheck`, `lua-language-server`, `busted`, `--dump-data`, `--create`, and `--load-game --until-tick 600`.

Do not skip this step. Do not rely only on headless Factorio — also check `luacheck` and `lua-language-server` output for regressions.

`validate.sh` prints its own pass/fail summary — read that rather than piping it through `grep`/`head`. If you need different output, change the script (flags or env vars are fine).

## Probing the real game

`tools/probe.sh <probe.lua> [--ref <git-ref>] [--ticks N]` runs a throwaway module inside headless
Factorio and prints anything it `log()`s containing `PROBE`. Use it for behaviour that only the
real API can answer — entity status, power, what a drill bound to. `--ref` stages a git ref
instead of the working tree, which makes an A/B against unmodified code one command. The mod is
staged into a temp directory, so the repo is never touched and there is no wiring to remember to
remove. Probes live in `tools/probes/`.

**`on_nth_tick` also fires at tick 0 when a save loads.** A probe that reports on the first firing
measures a world that has not run a single tick: everything reads `no_power`, no drill has a
mining target, and no assembler has started. Guard with `if game.tick == 0 then return end`.

## Tests

`test/` holds [busted](https://lunarmodules.github.io/busted/) specs, run by `validate.sh` step 3 and configured by `.busted`. Install with `luarocks install --local busted`; the step SKIPs (loudly) if the binary is missing, and honours a `BUSTED` env var override.

`test/factorio_mock.lua` stands up the runtime globals (`game`, `storage`, `prototypes`, `defines`) that a module under test reads — `mock.setup{...}` takes a technology-name → spec table and wires prerequisites by name. Call `mock.teardown()` in `after_each`, and clear `package.loaded` for the module under test before requiring it so each spec gets fresh state.

Prefer adding a spec here over ad-hoc probe scripts that get `require`d from `control.lua` — those need a headless round trip and leave the repo dirty. When only the real API can answer the question, use `tools/probe.sh` rather than hand-wiring one. `test/` is excluded from `lua-language-server` via `workspace.ignoreDir`, because the mock's globals otherwise shadow the real API stubs and produce false `undefined-field` reports.

## What this mod is

Factorio 2.0 mod "Orbital Trading Company" (`info.json`, version 0.1.0, depends on `factorio-charts >= 1.0.0`). Players spawn on a 10x10 floating platform on a resource-free Nauvis, join or create a **company** (implemented as a Factorio force), and expand a network of interlinked platform "rooms" (hubs, corridors, factories, orbital stations, asteroid mines, water pumps). Buy/sell chests interact with a shared credit economy; a dynamic market prices items and reacts to supply and demand.

## Code layout

- `data.lua` — loads every file in `prototypes/`.
- `data-updates.lua` — out-of-map tile autoplace.
- `data-final-fixes.lua` — strips entity/decorative autoplace + enemies from Nauvis; rocket silo uses void energy.
- `control.lua` — all event wiring (init/load, ticks, GUI, built/mined/died, teleporters). Per-tick logic runs on `on_nth_tick(1)`; history + trading GUI refresh on `on_nth_tick(60)`.
- `scripts/` — runtime modules (see below).
- `prototypes/` — one file per entity/item; several deepcopy base prototypes (gate control, company monitor, teleporter, water pump).
- `types.lua` — lua-language-server stubs (partial classes, `remote.call`).
- `doc/` — design backlog (`design-thinking.md`) and plans. Read before starting economy/expansion work.
- `scripts/shapes/` — **captured** shape definitions (data, not code), one file per shape, plus the procedural `connector.lua`. Do not hand-write geometry here; capture it in game. See README.md "Capturing shapes".
- `scripts/shape_hooks/` — per-shape post-apply behaviour, registered in `init.lua`.
- `tools/` — one-off migration harness (`export_builtin_shapes.lua`) and the pre-capture generators it renders (`legacy_shapes/`). Excluded from lua-language-server via `workspace.ignoreDir`.

## Runtime module map (`scripts/`)

- `buy_chest.lua` — buy chest reads green+red circuit signals as desired counts, buys at `floor(price * 1.01 + 0.5)`, deducts from company credits. `process()` runs every tick. Registered in `storage.buy_chests[unit_number] = { chest, force_name }`.
- `sell_chest.lua` — auto-sells contents at `floor(price * 0.99 + 0.5)`. Same storage shape.
- `pricing.lua` — BFS through tech tree computing a static base price per item (raw resources = 100; recipe cost = ingredients + smelting fuel + `energy * 10`/s). Runs on init/load into `storage.prices`. This is now only the **anchor**; the traded price is the anchor scaled by Nauvis's stock level.
- `stock.lua` — Nauvis's finite warehouse, `storage.stock.items[item] = count`. `TARGET_STOCK = 1000`, `SCARCITY_CAP = 20`. `scarcity()` returns `(T/s)^0.7` below target and `(T/s)^2` above, so prices climb as shelves empty and collapse when flooded. Unknown items lazily seed at `TARGET_STOCK` on first `get`, so items seed themselves as tech unlocks them. `take` never returns more than is held — that is the hard stop at zero.
- `supply_demand.lua` — 10-tick periods aggregate buys/sells; `price_offsets[item]` drift by `demand * 0.01`, decay `* 0.95`. Applied to the anchor *before* the scarcity multiple. Now partly redundant with stock movement — see `doc/nauvis_economy.md` §1.
- `utils.lua` — `format_number` (comma thousands), `get_base_price`, `get_price` (`(base + offset) * scarcity`, floored at 1 and capped at `base * 20`), `get_stock`.
- `supply_belts.lua` — per-tick processing for Nauvis's two physical stock interfaces. Supply: pushes one item per lane per tick from stock onto a registered belt, stopping when stock runs out; lane 1 takes `left`, lane 2 takes `right`, and a nil lane is skipped so it stays clear for something else to load. `register_from_def` resolves a shape entity's `item` / `item_left` / `item_right` onto those two lanes. Intake: drains every transport line into stock.
- `research.lua` — Nauvis's research monopoly. Instantly researches the three craft-item trigger techs (`steam-power`, `electronics`, `automation-science-pack`) on init, replays every Nauvis technology onto all other forces, and disables every recipe producing a `tool`-type item or a lab. `ensure_research` auto-queues the cheapest technology whose ingredients Nauvis can actually make (currently red science only). `block_lab` destroys and refunds labs built by non-Nauvis forces.
- `nauvis_industry.lua` — one-shot builder for the sealed production room (north of the player platform, replacing the old top airlock) and the ore mine far to the west. Both are captured shapes applied at fixed world positions; only `seal_top_airlock` and charting remain as code. Idempotent via `storage.nauvis_industry.built`.
- `item_filter.lua` — allowed items are subgroup `raw-resource`/`raw-material`/`intermediate-product`, non-hidden, and either research-free or craftable by the force's enabled recipes. Cached per player in `player_data.allowed_items`, invalidated on research finish.
- `trading_history.lua` — 60-entry ring buffer per force per item (`storage.trading_history[force][item][slot] = { bought, sold, price }`), plus `storage.trading_chart[force]` (factorio-charts data). `advance_second()` advances `storage.trading_history_head`.
- `market_gui.lua` — persistent Market window (filter All/Pinned/None, search, pin checkboxes, price + trend arrows) and the top-center Credits frame. Buy price displayed is `floor(price * 1.01 + 0.5)`.
- `trading_gui.lua` — Profit & Loss window (shortcut `otc-trading`): three chart panels (income/expense/profit) rendered via `__factorio-charts__.charts` on a dedicated `otc-trading-charts` surface, plus an item list with per-series checkboxes and per-second rates. Per-player state under `player_data.trading_*`.
- `company_gui.lua` — create/join company. Creating gives `STARTING_CREDITS = 5000`. Sets `player.force` to the company force. Opened by selecting the `otc-company-monitor`.
- `expand_gui.lua` — expansion shop, opened from a gate computer. Shape costs are local constants (`HUB_COST=1` … `COPPER_ASTEROID_COST=6`). Preview via `platform.show_preview`, buy via `platform.expand_from_gate`. Closes if player walks >6 tiles from the gate.
- `platform_gates.lua` — the 4 starting airlocks (east/west/north/south); `storage.gates["surface:x,y"]` and `storage.gates_by_id[computer_unit_number]`.
- `shape_def.lua` — the shape data format: rotation maths, `transform` (pure, world coordinates), `apply`, `preview`, `clearance_box`, `origin_for_gate`. Canonical orientation is gate-on-west, room extending east; the four compass directions are rotations of the one capture. `DEFAULT_CORRECT_TILES` holds the `set_tiles` correction defaults (`otc-platform` is false, everything else true).
- `shape_runs.lua` / `shape_io.lua` — run-length packing for tile lists, and the definition → Lua source serializer shared by the in-game capture and the offline migration harness.
- `shape_capture.lua` — the authoring tool: `/otc-capture-shape <name>`, the selection-tool handler, and `capture_area` which reads a rectangle of world back into a definition. Roles come from `shape_config` tags first, then `ROLE_BY_NAME`; anchors come from `otc-shape-marker` panel text. Admin-only.
- `shape_config.lua` — the other authoring tool: `/otc-config-shape` grants a selection tool that tags entities with a `role`, plus a per-lane item for `role = "supply"`, which `capture_entity` then merges into the definition. `LANE_SIDES` maps transport line index to the screen side it occupies for a given belt facing, so the pickers say "top"/"bottom" rather than "lane 1"/"lane 2" — line 1 is the lane 90° counter-clockwise from travel, so it is top on an east-facing belt and bottom on a west-facing one. Each tag draws a floating label on its entity. Admin-only; both tools are `only-in-cursor` so they cannot reach a player's inventory.
- `shape_registry.lua` — name → definition. Add a line here when you capture a new shape. Also read at the **data stage** by `prototypes/shape_place.lua`, so shape files must stay pure data (`scripts.shape_runs` is their only dependency).
- `shape_place.lua` — the dev placer for shapes that are not bought from a gate: `/otc-place-shape` opens a list, picking one puts a per-shape placement item in the cursor, and left-clicking builds it at the marker's footprint. Admin-only, always placed for the Nauvis force. `on_marker_built` swaps the dummy marker for the real shape; `origin_from_marker` converts the marker's centre back to the shape's top-left origin.
- `room_builder.lua` — shared placement helpers (`place_wall`, `place_gate`, `place_computer`, `register_gate`, `get_surface_force`, `clear_area`), extracted so hooks can use them without requiring `platform.lua`.
- `platform.lua` — now thin: `expand_from_gate` and `show_preview` resolve a definition, work out origin + rotation, add the connector, apply, and run the hook. `build_shape` places a definition at a fixed position (starting room, production room, mine blocks).

## Storage schema (persisted in `storage`)

- `players[player.index]` — `company`, `allowed_items`, `market_filter`, `pinned_items`, `trading_selected_force`, `trading_chart_selection`, `trading_chart_state`, `trading_list_state`, `trading_search_text`, `active_gate`, `selected_shape`, `preview_renderings`; legacy `credits`.
- `companies[force_name] = { credits }` — the balance sheet.
- `station_forces[station_name]`, `rocket_silos[unit_number]`, `otc_teleporters[unit_number]`, `otc_return_teleporters[unit_number] = { surface, position }`, `otc_station_index`.
- `buy_chests` / `sell_chests` — keyed by unit_number.
- `prices`, `supply_demand { tick_counter, period_buys, period_sells, price_offsets }`.
- `stock { items }` — Nauvis's warehouse. Not a Factorio inventory; nothing in the world holds it.
- `supply_belts[unit_number] = { entity, left, right }`, `intake_belts[unit_number] = { entity }`.
- `nauvis_industry { built }`.
- `trading_history`, `trading_history_head`, `trading_chart`, `chart_surface`.
- `gates`, `gates_by_id`.
- `shape_capture { pending }` — per-player pending capture name for `/otc-capture-shape`.
- `shape_place { selected, clear }` — per-player shape choice for the placer and whether it clears the footprint first (defaults on).
- `shape_config { entities, selection }` — `entities[unit_number] = { entity, role, item_left, item_right, label }` are the in-game role tags; `selection[player_index]` is the entity list the open config window is showing. Entries hold the entity so a mined one can be swept along with its label.

`ensure_company_setup()` in `control.lua` migrates legacy state (player `credits` → "Default" company) and repairs `force_name` on chest entries — extend it when adding migrations.

## Conventions

- 4-space indent. Module pattern: `local M = {}` … `return M`. No comments unless asked.
- Names: prototypes/entities use `otc-` (hyphens); GUI elements use `otc_` (underscores). Loot: `otc_trading_*`, `otc_market_*`, `otc_expand_*`, `otc_company_*`.
- `storage` (never `global`). Lua 5.2 std.
- Suppress spurious diagnostics with `---@diagnostic disable-next-line: undefined-field`.
- Req is `require("scripts.foo")` relative to mod root.
- GUI work: destroy + rebuild list rows rather than mutating when structure changes (see `market_gui.rebuild_market_list`, `trading_gui.rebuild_rows`); factorio-charts chunks must be allocated/freed via `charts.surface.allocate_chunk`/`free_chunk` and render objects destroyed.

## Gotchas

- Buy/sell multipliers live in **three** places: `buy_chest.lua`/`sell_chest.lua` (execution) and `market_gui.lua` (display). Actual values are 1.01/0.99
- Players join a company via GUI; `player.force` is set to the company force, so chest `force_name` is captured at build/register time and must not be read from the entity afterwards.
- Rocket-silo GUI is suppressed for otc station silos (`storage.rocket_silos`) — delivery via silo is not yet implemented.
- New surface creation (orbital stations) requires explicit chunk generation and `treat_missing_as_default = false` autoplace settings to stay empty.
- **Inserter `direction` points at the pickup, not the drop.** An inserter facing `east` picks up from the tile to its east and drops to its west. Getting this backwards is silent — the inserter just reports `waiting_for_source_items` forever.
- **A mining drill binds to its ore when it is created.** Build resources before entities or the drill reports `no_minable_resources` forever — rotating it in game is what forces a re-scan. `shape_def.apply` orders it correctly and `test/shape_apply_spec.lua` pins that.
- **An unpaired underground belt works, but only on lines 1 and 2.** `otc-supply-belt` conveys items and inserters can pick off it exactly like a vanilla unpaired underground belt — it is *not* scenery, despite what this file used to claim. What is true is that it reports 4 transport lines and only 1 and 2 are the visible face; 3 and 4 are the buried half, and an item inserted there is stranded forever. `supply_belts.supply_line_count` caps supply at 2 for this reason; intake still drains all 4 so strays are recovered. `tools/probes/supply_belt_lines.lua` pins it. Register either the `otc-supply-belt` itself or a plain `transport-belt` in front of it — both work; the belt itself is usually what you want, because inserters can then take from it directly.
- **A supply belt is only ever an exit (`type = "output"`).** As an entrance it swallows items and plays the wrong animation. `belt_to_ground_type` is **read-only**, and assigning `direction` just flips the type again — they are the same underlying property — so an underground belt cannot be *told* to be an exit, only built as one. `shape_def.create_entity` forces `output` for `otc-supply-belt` regardless of what a capture says, `shape_capture` normalises it on the way out, and `supply_belts.enforce_exit` rebuilds the entity on `on_player_rotated_entity` so a rotation becomes a 180° turn. The rebuild changes `unit_number`, so the supply registration and the `shape_config` tag both migrate — see `shape_config.migrate`. `tools/probes/supply_belt_rotate.lua` pins all of it.
- **A nil lane must stay clear.** `supply_belts.process` picks its item with an `if`, not `cond and data.left or data.right` — that idiom falls through when the left lane is nil and feeds it the right lane's item, quietly filling a lane reserved for an inserter's output.
- **`otc-supply-belt` and `otc-intake-belt` get their role from `ROLE_BY_NAME`.** Each prototype has exactly one purpose, so the config tool only needs to set a supply belt's per-lane items; the role is never worth tagging and a capture cannot lose it.
- **Rotating an underground belt keeps its `unit_number` and its prototype.** It is not swapped for a vanilla belt; only `belt_to_ground_type` and `direction` change. A `shape_config` tag on a hand-built belt survives a rotation — but a *placed* shape's belts are freshly created entities that never had tags, so the config tool showing "(none)" on them is correct, not a bug.
- **There is no API for polling the mouse position.** `cursor_position` exists only on a `CustomInputEvent`, so a hand-drawn preview cannot follow the cursor. `prototypes/shape_place.lua` gets a real hover preview by generating a dummy `simple-entity-with-owner` per shape whose `tile_width`/`tile_height` match its footprint, and letting Factorio draw its own build preview. The dummy sits on its own `collision-layer` (`otc-placement`) that nothing else uses: a **non-empty** mask is what makes the engine draw the footprint highlight at all — an empty one renders nothing and the cursor looks empty — while a layer with no other members still collides with nothing, so placement is never blocked. Clobbering is handled deliberately by `room_builder.clear_area`, not by collision.
- **Placing from the cursor is limited by build reach**, which no shape-sized room can satisfy. `shape_place` raises `force.character_build_distance_bonus` while the tool is held and restores it on placement, on closing the window, and from `on_player_cursor_stack_changed` — the bonus is force-wide, so every exit route has to put it back.
- **Prefix strings used in Lua patterns must be escaped.** `otc-place-marker-` matched nothing until the hyphens became `%-`; the failure is silent, the tool just does nothing.
- Nauvis's whole surface is `out-of-map` (`data-updates.lua`), so anything built outside the player platform must lay its own tiles first.
- **Entity positions in shape definitions are exact centres**, not the sloppy integer tile coordinates `create_entity` will snap for you. `{7, 1}` and `{7.5, 1.5}` place a 1x1 entity identically, but they rotate to different tiles — always store the snapped centre. `test/shape_def_spec.lua` fails on off-grid positions.
- **A rotated shape is a true rotation, not a mirror**, so a room must be an odd number of tiles across its connection axis or its gate sits half a tile off centre and rotating shifts the whole room sideways. The factory was widened from 32 to 33 for exactly this reason. `test/shape_def_spec.lua` asserts every shape stays centred on its gate in all four directions.
- Only the east/west/north airlocks exist. The `south` entry (screen-top, gate at `{0,-6}`) was removed from `platform_gates.AIRLOCKS` to make room for the production room. Note the table's labels are y-flipped relative to Factorio's directions.
