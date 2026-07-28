# Orbital Trading Company

A Factorio 2.0 mod where players start on a 10x10 concrete platform floating in space with a credits-based item purchasing system.

## How It Works

- On game start, the player spawns on a small concrete platform surrounded by void
- A **Buy Chest** and a **Constant Combinator** are placed automatically
- The combinator is pre-configured with 1 iron ore and 1 coal signals
- A green circuit wire connects the combinator to the buy chest
- The buy chest reads the circuit network signals and fills itself to match, deducting 1 credit per item
- Players start with **1,000 credits**
- The chest's "Read contents" option is disabled to prevent feedback loops

## Usage

1. Place a **Buy Chest** near a **Constant Combinator**
2. Connect them with green circuit wire
3. Set signals on the combinator for the items you want (e.g., 5 iron plate = buy 5 iron plate)
4. The buy chest automatically fills to match the combinator signals
5. Each item costs 1 credit — your credit balance is shown in the GUI

## Installation

Copy the `orbital-trading-company` folder into your Factorio mods directory (`~/.factorio/mods/`), then enable it in the mods menu.

## File Structure

```
orbital-trading-company/
  info.json          - Mod metadata (name, version, dependencies)
  data.lua           - Prototype definitions (item, recipe, entity)
  control.lua        - Runtime logic (platform, GUI, buying, circuits)
  locale/en/locale.cfg - English localization strings
  .luarc.json        - Lua Language Server configuration (Factorio API types)
  README.md          - This file
```

## Dev Tooling

### Lua Language Server with Factorio API

The project is configured with [lua-language-server](https://github.com/LuaLS/lua-language-server) (luaLS) for autocompletion, type checking, and inline documentation for the full Factorio 2.0 API.

**Setup (after cloning):**

```sh
# Install FMTK CLI (Factorio Modding Tool Kit)
npm install -g factoriomod-debug

# Generate Factorio API type definitions
fmtk docs -o latest
```

This creates the `factorio/` directory (gitignored) with type definitions for all Runtime and Prototype API classes, events, concepts, and defines.

**Editor support:**

- **VS Code**: Install the [Lua](https://marketplace.visualstudio.com/items?itemName=sumneko.lua) extension by sumneko
- **Other editors**: Any editor with luaLS support works (Neovim, Sublime, etc.)

**Regenerating after Factorio updates:**

```sh
fmtk docs -o latest
```

## Design Notes

- Map generation is forced to empty (no resources, water, cliffs, enemies)
- Pollution and enemy expansion are disabled
- The intro cutscene and crash site are disabled
- The buy chest entity type is `container` (not `logistic-container`) with circuit wire connections
- The buy chest uses requester chest graphics from the base mod
- Game state is stored in `storage` (Factorio 2.0's replacement for `global`)

---

## Contributing

This mod targets **Factorio 2.0**. Do not use Factorio 1.1 API patterns.

### Validating changes

The project uses two tools for static analysis. Run both before submitting changes:

```sh
# Type checking with Factorio API definitions
lua-language-server --check control.lua
lua-language-server --check data.lua

# Linting
luacheck control.lua data.lua
```

[lua-language-server](https://github.com/LuaLS/lua-language-server) provides autocompletion and type checking for the full Factorio Runtime and Prototype API. Use your editor's luaLS integration to catch issues as you type.

[luacheck](https://github.com/mpeterv/luacheck) catches common Lua mistakes (undefined variables, unused args, etc). Its config is in `.luacheckrc`.

### Headless smoke test

Factorio's headless mode can load the mod and start a game without a GUI, catching runtime errors before human testing. You need a Factorio installation (headless or full).

Find your Factorio binary:

```sh
# Steam on Linux (default)
FACTORIO=~/.local/share/Steam/steamapps/common/Factorio/bin/x64/factorio

# Headless server install
FACTORIO=/opt/factorio/bin/x64/factorio
```

Run the smoke tests:

```sh
MODS=~/.factorio/mods

# 1. Validate prototype loading (data stage only)
$FACTORIO --mod-directory "$MODS" --dump-data

# 2. Create a save and run for a few ticks
$FACTORIO --mod-directory "$MODS" --create /tmp/test-save.zip
$FACTORIO --mod-directory "$MODS" --load-game /tmp/test-save.zip --until-tick 600
```

`--dump-data` loads all mods, validates prototype definitions, and exits. This catches data-stage errors quickly.

`--until-tick 600` runs the game for 600 ticks (10 seconds of game time) then exits. Check the log at `~/.factorio/factorio-current.log` for errors.

For API reference, consult the official docs: https://lua-api.factorio.com/latest/
