local market_gui = require("scripts.market_gui")
local expand_gui = require("scripts.expand_gui")
local company = require("scripts.company")
local nauvis = require("scripts.nauvis")
local utils = require("scripts.utils")
local item_filter = require("scripts.item_filter")
local research = require("scripts.research")
local nauvis_expansion = require("scripts.nauvis_expansion")
local stock = require("scripts.stock")
local voting = require("scripts.voting")

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

local BALLOT_ROOT = "otc_company_ballot_"
local BALLOT_TIMER = "otc_company_ballot_timer_"
local BALLOT_PICK = "otc_company_ballot_pick_"
local BALLOT_YOURS = "otc_company_ballot_yours_"
local BALLOT_TALLY = "otc_company_ballot_tally_"
local BALLOT_COUNT = "otc_company_ballot_count_"

local function ballot_timer_caption(ballot)
    local remaining = math.max(ballot.end_tick - game.tick, 0)
    return string.format("Closes in %d:%02d -- %d of %d bonds cast",
        math.floor(remaining / 3600), math.floor(remaining / 60) % 60,
        select(2, voting.tally(ballot.kind)), voting.eligible_weight())
end

local function ballot_yours_caption(player, kind)
    local weight = voting.weight(player.index)
    if weight <= 0 then
        return "You hold no bonds, so you have no vote."
    end
    local ballot = voting.active(kind)
    local vote = voting.get_vote(player.index, kind)
    local label = vote and voting.option_label(ballot, vote) or "not cast"
    return { "", string.format("Your %d bond(s): ", weight), label }
end

local function ballot_count_caption(option, counts)
    return { "", option.label, string.format(": %d", counts[option.key] or 0) }
end

--- One renderer for all three ballots. The option list is frozen when a ballot
--- opens, so the dropdown's items are written once and only captions are
--- refreshed -- the periodic refresh must never move a selection out from under
--- someone mid-click.
local function build_ballot_section(player, content, kind)
    local flow = content.add { type = "flow", name = BALLOT_ROOT .. kind, direction = "vertical" }
    local ballot = voting.active(kind)
    if not ballot then
        flow.add { type = "label", caption = voting.idle_caption(kind) }
        return flow
    end

    flow.add {
        type = "label",
        name = BALLOT_TIMER .. kind,
        caption = ballot_timer_caption(ballot),
        style = "caption_label",
    }

    local row = flow.add { type = "flow", direction = "horizontal" }
    row.style.vertical_align = "center"
    row.add { type = "label", caption = "Vote:" }
    local items, selected_index = {}, 0
    local current = voting.get_vote(player.index, kind)
    for index, option in ipairs(ballot.options) do
        items[index] = option.label
        if option.key == current then selected_index = index end
    end
    local dropdown = row.add {
        type = "drop-down",
        name = BALLOT_PICK .. kind,
        items = items,
        selected_index = selected_index,
    }
    dropdown.style.horizontally_stretchable = true
    row.add {
        type = "button",
        name = "otc_company_ballot_vote_" .. kind,
        caption = "Cast",
        style = "green_button",
    }

    flow.add {
        type = "label",
        name = BALLOT_YOURS .. kind,
        caption = ballot_yours_caption(player, kind),
        style = "caption_label",
    }

    local tally = flow.add { type = "flow", name = BALLOT_TALLY .. kind, direction = "vertical" }
    local counts = voting.tally(kind)
    for _, option in ipairs(ballot.options) do
        local label = tally.add {
            type = "label",
            name = BALLOT_COUNT .. kind .. "_" .. option.key,
            caption = ballot_count_caption(option, counts),
        }
        if option.tooltip then label.tooltip = option.tooltip end
    end
    return flow
end

local function refresh_ballot_section(player, content, kind)
    local flow = content[BALLOT_ROOT .. kind]
    if not flow or not flow.valid then return end
    local ballot = voting.active(kind)
    if not ballot then return end

    local timer = flow[BALLOT_TIMER .. kind]
    if timer and timer.valid then timer.caption = ballot_timer_caption(ballot) end

    local yours = flow[BALLOT_YOURS .. kind]
    if yours and yours.valid then yours.caption = ballot_yours_caption(player, kind) end

    local tally = flow[BALLOT_TALLY .. kind]
    if tally and tally.valid then
        local counts = voting.tally(kind)
        for _, option in ipairs(ballot.options) do
            local label = tally[BALLOT_COUNT .. kind .. "_" .. option.key]
            if label and label.valid then
                label.caption = ballot_count_caption(option, counts)
            end
        end
    end
