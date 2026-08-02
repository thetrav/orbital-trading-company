# Nauvis as producer: fixed stock, monopoly research, and physical supply

Plan for turning Nauvis from an infinite counterparty with static prices into a **real
actor with a finite warehouse**. Nauvis mines its own ore, runs its own assemblers and
lab, holds the only labs in the game, and prices every trade off the stock level in its
warehouse rather than off a fixed base price.

Supersedes the pricing half of `design-thinking.md` § economy. Builds on
`company_ownership.md` — Nauvis the *state* (money supply, share market) is unchanged;
this document adds Nauvis the *producer*.

---

## 1. Model

### The warehouse is the market

Today `utils.get_price` returns `pricing.lua`'s static tech-tree base plus a drift offset,
and buy chests conjure items from nothing. Both go away as sources of truth. Instead:

```
storage.stock.items[item_name] = count
```

This is a plain Lua table, **not** a Factorio inventory. Nothing in the world holds it.
Every buy chest purchase decrements it; every sell chest sale increments it; Nauvis's own
miners increment it; Nauvis's own assemblers decrement it.

| Flow | Direction |
| --- | --- |
| Company buy chest fills an order | stock **down** |
| Company sell chest sells | stock **up** |
| Nauvis mining drill output reaches an intake belt | stock **up** |
| Nauvis supply belt feeds its assemblers | stock **down** |

`TARGET_STOCK = 1000` per item is what Nauvis wants to hold.

### Price is a scarcity multiple of intrinsic value

`pricing.lua` stays. Its BFS through the tech tree is the only thing that knows a
processing unit is intrinsically worth more than an iron plate, and that relationship
should not be an accident of how fast the warehouse drains. So base price becomes the
**anchor**, and stock supplies the **multiplier**:

```lua
price(item) = clamp(1, round(base(item) * scarcity(stock(item))), base(item) * SCARCITY_CAP)

scarcity(s) =
    s <= 0    -> nil              -- sold out, no price
    s <  T    -> (T / s) ^ 0.7    -- climbs as the shelf empties
    s >= T    -> (T / s) ^ 2      -- collapses as the shelf overflows
```

with `T = TARGET_STOCK = 1000` and `SCARCITY_CAP = 20`.

| Stock | Multiplier | Note |
| --- | --- | --- |
| 0 | — | sold out; buy chest gets nothing |
| 10 | 20× | capped |
| 100 | 5.0× | |
| 500 | 1.6× | |
| **1000** | **1.0×** | target |
| 2000 | 0.25× | |
| 4000 | 0.06× | |
| 10 000 | 0.01× | floors at 1 credit for most items |

The asymmetry is deliberate and is what the request asks for: Nauvis will always take
your goods, but dumping 10 000 iron plates on it earns almost nothing for the last 9 000.
The 1-credit floor means selling is never literally worthless, so a player with a
production line and nothing else can always crawl back to solvency.

### Sold out means sold out

At `stock <= 0` a buy chest receives **nothing** — no partial fill, no emergency price.
This is the point of the whole change: the economy is fixed, not infinite, and an item
nobody produces stops being purchasable until somebody produces it.

There is **no starting seed at all**: the warehouse begins empty and an item with no entry
reads as zero. Nauvis owns only what it has mined, made, or been sold, so every price starts
pinned at the 20× ceiling and every shelf is stocked by somebody. That is what makes
smelting — and supplying Nauvis generally — the obvious first business rather than an
optional one.

Consequence worth naming: with no starting plate stock and no furnaces, Nauvis's own
assemblers sit idle at game start too — the production room genuinely waits on players.
Ore stock climbs forever from mining while plate stock is entirely player-driven: it rises
only when someone sells plates, and falls both from purchases and from Nauvis's own
science production. Ore prices sink toward the floor; plate prices start high and settle
wherever the community's smelting throughput lands them.

### Supply and demand offsets stay, for now

`supply_demand.lua` keeps drifting `price_offsets` on the 10-tick period, applied to the
anchor before the scarcity multiple:

```lua
price = clamp(1, round((base + offset) * scarcity(stock)), base * SCARCITY_CAP)
```

This double-counts — a purchase now both raises the offset and lowers the stock, and both
push the price up. It is kept because the offset reacts within 10 ticks while stock moves
slowly, so it still does useful work smoothing burst trades. **Flagged as the first thing
to delete** if prices turn out to whipsaw; the module is self-contained and removing it is
a one-line change in `utils.get_price`.

