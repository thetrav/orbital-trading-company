local PLATFORM_SIZE = 10
local PLATFORM_HALF = PLATFORM_SIZE / 2
local STARTING_CREDITS = 1000
local BUY_CHEST_NAME = "otc-buy-chest"
local SELL_CHEST_NAME = "otc-sell-chest"
local COMBINATOR_NAME = "constant-combinator"
local BUY_CHEST_POSITION = { x = -4, y = 0 }
local COMBINATOR_POSITION = { x = -4, y = -1 }
local SELL_CHEST_POSITION = { x = 4, y = 0 }

local BASE_ORE_PRICE = 100
local TIME_COST_PER_SECOND = 10
local FURNACE_POWER = 90000
local COAL_FUEL_VALUE = 4000000
local BUY_MULTIPLIER = 1.05
local SELL_MULTIPLIER = 0.90

local ALLOWED_SUBGROUPS = {
    ["raw-resource"] = true,
    ["raw-material"] = true,
    ["intermediate-product"] = true,
}

local RESEARCH_FREE_SUBGROUPS = {
    ["raw-resource"] = true,
}

local function is_item_hidden(prototype)
    if not prototype.flags then return false end
    if type(prototype.flags) == "table" then
        if prototype.flags.hidden then return true end
        for _, flag in pairs(prototype.flags) do
            if flag == "hidden" then return true end
        end
    end
    return false
end

local function is_item_allowed(item_name, force)
    local prototype = prototypes.item[item_name]
    if not prototype then return false end
    if is_item_hidden(prototype) then return false end
    local subgroup = prototype.subgroup
    if not subgroup or not ALLOWED_SUBGROUPS[subgroup.name] then return false end
    if RESEARCH_FREE_SUBGROUPS[subgroup.name] then return true end
    for _, recipe in pairs(force.recipes) do
        if recipe.enabled then
            for _, product in pairs(recipe.products) do
                if product.name == item_name then
                    return true
                end
            end
        end
    end
    return false
end

local function get_allowed_items(force)
    local items = {}
    for name, prototype in pairs(prototypes.item) do
        if is_item_allowed(name, force) then
            table.insert(items, { name = name, prototype = prototype })
        end
    end
    table.sort(items, function(a, b) return a.prototype.order < b.prototype.order end)
    return items
end

local function is_in_platform(x, y)
    return x >= -PLATFORM_HALF and x < PLATFORM_HALF
       and y >= -PLATFORM_HALF and y < PLATFORM_HALF
end

local function build_platform(surface, area)
    local tiles = {}
    for x = area.left_top.x, area.right_bottom.x - 1 do
        for y = area.left_top.y, area.right_bottom.y - 1 do
            local tile_name = is_in_platform(x, y) and "concrete" or "out-of-map"
            table.insert(tiles, {name = tile_name, position = {x, y}})
        end
    end
    surface.set_tiles(tiles, true)
end

local function format_credits(amount)
    local formatted = tostring(amount)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

local function get_price(item_name)
    if storage.prices and storage.prices[item_name] then
        return storage.prices[item_name]
    end
    return BASE_ORE_PRICE
end

local function format_price(price)
    local formatted = tostring(price)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return formatted
end

local function calculate_recipe_cost(recipe, prices)
    local ingredient_cost = 0
    for _, ingredient in pairs(recipe.ingredients) do
        local price = prices[ingredient.name] or 0
        ingredient_cost = ingredient_cost + ingredient.amount * price
    end

    local fuel_cost = 0
    local ok, categories = pcall(function() return recipe.categories end)
    if ok and categories then
        for _, cat in pairs(categories) do
            if cat == "smelting" then
                fuel_cost = recipe.energy * FURNACE_POWER / COAL_FUEL_VALUE * (prices["coal"] or BASE_ORE_PRICE)
                break
            end
        end
    end

    local time_cost = recipe.energy * TIME_COST_PER_SECOND

    local total = ingredient_cost + fuel_cost + time_cost

    local total_results = 0
    for _, product in pairs(recipe.products) do
        total_results = total_results + product.amount
    end

    if total_results == 0 then return {} end

    local cost_per_unit = math.floor(total / total_results + 0.5)

    local result_costs = {}
    for _, product in pairs(recipe.products) do
        result_costs[product.name] = cost_per_unit
    end
    return result_costs