end

--- A ballot opening or closing changes the tab's structure, not just its
--- numbers, so the cheap refresh has to notice and hand over to a full rebuild.
local function ballot_signature()
    local parts = {}
    for index, kind in ipairs(voting.KINDS) do
        local ballot = voting.active(kind)
        parts[index] = tostring(ballot and ballot.start_tick or 0)
    end
    return table.concat(parts, ",")
end

local function selected_ballot_key(player, kind)
    local frame = player.gui.screen.otc_company_frame
    local tabs = frame and frame.otc_company_tabs
    local content = tabs and tabs.otc_company_content_nauvis
    local flow = content and content[BALLOT_ROOT .. kind]
    if not flow or not flow.valid then return nil end
    for _, child in ipairs(flow.children) do
        local dropdown = child[BALLOT_PICK .. kind]
        if dropdown and dropdown.valid then
            local ballot = voting.active(kind)
            local option = ballot and dropdown.selected_index > 0
                and ballot.options[dropdown.selected_index]
            return option and option.key or nil
        end
    end
    return nil
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

local function item_caption(item_name)
    local prototype = prototypes.item[item_name]
    return prototype and prototype.localised_name or item_name
end

local function expansion_status_caption()
    local target = nauvis_expansion.target()
    local option = target and nauvis_expansion.get_option(target)
    if not option then
        return "Nothing under construction -- the winning vote below becomes the next build."
    end
    local have, need = 0, 0
    for _, row in ipairs(nauvis_expansion.remaining(target)) do
        have, need = have + row.have, need + row.need
    end
    return { "", "Building: ", option.label, string.format("  (%d/%d goods delivered)", have, need) }
end

local function bill_row_caption(row)
    return { "", item_caption(row.name), string.format(": %d / %d", row.have, row.need) }
end

local function build_expansion_section(player, content)
    content.add { type = "line" }
    content.add { type = "label", caption = "Expansion", style = "bold_label" }
    content.add {
        type = "label",
        name = "otc_company_nauvis_expansion_status",
        caption = expansion_status_caption(),
        style = "caption_label",
    }

    local bill = content.add {
        type = "flow", name = "otc_company_nauvis_expansion_bill", direction = "vertical",
    }
    local target = nauvis_expansion.target()
    if target then
        for _, row in ipairs(nauvis_expansion.remaining(target)) do
            local line = bill.add {
                type = "flow", name = "otc_company_nauvis_bill_row_" .. row.name, direction = "horizontal",
            }
            line.style.vertical_align = "center"
            line.add { type = "sprite", sprite = "item/" .. row.name }
            line.add { type = "label", name = "otc_company_nauvis_bill_" .. row.name, caption = bill_row_caption(row) }
        end
        bill.add {
            type = "label",
            caption = "Nauvis only spends warehouse surplus above " .. utils.format_number(stock.TARGET_STOCK)
                .. ", so sell it more than it wants to keep.",
        }
    end

    build_ballot_section(player, content, "expansion")
end

local function refresh_expansion_section(player, content)
    local status = content.otc_company_nauvis_expansion_status
    if not status or not status.valid then return end
    status.caption = expansion_status_caption()

    local bill = content.otc_company_nauvis_expansion_bill
    local target = nauvis_expansion.target()
    if bill and bill.valid and target then
        for _, row in ipairs(nauvis_expansion.remaining(target)) do
            local line = bill["otc_company_nauvis_bill_row_" .. row.name]
            local label = line and line["otc_company_nauvis_bill_" .. row.name]
            if label and label.valid then label.caption = bill_row_caption(row) end
        end
    end

    refresh_ballot_section(player, content, "expansion")
end

local function mayor_caption()
    local index = nauvis.get_mayor()
    local mayor = index and game.get_player(index)
    return "Mayor: " .. (mayor and mayor.name or "vacant")
end

local function bonds_caption(player)
    return string.format("Your bonds: %d of %d issued",
        nauvis.get_bonds(player.index), nauvis.total_bonds())
end

