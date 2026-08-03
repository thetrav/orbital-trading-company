local mock = require("test.factorio_mock")

local GREEN = 3
local RED = 4

local function setup_globals()
    _G.game = { forces = {}, connected_players = {}, players = {} }
    _G.storage = {}
    _G.defines = {
        inventory = { chest = 1 },
        wire_connector_id = { circuit_green = GREEN, circuit_red = RED },
        input_action = { start_research = 1, cancel_research = 2, move_research = 3 },
        relative_gui_type = { container_gui = "container_gui" },
        relative_gui_position = { right = "right" },
    }
    _G.prototypes = { item = {} }
    for order, name in ipairs({ "iron-ore", "copper-ore", "stone" }) do
        _G.prototypes.item[name] = {
            name = name,
            type = "item",
            order = tostring(order),
            localised_name = name,
            subgroup = { name = "raw-resource" },
        }
    end
end

local function load_modules()
    for _, name in ipairs({
        "scripts.trading_silo", "scripts.trading_silo_gui", "scripts.utils", "scripts.stock",
        "scripts.nauvis", "scripts.supply_demand", "scripts.trading_history",
        "scripts.item_filter", "scripts.research",
    }) do
        package.loaded[name] = nil
    end
    local trading_silo = require("scripts.trading_silo")
    trading_silo.init()
    return trading_silo, require("scripts.trading_silo_gui")
end

local function make_player(signals)
    local force = { name = "Acme", recipes = {} }
    _G.game.forces["Acme"] = force
    local entity = {
        valid = true,
        name = "otc-trading-silo",
        unit_number = 1,
        force = force,
        get_circuit_network = function(connector)
            if not signals or not signals[connector] then return nil end
            return { signals = signals[connector] }
        end,
    }
    local player = {
        index = 1,
        force = force,
        gui = { relative = mock.gui_root() },
        printed = {},
    }
    player.print = function(message) player.printed[#player.printed + 1] = message end
    return player, entity
end

local function frame(player) return player.gui.relative.otc_silo_frame end
local function orders(player) return frame(player).otc_silo_content end
local function panel(player, side) return orders(player).otc_silo_panels[side] end
local function add_flow(player, side) return panel(player, side)["otc_silo_add_flow_" .. side] end
local function picker(player, side) return add_flow(player, side)["otc_silo_add_" .. side] end
local function rows(player, side) return panel(player, side)["otc_silo_" .. side .. "_list"].children end

describe("trading silo gui", function()
    local trading_silo, gui, player, entity

    before_each(function()
        setup_globals()
        trading_silo, gui = load_modules()
        player, entity = make_player()
    end)

    after_each(function()
        mock.teardown()
    end)

    it("anchors beside the container window instead of replacing it", function()
        gui.open(player, entity)

        assert.is_true(frame(player) ~= nil)
        assert.is_nil(player.opened, "the vanilla window must be left alone")
        assert.equals("container_gui", frame(player).anchor.gui)
        assert.equals("otc-trading-silo", frame(player).anchor.name)
        assert.is_true(panel(player, "buy") ~= nil)
        assert.is_true(panel(player, "sell") ~= nil)
    end)

    it("registers a silo that was never built through a hook", function()
        gui.open(player, entity)
        assert.is_true(trading_silo.get(1) ~= nil)
    end)

    it("adds a buy order through the picker and gives it a quantity field", function()
        gui.open(player, entity)
        local button = picker(player, "buy")
        button.elem_value = "iron-ore"
        gui.on_elem_changed(player, button)

        local data = trading_silo.get(1)
        assert.equals(1, #data.buy)
        assert.equals("iron-ore", data.buy[1].item)
        assert.equals(1, #rows(player, "buy"))
        assert.is_nil(button.elem_value, "picker should clear after a pick")

        local field = rows(player, "buy")[1].otc_silo_qty_1
        assert.is_true(field ~= nil)
        field.text = "250"
        gui.on_text_changed(player, field)
        assert.equals(250, data.buy[1].quantity)
    end)

    it("refuses an item that is already listed on the other side", function()
        gui.open(player, entity)
        local sell_picker = picker(player, "sell")
        sell_picker.elem_value = "copper-ore"
        gui.on_elem_changed(player, sell_picker)

        local buy_picker = picker(player, "buy")
        buy_picker.elem_value = "copper-ore"
        gui.on_elem_changed(player, buy_picker)

        local data = trading_silo.get(1)
        assert.equals(0, #data.buy)
        assert.equals(1, #data.sell)
        assert.equals(1, #player.printed)
    end)

    it("reorders and deletes rows from their buttons", function()
        gui.open(player, entity)
        local data = trading_silo.get(1)
        trading_silo.add_buy(data, "iron-ore", 1)
        trading_silo.add_buy(data, "copper-ore", 2)
        gui.on_checked(player, orders(player).otc_silo_circuit_flow.otc_silo_circuit)
        gui.on_checked(player, orders(player).otc_silo_circuit_flow.otc_silo_circuit)

        gui.on_click(player, rows(player, "buy")[2].otc_silo_up_buy_2)
        assert.equals("copper-ore", data.buy[1].item)

        gui.on_click(player, rows(player, "buy")[1].otc_silo_del_buy_1)
        assert.equals(1, #data.buy)
        assert.equals("iron-ore", data.buy[1].item)
        assert.equals(1, #rows(player, "buy"))
    end)

    it("goes read-only under circuit control and comes back", function()
        player, entity = make_player({ [GREEN] = {
            { signal = { type = "item", name = "stone" }, count = 40 },
        } })
        gui.open(player, entity)
        local data = trading_silo.get(1)
        trading_silo.add_buy(data, "iron-ore", 5)

        local checkbox = orders(player).otc_silo_circuit_flow.otc_silo_circuit
        checkbox.state = true
        gui.on_checked(player, checkbox)

        assert.is_true(data.circuit.enabled)
        assert.is_false(add_flow(player, "buy").visible)
        assert.equals(1, #rows(player, "buy"))
        assert.is_nil(rows(player, "buy")[1].otc_silo_qty_1, "quantity must not be editable")
        assert.is_nil(rows(player, "buy")[1].otc_silo_del_buy_1, "rows must not be deletable")

        checkbox.state = false
        gui.on_checked(player, checkbox)
        assert.is_true(add_flow(player, "buy").visible)
        assert.is_true(rows(player, "buy")[1].otc_silo_qty_1 ~= nil)
    end)

    it("selects the wire the silo reads", function()
        gui.open(player, entity)
        local flow = orders(player).otc_silo_circuit_flow.otc_silo_wire_flow
        gui.on_checked(player, flow.otc_silo_wire_both)

        assert.equals("both", trading_silo.get(1).circuit.wire)
        assert.is_true(flow.otc_silo_wire_both.state)
        assert.is_false(flow.otc_silo_wire_green.state)
    end)

    it("goes away when the silo's own window closes", function()
        gui.open(player, entity)

        assert.is_false(gui.on_closed(player, { valid = true, name = "steel-chest" }))
        assert.is_true(frame(player) ~= nil, "another entity's window must not close it")

        assert.is_true(gui.on_closed(player, entity))
        assert.is_nil(frame(player))
        assert.is_nil(storage.players[1].trading_silo_unit)
    end)

    it("reopens cleanly without stacking frames", function()
        gui.open(player, entity)
        gui.open(player, entity)
        assert.equals(1, #player.gui.relative.children)
    end)

    it("closes itself if the silo stops existing", function()
        gui.open(player, entity)
        entity.valid = false
        gui.refresh(player)
        assert.is_nil(frame(player))
    end)
end)
