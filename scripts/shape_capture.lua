local shape_io = require("scripts.shape_io")
local shape_def = require("scripts.shape_def")

local M = {}

M.TOOL_NAME = "otc-shape-capture"
M.MARKER_NAME = "otc-shape-marker"

local OUTPUT_DIR = "otc-shapes/"

-- Entities the game engine (or another mod) puts in the world that are never
-- part of a shape.
local IGNORED_TYPES = {
    character = true,
    ["item-entity"] = true,
    ["entity-ghost"] = true,
    ["tile-ghost"] = true,
    ["item-request-proxy"] = true,
    ["flying-text"] = true,
    corpse = true,
    particle = true,
    explosion = true,
    highlight_box = true,
    rocket_silo_rocket = true,
}

-- Entities whose placement carries bookkeeping beyond create_entity, so a hook
-- has to build them rather than shape_def.apply.
local ROLE_BY_NAME = {
    ["gate"] = "gate",
    ["otc-gate-computer"] = "computer",
    ["otc-water-pump"] = "pump",
    ["rocket-silo"] = "silo",
    ["otc-teleporter"] = "teleporter",
    ["otc-buy-chest"] = "buy_chest",
    ["otc-sell-chest"] = "sell_chest",
    ["otc-company-monitor"] = "company_monitor",
    ["lab"] = "lab",
}

local SKIP_CREATE_ROLES = {
    gate = true,
    computer = true,
    teleporter = true,
    return_teleporter = true,
    company_monitor = true,
}

-- Base layers first, so decorative floors land on top of the structural ones.
local LAYER_ORDER = {
    ["otc-platform"] = 1,
    ["grass-1"] = 1,
    ["dirt-7"] = 1,
    ["refined-concrete"] = 2,
    ["concrete"] = 3,
    ["refined-hazard-concrete-left"] = 4,
    ["refined-hazard-concrete-right"] = 4,
}

local function layer_rank(name)
    return LAYER_ORDER[name] or 2
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Marker text is `role` or `role:argument`, e.g. `origin`, `supply:iron-plate`.
local function parse_marker(text)
    text = trim(text or "")
    if text == "" then return nil end
    local role, arg = text:match("^([^:]+):(.*)$")
    if role then return trim(role), trim(arg) end
    return text, nil
end

--- Which wall a position belongs to: the nearest edge of the shape's bounds.
--- Nearest rather than exact, because an opening is often inset a tile behind
--- an airlock stub or an approach strip.
local function side_from_edge(x, y, bounds)
    if not bounds then return nil end
    local left, top, right, bottom = bounds[1][1], bounds[1][2], bounds[2][1], bounds[2][2]
    -- This codebase labels +y as "north"; see AGENTS.md.
    local distances = {
        west = x - left,
        east = right - x,
        north = bottom - y,
        south = y - top,
    }
    local best, best_distance
    for _, side in ipairs { "west", "east", "north", "south" } do
        if not best_distance or distances[side] < best_distance then
            best, best_distance = side, distances[side]
        end
    end
    return best
end

local function state()
    storage.shape_capture = storage.shape_capture or { pending = {} }
    storage.shape_capture.pending = storage.shape_capture.pending or {}
    return storage.shape_capture
end

function M.init()
    state()
end

function M.pending(player)
    return state().pending[player.index]
end

function M.set_pending(player, name, tile_mode)
    state().pending[player.index] = { name = name, tile_mode = tile_mode or "all" }
end

local function collect_markers(surface, area, origin)
    local markers = {}
    for _, entity in ipairs(surface.find_entities_filtered { area = area, name = M.MARKER_NAME }) do
        local role, arg = parse_marker(entity.display_panel_text)
        if role then
            markers[#markers + 1] = {
                role = role,
                arg = arg ~= "" and arg or nil,
                x = math.floor(entity.position.x) - origin.x,
                y = math.floor(entity.position.y) - origin.y,
            }
        end
    end
    return markers
end

local function find_origin(surface, area)
    for _, entity in ipairs(surface.find_entities_filtered { area = area, name = M.MARKER_NAME }) do
        local role = parse_marker(entity.display_panel_text)
        if role == "origin" then
            return { x = math.floor(entity.position.x), y = math.floor(entity.position.y) }
        end
    end
    return { x = math.floor(area.left_top.x), y = math.floor(area.left_top.y) }
