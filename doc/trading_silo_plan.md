# Trading silo

**Status: built.** All seven phases are done and `./validate.sh` passes all six checks.
What follows is the plan as agreed; the two places reality differed are marked inline.

Replaces the buy chest and sell chest with a single large entity on the orbital station:
a 100-slot container that looks like a rocket silo, configured through its own GUI or by
circuit network. Only the orbital silo trades; the ground launch bay is untouched.

## Decisions

- **Buy orders maintain a level.** A row's quantity is the count to keep in the silo, not a
  one-shot order. Same semantics as the buy chest's circuit signals today.
- **Sell orders sell everything of that type.** No reserve, no quantity. Players keep
  reserves in other containers.
- **An item is never on both lists.** The picker on each side excludes anything already on
  either list; in circuit mode the sign of the signal decides, so the case cannot arise.
- **Partial fills, never failures.** Buy as much as the tightest of credits, Nauvis stock
  and free slots allows — the buy chest's existing behaviour.
- **Circuit control replaces the configuration, it does not merge with it.** While the
  checkbox is on, both panels are read-only and show the resolved live orders; the stored
  configuration is kept and comes back when it is switched off.
- **Signal sign selects the side.** Positive count = buy, maintain that many. Negative
  count = sell all of that item. Zero is ignored. The green/red/both selector only chooses
  which wires are read; "both" sums them exactly like `buy_chest.read_circuit_signals`.
- **Per silo entity, not per company.** One silo per company today; the configuration lives
  on the entity's registration so more silos later need no rework.
- **No rate limiting.** Trades settle per tick as the chests did. Launch cycles, payload
  caps and animation are a later feature.
- **No migration.** The mod is unreleased; the chests and their storage are deleted outright.

## Entity

New prototype `otc-trading-silo` in `prototypes/trading_silo.lua`:

- `type = "container"`. It shipped as a `logistic-container` in storage mode, which does let
  bots deposit and withdraw, but a logistic chest with no roboport coverage flashes a "not
  connected to network" alert and the orbital station has no network. Bots are deferred;
  restoring the type plus `logistic_mode` and `max_logistic_slots` brings them back.
  Inserters need nothing special either way.
- `inventory_size = 100`.
- `collision_box` / `selection_box` copied from `rocket-silo` (9x9, `{-4.2,-4.2}..{4.2,4.2}`
  and `{-4.5,-4.5}..{4.5,4.5}`) so it drops into the station shape on the same footprint.
- `picture` built from `data.raw["rocket-silo"]["rocket-silo"]`'s `shadow_sprite`,
  `base_day_sprite`, `door_back_sprite` and `door_front_sprite` as static layers, so the art
  and its shifts are inherited rather than retyped. Doors are drawn shut; there is no
  animation until launches exist.
- `circuit_wire_max_distance`, `draw_circuit_wires = true`.
- `minable = false`, no recipe. It arrives with the station shape and is never in an
  inventory.

A real `rocket-silo` cannot be used: its input inventory is recipe-filtered to rocket parts
and its cargo path is the rocket, which is explicitly not wanted here.

**Risk closed:** `tools/probes/trading_silo.lua` confirms the entity places at 9x9, reports
100 slots, takes goods from an inserter, runs a live buy/sell cycle, and — since bots were
switched off — stays invisible to a powered roboport network in range. The sprites have not been looked at on screen yet — that is the one thing
left that only a human eye can check.

## Model — `scripts/trading_silo.lua`

Simulation only, no GUI. The GUI module calls into it; nothing here reads `game.players`.

```
storage.trading_silos[unit_number] = {
    entity,
    force_name,
    buy  = { { item = "iron-plate", quantity = 500 }, ... },   -- ordered
    sell = { { item = "copper-ore" }, ... },                   -- ordered
    circuit = { enabled = false, wire = "green" },             -- "green" | "red" | "both"
}
```

Both lists are arrays, not maps: the order is the player's priority and is what decides who
gets served when credits run short.

API:

