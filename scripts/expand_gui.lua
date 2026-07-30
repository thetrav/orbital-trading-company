local utils = require("scripts.utils")
local market_gui = require("scripts.market_gui")
local platform = require("scripts.platform")

local M = {}

local HUB_COST = 1
local CORRIDOR_COST = 2
local FACTORY_COST = 4
local IRON_ASTEROID_COST = 6
local COPPER_ASTEROID_COST = 6
local ORBITAL_STATION_COST = 1
local WATER_CONNECTION_COST = 2

function M.create_expand_gui(player)
    if player.gui.screen.otc_expand_frame then
        player.gui.screen.otc_expand_frame.destroy()
    end

    local frame = player.gui.screen.add {
        type = "frame",
        name = "otc_expand_frame",
        direction = "vertical",
    }
    frame.auto_center = true
    frame.style.size = {220, 250}
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
        caption = "Expand",
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
        type = "button",
        name = "otc_expand_close",
        caption = "✕",
        style = "frame_action_button",
    }

    local inner = frame.add {
        type = "frame",
        name = "otc_expand_inner",
        style = "inside_deep_frame",
    }
    inner.style.horizontally_stretchable = true
    inner.style.vertically_stretchable = true
    inner.style.padding = 2

    local list = inner.add {
        type = "scroll-pane",
        name = "otc_expand_list",
        direction = "vertical",
    }
    list.style.horizontally_stretchable = true
    list.style.vertically_stretchable = true

    local buy_row = frame.add {
        type = "flow",
        name = "otc_expand_buy_row",
        direction = "horizontal",
    }
    buy_row.style.horizontally_stretchable = true
    buy_row.style.padding = 4

    local buy_button = buy_row.add {
        type = "button",
        name = "otc_expand_buy_button",
        caption = "Buy",
        style = "green_button",
        enabled = false,
    }
    buy_button.style.horizontally_stretchable = true

    M.rebuild(player)

    frame.visible = false
end

function M.rebuild(player)
    local frame = player.gui.screen.otc_expand_frame
    if not frame then return end
    local list = frame.otc_expand_inner and frame.otc_expand_inner.otc_expand_list
    if not list then return end

    for _, child in ipairs(list.children) do
        child.destroy()
    end

    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    local gate_key = player_data.active_gate
    if not gate_key then return end

    local gate_state = storage.gates and storage.gates[gate_key]
    if not gate_state then return end

    if gate_state.expanded then
        list.add {
            type = "label",
            caption = "Platform already expanded here.",
        }
        return
    end

    player_data.selected_shape = nil
    M.clear_preview(player_data)

    local function add_listing(sprite_tag, label, cost, shape_name)
        local row = list.add {
            type = "flow",
            direction = "horizontal",
        }
        row.style.vertical_align = "center"
        row.style.horizontally_stretchable = true

        row.add {
            type = "sprite",
            sprite = sprite_tag,
            ignored_by_interaction = true,
        }

        local btn = row.add {
            type = "button",
            name = "otc_shape_" .. shape_name,
            caption = label,
            style = "list_box_item",
            mouse_button_filter = {"left"},
        }
        btn.style.horizontally_stretchable = true

        local cost_label = row.add {
            type = "label",
            caption = "₾" .. cost,
            ignored_by_interaction = true,
        }
        cost_label.style.minimal_width = 35
        cost_label.style.horizontal_align = "right"
    end

    local is_nauvis = gate_state.surface_name == "nauvis"

    add_listing("item/gate", "Hub", HUB_COST, "hub")
    if is_nauvis then
        add_listing("item/rocket-silo", "Orbital station", ORBITAL_STATION_COST, "orbital_station")
    else
        add_listing("item/transport-belt", "Corridor", CORRIDOR_COST, "corridor")
        add_listing("item/assembling-machine-2", "Factory", FACTORY_COST, "factory")
        add_listing("item/iron-ore", "Iron Asteroid", IRON_ASTEROID_COST, "iron_asteroid")
        add_listing("item/copper-ore", "Copper Asteroid", COPPER_ASTEROID_COST, "copper_asteroid")
        add_listing("item/offshore-pump", "Water Connection", WATER_CONNECTION_COST, "water_connection")
    end

    local buy_button = frame.otc_expand_buy_row.otc_expand_buy_button
    if buy_button then
        buy_button.enabled = false
        buy_button.caption = "Buy"
    end
end

local function get_list(frame)
    if not frame then return nil end
    local inner = frame.otc_expand_inner
    if not inner then return nil end
    return inner.otc_expand_list
end

