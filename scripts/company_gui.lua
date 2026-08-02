local market_gui = require("scripts.market_gui")
local expand_gui = require("scripts.expand_gui")
local company = require("scripts.company")
local nauvis = require("scripts.nauvis")
local utils = require("scripts.utils")
local item_filter = require("scripts.item_filter")
local research = require("scripts.research")
local stock = require("scripts.stock")

local M = {}

local TAB_ORDER = { "companies", "company", "nauvis" }
local TAB_INDEX = { companies = 1, company = 2, nauvis = 3 }

local function rebuild_companies_tab(player, content)
    for _, child in ipairs(content.children) do child.destroy() end

    local player_data = storage.players[player.index]
    local held_name = player_data.company

    if not held_name then
        content.add { type = "label", caption = "Found a new company:", style = "bold_label" }
        local create_flow = content.add { type = "flow", name = "otc_company_create_flow", direction = "horizontal" }
        create_flow.style.vertical_align = "center"
        local name_field = create_flow.add { type = "textfield", name = "otc_company_name" }
        name_field.style.width = 300
        local capital_field = create_flow.add {
            type = "textfield",
            name = "otc_company_capital",
            numeric = true,
            text = tostring(company.FOUNDING_MIN),
        }
        capital_field.style.width = 140
        create_flow.add { type = "button", name = "otc_company_create", caption = "Create", style = "green_button" }
        content.add { type = "line" }
    else
        content.add {
            type = "label",
            caption = "You hold shares in " .. held_name .. ". Manage it from the Company tab.",
            style = "caption_label",
        }
        content.add { type = "line" }
    end

    content.add { type = "label", caption = "Companies:", style = "bold_label" }
    local scroll = content.add { type = "scroll-pane", name = "otc_company_join_list", direction = "vertical" }
    scroll.style.height = 400
    scroll.style.width = 680

    for name, comp in pairs(storage.companies) do
        if not company.is_state(name) then
            local row = scroll.add { type = "flow", direction = "horizontal" }
            row.style.vertical_align = "center"
            row.style.horizontally_stretchable = true

            row.add { type = "label", caption = name }

            local holders_label = row.add { type = "label", caption = company.holder_count(comp) .. " holders" }
            holders_label.style.left_margin = 8

            local per_share = company.per_share(comp)
            local price_label = row.add {
                type = "label",
                caption = "₾" .. utils.format_number(math.floor(per_share + 0.5)) .. "/share",
            }
            price_label.style.left_margin = 8

            local spacer = row.add { type = "empty-widget" }
            spacer.style.horizontally_stretchable = true

            if comp.receivership then
                if held_name then
                    local btn = row.add {
                        type = "button",
                        name = "otc_company_takeover_" .. name,
                        caption = "Take over",
                        enabled = false,
                    }
                    btn.tooltip = "You already hold shares in a company."
                else
                    local cost = math.floor(company.takeover_price(comp) * nauvis.get_holding(name) + 0.5)
                    row.add {
                        type = "button",
                        name = "otc_company_takeover_" .. name,
                        caption = "Take over (₾" .. utils.format_number(cost) .. ")",
                        style = "green_button",
                    }
                end
            else
                local available = company.available_shares(name, comp)
                if held_name then
                    local btn = row.add {
                        type = "button",
                        name = "otc_company_join_" .. name,
                        caption = "Join",
                        enabled = false,
                    }
                    btn.tooltip = "You already hold shares in a company."
                elseif available <= 0 then
                    row.add { type = "label", caption = "No shares available" }
                else
                    local cost = math.floor(per_share * available + 0.5)
                    row.add {
                        type = "button",
                        name = "otc_company_join_" .. name,
                        caption = "Join (₾" .. utils.format_number(cost) .. ")",
                        style = "green_button",
                    }
                end
            end
        end
    end
end