### Nauvis owns research

Companies cannot research. Not "cannot research efficiently" — cannot at all:

- Every science-pack recipe and the `lab` recipe are **disabled** on every company force.
- Placing a `lab`-type entity on a non-Nauvis force is **cancelled** and the item refunded.
- Science packs and labs are **removed from `item_filter`**, so they never appear in the
  Market window and a buy chest will not order them.

Research happens in exactly one place: the Nauvis lab in the sealed production room,
running on packs Nauvis assembles from stock. What Nauvis unlocks, everyone gets:

- On founding, a new company force is granted every technology Nauvis has researched.
- `on_research_finished` for the Nauvis force replays that technology onto every company
  force, then re-applies the recipe bans (unlocking a tech re-enables its recipes).

`steam-power`, `electronics` and `automation-science-pack` — the base game's three
craft-item trigger technologies that gate red science — are researched instantly on
`on_init` for Nauvis, so the production room can start working on tick one.

The effect on players: the tech tree stops being something you buy your way through and
becomes a **shared clock** driven by how well the collective keeps Nauvis supplied with
plates. Starving Nauvis of iron and copper stalls everyone's progress.

---

## 2. New entities

Two prototypes, both `table.deepcopy` of `underground-belt` (same pattern as
`prototypes/water_pump.lua` deepcopying `offshore-pump`), so they render as the familiar
underground belt mouth with no new art.

### `otc-supply-belt` — the shelf

Created with `type = "output"` and no neighbour. It looks like a belt emerging from
underground. A script pushes items onto its two transport lines from Nauvis stock, one
configured item per side, stopping when that item's stock hits zero.

```lua
storage.supply_belts[unit_number] = { entity = e, left = "iron-plate", right = "copper-plate" }
```

### `otc-intake-belt` — the drain

Created with `type = "input"`. Anything that reaches its transport lines is removed and
added to Nauvis stock. Mining drills and belts feed it exactly like a real underground
belt entrance.

```lua
storage.intake_belts[unit_number] = { entity = e }
```

Both are `minable = false`, `destructible = false`, and only ever placed by the mod on
the Nauvis force. Neither has an item, so players cannot obtain or place one.

**Risk:** an unpaired `underground-belt` is an unusual state. If items refuse to move on
one, the fallback is a `linked-belt` pair with the far end parked on an unreachable
surface, or a plain belt with the underground structure drawn over it as a rendering.
Which of the four transport-line indices are the outward-flowing pair has to be
determined by test, not by reading docs.

---

## 3. Geography

Both new installations sit on the `nauvis` surface, outside the player-reachable platform,
which today is the 11×11 room at the origin (`R = 5`) walled at ±6.

Everything on `nauvis` is `out-of-map` (see `data-updates.lua`), so both sites must lay
their own tiles before anything is placed.

### The production room — replaces the top airlock

`platform_gates.AIRLOCKS` labels `{0, 6}` as `north`, but Factorio's +y is screen-*down*.
The airlock a player sees at the **top** of their room is the entry the code calls
**`south`**, gate at `{0, -6}`, computer at `{0, -7}`. That entry is deleted: solid wall
replaces the gate, and the player loses that expansion direction.

Beyond it, a sealed room with no gate and no door:

```
        y = -20  +-------------------------+
                 |  solar  solar  solar    |
                 |  accu   accu   accu     |
                 |                         |
                 |  [supply]==> AM1 -> AM2 |   AM1: iron plate -> iron gear wheel
                 |  [supply]==>  ^     |   |   AM2: gear + copper plate -> red science
                 |               |     v   |
                 |             (inserters) |
                 |               LAB       |
        y = -9   +-------------------------+
                 ######## solid wall #######
        y = -6            (was the airlock)
```

Its own isolated power grid — solar panels plus accumulators, no connection to anything
players can touch, sized so the lab and both assemblers run through the night. The room is
charted for every force so players can watch it work; that visibility is the point, since
it is the only feedback on where their plates are going.

### The mine — west of the platform

A second sealed site around `x = -60 .. -30`, far enough that no expansion can reach it.
Three patches — iron ore, copper ore, coal — each with electric mining drills feeding a
short belt run into an `otc-intake-belt`. Its own solar + accumulator grid.

This is the only source of new matter in the game. Its throughput is the hard ceiling on
how fast ore prices can fall.

---