end

local function calculate_prices()
    local prices = {}
    local item_depth = {}

    for name, prototype in pairs(prototypes.item) do
        if prototype.subgroup and prototype.subgroup.name == "raw-resource" then
            prices[name] = BASE_ORE_PRICE
            item_depth[name] = 0
        end
    end

    for _, recipe in pairs(prototypes.recipe) do
        if recipe.enabled then
            local result_costs = calculate_recipe_cost(recipe, prices)
            for result_name, cost in pairs(result_costs) do
                if not prices[result_name] then
                    prices[result_name] = cost
                    item_depth[result_name] = 0
                end
            end
        end
    end

    local processed_techs = {}
    local remaining_techs = {}
    for name, tech in pairs(prototypes.technology) do
        remaining_techs[name] = tech
    end

    local max_iterations = 100
    local iteration = 0
    while next(remaining_techs) and iteration < max_iterations do
        iteration = iteration + 1
        local level_techs = {}

        for name, tech in pairs(remaining_techs) do
            local all_prereqs_met = true
            for _, prereq in pairs(tech.prerequisites) do
                if not processed_techs[prereq.name] then
                    all_prereqs_met = false
                    break
                end
            end
            if all_prereqs_met then
                table.insert(level_techs, tech)
            end
        end

        if #level_techs == 0 then break end

        for _, tech in pairs(level_techs) do
            processed_techs[tech.name] = true
            remaining_techs[tech.name] = nil

            for _, effect in pairs(tech.effects) do
                if effect.type == "unlock-recipe" then
                    local recipe = prototypes.recipe[effect.recipe]
                    if recipe then
                        local result_costs = calculate_recipe_cost(recipe, prices)
                        for result_name, cost in pairs(result_costs) do
                            if not prices[result_name] then
                                prices[result_name] = cost
                                item_depth[result_name] = iteration
                            elseif item_depth[result_name] == iteration then
                                if cost < prices[result_name] then
                                    prices[result_name] = cost
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return prices
end

local function create_credits_gui(player)
    if player.gui.screen.otc_credits_frame then
        player.gui.screen.otc_credits_frame.destroy()
    end

    local frame = player.gui.screen.add {
        type = "frame",
        name = "otc_credits_frame",
        direction = "vertical",
    }
    frame.style.size = {120, 70}
    frame.style.padding = 4
    frame.style.bottom_padding = 8

    local title_flow = frame.add {
        type = "flow",
        name = "title_flow",
        direction = "horizontal",
    }
    title_flow.style.vertical_align = "center"
    title_flow.drag_target = frame

    title_flow.add {
        type = "label",
        style = "frame_title",
        caption = "Credits",
        ignored_by_interaction = true,
    }

    local drag = title_flow.add {
        type = "empty-widget",
        style = "draggable_space",
        ignored_by_interaction = true,
    }
    drag.style.height = 24
    drag.style.horizontally_stretchable = true

    local player_data = storage.players and storage.players[player.index]
    local credits = player_data and player_data.credits or STARTING_CREDITS
    local label = frame.add {
        type = "label",
        name = "otc_credits_label",
        caption = format_credits(credits),
    }
    label.style.font = "default-listbox"
    label.style.horizontal_align = "center"
    label.style.horizontally_stretchable = true

    return frame
end

