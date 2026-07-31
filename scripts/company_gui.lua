local market_gui = require("scripts.market_gui")
local expand_gui = require("scripts.expand_gui")

local M = {}
local STARTING_CREDITS = 5000

local function assign_player(player, force_name)
    local frame = player.gui.screen.otc_company_frame
    if frame then frame.destroy() end

    local player_data = storage.players[player.index]
    if not player_data then
        storage.players[player.index] = {}
        player_data = storage.players[player.index]
    end
    player_data.company = force_name
    player.force = game.forces[force_name]

    market_gui.init_player(player)
    expand_gui.init_player(player)
end

function M.open(player)
    local existing = player.gui.screen.otc_company_frame
    if existing then return end

    local frame = player.gui.screen.add{
        type = "frame",
        name = "otc_company_frame",
        direction = "vertical",
    }
    frame.auto_center = true
    frame.style.padding = 12

    local titlebar = frame.add{
        type = "flow",
        direction = "horizontal",
    }
    titlebar.drag_target = frame

    titlebar.add{
        type = "label",
        caption = "Company Management",
        style = "frame_title",
    }

    titlebar.add{
        type = "empty-widget",
        style = "draggable_space_header",
    }.style.horizontally_stretchable = true

    titlebar.add{
        type = "sprite-button",
        name = "otc_company_close",
        sprite = "utility/close",
        style = "frame_action_button",
        tooltip = {"gui.close"},
    }

    local player_data = storage.players[player.index]

    if player_data and player_data.company then
        frame.add {
            type = "label",
            caption = "You belong to: " .. player_data.company,
            style = "caption_label",
        }
    else
        frame.add {
            type = "label",
            caption = "Found a new company:",
            style = "bold_label",
        }
        local create_flow = frame.add { type = "flow", name = "otc_company_create_flow", direction = "horizontal" }
        create_flow.style.vertical_align = "center"
        local name_field = create_flow.add {
            type = "textfield",
            name = "otc_company_name",
        }
        name_field.style.width = 200
        create_flow.add {
            type = "button",
            name = "otc_company_create",
            caption = "Create",
            style = "green_button",
        }

        frame.add { type = "line" }

        frame.add {
            type = "label",
            caption = "Or join an existing company:",
            style = "bold_label",
        }

        local scroll = frame.add {
            type = "scroll-pane",
            name = "otc_company_join_list",
            direction = "vertical",
        }
        scroll.style.height = 150
        scroll.style.width = 300

        for _, force in pairs(game.forces) do
            if force.name ~= "Nauvis" and force.name ~= "player"
                and force.name ~= "enemy" and force.name ~= "neutral" then
                local row = scroll.add { type = "flow", direction = "horizontal" }
                row.style.vertical_align = "center"
                row.style.horizontally_stretchable = true
                row.add { type = "label", caption = force.name }
                row.add {
                    type = "button",
                    name = "otc_company_join_" .. force.name,
                    caption = "Join",
                    style = "green_button",
                }
            end
        end
    end
end

function M.close(player)
    local frame = player.gui.screen.otc_company_frame
    if frame then frame.destroy() end
end

function M.handle_create(player)
    local frame = player.gui.screen.otc_company_frame
    if not frame then return end
    local create_flow = frame.otc_company_create_flow
    local field = create_flow and create_flow.otc_company_name
    if not field then return end
    local name = field.text
    if not name or name == "" then
        player.print("Enter a company name!")
        return
    end
    name = name:match("^%s*(.-)%s*$")
    if not name or name == "" then
        player.print("Enter a valid company name!")
        return
    end
    if name == "Nauvis" or name == "player" or name == "enemy" or name == "neutral" then
        player.print("That name is reserved!")
        return
    end
    if game.forces[name] then
        player.print("A company named '" .. name .. "' already exists!")
        return
    end
    local player_data = storage.players[player.index]
    if player_data and player_data.company then
        player.print("You already belong to a company!")
        return
    end
    game.create_force(name)
    for _, force in pairs(game.forces) do
        force.set_cease_fire(game.forces[name], true)
        force.set_friend(game.forces[name], true)
    end
    storage.companies[name] = { credits = STARTING_CREDITS }
    assign_player(player, name)
end

function M.handle_join(player, force_name)
    if not game.forces[force_name] then
        player.print("Company no longer exists!")
        return
    end
    local player_data = storage.players[player.index]
    if player_data and player_data.company then
        player.print("You already belong to a company!")
        return
    end
    assign_player(player, force_name)
end

function M.init_or_restore(player)
    local player_data = storage.players[player.index]
    local company_name = player_data and player_data.company

    if company_name and game.forces[company_name] then
        player.force = game.forces[company_name]
        if not player.gui.screen.otc_credits_frame then
            market_gui.init_player(player)
        end
        if not player.gui.screen.otc_expand_frame then
            expand_gui.init_player(player)
        end
    end
end

return M