## 4. Storage schema

```lua
storage.stock = {
    items = { [item_name] = count },   -- Nauvis's warehouse; not a Factorio inventory
}

storage.supply_belts = { [unit_number] = { entity, left = item, right = item } }
storage.intake_belts = { [unit_number] = { entity } }

storage.nauvis_industry = {
    built = false,          -- production room + mine placed
    room_entities = {},     -- unit numbers, for repair/rebuild
    mine_entities  = {},
}
```

### Migration

Extend `ensure_company_setup()` in `control.lua`:

1. Create `storage.stock.items`. Nothing is seeded; whatever an existing save already
   accumulated is kept.
2. If `storage.nauvis_industry.built` is false, build the production room and the mine.
   This makes the whole feature land on existing saves, not just new games.
3. Disable science-pack and lab recipes on every existing company force, and sync Nauvis's
   researched technologies onto them.
4. Delete the `south` airlock gate and computer if they still exist, and wall the gap.

---

## 5. Phasing

Each phase ends with `./validate.sh` green.

1. **Stock + pricing.** `scripts/stock.lua`, seeding, `utils.get_price` reading the
   scarcity multiple, buy chest hard-stopping at zero and decrementing, sell chest
   incrementing. No new entities, no new geography. Fully playable and independently
   verifiable — the economy tightens and nothing else changes.
2. **Belt entities.** Both prototypes, the per-tick supply/intake processing, and a
   throwaway test placement to settle the transport-line-index question before anything
   depends on it.
3. **The mine.** Tiles, ore patches, drills, belts, intake, solar grid. Stock of the three
   ores starts climbing; prices visibly react. Confirms the intake half end-to-end.
4. **The production room.** Removes the top airlock, builds the sealed room, supply belts
   feeding assemblers from stock. Confirms the supply half end-to-end and starts draining
   plate stock.
5. **Research monopoly.** Instant trigger techs for Nauvis, propagation on
   `on_research_finished`, grant-on-founding, recipe bans, lab placement block,
   `item_filter` exclusions.

Phases 1 and 5 are the ones players will feel. Phases 2–4 are the machinery that makes
phase 5's demand signal real rather than a number in a table; until phase 4 lands, Nauvis
consumes nothing and plate prices never move on their own.

---

## 6. Risks and open questions

- **Ore inflation is unbounded.** Nauvis mines forever and never smelts, so ore stock
  climbs without limit and ore prices pin to the 1-credit floor within hours. That makes
  ore worthless to sell — arguably correct, since players should be selling *plates* — but
  it also means a player who buys a cheap ore, smelts it and sells the plate is running an
  infinite money printer bounded only by drill throughput. Watch the spread; the levers
  are drill count, and giving Nauvis furnaces so it converts its own ore.
- **Sold-out soft lock.** With a hard stop at zero and no strategic reserve, a coordinated
  or careless drain of iron plate stops every company that has not yet built smelting.
  Considered acceptable because the fix is available to any player with an ore patch, but
  the first playtest should watch for it. Cheap stopgap if it bites: floor plate stock at
  a small reserve purchasable at the 20× cap.
- **Research is a shared single point of failure.** If nobody sells Nauvis plates, nobody
  in the game researches anything, ever. This is the intended cooperative pressure, but in
  a small or antisocial multiplayer game it reads as the game being broken rather than as a
  problem to solve. Mitigation if needed: a slow trickle of Nauvis-mined ore auto-smelted
  into a minimum science rate, so progress is merely slow rather than stopped.
- **Unpaired underground belts.** See § 2. The single largest implementation unknown, and
  the reason phase 2 exists as its own step rather than being folded into phases 3 and 4.
- **`supply_demand.lua` double-counts.** See § 1. Kept deliberately; delete if prices
  oscillate.
- **Open — should Nauvis's stock be visible?** The Market window shows a price; it does not
  show that iron plate is down to 40 units. Showing stock makes the scarcity mechanic
  legible and turns the market into a shared dashboard; hiding it preserves price discovery
  as the game. Plan assumes **visible**, as a stock column in the Market window, because an
  invisible hard stop at zero is indistinguishable from a bug.
- **Open — do Nauvis's assemblers scale?** One gear assembler and one science assembler
  fix the research rate permanently. Nauvis expanding its own factory as stock allows is the
  natural sequel and is what `design-thinking.md` gestures at with "a very dumb AI player
  for nauvis". Out of scope here.
