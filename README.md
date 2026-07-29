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

Run `./validate.sh` from the mod directory to run all checks:

| # | Check | What it catches |
|---|-------|-----------------|
| 1 | `luacheck` | Unused variables, undefined globals, common Lua mistakes |
| 2 | `lua-language-server` | Type mismatches against Factorio 2.0 API definitions |
| 3 | `--dump-data` (headless) | Prototype definition errors in `data.lua` |
| 4 | `--create` (headless) | Save-creation errors (runtime init) |
| 5 | `--load-game --until-tick 600` (headless) | Runtime errors during the first 10 seconds of gameplay |

The script expects a Factorio binary at `~/.local/share/Steam/steamapps/common/Factorio/bin/x64/factorio` and mods at `~/.factorio/mods`. Adjust paths at the top of `validate.sh` if your setup differs.

**All changes must pass `./validate.sh` before being committed.**

For API reference, consult the official docs: https://lua-api.factorio.com/latest/
