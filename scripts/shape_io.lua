local shape_runs = require("scripts.shape_runs")

local M = {}

local function num(n)
    if n == math.floor(n) then
        return string.format("%d", n)
    end
    return string.format("%s", tostring(n))
end

local function str(s)
    return string.format("%q", s)
end

local function pos(p)
    return "{ " .. num(p[1]) .. ", " .. num(p[2]) .. " }"
end

local ENTITY_KEY_ORDER = {
    "name", "position", "direction", "role", "recipe", "belt_type",
    "item", "item_left", "item_right", "force", "minable", "preview",
}

local function entity_line(e, indent)
    local parts = {}
    local seen = {}
    local function emit(key)
        seen[key] = true
        local v = e[key]
        if v == nil then return end
        if key == "position" then
            parts[#parts + 1] = "position = " .. pos(v)
        elseif type(v) == "string" then
            parts[#parts + 1] = key .. " = " .. str(v)
        elseif type(v) == "number" then
            parts[#parts + 1] = key .. " = " .. num(v)
        elseif type(v) == "boolean" then
            parts[#parts + 1] = key .. " = " .. tostring(v)
        end
    end
    for _, key in ipairs(ENTITY_KEY_ORDER) do emit(key) end
    local extra = {}
    for key in pairs(e) do
        if not seen[key] and key ~= "create_args" then extra[#extra + 1] = key end
    end
    table.sort(extra)
    for _, key in ipairs(extra) do emit(key) end

    local single = indent .. "{ " .. table.concat(parts, ", ") .. " },"
    if #single <= 118 then return single end

    local lines = { indent .. "{" }
    for _, part in ipairs(parts) do
        lines[#lines + 1] = indent .. "    " .. part .. ","
    end
    lines[#lines + 1] = indent .. "},"
    return table.concat(lines, "\n")
end

local function runs_block(tiles, indent)
    local runs = shape_runs.compress(tiles)
    local lines = {}
    for _, r in ipairs(runs) do
        lines[#lines + 1] = indent .. "    { " .. num(r[1]) .. ", " .. num(r[2]) .. ", " .. num(r[3]) .. " },"
    end
    return lines
end

local function tile_layers_block(layers, key, out)
    if not layers or #layers == 0 then return end
    out[#out + 1] = "    " .. key .. " = {"
    for _, layer in ipairs(layers) do
        out[#out + 1] = "        {"
        out[#out + 1] = "            name = " .. str(layer.name) .. ","
        if layer.correct ~= nil then
            out[#out + 1] = "            correct = " .. tostring(layer.correct) .. ","
        end
        out[#out + 1] = "            tiles = runs.expand {"
        for _, line in ipairs(runs_block(layer.tiles, "            ")) do
            out[#out + 1] = line
        end
        out[#out + 1] = "            },"
        out[#out + 1] = "        },"
    end
    out[#out + 1] = "    },"
end

--- Render a shape definition as loadable Lua source.
function M.serialize(def)
    local out = {}
    out[#out + 1] = "-- Shape definition captured from the game."
    out[#out + 1] = "-- Re-capture in game with: /otc-capture-shape " .. (def.name or "<name>")
    out[#out + 1] = "-- Coordinates are shape-local; the canonical orientation is a gate on the"
    out[#out + 1] = "-- west edge with the room extending east. See README.md \"Capturing shapes\"."
    out[#out + 1] = "local runs = require(\"scripts.shape_runs\")"
    out[#out + 1] = ""
    out[#out + 1] = "return {"
    out[#out + 1] = "    format = " .. num(def.format or 1) .. ","
    out[#out + 1] = "    name = " .. str(def.name) .. ","
    if def.hook then
        out[#out + 1] = "    hook = " .. str(def.hook) .. ","
    end
    if def.destroy_decoratives ~= nil then
        out[#out + 1] = "    destroy_decoratives = " .. tostring(def.destroy_decoratives) .. ","
    end
    if def.clear_area ~= nil then
        out[#out + 1] = "    clear_area = " .. tostring(def.clear_area) .. ","
    end

    if def.connection then
        local c = def.connection
        local bits = {
            "position = { x = " .. num(c.position.x) .. ", y = " .. num(c.position.y) .. " }",
            "side = " .. str(c.side),
            "gap = " .. num(c.gap or 0),
        }
        if c.connector ~= nil then
            bits[#bits + 1] = "connector = " .. tostring(c.connector)
        end
        out[#out + 1] = "    connection = { " .. table.concat(bits, ", ") .. " },"
    end

    if def.clearance_box then
        local b = def.clearance_box
        out[#out + 1] = "    clearance_box = { " .. pos(b[1]) .. ", " .. pos(b[2]) .. " },"
    end

    tile_layers_block(def.hidden_tiles, "hidden_tiles", out)
    tile_layers_block(def.tile_layers, "tile_layers", out)

    if def.entities and #def.entities > 0 then
        out[#out + 1] = "    entities = {"
        for _, e in ipairs(def.entities) do
            out[#out + 1] = entity_line(e, "        ")
        end
        out[#out + 1] = "    },"
    end

    if def.resources and #def.resources > 0 then
        out[#out + 1] = "    resources = {"
        for _, r in ipairs(def.resources) do
            out[#out + 1] = "        { name = " .. str(r.name) .. ", position = " .. pos(r.position)
                .. ", amount = " .. num(r.amount or 0) .. " },"
        end
        out[#out + 1] = "    },"
    end

    if def.anchors and next(def.anchors) then
        local names = {}
        for name in pairs(def.anchors) do names[#names + 1] = name end
        table.sort(names)
        out[#out + 1] = "    anchors = {"
        for _, name in ipairs(names) do
            local a = def.anchors[name]
            local bits = "position = { x = " .. num(a.position.x) .. ", y = " .. num(a.position.y) .. " }"
            if a.side then bits = bits .. ", side = " .. str(a.side) end
            out[#out + 1] = "        [" .. str(name) .. "] = { " .. bits .. " },"
        end
        out[#out + 1] = "    },"
    end

    if def.notes and #def.notes > 0 then
        out[#out + 1] = "    notes = {"
        for _, note in ipairs(def.notes) do
            out[#out + 1] = "        " .. str(note) .. ","
        end
        out[#out + 1] = "    },"
    end

    out[#out + 1] = "}"
    out[#out + 1] = ""
    return table.concat(out, "\n")
end

return M