end

--- `all` keeps every tile in the selection; `artificial` drops the ones the map
--- generator could have placed itself, which is usually the terrain that
--- happened to fall inside the rectangle rather than part of the shape.
local function tile_wanted(name, mode)
    if name == "out-of-map" then return false end
    if mode == "artificial" then
        local prototype = prototypes.tile[name]
        return not (prototype and prototype.autoplace_specification)
    end
    return true
end

local function collect_tiles(surface, area, origin, def, mode)
    local by_name, hidden_by_name = {}, {}
    for _, tile in ipairs(surface.find_tiles_filtered { area = area }) do
        if tile_wanted(tile.name, mode) then
            local x = tile.position.x - origin.x
            local y = tile.position.y - origin.y
            by_name[tile.name] = by_name[tile.name] or {}
            table.insert(by_name[tile.name], { x, y })

            local hidden = surface.get_hidden_tile(tile.position)
            if hidden and tile_wanted(hidden, mode) then
                hidden_by_name[hidden] = hidden_by_name[hidden] or {}
                table.insert(hidden_by_name[hidden], { x, y })
            end
        end
    end

    local function to_layers(source)
        local layers = {}
        for name, tiles in pairs(source) do
            layers[#layers + 1] = { name = name, correct = shape_def.correct_default(name), tiles = tiles }
        end
        table.sort(layers, function(a, b)
            local ra, rb = layer_rank(a.name), layer_rank(b.name)
            if ra ~= rb then return ra < rb end
            return a.name < b.name
        end)
        return layers
    end

    def.tile_layers = to_layers(by_name)
    local hidden = to_layers(hidden_by_name)
    if #hidden > 0 then def.hidden_tiles = hidden end
end

local function capture_entity(entity, origin)
    local e = {
        name = entity.name,
        position = { entity.position.x - origin.x, entity.position.y - origin.y },
    }
    if entity.direction and entity.direction ~= 0 then
        e.direction = entity.direction
    end
    local role = ROLE_BY_NAME[entity.name]
    if role then
        e.role = role
        if SKIP_CREATE_ROLES[role] then e.skip_create = true end
    end
    if entity.type == "assembling-machine" then
        local recipe = entity.get_recipe()
        if recipe then e.recipe = recipe.name end
    end
    if entity.type == "underground-belt" then
        e.belt_type = entity.belt_to_ground_type
    end
    return e
end

--- Read a rectangle of the world back into a shape definition table.
function M.capture_area(surface, area, name, opts)
    opts = opts or {}
    local origin = find_origin(surface, area)
    local def = {
        format = shape_def.FORMAT,
        name = name,
        entities = {},
        resources = {},
        notes = {},
    }

    local tile_mode = opts.tile_mode or "all"
    if opts.entities_only then tile_mode = "none" end
    if tile_mode ~= "none" then
        collect_tiles(surface, area, origin, def, tile_mode)
    end

    local gates = {}
    for _, entity in ipairs(surface.find_entities_filtered { area = area }) do
        if entity.valid and entity.name ~= M.MARKER_NAME and not IGNORED_TYPES[entity.type] then
            if entity.type == "resource" then
                def.resources[#def.resources + 1] = {
                    name = entity.name,
                    position = { math.floor(entity.position.x) - origin.x, math.floor(entity.position.y) - origin.y },
                    amount = entity.amount,
                }
            else
                local e = capture_entity(entity, origin)
                def.entities[#def.entities + 1] = e
                if e.role == "gate" then gates[#gates + 1] = e end
            end
        end
    end

    local bounds = shape_def.tile_bounds(def)
    if bounds then
        def.clearance_box = bounds
    end

    -- Give every gate the side it sits on, so rotation and the connector agree.
    for _, gate in ipairs(gates) do
        gate.side = side_from_edge(math.floor(gate.position[1]), math.floor(gate.position[2]), bounds)
            or "west"
    end

    local markers = collect_markers(surface, area, origin)
    def.anchors = {}
    for _, marker in ipairs(markers) do
        if marker.role == "connection" then
            def.connection = {
                position = { x = marker.x, y = marker.y },
                side = side_from_edge(marker.x, marker.y, bounds) or "west",
                gap = tonumber(marker.arg) or 3,
                connector = true,
            }
        elseif marker.role ~= "origin" then
            def.anchors[marker.role] = { position = { x = marker.x, y = marker.y } }
        end
    end

    if not def.connection then
        for _, gate in ipairs(gates) do
            if gate.side == "west" then
                def.connection = {
                    position = { x = math.floor(gate.position[1]), y = math.floor(gate.position[2]) },
                    side = "west",
                    gap = 3,
                    connector = true,
                }
                break
            end
        end
    end

    if #def.resources == 0 then def.resources = nil end
    if not next(def.anchors) then def.anchors = nil end

    table.insert(def.notes, "Captured from " .. surface.name .. " at origin "
        .. origin.x .. "," .. origin.y .. ".")
    if not def.connection then
        table.insert(def.notes, "No connection anchor found: place an otc-shape-marker reading")
        table.insert(def.notes, "\"connection:<gap>\", or a gate on the west edge, and re-capture.")
    end

    return def, origin
end

--- Capture and write to script-output/otc-shapes/<name>.lua.
function M.capture_for_player(player, surface, area, opts)
    local pending = M.pending(player)
    if not pending then
        player.print("No shape name set. Run /otc-capture-shape <name> first.")
        return
    end

    local name = pending.name
    opts = opts or {}
    opts.tile_mode = pending.tile_mode
    local def = M.capture_area(surface, area, name, opts)
    local path = OUTPUT_DIR .. name .. ".lua"
    helpers.write_file(path, shape_io.serialize(def), false, player.index)

    local tile_count, natural = 0, {}
    for _, layer in ipairs(def.tile_layers or {}) do
        tile_count = tile_count + #layer.tiles
        if not tile_wanted(layer.name, "artificial") then
            natural[#natural + 1] = layer.name
        end
    end
    player.print(string.format(
        "Captured %q: %d tiles, %d entities, %d resources -> script-output/%s",
        name, tile_count, #(def.entities or {}), #(def.resources or {}), path))
    if not def.connection then
        player.print("  (no connection anchor found; see the notes in the generated file)")
    end
    if #natural > 0 then
        player.print("  (kept naturally generated tiles: " .. table.concat(natural, ", ")
            .. " -- re-run with tiles=artificial to drop terrain that just fell inside the selection)")
    end
end

function M.give_tool(player, name, tile_mode)
    M.set_pending(player, name, tile_mode)
    if player.cursor_stack and player.cursor_stack.can_set_stack { name = M.TOOL_NAME } then
        player.cursor_stack.set_stack { name = M.TOOL_NAME, count = 1 }
    end
end

local TILE_MODES = { all = true, artificial = true, none = true }
local USAGE = "Usage: /otc-capture-shape <name> [tiles=all|artificial|none]"

function M.register_commands()
    commands.add_command("otc-capture-shape",
        "Capture a shape: /otc-capture-shape <name>, then drag the selection tool over it.",
        function(event)
            local player = game.get_player(event.player_index)
            if not player then return end

            local name, tile_mode
            for word in (event.parameter or ""):gmatch("%S+") do
                local mode = word:match("^tiles=(%a+)$")
                if mode then
                    tile_mode = mode
                elseif not name then
                    name = word
                end
            end

            if not name or not name:match("^[%w_]+$") then
                player.print(USAGE .. "  (name: letters, digits and underscores)")
                return
            end
            if tile_mode and not TILE_MODES[tile_mode] then
                player.print(USAGE)
                return
            end

            M.give_tool(player, name, tile_mode)
            player.print("Ready to capture \"" .. name .. "\" (tiles=" .. (tile_mode or "all")
                .. "). Drag the capture tool over the shape: left-drag captures tiles and entities, "
                .. "right-drag captures entities only.")
        end)
end

function M.on_selected_area(event, entities_only)
    if event.item ~= M.TOOL_NAME then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    M.capture_for_player(player, event.surface, event.area, { entities_only = entities_only })
end

return M
