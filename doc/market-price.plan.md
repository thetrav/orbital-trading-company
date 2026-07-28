# Dynamic Market Pricing Plan

## Overview

Replace hardcoded 1-credit-per-item pricing with a dynamic system calculated at game start based on recipes, crafting time, and fuel costs. Uses BFS through the tech tree to determine recipe priority.

## Algorithm

### BFS Tech Tree Traversal
1. Raw resources (`raw-resource` subgroup) = 100 credits each (base price)
2. Process enabled recipes (depth 0, no tech needed)
3. BFS through technologies level-by-level: process a tech only when ALL prerequisites are done
4. For each recipe unlocked at a level, calculate cost; assign to results if unpriced or cheaper at same depth
5. If an item has multiple recipes at the same BFS depth, use the cheapest

### Recipe Cost Formula
```
ingredient_cost = sum(ingredient.amount * prices[ingredient.name])
fuel_cost = energy_required * 90000 / 4000000 * coal_price  (smelting only)
time_cost = energy_required * TIME_COST_PER_SECOND
total = ingredient_cost + fuel_cost + time_cost
price_per_unit = total / sum(result.amounts)
```

### Buy/Sell Spread
- Buy price = ceil(price * 1.05)  (105% of base)
- Sell price = floor(price * 0.90) (90% of base)

All prices are integers. No fractional credits.

## Constants

```lua
local BASE_ORE_PRICE = 100
local TIME_COST_PER_SECOND = 10
local FURNACE_POWER = 90000        -- stone furnace watts
local COAL_FUEL_VALUE = 4000000    -- 4MJ
local BUY_MULTIPLIER = 1.05
local SELL_MULTIPLIER = 0.90
```

## Example Prices

| Item         | Base | Buy (105%) | Sell (90%) |
|--------------|------|------------|------------|
| Iron ore     | 100  | 105        | 90         |
| Coal         | 100  | 105        | 90         |
| Iron plate   | 139  | 146        | 125        |
| Steel plate  | 891  | 936        | 801        |
| Iron gear    | 283  | 298        | 254        |

## Implementation

### Files Modified
- `control.lua` — all changes in this single file

### New Constants (top of file)
- `BASE_ORE_PRICE = 100`
- `TIME_COST_PER_SECOND = 10`
- `FURNACE_POWER = 90000`
- `COAL_FUEL_VALUE = 4000000`
- `BUY_MULTIPLIER = 1.05`
- `SELL_MULTIPLIER = 0.90`

### New Functions
| Function | Purpose |
|----------|---------|
| `calculate_recipe_cost(recipe, prices)` | Returns `{[result_name] = cost_per_unit}` |
| `calculate_prices()` | BFS traversal, returns full prices table |
| `get_price(item_name)` | Returns `storage.prices[name]` or `BASE_ORE_PRICE` |
| `format_price(price)` | Formats as `"₾139"`, `"₾1,200"` |

### Modified Functions
| Function | Change |
|----------|--------|
| `on_init` | Call `calculate_prices()`, store in `storage.prices` |
| `on_load` | Recalculate prices (handles mod updates) |
| `process_buy_chests` | `credits - count * get_price(name) * BUY_MULTIPLIER` |
| `process_sell_chests` | `credits + count * get_price(name) * SELL_MULTIPLIER` |
| `rebuild_market_list` | Show `format_price(get_price(name) * BUY_MULTIPLIER)` |