local function rebuild_company_tab(player, content)
    for _, child in ipairs(content.children) do child.destroy() end

    local player_data = storage.players[player.index]
    local name = player_data.company

    if not name then
        content.add {
            type = "label",
            caption = "You don't hold shares in a company yet. Use the Companies tab to found or join one.",
        }
        return
    end

    local comp = company.get(name)
    if not comp then
        content.add { type = "label", caption = "Company no longer exists." }
        return
    end

    content.add { type = "label", caption = name, style = "frame_title" }
    local seconds = math.floor((game.tick - (comp.founded_tick or 0)) / 60)
    content.add { type = "label", caption = "Founded " .. seconds .. "s ago" }

    if comp.receivership then
        local badge = content.add { type = "label", caption = "IN RECEIVERSHIP" }
        badge.style.font_color = { r = 0.9, g = 0.2, b = 0.2 }
    end

    content.add { type = "line" }

    local per_share = company.per_share(comp)
    content.add {
        type = "label",
        caption = "Company credits: ₾" .. utils.format_number(math.floor(comp.credits + 0.5)),
        style = "caption_label",
    }
    content.add {
        type = "label",
        caption = "Per-share value (cash basis): ₾" .. utils.format_number(math.floor(per_share + 0.5)),
    }

    content.add { type = "line" }

    local holder = comp.holders[player.index]
    if holder then
        content.add {
            type = "label",
            caption = "Your shares: " .. holder.shares .. " (" ..
                string.format("%.1f", company.percent(comp, player.index)) .. "%)",
            style = "caption_label",
        }
        content.add {
            type = "label",
            caption = "Your holding value: ₾" .. utils.format_number(math.floor(holder.shares * per_share + 0.5)),
        }
    end
    content.add {
        type = "label",
        caption = "Personal credits: ₾" .. utils.format_number(math.floor((player_data.personal_credits or 0) + 0.5)),
    }

    if company.holder_count(comp) > 1 then
        content.add { type = "line" }
        content.add { type = "label", caption = "Holders:", style = "bold_label" }
        local rows = content.add { type = "table", column_count = 4 }
        rows.style.horizontal_spacing = 12
        for _, row in ipairs(company.sorted_holders(comp)) do
            local holder_player = game.get_player(row.player_index)
            rows.add { type = "label", caption = holder_player and holder_player.name or ("#" .. row.player_index) }
            rows.add { type = "label", caption = row.role }
            rows.add { type = "label", caption = tostring(row.shares) }
            rows.add { type = "label", caption = string.format("%.1f%%", company.percent(comp, row.player_index)) }
        end
        local nauvis_held = nauvis.get_holding(name)
        if nauvis_held > 0 then
            local issued = math.max(comp.shares_issued or 0, 1)
            rows.add { type = "label", caption = "Nauvis (unsold)" }
            rows.add { type = "label", caption = "--" }
            rows.add { type = "label", caption = tostring(nauvis_held) }
            rows.add { type = "label", caption = string.format("%.1f%%", nauvis_held / issued * 100) }
        end
    end

    if holder then
        content.add { type = "line" }
        local settlement = company.settlement_price(name, comp)
        local payout = math.floor(settlement * holder.shares + 0.5)
        content.add {
            type = "button",
            name = "otc_company_leave",
            caption = "Leave (₾" .. utils.format_number(payout) .. ")",
            style = "red_button",
        }
    end
end

local function format_tech_name(tech_name)
    local prototype = prototypes.technology[tech_name]
    if prototype and prototype.localised_name then
        return prototype.localised_name
    end
    return tech_name
end

local function current_research_caption()
    local current = research.current_research_name()
    if not current then return "Idle -- no research selected" end
    local state = game.forces[nauvis.FORCE_NAME]
    local progress = state and state.research_progress or 0
    return { "", "Researching: ", format_tech_name(current), string.format("  (%.0f%%)", progress * 100) }
end