local function rebuild_market_list(player)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    local frame = player.gui.screen.otc_market_frame
    if not frame then return end

    local search = ""
    local search_frame = frame.otc_market_search_frame
    if search_frame and search_frame.visible then
        local field = search_frame.otc_market_search
        if field and field.text then
            search = string.lower(field.text)
        end
    end

    local old_inner = frame.otc_market_inner
    if old_inner then old_inner.destroy() end

    local inner = frame.add {
        type = "frame",
        name = "otc_market_inner",
        style = "inside_deep_frame",
    }
    inner.style.horizontally_stretchable = true
    inner.style.vertically_stretchable = true
    inner.style.padding = 2

    local list = inner.add {
        type = "scroll-pane",
        name = "otc_market_list",
        direction = "vertical",
    }
    list.style.height = 420
    list.style.horizontally_stretchable = true

    for _, item in pairs(player_data.allowed_items) do
        if search == "" or string.find(string.lower(item.name), search, 1, true) then
            local row = list.add {
                type = "flow",
                direction = "horizontal",
            }
            row.style.vertical_align = "center"

            row.add {
                type = "sprite-button",
                style = "slot_button",
            }

            row.add {
                type = "sprite",
                sprite = "item/" .. item.name,
            }

            row.add {
                type = "label",
                caption = "₾" .. format_price(math.floor(get_price(item.name) * BUY_MULTIPLIER + 0.5)),
            }
        end
    end
end

local function create_market_gui(player)
    if player.gui.screen.otc_market_frame then
        player.gui.screen.otc_market_frame.destroy()
    end

    local frame = player.gui.screen.add {
        type = "frame",
        name = "otc_market_frame",
        direction = "vertical",
        style = "frame",
    }
    frame.style.size = {180, 500}
    frame.style.padding = 4

    local title_flow = frame.add {
        type = "flow",
        name = "title_flow",
        direction = "horizontal",
    }
    title_flow.style.vertical_align = "center"
    title_flow.drag_target = frame

    title_flow.add {
        type = "label",
        style = "frame_title",
        caption = "Market",
        ignored_by_interaction = true,
    }

    local drag = title_flow.add {
        type = "empty-widget",
        style = "draggable_space",
        ignored_by_interaction = true,
    }
    drag.style.height = 24
    drag.style.horizontally_stretchable = true

    title_flow.add {
        type = "sprite-button",
        name = "otc_market_search_button",
        style = "tool_button",
        sprite = "utility/search",
    }

    local search_flow = frame.add {
        type = "flow",
        name = "otc_market_search_frame",
        direction = "horizontal",
    }
    search_flow.style.horizontally_stretchable = true
    search_flow.visible = false

    search_flow.add {
        type = "sprite",
        sprite = "utility/search",
    }

    local search_field = search_flow.add {
        type = "textfield",
        name = "otc_market_search",
    }
    search_field.style.horizontally_stretchable = true

    local player_data = storage.players and storage.players[player.index]
    if player_data then
        player_data.allowed_items = get_allowed_items(player.force)
    end

    rebuild_market_list(player)

    return frame
end

local function init_player(player)
    storage.players = storage.players or {}
    if not storage.players[player.index] then
        storage.players[player.index] = { credits = STARTING_CREDITS }
    end
    create_credits_gui(player)
    create_market_gui(player)
end

local function update_credits_gui(player_index)
    local player = game.get_player(player_index)
    if not player then return end
    local frame = player.gui.screen.otc_credits_frame
    if not frame then return end
    local label = frame.otc_credits_label
    if not label then return end
    local player_data = storage.players and storage.players[player_index]
    local credits = player_data and player_data.credits or 0
    label.caption = format_credits(credits)
end

local function find_combinator_above(chest)
    local pos = chest.position
    local search_area = {
        { pos.x - 0.5, pos.y - 1.5 },
        { pos.x + 0.5, pos.y - 0.5 },
    }
    local entities = chest.surface.find_entities_filtered {
        area = search_area,
        name = COMBINATOR_NAME,
        force = chest.force,
    }
    return entities[1]
end

local function connect_combinator_to_chest(combinator, chest)
    if combinator and combinator.valid and chest and chest.valid then
        local combinator_out = combinator.get_wire_connector(defines.wire_connector_id.circuit_green, true)
        local chest_in = chest.get_wire_connector(defines.wire_connector_id.circuit_green, true)
        if combinator_out and chest_in then
            combinator_out.connect_to(chest_in, false, defines.wire_origin.player)
        end
    end
