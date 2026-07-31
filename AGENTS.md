# Agent instructions

## Validation

After every batch of changes, run `./validate.sh` and verify all 5 checks pass before reporting done. The script runs `luacheck`, `lua-language-server`, `--dump-data`, `--create`, and `--load-game --until-tick 600`.

Do not skip this step. Do not rely only on headless Factorio — also check `luacheck` and `lua-language-server` output for regressions.

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
- `scripts/shapes/` — pure geometry per expansion shape: `get_positions(...)`, `get_bounding_box(...)`, `get_gate_pos(...)`. `platform.lua` renders previews and applies them on buy.

## Runtime module map (`scripts/`)

- `buy_chest.lua` — buy chest reads green+red circuit signals as desired counts, buys at `floor(price * 1.01 + 0.5)`, deducts from company credits. `process()` runs every tick. Registered in `storage.buy_chests[unit_number] = { chest, force_name }`.
- `sell_chest.lua` — auto-sells contents at `floor(price * 0.99 + 0.5)`. Same storage shape.
- `pricing.lua` — BFS through tech tree computing a static base price per item (raw resources = 100; recipe cost = ingredients + smelting fuel + `energy * 10`/s). Runs on init/load into `storage.prices`.
- `supply_demand.lua` — 10-tick periods aggregate buys/sells; `price_offsets[item]` drift by `demand * 0.01`, decay `* 0.95`, clamped to ±50% of base. Effective price = base + offset (min 1).
- `utils.lua` — `format_number` (comma thousands), `get_base_price`, `get_price` (base + supply/demand offset).
- `item_filter.lua` — allowed items are subgroup `raw-resource`/`raw-material`/`intermediate-product`, non-hidden, and either research-free or craftable by the force's enabled recipes. Cached per player in `player_data.allowed_items`, invalidated on research finish.
- `trading_history.lua` — 60-entry ring buffer per force per item (`storage.trading_history[force][item][slot] = { bought, sold, price }`), plus `storage.trading_chart[force]` (factorio-charts data). `advance_second()` advances `storage.trading_history_head`.
- `market_gui.lua` — persistent Market window (filter All/Pinned/None, search, pin checkboxes, price + trend arrows) and the top-center Credits frame. Buy price displayed is `floor(price * 1.01 + 0.5)`.
- `trading_gui.lua` — Profit & Loss window (shortcut `otc-trading`): three chart panels (income/expense/profit) rendered via `__factorio-charts__.charts` on a dedicated `otc-trading-charts` surface, plus an item list with per-series checkboxes and per-second rates. Per-player state under `player_data.trading_*`.
- `company_gui.lua` — create/join company. Creating gives `STARTING_CREDITS = 5000`. Sets `player.force` to the company force. Opened by selecting the `otc-company-monitor`.
- `expand_gui.lua` — expansion shop, opened from a gate computer. Shape costs are local constants (`HUB_COST=1` … `COPPER_ASTEROID_COST=6`). Preview via `platform.show_preview`, buy via `platform.expand_from_gate`. Closes if player walks >6 tiles from the gate.
- `platform_gates.lua` — the 4 starting airlocks (east/west/north/south); `storage.gates["surface:x,y"]` and `storage.gates_by_id[computer_unit_number]`.
- `platform.lua` — the big one: room construction, preview rendering, orbital station surface creation (`otc-station-N`), teleporter + buy/sell chest + rocket silo + water pump placement on stations.

## Storage schema (persisted in `storage`)

- `players[player.index]` — `company`, `allowed_items`, `market_filter`, `pinned_items`, `trading_selected_force`, `trading_chart_selection`, `trading_chart_state`, `trading_list_state`, `trading_search_text`, `active_gate`, `selected_shape`, `preview_renderings`; legacy `credits`.
- `companies[force_name] = { credits }` — the balance sheet.
- `station_forces[station_name]`, `rocket_silos[unit_number]`, `otc_teleporters[unit_number]`, `otc_return_teleporters[unit_number] = { surface, position }`, `otc_station_index`.
- `buy_chests` / `sell_chests` — keyed by unit_number.
- `prices`, `supply_demand { tick_counter, period_buys, period_sells, price_offsets }`.
- `trading_history`, `trading_history_head`, `trading_chart`, `chart_surface`.
- `gates`, `gates_by_id`.

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