-- The dropdown is player-editable, so its options are only rewritten when the
-- underlying frontier actually changes -- otherwise the periodic refresh would stomp
-- whatever the player had highlighted before they got to press Apply.
local function populate_research_dropdown(dropdown, player_data)
    local available = research.get_available_technologies()
    local previous = player_data.nauvis_research_options
    -- The dropdown's own item count matters as well as the cached list: reopening the
    -- tab builds a fresh (empty) dropdown while the cache still holds the old options,
    -- and comparing only the cache would leave the new element unpopulated.
    local changed = #dropdown.items ~= #available or not previous or #previous ~= #available
    if not changed then
        for i = 1, #available do
            if previous[i] ~= available[i] then
                changed = true
                break
            end
        end
    end

    if changed then
        local items = {}
        for i, tech_name in ipairs(available) do
            items[i] = format_tech_name(tech_name)
        end
        dropdown.items = items
        player_data.nauvis_research_options = available
    end

    local wanted = player_data.nauvis_research_selection or research.get_next_research()
    local selected_index = 0
    for i, tech_name in ipairs(available) do
        if tech_name == wanted then
            selected_index = i
            break
        end
    end
    if dropdown.selected_index ~= selected_index then
        dropdown.selected_index = selected_index
    end
end

function M.selected_research_name(player)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return nil end
    local options = player_data.nauvis_research_options
    local frame = player.gui.screen.otc_company_frame
    local tabs = frame and frame.otc_company_tabs
    local content = tabs and tabs.otc_company_content_nauvis
    local row = content and content.otc_company_nauvis_research_row
    local dropdown = row and row.otc_company_nauvis_research
    if not dropdown or not options then return nil end
    local index = dropdown.selected_index
    if index == 0 then return nil end
    return options[index]
end

local ROW_PREFIX = "otc_company_nauvis_stock_row_"
local COUNT_PREFIX = "otc_company_nauvis_stock_count_"

-- The warehouse holds things players cannot trade -- the science packs Nauvis makes
-- for itself, above all -- so the listing is the tradeable set plus whatever else is
-- actually on the shelves, rather than item_filter's list alone.
local function warehouse_items(player_data)
    local seen = {}
    local items = {}
    for _, item in pairs(player_data and player_data.allowed_items or {}) do
        if not seen[item.name] then
            seen[item.name] = true
            table.insert(items, item)
        end
    end
    for name, count in pairs(stock.items()) do
        if count > 0 and not seen[name] then
            local prototype = prototypes.item[name]
            if prototype then
                seen[name] = true
                table.insert(items, { name = name, prototype = prototype })
            end
        end
    end
    table.sort(items, function(a, b)
        if a.prototype.order == b.prototype.order then return a.name < b.name end
        return a.prototype.order < b.prototype.order
    end)
    return items
end

local function add_stock_row(stock_list, item, index)
    local row = stock_list.add {
        type = "flow", name = ROW_PREFIX .. item.name, direction = "horizontal", index = index,
    }
    row.style.vertical_align = "center"
    row.add { type = "sprite", sprite = "item/" .. item.name }
    local name_label = row.add { type = "label", caption = item.prototype.localised_name }
    name_label.style.horizontally_stretchable = true
    local count_label = row.add { type = "label", name = COUNT_PREFIX .. item.name }
    count_label.style.horizontal_align = "right"
    market_gui.apply_stock_label(count_label, item.name)
    return row
end