end

local function register_buy_chest(entity)
    if not entity or not entity.valid then return end
    if entity.name ~= BUY_CHEST_NAME then return end

    local cb = entity.get_or_create_control_behavior()
    cb.read_contents = false

    local combinator = find_combinator_above(entity)
    if not combinator then return end

    connect_combinator_to_chest(combinator, entity)

    storage.buy_chests = storage.buy_chests or {}
    storage.buy_chests[entity.unit_number] = {
        chest = entity,
        combinator = combinator,
    }
end

local function unregister_buy_chest(unit_number)
    if not storage.buy_chests then return end
    storage.buy_chests[unit_number] = nil
end

local function register_sell_chest(entity)
    if not entity or not entity.valid then return end
    if entity.name ~= SELL_CHEST_NAME then return end

    storage.sell_chests = storage.sell_chests or {}
    storage.sell_chests[entity.unit_number] = entity
end

local function unregister_sell_chest(unit_number)
    if not storage.sell_chests then return end
    storage.sell_chests[unit_number] = nil
end

local function process_sell_chests()
    if not storage.sell_chests then return end

    for unit_number, chest in pairs(storage.sell_chests) do
        if not chest.valid then
            storage.sell_chests[unit_number] = nil
        else
            local inventory = chest.get_inventory(defines.inventory.chest)
            local contents = inventory.get_contents()
            if #contents > 0 then
                local player = game.connected_players[1]
                if player then
                    local player_data = storage.players and storage.players[player.index]
                    if player_data then
                        for _, item in pairs(contents) do
                            if is_item_allowed(item.name, chest.force) then
                                local removed = inventory.remove({ name = item.name, count = item.count })
                                if removed > 0 then
                                    local sell_value = math.floor(removed * get_price(item.name) * SELL_MULTIPLIER + 0.5)
                                    player_data.credits = player_data.credits + sell_value
                                    update_credits_gui(player.index)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function read_circuit_signals(chest)
    local signals = {}
    local green_id = chest.get_circuit_network(defines.wire_connector_id.circuit_green)
    if green_id then
        for _, sig in pairs(green_id.signals or {}) do
            if sig.signal and sig.signal.name then
                signals[sig.signal.name] = (signals[sig.signal.name] or 0) + sig.count
            end
        end
    end
    local red_id = chest.get_circuit_network(defines.wire_connector_id.circuit_red)
    if red_id then
        for _, sig in pairs(red_id.signals or {}) do
            if sig.signal and sig.signal.name then
                signals[sig.signal.name] = (signals[sig.signal.name] or 0) + sig.count
            end
        end
    end
    return signals
end

local function process_buy_chests()
    if not storage.buy_chests then return end

    for unit_number, data in pairs(storage.buy_chests) do
        if not data.chest.valid or not data.combinator.valid then
            storage.buy_chests[unit_number] = nil
        else
            local signals = read_circuit_signals(data.chest)
            local cb = data.chest.get_or_create_control_behavior()
            if cb.read_contents then cb.read_contents = false end
            if next(signals) then
                local inventory = data.chest.get_inventory(defines.inventory.chest)

                for item_name, desired in pairs(signals) do
                    if is_item_allowed(item_name, data.chest.force) then
                        local current = inventory.get_item_count(item_name)
                        local deficit = desired - current

                        if deficit > 0 then
                            local player = game.connected_players[1]
                            if player then
                                local player_data = storage.players and storage.players[player.index]
                                if player_data then
                                    local buy_price = math.floor(get_price(item_name) * BUY_MULTIPLIER + 0.5)
                                    local can_afford = math.floor(player_data.credits / buy_price)
                                    local to_buy = math.min(deficit, can_afford)
                                    if to_buy > 0 then
                                        local inserted = inventory.insert({ name = item_name, count = to_buy })
                                        if inserted > 0 then
                                            player_data.credits = player_data.credits - inserted * buy_price
                                            update_credits_gui(player.index)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