local function get_buy_button(frame)
    if not frame then return nil end
    local row = frame.otc_expand_buy_row
    if not row then return nil end
    return row.otc_expand_buy_button
end

local function clear_toggled(list)
    if not list then return end
    for _, child in ipairs(list.children) do
        if child.type == "button" or child.type == "sprite-button" then
            child.toggled = false
        end
    end
end

function M.handle_selection_change(player, shape)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    M.clear_preview(player_data)
    local frame = player.gui.screen.otc_expand_frame
    local list = get_list(frame)
    clear_toggled(list)

    if not shape then
        player_data.selected_shape = nil
        local btn = get_buy_button(frame)
        if btn then
            btn.enabled = false
            btn.caption = "Buy"
        end
        return
    end

    player_data.selected_shape = shape

    local btn = list and list["otc_shape_" .. shape]
    if btn then
        btn.toggled = true
    end

    local gate_key = player_data.active_gate
    if not gate_key then return end
    local gate_state = storage.gates and storage.gates[gate_key]
    if not gate_state then return end

    local surface = game.surfaces[gate_state.surface_name]
    player_data.preview_renderings = platform.show_preview(surface, player, gate_state.pos, shape)

    local buy_btn = get_buy_button(frame)
    if buy_btn then
        local cost = shape == "hub" and HUB_COST
            or shape == "corridor" and CORRIDOR_COST
            or shape == "factory" and FACTORY_COST
            or shape == "orbital_station" and ORBITAL_STATION_COST
            or shape == "water_connection" and WATER_CONNECTION_COST
            or shape == "iron_asteroid" and IRON_ASTEROID_COST
            or COPPER_ASTEROID_COST
        buy_btn.enabled = true
        buy_btn.caption = "Buy (₾" .. utils.format_number(cost) .. ")"
    end
end

function M.clear_preview(player_data)
    if player_data.preview_renderings then
        platform.clear_preview(player_data.preview_renderings)
        player_data.preview_renderings = nil
    end
end

function M.check_proximity(player)
    local frame = player.gui.screen.otc_expand_frame
    if not frame or not frame.visible then return end

    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    local gate_key = player_data.active_gate
    if not gate_key then
        M.close(player)
        return
    end

    local gate_state = storage.gates and storage.gates[gate_key]
    if not gate_state then
        M.close(player)
        return
    end

    local dx = player.position.x - gate_state.pos.x
    local dy = player.position.y - gate_state.pos.y
    if dx * dx + dy * dy > 36 then
        M.close(player)
    end
end

function M.handle_buy_expansion(player)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    local shape = player_data.selected_shape
    if not shape then
        player.print("Select a shape first!")
        return
    end

    local gate_key = player_data.active_gate
    if not gate_key then
        player.print("Select a gate first!")
        return
    end

    local gate_state = storage.gates and storage.gates[gate_key]
    if not gate_state or gate_state.expanded then
        player.print("Gate already expanded!")
        return
    end

    local company = storage.companies and storage.companies[player_data.company]
    local credits = company and company.credits or 0
    local cost = shape == "hub" and HUB_COST
        or shape == "corridor" and CORRIDOR_COST
        or shape == "factory" and FACTORY_COST
        or shape == "orbital_station" and ORBITAL_STATION_COST
        or shape == "water_connection" and WATER_CONNECTION_COST
        or shape == "iron_asteroid" and IRON_ASTEROID_COST
        or COPPER_ASTEROID_COST
    if cost > 0 and credits < cost then
        player.print("Not enough credits!")
        return
    end

    local surface = game.surfaces[gate_state.surface_name]
    local ok, err = platform.expand_from_gate(surface, gate_state.pos, shape, player.force.name)
    if ok then
        company.credits = company.credits - cost
        gate_state.expanded = true
        market_gui.update_all_forces_credits()
        player.print("Platform expanded!")
        M.close(player)
    elseif err then
        player.print(err)
    end
end

function M.show_for_gate(player, gate_state)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    M.clear_preview(player_data)
    player_data.selected_shape = nil

    player_data.active_gate = gate_state.key
    M.rebuild(player)

    local frame = player.gui.screen.otc_expand_frame
    if frame then
        frame.visible = true
    end
end

function M.close(player)
    local player_data = storage.players and storage.players[player.index]
    if player_data then
        M.clear_preview(player_data)
        player_data.active_gate = nil
        player_data.selected_shape = nil
    end

    local frame = player.gui.screen.otc_expand_frame
    if frame then
        frame.visible = false
    end
end

function M.init_player(player)
    M.create_expand_gui(player)
end

return M