local function rebuild_nauvis_tab(player, content)
    for _, child in ipairs(content.children) do child.destroy() end

    local player_data = storage.players[player.index]

    content.add { type = "label", caption = "Nauvis", style = "frame_title" }
    content.add {
        type = "label",
        caption = "The state. Not joinable; mints and burns credits as players trade.",
    }
    content.add { type = "line" }
    content.add {
        type = "label",
        name = "otc_company_nauvis_minted",
        caption = "Minted: ₾" .. utils.format_number(math.floor(storage.nauvis.minted + 0.5)),
    }
    content.add {
        type = "label",
        name = "otc_company_nauvis_burned",
        caption = "Burned: ₾" .. utils.format_number(math.floor(storage.nauvis.burned + 0.5)),
    }
    content.add {
        type = "label",
        name = "otc_company_nauvis_net",
        caption = "Net money supply: ₾" .. utils.format_number(math.floor(nauvis.net() + 0.5)),
        style = "caption_label",
    }

    content.add { type = "line" }
    content.add { type = "label", caption = "Research", style = "bold_label" }
    content.add {
        type = "label",
        name = "otc_company_nauvis_current_research",
        caption = current_research_caption(),
        style = "caption_label",
    }

    local research_row = content.add {
        type = "flow", name = "otc_company_nauvis_research_row", direction = "horizontal",
    }
    research_row.style.vertical_align = "center"
    research_row.add { type = "label", caption = "Next:" }
    local research_dropdown = research_row.add {
        type = "drop-down",
        name = "otc_company_nauvis_research",
    }
    research_dropdown.style.horizontally_stretchable = true
    populate_research_dropdown(research_dropdown, player_data)
    research_row.add {
        type = "button",
        name = "otc_company_nauvis_apply_research",
        caption = "Apply",
        style = "green_button",
    }

    content.add { type = "line" }
    content.add { type = "label", caption = "Warehouse stock", style = "bold_label" }
    local stock_frame = content.add {
        type = "frame", name = "otc_company_nauvis_stock_frame", style = "inside_deep_frame",
    }
    stock_frame.style.horizontally_stretchable = true
    local stock_list = stock_frame.add {
        type = "scroll-pane",
        name = "otc_company_nauvis_stock_list",
        direction = "vertical",
    }
    stock_list.style.height = 220
    stock_list.style.horizontally_stretchable = true
    stock_list.style.padding = 4

    if not player_data.allowed_items then
        player_data.allowed_items = item_filter.get_allowed_items(player.force)
    end
    for i, item in ipairs(warehouse_items(player_data)) do
        add_stock_row(stock_list, item, i)
    end

    content.add { type = "line" }
    content.add { type = "label", caption = "Held company shares (market-making):", style = "bold_label" }
    local any = false
    for name, shares in pairs(storage.nauvis.holdings) do
        any = true
        content.add { type = "label", caption = name .. ": " .. shares .. " shares" }
    end
    if not any then
        content.add { type = "label", caption = "None." }
    end

    content.add { type = "line" }
    content.add { type = "label", caption = "Bonds", style = "bold_label" }
    local bonds_btn = content.add { type = "button", caption = "Buy bonds", enabled = false }
    bonds_btn.tooltip = "Coming soon: convert personal credits into Nauvis bonds carrying governance votes."
end

function M.refresh_nauvis_tab(player)
    local frame = player.gui.screen.otc_company_frame
    if not frame then return end
    local tabs = frame.otc_company_tabs
    if not tabs then return end
    local content = tabs.otc_company_content_nauvis
    if not content then return end
    rebuild_nauvis_tab(player, content)
end

-- Updates values in place instead of destroying/rebuilding rows, so the stock
-- scroll-pane keeps its scroll position across the periodic refresh. Only call
-- rebuild_nauvis_tab when the allowed-items list itself can have changed (research).
function M.refresh_nauvis_stock(player)
    local frame = player.gui.screen.otc_company_frame
    if not frame then return end
    local tabs = frame.otc_company_tabs
    if not tabs then return end
    local content = tabs.otc_company_content_nauvis
    if not content then return end

    local minted = content.otc_company_nauvis_minted
    if minted and minted.valid then
        minted.caption = "Minted: ₾" .. utils.format_number(math.floor(storage.nauvis.minted + 0.5))
    end
    local burned = content.otc_company_nauvis_burned
    if burned and burned.valid then
        burned.caption = "Burned: ₾" .. utils.format_number(math.floor(storage.nauvis.burned + 0.5))
    end
    local net = content.otc_company_nauvis_net
    if net and net.valid then
        net.caption = "Net money supply: ₾" .. utils.format_number(math.floor(nauvis.net() + 0.5))
    end

    local player_data = storage.players[player.index]

    local current_research = content.otc_company_nauvis_current_research
    if current_research and current_research.valid then
        current_research.caption = current_research_caption()
    end

    local research_row = content.otc_company_nauvis_research_row
    local dropdown = research_row and research_row.otc_company_nauvis_research
    if dropdown and dropdown.valid and player_data then
        populate_research_dropdown(dropdown, player_data)
    end

    local stock_frame = content.otc_company_nauvis_stock_frame
    local stock_list = stock_frame and stock_frame.otc_company_nauvis_stock_list
    if not stock_list then return end

    local items = warehouse_items(player_data)
    local wanted = {}
    for _, item in pairs(items) do wanted[item.name] = true end
    for _, row in pairs(stock_list.children) do
        local item_name = row.name and string.match(row.name, "^otc_company_nauvis_stock_row_(.+)$")
        if item_name and not wanted[item_name] then row.destroy() end
    end
    for i, item in ipairs(items) do
        local row = stock_list[ROW_PREFIX .. item.name] or add_stock_row(stock_list, item, i)
        local count_label = row[COUNT_PREFIX .. item.name]
        if count_label and count_label.valid then
            market_gui.apply_stock_label(count_label, item.name)
        end
    end
