local utils = require("scripts.utils")
local market_gui = require("scripts.market_gui")
local platform = require("scripts.platform")

local M = {}

local EXPANSION_COST = 1

function M.create_store_gui(player)
    if player.gui.screen.otc_store_frame then
        player.gui.screen.otc_store_frame.destroy()
    end

    local frame = player.gui.screen.add {
        type = "frame",
        name = "otc_store_frame",
        direction = "vertical",
    }
    frame.style.size = {280, 160}
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
        caption = "Shop",
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
        name = "otc_store_close",
        caption = "✕",
        style = "frame_action_button",
    }

    local inner = frame.add {
        type = "frame",
        name = "otc_store_inner",
        style = "inside_deep_frame",
    }
    inner.style.horizontally_stretchable = true
    inner.style.vertically_stretchable = true
    inner.style.padding = 2

    local list = inner.add {
        type = "scroll-pane",
        name = "otc_store_list",
        direction = "vertical",
    }
    list.style.horizontally_stretchable = true
    list.style.height = 80

    M.rebuild(player)

    frame.visible = false
end

function M.rebuild(player)
    local frame = player.gui.screen.otc_store_frame
    if not frame then return end
    local list = frame.otc_store_inner and frame.otc_store_inner.otc_store_list
    if not list then return end

    for _, child in ipairs(list.children) do
        child.destroy()
    end

    local gate_key = storage.players and storage.players[player.index]
        and storage.players[player.index].active_gate

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

    local row = list.add {
        type = "flow",
        direction = "horizontal",
    }
    row.style.vertical_align = "center"

    row.add {
        type = "sprite",
        sprite = "item/gate",
    }

    row.add {
        type = "label",
        caption = "Platform Expansion",
    }

    row.add {
        type = "label",
        caption = "₾" .. utils.format_number(EXPANSION_COST),
    }

    row.add {
        type = "button",
        name = "otc_store_buy_expansion",
        caption = "Buy",
    }
end

function M.handle_buy_expansion(player)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

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

    if player_data.credits < EXPANSION_COST then
        player.print("Not enough credits!")
        return
    end

    local surface = game.surfaces[1]
    local ok, err = platform.expand_from_gate(surface, gate_state.pos)
    if ok then
        player_data.credits = player_data.credits - EXPANSION_COST
        gate_state.expanded = true
        market_gui.update_credits_gui(player.index)
        player.print("Platform expanded!")
        M.close(player)
    elseif err then
        player.print(err)
    end
end

function M.show_for_gate(player, gate_state)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    player_data.active_gate = gate_state.key
    M.rebuild(player)

    local frame = player.gui.screen.otc_store_frame
    if frame then
        frame.visible = true
    end
end

function M.close(player)
    local player_data = storage.players and storage.players[player.index]
    if player_data then
        player_data.active_gate = nil
    end

    local frame = player.gui.screen.otc_store_frame
    if frame then
        frame.visible = false
    end
end

function M.init_player(player)
    M.create_store_gui(player)
end

return M