script.on_init(function()
    if remote.interfaces["freeplay"] then
        remote.call("freeplay", "set_skip_intro", true)
        remote.call("freeplay", "set_disable_crashsite", true)
    end

    storage.players = {}

    local surface = game.surfaces[1]
    game.map_settings.pollution.enabled = false
    game.map_settings.enemy_expansion.enabled = false

    local mgs = surface.map_gen_settings
    mgs.width = 0
    mgs.height = 0
    mgs.starting_area = 0
    mgs.terrain_segmentation = 0
    mgs.water = 0
    mgs.cliff_settings.cliff_elevation_interval = 0
    mgs.cliff_settings.richness = 0
    mgs.peaceful_mode = true
    mgs.no_enemies_mode = true
    mgs.autoplace_controls = {}
    surface.map_gen_settings = mgs

    local radius = 160
    build_platform(surface, {
        left_top = {x = -radius, y = -radius},
        right_bottom = {x = radius, y = radius}
    })

    for _, player in pairs(game.connected_players) do
        player.teleport({0.5, 0.5}, surface)
        init_player(player)
    end

    local combinator = surface.create_entity {
        name = COMBINATOR_NAME,
        position = COMBINATOR_POSITION,
        force = "player",
    }
    if combinator then
        combinator.minable = false
        combinator.destructible = false

        local behaviour = combinator.get_or_create_control_behavior()
        local section = behaviour.get_section(1)
        section.set_slot(1, { value = { type = "item", name = "iron-ore", quality = "normal" }, min = 1 })
        section.set_slot(2, { value = { type = "item", name = "coal", quality = "normal" }, min = 1 })
    end

    local chest = surface.create_entity {
        name = BUY_CHEST_NAME,
        position = BUY_CHEST_POSITION,
        force = "player",
    }
    if chest then
        chest.minable = false
        chest.destructible = false
        register_buy_chest(chest)
    end

    local sell_chest = surface.create_entity {
        name = SELL_CHEST_NAME,
        position = SELL_CHEST_POSITION,
        force = "player",
    }
    if sell_chest then
        sell_chest.minable = false
        sell_chest.destructible = false
        register_sell_chest(sell_chest)
    end

    storage.prices = calculate_prices()
end)

script.on_load(function()
    storage.prices = calculate_prices()
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    init_player(player)
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if player and not player.gui.screen.otc_credits_frame then
        init_player(player)
    end
end)

script.on_event(defines.events.on_chunk_generated, function(event)
    if event.surface.index ~= 1 then return end
    build_platform(event.surface, event.area)
end)

script.on_nth_tick(1, function()
    process_buy_chests()
    process_sell_chests()
end)

script.on_event(defines.events.on_built_entity, function(event)
    register_buy_chest(event.created_entity)
    register_sell_chest(event.created_entity)
end)

script.on_event(defines.events.on_entity_died, function(event)
    if event.entity.name == BUY_CHEST_NAME then
        unregister_buy_chest(event.entity.unit_number)
    elseif event.entity.name == SELL_CHEST_NAME then
        unregister_sell_chest(event.entity.unit_number)
    end
end)

script.on_event(defines.events.on_player_mined_entity, function(event)
    if event.entity.name == BUY_CHEST_NAME then
        unregister_buy_chest(event.entity.unit_number)
    elseif event.entity.name == SELL_CHEST_NAME then
        unregister_sell_chest(event.entity.unit_number)
    end
end)

script.on_event(defines.events.on_gui_click, function(event)
    if event.element.name == "otc_market_search_button" then
        local player = game.get_player(event.player_index)
        if not player then return end
        local frame = player.gui.screen.otc_market_frame
        if not frame then return end
        local search_frame = frame.otc_market_search_frame
        if not search_frame then return end
        search_frame.visible = not search_frame.visible
        if not search_frame.visible then
            local field = search_frame.otc_market_search
            if field then field.text = "" end
            rebuild_market_list(player)
        end
    end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
    if event.element.name == "otc_market_search" then
        local player = game.get_player(event.player_index)
        if player then
            rebuild_market_list(player)
        end
    end
end)
