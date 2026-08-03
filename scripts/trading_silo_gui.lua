local trading_silo = require("scripts.trading_silo")
local item_filter = require("scripts.item_filter")

local M = {}

local WIRES = { "green", "red", "both" }

local function player_data(player)
    storage.players = storage.players or {}
    storage.players[player.index] = storage.players[player.index] or {}
    return storage.players[player.index]
end

local function silo_of(player)
    local data = player_data(player)
    if not data.trading_silo_unit then return nil end
    local silo = trading_silo.get(data.trading_silo_unit)
    if not silo or not silo.entity.valid then return nil end
    return silo
end

local function frame_of(player)
    return player.gui.relative.otc_silo_frame
end

local function add_order_row(parent, side, index, order, editable)
    local row = parent.add { type = "flow", direction = "horizontal" }
    row.style.vertical_align = "center"
    row.style.horizontally_stretchable = true

    row.add {
        type = "sprite-button",
        sprite = "item/" .. order.item,
        style = "transparent_slot",
        tooltip = order.item,
        ignored_by_interaction = true,
    }

    local label = row.add { type = "label", caption = prototypes.item[order.item].localised_name }
    label.style.width = 110

    if side == "buy" then
        if editable then
            local field = row.add {
                type = "textfield",
                name = "otc_silo_qty_" .. index,
                numeric = true,
                allow_decimal = false,
                allow_negative = false,
                text = tostring(order.quantity),
            }
            field.style.width = 60
        else
            local quantity = row.add { type = "label", caption = tostring(order.quantity) }
            quantity.style.width = 60
        end
    end

    local spacer = row.add { type = "empty-widget" }
    spacer.style.horizontally_stretchable = true

    if editable then
        row.add {
            type = "sprite-button",
            name = "otc_silo_up_" .. side .. "_" .. index,
            sprite = "utility/speed_up",
            style = "mini_button",
            tooltip = "Move up",
        }
        row.add {
            type = "sprite-button",
            name = "otc_silo_down_" .. side .. "_" .. index,
            sprite = "utility/speed_down",
            style = "mini_button",
            tooltip = "Move down",
        }
        row.add {
            type = "sprite-button",
            name = "otc_silo_del_" .. side .. "_" .. index,
            sprite = "utility/trash",
            style = "mini_button",
            tooltip = "Remove",
        }
    end
end

local function rebuild_lists(player)
    local frame = frame_of(player)
    local silo = silo_of(player)
    if not frame or not silo then return end

    local editable = not silo.circuit.enabled
    local buy, sell = trading_silo.resolve(silo)
    if editable then
        buy, sell = silo.buy, silo.sell
    end

    local lists = { buy = buy, sell = sell }
    local panels = frame.otc_silo_content.otc_silo_panels
    for _, side in ipairs({ "buy", "sell" }) do
        local panel = panels[side]
        local scroll = panel["otc_silo_" .. side .. "_list"]
        for _, child in ipairs(scroll.children) do child.destroy() end
        for index, order in ipairs(lists[side]) do
            add_order_row(scroll, side, index, order, editable)
        end
        panel["otc_silo_add_flow_" .. side].visible = editable
    end
end

local function rebuild_circuit(player)
    local frame = frame_of(player)
    local silo = silo_of(player)
    if not frame or not silo then return end

    local flow = frame.otc_silo_content.otc_silo_circuit_flow
    flow.otc_silo_circuit.state = silo.circuit.enabled
    for _, wire in ipairs(WIRES) do
        local button = flow.otc_silo_wire_flow["otc_silo_wire_" .. wire]
        button.state = silo.circuit.wire == wire
        button.enabled = silo.circuit.enabled
    end
end

--- Only circuit-driven lists change on their own; a configured one only changes
--- when the player changes it, and rebuilding it under them would fight the
--- textfield they are typing in.
function M.refresh(player)
    local frame = frame_of(player)
    if not frame then return end
    local silo = silo_of(player)
    if not silo then
        M.close(player)
        return
    end
    if silo.circuit.enabled then
        rebuild_lists(player)
    end
end

function M.close(player)
    local frame = frame_of(player)
    if frame then frame.destroy() end
    player_data(player).trading_silo_unit = nil
end