local function build_governance_section(player, content)
    content.add { type = "line" }
    content.add { type = "label", caption = "Governance", style = "bold_label" }
    content.add {
        type = "label",
        name = "otc_company_nauvis_mayor",
        caption = mayor_caption(),
        style = "caption_label",
    }
    content.add {
        type = "label",
        name = "otc_company_nauvis_bonds",
        caption = bonds_caption(player),
    }

    local row = content.add {
        type = "flow", name = "otc_company_nauvis_gov_row", direction = "horizontal",
    }
    row.style.vertical_align = "center"
    local buy = row.add {
        type = "button",
        name = "otc_company_bond_buy",
        caption = "Buy a bond (₾" .. utils.format_number(nauvis.bond_price(player.index)) .. ")",
    }
    buy.tooltip = string.format(
        "A bond is one vote in every Nauvis ballot. It costs %.0f%% of everything the "
        .. "world is worth -- every credit in existence plus Nauvis's warehouse -- "
        .. "multiplied by the bonds you already hold, so each one you buy is dearer "
        .. "than the last. The purchase burns the money back out of the supply.\n"
        .. "World value: ₾%s",
        nauvis.BOND_RATE * 100, utils.format_number(math.floor(nauvis.total_value() + 0.5)))
    local election = row.add {
        type = "button",
        name = "otc_company_election_mayor",
        caption = "Call a mayoral election",
        enabled = voting.active("mayor") == nil,
    }
    election.tooltip = "Any bondholder can put the mayor's office to a vote."

    build_ballot_section(player, content, "mayor")
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

    build_governance_section(player, content)

    content.add { type = "line" }
    content.add { type = "label", caption = "Research", style = "bold_label" }
    content.add {
        type = "label",
        name = "otc_company_nauvis_current_research",
        caption = current_research_caption(),
        style = "caption_label",
    }
    build_ballot_section(player, content, "research")

    build_expansion_section(player, content)
    -- The bill of materials is per target, and a ballot opening or closing adds
    -- and removes whole rows, so the periodic refresh has to know when to rebuild
    -- rather than just rewrite captions.
    player_data.nauvis_expansion_shown = nauvis_expansion.target()
    player_data.nauvis_ballots_shown = ballot_signature()

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

    if player_data and (player_data.nauvis_expansion_shown ~= nauvis_expansion.target()
        or player_data.nauvis_ballots_shown ~= ballot_signature()) then
        rebuild_nauvis_tab(player, content)
        return
    end

    local mayor = content.otc_company_nauvis_mayor
    if mayor and mayor.valid then mayor.caption = mayor_caption() end
    local bonds = content.otc_company_nauvis_bonds
    if bonds and bonds.valid then bonds.caption = bonds_caption(player) end
    local gov_row = content.otc_company_nauvis_gov_row
    local buy = gov_row and gov_row.otc_company_bond_buy
    if buy and buy.valid then
        buy.caption = "Buy a bond (₾" .. utils.format_number(nauvis.bond_price(player.index)) .. ")"
    end

    refresh_ballot_section(player, content, "mayor")
    refresh_ballot_section(player, content, "research")
    refresh_expansion_section(player, content)

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
    nauvis_expansion.chart_force(player.force)
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

function M.handle_ballot_vote(player, kind)
    local key = selected_ballot_key(player, kind)
    if not key then
        player.print("Pick something on the ballot first.")
        return
    end

    local ok, err = voting.cast(player.index, kind, key)
    if not ok then
        player.print(err)
        return
    end

    local ballot = voting.active(kind)
    player.print({ "", string.format("Cast %d bond(s) for ", voting.weight(player.index)),
        ballot and voting.option_label(ballot, key) or key, "." })
    M.refresh_nauvis_tab(player)
end

function M.handle_call_election(player, kind)
    if voting.weight(player.index) <= 0 then
        player.print("You hold no Nauvis bonds, so you cannot call a vote.")
        return
    end
    local ok, err = voting.open(kind, player.name)
    if not ok then
        player.print(err)
        return
    end
    M.refresh_nauvis_tab(player)
end

function M.handle_buy_bond(player)
    local ok, result = nauvis.buy_bond(player.index)
    if not ok then
        player.print(result)
        return
    end
    player.print("Bought a Nauvis bond for ₾" .. utils.format_number(result)
        .. ". You now hold " .. nauvis.get_bonds(player.index) .. ".")
    M.rebuild_all(player)
end

function M.handle_click(player, element_name)
    if element_name == "otc_company_close" then
        M.close(player)
        return
    end
    if element_name == "otc_company_bond_buy" then
        M.handle_buy_bond(player)
        return
    end
    local election_kind = string.match(element_name, "^otc_company_election_(.+)$")
    if election_kind then
        M.handle_call_election(player, election_kind)
        return
    end
    local ballot_kind = string.match(element_name, "^otc_company_ballot_vote_(.+)$")
    if ballot_kind then
        M.handle_ballot_vote(player, ballot_kind)
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