end

function M.rebuild_all(player)
    local frame = player.gui.screen.otc_company_frame
    if not frame then return end
    local tabs = frame.otc_company_tabs
    if not tabs then return end
    rebuild_companies_tab(player, tabs.otc_company_content_companies)
    rebuild_company_tab(player, tabs.otc_company_content_company)
    rebuild_nauvis_tab(player, tabs.otc_company_content_nauvis)
end

local PROXIMITY_LIMIT_SQ = 36

function M.open(player, entity)
    local existing = player.gui.screen.otc_company_frame
    if existing then return end

    local frame = player.gui.screen.add {
        type = "frame",
        name = "otc_company_frame",
        direction = "vertical",
    }
    frame.auto_center = true
    frame.style.padding = 12

    local titlebar = frame.add {
        type = "flow",
        direction = "horizontal",
    }
    titlebar.drag_target = frame

    titlebar.add {
        type = "label",
        caption = "Company Management",
        style = "frame_title",
    }

    titlebar.add {
        type = "empty-widget",
        style = "draggable_space_header",
    }.style.horizontally_stretchable = true

    titlebar.add {
        type = "sprite-button",
        name = "otc_company_close",
        sprite = "utility/close",
        style = "frame_action_button",
        tooltip = {"gui.close"},
    }

    local tabs = frame.add { type = "tabbed-pane", name = "otc_company_tabs" }
    tabs.style.width = 760

    local tab_companies = tabs.add { type = "tab", name = "otc_company_tab_companies", caption = "Companies" }
    local content_companies = tabs.add {
        type = "flow", name = "otc_company_content_companies", direction = "vertical",
    }
    tabs.add_tab(tab_companies, content_companies)

    local tab_company = tabs.add { type = "tab", name = "otc_company_tab_company", caption = "Company" }
    local content_company = tabs.add { type = "flow", name = "otc_company_content_company", direction = "vertical" }
    tabs.add_tab(tab_company, content_company)

    local tab_nauvis = tabs.add { type = "tab", name = "otc_company_tab_nauvis", caption = "Nauvis" }
    local content_nauvis = tabs.add { type = "flow", name = "otc_company_content_nauvis", direction = "vertical" }
    tabs.add_tab(tab_nauvis, content_nauvis)

    rebuild_companies_tab(player, content_companies)
    rebuild_company_tab(player, content_company)
    rebuild_nauvis_tab(player, content_nauvis)

    local player_data = storage.players[player.index]
    local selected = player_data.company_gui_tab
    if not selected then
        selected = player_data.company and "company" or "companies"
    end
    tabs.selected_tab_index = TAB_INDEX[selected] or 1

    player_data.company_gui_monitor = entity
end

function M.close(player)
    local frame = player.gui.screen.otc_company_frame
    if frame then frame.destroy() end
    local player_data = storage.players and storage.players[player.index]
    if player_data then player_data.company_gui_monitor = nil end
end

function M.check_proximity(player)
    local frame = player.gui.screen.otc_company_frame
    if not frame then return end

    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end

    local monitor = player_data.company_gui_monitor
    if not monitor or not monitor.valid or monitor.surface ~= player.surface then
        M.close(player)
        return
    end

    local dx = player.position.x - monitor.position.x
    local dy = player.position.y - monitor.position.y
    if dx * dx + dy * dy > PROXIMITY_LIMIT_SQ then
        M.close(player)
    end
