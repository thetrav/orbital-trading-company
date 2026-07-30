return {
    {
        type = "custom-input",
        name = "otc-toggle-trading",
        key_sequence = "",
        consuming = "none",
    },
    {
        type = "shortcut",
        name = "otc-trading",
        order = "z[otc]-a[trading]",
        action = "lua",
        icon = "__core__/graphics/icons/mod-manager/history.png",
        icon_size = 32,
        small_icon = "__core__/graphics/icons/mod-manager/history.png",
        small_icon_size = 32,
        toggleable = true,
    },
}