- `register(entity)` / `unregister(unit_number)`
- `add_buy(data, item)`, `add_sell(data, item)`, `set_quantity(data, index, n)`,
  `remove(data, side, index)`, `move(data, side, index, delta)`
- `is_listed(data, item)` — the picker's exclusion test, checks both sides
- `resolve(data)` → `buy_map, sell_set`, the effective orders for this tick:
  - circuit off: straight from the configured lists, in list order
  - circuit on: read the selected wires (summed for "both"), positive counts become buy
    targets, negative become sell entries, zero is dropped. Buy is built first and an item
    already in it is skipped for sell — with summed signals an item has one sign so this is
    a guard, not a live path.
  - either way, everything is filtered through `item_filter.is_item_allowed`.
- `process()` — per tick, over every registered silo:
  - buys, in order: `deficit = target - inventory count`; `to_buy = min(deficit,
    floor(credits / buy_price), stock.get(item))`; insert, then `stock.take` /
    `company.credits` / `nauvis.burn` / `supply_demand.record_buy` /
    `trading_history.record_buy` on the amount actually inserted.
  - sells: remove the whole count of each listed item, then `stock.add` / credits /
    `nauvis.mint` / `record_sell` / `trading_history.record_sell`.
  - multipliers stay 1.01 and 0.99, still duplicated in `market_gui` — the
    existing three-places gotcha becomes two places and is worth collapsing while here.

Called from `control.lua`'s `on_nth_tick(1)` where `buy_chest.process()` was.

## GUI — `scripts/trading_silo_gui.lua`

*Revised after the first build: the tabbed window is gone.* A custom frame cannot show the
player's inventory beside the chest or support shift-click transfer, and both are what a
container is expected to do. So `player.opened` is left alone — the vanilla container window
opens exactly as it does for any chest — and the order panel is a `player.gui.relative`
frame anchored to `defines.relative_gui_type.container_gui` scoped by
`name = "otc-trading-silo"`, sitting to its right and closing with it. There is no Inventory
tab, no slot grid and no hand-rolled transfer; a Fluids tab, if it ever happens, becomes a
tabbed pane inside this panel.

Layout:

```
   (vanilla container window)      ┌ Trading ──────────────────────┐
   ┌───────────────────────┐       │ [ ] Control with circuit net  │
   │  Trading Silo         │       │ (o)Green ( )Red ( )Both       │
   │  ▣▣▣▣▣▣▣▣▣▣ 100 slots │       ├───────────────┬───────────────┤
   │  ▣▣▣▣▣▣▣▣▣▣           │       │ Buy orders    │ Sell orders   │
   ├───────────────────────┤       │ ┌── scroll ─┐ │ ┌── scroll ─┐ │
   │  (player inventory)   │       │ │[i] iron   │ │ │[i] copper │ │
   │  ▣▣▣▣▣▣▣▣▣▣           │       │ │ [500] ▲▼x │ │ │      ▲▼ x │ │
   └───────────────────────┘       │ └───────────┘ │ └───────────┘ │
                                   │ [ + ]         │ [ + ]         │
                                   └───────────────┴───────────────┘
```

- `[+]` is a `choose-elem-button` with `elem_type = "item"` — it brings its own searchable
  item chooser for free. `on_gui_elem_changed` validates against `item_filter` and
  `is_listed`, rejecting with a `player.print` and clearing the button. A bespoke filtered
  list with its own search is the nicer version and is deferred.
- Rows are destroyed and rebuilt on any structural change, per the repo's GUI convention.
- Quantity fields are `numeric` textfields committed on `on_gui_text_changed`, clamped to
  ≥ 1.
- With the circuit checkbox on, the panels are rebuilt from `resolve()` every 60 ticks and
  carry no `+`, no `▲▼`, no `x` and read-only quantities.
- Live price per row and a search box in the picker are noted as nice-to-have and left out.
  No credits balance and no projected spend.

Per-player state under `storage.players[i].trading_silo_unit`, the open silo's unit_number.

## Removals