end

function M.handle_tab_changed(player, element)
    if element.name ~= "otc_company_tabs" then return end
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end
    player_data.company_gui_tab = TAB_ORDER[element.selected_tab_index] or "companies"
end

local function select_tab(player, tab_name)
    local player_data = storage.players[player.index]
    player_data.company_gui_tab = tab_name
    local frame = player.gui.screen.otc_company_frame
    if frame and frame.otc_company_tabs then
        frame.otc_company_tabs.selected_tab_index = TAB_INDEX[tab_name] or 1
    end
end

function M.handle_create(player)
    local frame = player.gui.screen.otc_company_frame
    if not frame then return end
    local content = frame.otc_company_tabs.otc_company_content_companies
    local create_flow = content and content.otc_company_create_flow
    if not create_flow then return end
    local name_field = create_flow.otc_company_name
    local capital_field = create_flow.otc_company_capital
    if not name_field or not capital_field then return end

    local name = name_field.text and name_field.text:match("^%s*(.-)%s*$")
    local capital = tonumber(capital_field.text)

    local ok, err = company.create(player, name, capital)
    if not ok then
        player.print(err)
        return
    end

    market_gui.init_player(player)
    expand_gui.init_player(player)
    select_tab(player, "company")
    M.rebuild_all(player)
end

function M.handle_join(player, name)
    local ok, err = company.join(player, name)
    if not ok then
        player.print(err)
        return
    end

    market_gui.init_player(player)
    expand_gui.init_player(player)
    select_tab(player, "company")
    M.rebuild_all(player)
end

function M.handle_takeover(player, name)
    local ok, err = company.takeover(player, name)
    if not ok then
        player.print(err)
        return
    end

    market_gui.init_player(player)
    expand_gui.init_player(player)
    select_tab(player, "company")
    M.rebuild_all(player)
end

function M.handle_leave(player)
    local ok, err = company.leave(player)
    if not ok then
        player.print(err)
        return
    end

    if player.gui.screen.otc_market_frame then player.gui.screen.otc_market_frame.destroy() end
    if player.gui.screen.otc_expand_frame then player.gui.screen.otc_expand_frame.destroy() end
    market_gui.create_credits_gui(player)
    select_tab(player, "companies")
    M.rebuild_all(player)
end

function M.handle_apply_research(player)
    local tech_name = M.selected_research_name(player)
    if not tech_name then
        player.print("Pick a technology for Nauvis to research first.")
        return
    end

    local ok, err = research.set_next_research(tech_name)
    if not ok then
        player.print(err)
        return
    end

    local player_data = storage.players and storage.players[player.index]
    if player_data then
        player_data.nauvis_research_selection = nil
    end

    if research.current_research_name() == tech_name then
        player.print("Nauvis is now researching " .. tech_name .. ".")
    else
        player.print("Nauvis will research " .. tech_name .. " next.")
    end
    if not research.can_supply(tech_name) then
        player.print("Warning: Nauvis cannot produce the science packs that technology needs, "
            .. "so it will not progress.")
    end
    M.refresh_nauvis_stock(player)
end

function M.handle_research_selection(player, element)
    local player_data = storage.players and storage.players[player.index]
    if not player_data then return end
    local options = player_data.nauvis_research_options
    local index = element.selected_index
    player_data.nauvis_research_selection = options and index > 0 and options[index] or nil
end

function M.handle_click(player, element_name)
    if element_name == "otc_company_close" then
        M.close(player)
        return
    end
    if element_name == "otc_company_nauvis_apply_research" then
        M.handle_apply_research(player)
        return
    end
    if element_name == "otc_company_create" then
        M.handle_create(player)
        return
    end
    if element_name == "otc_company_leave" then
        M.handle_leave(player)
        return
    end
    local join_name = string.match(element_name, "^otc_company_join_(.+)$")
    if join_name then
        M.handle_join(player, join_name)
        return
    end
    local takeover_name = string.match(element_name, "^otc_company_takeover_(.+)$")
    if takeover_name then
        M.handle_takeover(player, takeover_name)
        return
    end
end

return M
