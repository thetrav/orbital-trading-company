local shape_def = require("scripts.shape_def")
local shape_registry = require("scripts.shape_registry")
local platform = require("scripts.platform")

local M = {}

-- Everything otc builds on Nauvis lands in one slot of one grid, centred on the
-- player compound at the origin. Slots are claimed in rings, and a ring only
-- covers the half-plane north of spawn (Factorio's -y is screen-up), so the
-- district reads as a rectangle growing east, north and west with the starting
-- compound in the middle of its bottom edge.
--
-- 32 is the pitch because the production room is 27 tiles across and a slot has
-- to hold the widest shape with room for the power lattice outside it.
local PITCH = 32
local POST = PITCH / 2
local PAD_MARGIN = 18
local PAD_TILE = "refined-concrete"

M.PITCH = PITCH

function M.init()
    local state = storage.district or {}
    state.taken = state.taken or {}
    state.posts = state.posts or {}
    state.slots = state.slots or {}
    storage.district = state
    return state
end

local function state()
    return storage.district or M.init()
end

--- Ring r holds 4r+1 slots: up the east column, west along the top, down the
--- west column. Walking them in that order is what draws the rectangle.
local function ring_slot(r, i)
    if i <= r then return r, -i end
    if i <= 3 * r - 1 then return r - (i - r), -r end
    return -r, -r + (i - 3 * r)
end

--- Slots through the end of ring r, so an index can be resolved to a ring
--- without walking every slot before it.
local function through(r)
    return 2 * r * r + 3 * r
end

--- The nth slot in claim order, as grid coordinates. Slot 0 is the first slot
--- of ring 1; the origin itself is the player compound and is never a slot.
function M.slot_at(n)
    local r = 1
    while n >= through(r) do r = r + 1 end
    local col, row = ring_slot(r, n - through(r - 1))
    -- `-i` with i = 0 is negative zero, which is equal to 0 but stringifies as
    -- "-0" -- so the row-0 slots would key differently from the same slot named
    -- by claim_at and get handed out twice.
    return col == 0 and 0 or col, row == 0 and 0 or row
end

function M.centre(col, row)
    return { x = col * PITCH, y = row * PITCH }
end

local function key_of(col, row)
    return string.format("%d,%d", col, row)
end

--- Take a specific slot, for the fixtures Nauvis starts the game with.
function M.claim_at(col, row)
    state().taken[key_of(col, row)] = true
    return M.centre(col, row)
end

--- Take the next free slot in ring order.
function M.claim()
    local taken = state().taken
    local n = 0
    while true do
        local col, row = M.slot_at(n)
        local key = key_of(col, row)
        if not taken[key] then
            taken[key] = true
            return M.centre(col, row), col, row
        end
        n = n + 1
    end
end

--- Where a shape's origin goes for its clearance box to sit centred in a slot.
function M.origin_for(def, centre)
    local box = def.clearance_box or shape_def.tile_bounds(def)
    if not box then return { x = centre.x, y = centre.y } end
    return {
        x = math.floor(centre.x - (box[1][1] + box[2][1]) / 2 + 0.5),
        y = math.floor(centre.y - (box[1][2] + box[2][2]) / 2 + 0.5),
    }
end

function M.pad_box(centre)
    return {
        { centre.x - PAD_MARGIN, centre.y - PAD_MARGIN },
        { centre.x + PAD_MARGIN, centre.y + PAD_MARGIN },
    }
end

local function pad_layer(centre)
    local tiles = {}
    for x = centre.x - PAD_MARGIN, centre.x + PAD_MARGIN do
        for y = centre.y - PAD_MARGIN, centre.y + PAD_MARGIN do
            tiles[#tiles + 1] = { x, y }
        end
    end
    return { { name = PAD_TILE, tiles = tiles } }
end

--- A substation at each of the slot's eight border points. Neighbours share
--- their border, so the lattice is continuous however the rectangle grows: 16
--- tiles apart is inside a substation's 18-tile wire reach, and no shape in the
--- district reaches past 14 tiles from its slot centre, so the ring never
--- collides with what it powers.
local function power_lattice(surface, centre, force_name)
    local posts = state().posts
    for _, offset in ipairs {
        { -POST, -POST }, { 0, -POST }, { POST, -POST },
        { -POST, 0 }, { POST, 0 },
        { -POST, POST }, { 0, POST }, { POST, POST },
    } do
        local x, y = centre.x + offset[1], centre.y + offset[2]
        local key = x .. "," .. y
        if not posts[key] then
            posts[key] = true
            local post = surface.create_entity {
                name = "substation",
                position = { x, y },
                force = force_name,
                create_build_effect_smoke = false,
            }
            if post then
                post.minable = false
                post.destructible = false
            end
        end
    end
end

function M.chart(surface, centre, force)
    local box = M.pad_box(centre)
    local area = { { box[1][1] - 2, box[1][2] - 2 }, { box[2][1] + 2, box[2][2] + 2 } }
    if force then
        force.chart(surface, area)
        return
    end
    for _, f in pairs(game.forces) do
        f.chart(surface, area)
    end
end

--- Charts everything claimed so far, for a force that did not exist when the
--- slots were built.
function M.chart_all(surface, force)
    for _, slot in ipairs(state().slots) do
        M.chart(surface, { x = slot.x, y = slot.y }, force)
    end
end

--- Lay the pad, build the shape centred in the slot, and tie it into the grid.
--- `owner` is the force the shape belongs to; the lattice always belongs to
--- Nauvis, because the grid is state infrastructure everyone shares.
function M.build(surface, shape_name, centre, owner, opts)
    local def = shape_registry.get(shape_name)
    if not def then
        log("district: unknown shape " .. tostring(shape_name))
        return nil
    end
    opts = opts or {}

    local origin = M.origin_for(def, centre)
    local ctx = platform.build_shape(surface, shape_name, origin, owner, {
        extra_tile_layers = pad_layer(centre),
        owned_by_force = opts.owned_by_force,
        context = opts.context,
    })
    power_lattice(surface, centre, "Nauvis")

    local st = state()
    st.slots[#st.slots + 1] = { x = centre.x, y = centre.y, shape = shape_name, owner = owner }
    M.chart(surface, centre)
    return ctx, origin
end

return M