- `prototypes/buy_chest.lua`, `prototypes/sell_chest.lua`, their `data.lua` lines
- `scripts/buy_chest.lua`, `scripts/sell_chest.lua`
- `control.lua`: the two requires, `BUY_CHEST_NAME`/`SELL_CHEST_NAME`, the register /
  unregister / process calls, and the `storage.buy_chests` / `sell_chests` repair loops at
  `control.lua:157-171`
- `storage.buy_chests`, `storage.sell_chests`
- roles `buy_chest`, `sell_chest`, `buy_chest_combinator` from `shape_config.lua`,
  `shape_capture.lua`, `tools/export_builtin_shapes.lua`, and the chest-wiring block in
  `scripts/shape_hooks/station_interior.lua`
- locale entries for both chests

`storage.rocket_silos` currently exists only to suppress the vanilla silo GUI and to hold
the station name; it is replaced by `storage.trading_silos`, and the `rocket-silo` branches
in `on_gui_opened`, `on_entity_died` and `on_player_mined_entity` go with it.

## Shapes

`scripts/shapes/station_interior.lua` and `scripts/shapes/orbital_station.lua` both carry a
`rocket-silo` at `{0.5, 0.5}` with `role = "silo"`, and `station_interior` also carries the
two chests and the combinator.

This is a 1:1 substitution, not authoring, so it is edited in place rather than recaptured:
`otc-trading-silo` inherits `rocket-silo`'s collision box, so the footprint, the centre snap
and the clearance box are all unchanged. No position, tile run or anchor is touched.

- both shapes: rename the silo entity, keep `role = "silo"`
- `station_interior`: delete the `otc-buy-chest`, `constant-combinator` and `otc-sell-chest`
  entries
- `shape_capture.ROLE_BY_NAME`: retarget `silo` from `rocket-silo` to `otc-trading-silo` so a
  later recapture still tags it

The station hooks then only need `trading_silo.register` on the `silo` role. Recapture is
worth doing later only to decide what, if anything, fills the corner the chests vacated —
a layout question, not a correctness one.

## Tests and validation

New `test/trading_silo_spec.lua` against the model, with `factorio_mock`:

- maintain semantics: target reached, no further buying; deficit after manual withdrawal
  buys again
- partial fill capped independently by credits, by `stock.get` and by free slots
- sell removes the full count and credits at the sell multiplier
- an item on the buy list is never sold; `is_listed` blocks both sides
- circuit resolve: positive → buy target, negative → sell, zero ignored, wire selection,
  "both" sums green and red
- ordering: with credits enough for one row, the first row is served

`./validate.sh` (all 6 checks) after each phase. `tools/probes/trading_silo.lua` for what
only the real API answers: inserter insert, bot deposit and withdraw, slot count, and that
the entity places on the station surface at 9x9.

*Changed during the build:* the GUI is unit tested too, against a `LuaGuiElement` stand-in
added to `factorio_mock`, rather than left to in-game checking — `test/trading_silo_gui_spec.lua`.
That spec is what caught the crash when the panel moved to `gui.relative` and a lookup path
went stale. And because busted turned out not to be installed here, step 3 was skipping
silently; it now resolves busted from `$BUSTED`, `PATH` or `~/.luarocks/bin`, and falls back
to `test/minimal_runner.lua` when there is none.

## Phases

1. **Entity.** Prototype + probe + a look in game. Nothing else until the container is
   confirmed to behave.
2. **Model.** `trading_silo.lua` with registration, order CRUD, `resolve` for the non-circuit
   path, and `process`. Specs. Wired into the tick loop. Silo is functional with no UI.
3. **Orders GUI.** Frame, tabs, two panels, picker, quantity, reorder, delete.
4. **Inventory tab.** Slot grid and cursor transfer.
5. **Circuit mode.** Checkbox, wire selector, `resolve`'s circuit path, read-only panels.
6. **Teardown.** Delete the chests and their wiring; swap the silo entity in both station
   shapes and drop the chest entries from `station_interior`; locale.
7. **Docs.** `AGENTS.md` module map, storage schema and gotchas (the container-not-silo
   reason, the sign convention, the hand-rolled inventory transfer).