--- Anchored beside the entity's own window rather than replacing it, so the
--- silo keeps the vanilla container GUI: the player's inventory on the right,
--- shift-click transfers, filters and all.
function M.open(player, entity)
    local silo = trading_silo.get(entity.unit_number)
    if not silo then
        silo = trading_silo.register(entity)
        if not silo then return end
    end

    M.close(player)

    local data = player_data(player)
    data.trading_silo_unit = entity.unit_number
    data.allowed_items = item_filter.get_allowed_items(player.force)

    local frame = player.gui.relative.add {
        type = "frame",
        name = "otc_silo_frame",
        caption = "Trading",
        direction = "vertical",
        anchor = {
            gui = defines.relative_gui_type.container_gui,
            position = defines.relative_gui_position.right,
            name = trading_silo.NAME,
        },
    }

    local content = frame.add {
        type = "frame",
        name = "otc_silo_content",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding",
    }

    local circuit_flow = content.add {
        type = "flow", name = "otc_silo_circuit_flow", direction = "vertical",
    }
    circuit_flow.add {
        type = "checkbox",
        name = "otc_silo_circuit",
        caption = "Control with circuit network",
        state = false,
        tooltip = "A positive signal is a quantity to maintain, a negative signal sells all of that item.",
    }
    local wire_flow = circuit_flow.add {
        type = "flow", name = "otc_silo_wire_flow", direction = "horizontal",
    }
    for _, wire in ipairs(WIRES) do
        local button = wire_flow.add {
            type = "radiobutton",
            name = "otc_silo_wire_" .. wire,
            caption = wire:sub(1, 1):upper() .. wire:sub(2),
            state = false,
        }
        button.style.right_margin = 8
    end

    content.add { type = "line" }

    local panels = content.add { type = "flow", name = "otc_silo_panels", direction = "horizontal" }
    for _, side in ipairs({ "buy", "sell" }) do
        local panel = panels.add { type = "flow", name = side, direction = "vertical" }
        panel.style.width = 290
        panel.add {
            type = "label",
            caption = side == "buy" and "Buy orders" or "Sell orders",
            style = "bold_label",
        }
        local scroll = panel.add {
            type = "scroll-pane",
            name = "otc_silo_" .. side .. "_list",
            direction = "vertical",
        }
        scroll.style.height = 300
        scroll.style.horizontally_stretchable = true
        local add_flow = panel.add {
            type = "flow", name = "otc_silo_add_flow_" .. side, direction = "horizontal",
        }
        add_flow.style.vertical_align = "center"
        add_flow.add {
            type = "choose-elem-button",
            name = "otc_silo_add_" .. side,
            elem_type = "item",
            tooltip = side == "buy" and "Add a buy order" or "Add a sell order",
        }
        local add_label = add_flow.add {
            type = "label",
            caption = side == "buy" and "Add buy order" or "Add sell order",
        }
        add_label.style.left_margin = 4
    end

    rebuild_circuit(player)
    rebuild_lists(player)
end

local function parse(name, prefix)
    local side, index = name:match("^" .. prefix .. "_(%a+)_(%d+)$")
    if not side then return nil end
    return side, tonumber(index)
end

function M.on_click(player, element)
    local silo = silo_of(player)
    if not silo or silo.circuit.enabled then return false end

    local side, index = parse(element.name, "otc_silo_del")
    if side then
        trading_silo.remove(silo, side, index)
        rebuild_lists(player)
        return true
    end

    side, index = parse(element.name, "otc_silo_up")
    if side then
        trading_silo.move(silo, side, index, -1)
        rebuild_lists(player)
        return true
    end

    side, index = parse(element.name, "otc_silo_down")
    if side then
        trading_silo.move(silo, side, index, 1)
        rebuild_lists(player)
        return true
    end

    return false
end

function M.on_elem_changed(player, element)
    local side = element.name:match("^otc_silo_add_(%a+)$")
    if not side then return false end

    local silo = silo_of(player)
    local item_name = element.elem_value
    element.elem_value = nil
    if not silo or not item_name then return true end

    if not item_filter.is_item_allowed(item_name, player.force) then
        player.print(item_name .. " cannot be traded.")
        return true
    end
    if trading_silo.is_listed(silo, item_name) then
        player.print(item_name .. " is already on a buy or sell list.")
        return true
    end

    if side == "buy" then
        trading_silo.add_buy(silo, item_name, 1)
    else
        trading_silo.add_sell(silo, item_name)
    end
    rebuild_lists(player)
    return true
end

function M.on_text_changed(player, element)
    local index = element.name:match("^otc_silo_qty_(%d+)$")
    if not index then return false end
    local silo = silo_of(player)
    if not silo or silo.circuit.enabled then return true end
    trading_silo.set_quantity(silo, tonumber(index), tonumber(element.text) or 1)
    return true
end

function M.on_checked(player, element)
    local silo = silo_of(player)
    if not silo then return false end

    if element.name == "otc_silo_circuit" then
        silo.circuit.enabled = element.state
        rebuild_circuit(player)
        rebuild_lists(player)
        return true
    end

    local wire = element.name:match("^otc_silo_wire_(%a+)$")
    if wire then
        silo.circuit.wire = wire
        rebuild_circuit(player)
        rebuild_lists(player)
        return true
    end

    return false
end

--- The entity's window closing takes the anchored panel with it.
function M.on_closed(player, entity)
    if not entity or not entity.valid or entity.name ~= trading_silo.NAME then return false end
    M.close(player)
    return true
end

return M
