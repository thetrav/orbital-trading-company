-- Nauvis generates as a normal world: terrain, water, cliffs, trees, rocks and
-- decoratives all stay, and Nauvis clears whatever is in the way when it
-- builds. Two things are taken away, and they are the two the economy rests on.

-- No ore, no oil, anywhere. Players have no resources of their own, so buying
-- from Nauvis is the only way to get matter into the game; a patch of iron
-- inside walking distance would undo that. The prototypes keep their autoplace
-- specifications -- the planet's setup requires them -- so this works by
-- dropping the resources out of Nauvis's own generation instead.
local NO_GENERATE = {
    ["iron-ore"] = true,
    ["copper-ore"] = true,
    ["stone"] = true,
    ["coal"] = true,
    ["crude-oil"] = true,
    ["uranium-ore"] = true,
}

-- No enemies either. `size = 0` is what actually stops a control from placing
-- anything; control.lua sweeps newly generated chunks as a second line, because
-- players are free to walk out and explore and there must be nothing to meet
-- them.
local ZERO_CONTROLS = { ["enemy-base"] = true }
for name in pairs(NO_GENERATE) do
    ZERO_CONTROLS[name] = true
end

local nauvis = data.raw.planet["nauvis"]
local settings = nauvis and nauvis.map_gen_settings

if settings then
    -- `data-updates.lua` gives `out-of-map` a probability-1 autoplace so orbital
    -- stations generate as void. That is global, and Nauvis's tile settings do
    -- not name it -- so without this, the fallback wins and the whole planet
    -- comes out as void. Nauvis lists every tile it wants; nothing else gets a
    -- say.
    local tiles = settings.autoplace_settings and settings.autoplace_settings.tile
    if tiles then
        tiles.treat_missing_as_default = false
    end

    for name in pairs(ZERO_CONTROLS) do
        local control = settings.autoplace_controls and settings.autoplace_controls[name]
        if control then
            control.frequency = 0
            control.size = 0
            control.richness = 0
        end
    end

    -- Nauvis names its resources explicitly, and a named entry is placed
    -- whatever the control says.
    local entities = settings.autoplace_settings and settings.autoplace_settings.entity
    if entities and entities.settings then
        for name in pairs(NO_GENERATE) do
            entities.settings[name] = nil
        end
    end
end

local silo = data.raw["rocket-silo"]["rocket-silo"]
if silo and silo.energy_source then
    silo.energy_source = { type = "void" }
end
