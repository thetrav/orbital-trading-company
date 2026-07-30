local nauvis = data.raw.planet["nauvis"]

if nauvis and nauvis.map_gen_settings then
    -- Disable all entity autoplace (trees, rocks, fish, enemies, etc.)
    nauvis.map_gen_settings.autoplace_settings.entity = {
        treat_missing_as_default = false,
        settings = {}
    }

    -- Disable decorative autoplace (optional, but usually desired)
    nauvis.map_gen_settings.autoplace_settings.decorative = {
        treat_missing_as_default = false,
        settings = {}
    }

    -- Explicitly disable enemy bases
    local enemy = nauvis.map_gen_settings.autoplace_controls["enemy-base"]
    if enemy then
        enemy.frequency = 0
        enemy.size = 0
        enemy.richness = 0
    end
end