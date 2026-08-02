-- Orbital station surfaces generate as pure void. `orbital_station.lua` asks
-- for a surface whose only tile autoplace is `out-of-map`, and a tile with no
-- autoplace specification cannot be asked for -- so this is what makes an
-- orbit empty rather than grassy.
--
-- It is deliberately global and unconditional, which is why Nauvis has to opt
-- out explicitly: see data-final-fixes.lua.
data.raw.tile["out-of-map"].autoplace = {
    probability_expression = 1,
    placement_density = 1,
    order = "a",
    default_enabled = true,
    force = "",
}
