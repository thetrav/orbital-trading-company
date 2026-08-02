local stock = require("scripts.stock")

local M = {}

M.SUPPLY_NAME = "otc-supply-belt"
M.INTAKE_NAME = "otc-intake-belt"

-- An underground belt reports 4 transport lines, but only 1 and 2 are the
-- visible face that moves and that inserters can reach; 3 and 4 are the buried
-- half, where an inserted item sits forever. Supply must therefore never push
-- past line 2. Intake still drains every line, so anything already stranded on
-- the buried side is recovered. tools/probes/supply_belt_lines.lua pins this.
local VISIBLE_LINES = 2

local function line_count(entity)
    return entity.get_max_transport_line_index()
end

local function supply_line_count(entity)
    return math.min(entity.get_max_transport_line_index(), VISIBLE_LINES)
end

function M.init()
    storage.supply_belts = storage.supply_belts or {}
    storage.intake_belts = storage.intake_belts or {}
end

--- A supply belt is only ever an exit. Rotating one in game flips it to an
--- entrance, where it swallows items instead of handing them out and plays the
--- wrong animation.
---
--- `belt_to_ground_type` is read-only and assigning `direction` just flips the
--- type again -- the two are the same underlying property -- so an underground
--- belt cannot be *told* to be an exit, only built as one. Rebuild it facing
--- the way the rotation asked for, which makes a rotation flip the exit 180
--- degrees instead of turning it into an entrance.
---
--- Returns the entity that now stands there, or nil if nothing was done. The
--- caller must read `unit_number` beforehand: a rebuild changes it, so anything
--- keyed by it has to be migrated.
function M.enforce_exit(entity)
    if not entity or not entity.valid or entity.name ~= M.SUPPLY_NAME then return nil end
    if entity.belt_to_ground_type == "output" then return nil end

    local surface, position, force = entity.surface, entity.position, entity.force
    local direction = entity.direction
    local old = entity.unit_number
    local data = storage.supply_belts and storage.supply_belts[old]
    entity.destroy()

    local rebuilt = surface.create_entity {
        name = M.SUPPLY_NAME,
        position = position,
        force = force,
        direction = direction,
        type = "output",
        create_build_effect_smoke = false,
    }
    if not rebuilt then return nil end

    if data then
        storage.supply_belts[old] = nil
        M.register_supply(rebuilt, data.left, data.right)
    end
    return rebuilt
end

function M.register_supply(entity, left_item, right_item)
    if not entity or not entity.valid then return end
    storage.supply_belts = storage.supply_belts or {}
    storage.supply_belts[entity.unit_number] = {
        entity = entity,
        left = left_item,
        right = right_item,
    }
end

--- Resolve a shape entity's item fields onto the two lanes. `item` is the
--- shorthand for "both lanes"; `item_left`/`item_right` override per lane, and
--- a lane left nil is simply never fed, which keeps it clear for something else
--- to put items on.
function M.register_from_def(entity, def)
    local left = def.item_left or def.item
    local right = def.item_right or def.item
    if not left and not right then return false end
    M.register_supply(entity, left, right)
    return true
end

function M.register_intake(entity)
    if not entity or not entity.valid then return end
    storage.intake_belts = storage.intake_belts or {}
    storage.intake_belts[entity.unit_number] = { entity = entity }
end

function M.process()
    for unit_number, data in pairs(storage.supply_belts or {}) do
        local entity = data.entity
        if not entity or not entity.valid then
            storage.supply_belts[unit_number] = nil
        else
            for index = 1, supply_line_count(entity) do
                -- Not `cond and data.left or data.right`: a nil left lane
                -- falls through that idiom and gets fed the right lane's item,
                -- filling a lane that was deliberately left clear.
                local item_name
                if index % 2 == 1 then item_name = data.left else item_name = data.right end
                local line = item_name and entity.get_transport_line(index)
                if line and line.can_insert_at_back() and stock.take(item_name, 1) > 0 then
                    line.insert_at_back({ name = item_name, count = 1 })
                end
            end
        end
    end

    for unit_number, data in pairs(storage.intake_belts or {}) do
        local entity = data.entity
        if not entity or not entity.valid then
            storage.intake_belts[unit_number] = nil
        else
            for index = 1, line_count(entity) do
                local line = entity.get_transport_line(index)
                if line then
                    for _, item in pairs(line.get_contents()) do
                        local removed = line.remove_item({ name = item.name, count = item.count })
                        if removed > 0 then
                            stock.add(item.name, removed)
                        end
                    end
                end
            end
        end
    end
end

return M
