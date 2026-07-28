std = "lua52"

globals = {
    "game",
    "script",
    "remote",
    "commands",
    "rendering",
    "storage",
    "defines",
    "settings",
    "mods",
    "data",
    "data_raw",
    "prototypes",
    "log",
    "localised_print",
}

read_globals = {
    "__DebugAdapter",
    "__Profiler",
    "util",
}

files["**/locale/**/*.lua"] = {
    globals = {},
}

exclude_files = {
    "factorio/",
}
