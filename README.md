# Orbital Trading Company

A Factorio 2.0 mod where players start on a 10x10 concrete platform floating in space with a credits-based item purchasing system.

## How It Works

- A green circuit wire connects the combinator to the buy chest
- The buy chest reads the circuit network signals and fills itself to match, deducting 1 credit per item
- The chest's "Read contents" option is disabled to prevent feedback loops

## Usage

1. Place a **Buy Chest** near a **Constant Combinator**
2. Connect them with green circuit wire
3. Set signals on the combinator for the items you want (e.g., 5 iron plate = buy 5 iron plate)
4. The buy chest automatically fills to match the combinator signals
5. cost can be found in the market ui, the credits for your company is diplayed in the top center
6. Use purchased goods to make more advanced intermediates
7. Place intermediates in a sell chest to get paid for them

Note that there are small transaction costs for buying and selling, if you buy something and immediately sell it you will make a loss.

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

## Capturing shapes

Rooms, starting buildings and expansion pieces are **captured from the game**, not written by
hand. You build the thing you want in the map editor, drag a tool over it, and the mod writes a
shape definition you can drop into `scripts/shapes/`.

### The workflow

1. Open the map editor (`/editor`) and build the shape somewhere with room around it.
2. Run `/otc-capture-shape my_room`. This names the next capture and puts the **Shape Capture
   Tool** in your cursor.
3. Drag the tool over the shape.
   - **Left-drag** captures tiles *and* entities.
   - **Right-drag** captures entities only, for layouts that go inside an existing room.

   A capture takes everything in the rectangle, terrain included. If grass and dirt that merely
   fell inside the selection show up in the output, re-run the command as
   `/otc-capture-shape my_room tiles=artificial` to drop any tile the map generator could have
   placed itself. `tiles=none` skips tiles entirely. The default, `tiles=all`, never silently
   discards anything — including ground you laid deliberately, as the Nauvis mine blocks do.
4. The definition is written to `script-output/otc-shapes/my_room.lua`, and the game prints a
   summary of what it found.
5. Copy that file into `scripts/shapes/` and add a line for it in `scripts/shape_registry.lua`.
   Give an expansion shape a cost in `scripts/expand_gui.lua` to make it purchasable.

Re-capturing is the normal way to edit a shape: change it in the editor, drag again, copy the
file over. The generated file is plain readable Lua, so hand-editing works too.

### Orientation and the connection anchor

Expansion shapes are captured **once**, facing east, and rotated to the other three directions
when they are built. Build it as if the player's gate were on the west side and the room extended
east; `scripts/shape_def.lua` handles the rest.

Rotation is a true rotation, not a mirror, so **make the room an odd number of tiles across**.
An even width puts the gate half a tile off centre, and the room then shifts sideways when it is
rotated. The tests fail on this.

A shape connects to the gate it was bought from through its `connection` anchor:

```lua
connection = { position = { x = -6, y = 0 }, side = "west", gap = 3, connector = true },
```

`gap` is how many tiles sit between the buying gate and the anchor, and `connector = true` asks
`scripts/shapes/connector.lua` to fill that space with the standard 3-wide walled tunnel. Shapes
that draw their own approach (the corridor, the asteroids) set `connector = false`.

The capture infers this from a `gate` entity on the west edge. To set it explicitly, place a
**Shape Marker** and type `connection:3` into its display panel.

### Markers

The **Shape Marker** entity (place it from the editor's entity list) labels an anchor. Whatever
you type into its panel becomes the anchor's role:

| Text | Meaning |
|---|---|
| `origin` | Shape-local `{0, 0}`. Defaults to the top-left corner of the selection. |
| `connection:3` | The connection anchor, with `gap = 3`. |
| anything else | Recorded in `def.anchors` for a hook to read. |

Markers are never rebuilt when the shape is placed.

### Tiles, and the `correct` flag

Each tile layer carries its own `correct` flag, passed straight to `LuaSurface.set_tiles` as
`correct_tiles`. It controls whether Factorio runs its transition-correction pass, which can
redraw the tiles *around* the shape as well:

- `otc-platform` defaults to **false** — platform sits directly on out-of-map, and correcting it
  bleeds transitions into the void.
- Everything else defaults to **true**, which is what natural tiles (`dirt-7`, `grass-1`) and
  the decorative floors want.

The defaults live in `shape_def.DEFAULT_CORRECT_TILES`; override per shape by editing the
`correct = ...` line in the generated file. Layers are applied in file order, so a base floor
listed first shows through where later layers don't cover.

### Hooks

Anything that needs bookkeeping beyond `create_entity` — registering a gate in `storage.gates`,
wiring a supply belt to an item, creating an orbital surface — lives in a hook named by the
definition:

```lua
hook = "room_gates",
```

Hooks are in `scripts/shape_hooks/` and registered in `scripts/shape_hooks/init.lua`. They
receive a context with the built entities grouped by role (`ctx.roles.gate`, `ctx.roles.supply`,
…), so they act on what the capture found rather than on hardcoded coordinates. Entities marked
`skip_create = true` are described by the definition but built by the hook.

Roles are inferred from entity names at capture time (see `ROLE_BY_NAME` in
`scripts/shape_capture.lua`). That lookup cannot tell a supply belt from any other transport
belt, and it knows nothing about the `item` a supply belt carries. Tag those in game with the
config tool.

### Tagging roles with the config tool

1. Run `/otc-config-shape` (admins only). This puts the **Shape Config Tool** in your cursor.
2. **Left-drag** over the entities you want to tag. A window lists each one with a role dropdown
   and an item picker.
3. Pick a role. A supply belt also gets **two item pickers, one per transport lane**, captioned
   with the screen side that lane occupies for that belt's facing — `top`/`bottom` for a
   horizontal belt, `left`/`right` for a vertical one. Leaving a picker empty keeps that lane
   clear, which is how you reserve it for an inserter to put things onto.
4. Every tagged entity gets a green floating label: `intake`, or `supply iron-plate` when both
   lanes carry the same thing, or `supply top=copper-plate` when only one lane is fed. That is
   how you check the tagging in the world before capturing.
5. **Right-drag** clears the tags under the selection.

Capture afterwards as normal: a tagged role beats the `ROLE_BY_NAME` lookup, and both `role` and
`item` land in the generated file, so nothing needs hand-editing.

Supply and intake belts get their role automatically from their prototype — each exists for one
purpose — so the only thing worth setting on them is a supply belt's per-lane items.

A capture always writes those out per lane, as `item_left` / `item_right`, so a lane left clear
for an inserter to fill is visible in the file rather than inferred. (`item = "iron-plate"` is
still understood when read, and older shapes use it to mean both lanes.)
`supply_belts.register_from_def` resolves all three fields, so a hook never reasons about lanes.

Add a role to `shape_config.ROLES` to offer it in the dropdown — `shape_def` buckets whatever
string it is given, so no other code has to change.

Tags live in `storage`, not on the entity, so they survive a save but not a rebuild: mine and
replace a tagged belt and you must tag it again. The tool is granted only by the command and is
flagged `only-in-cursor`, so it cannot reach a regular player's inventory.

### Placing a shape by hand

Shapes that are not bought from a gate — fixed Nauvis builds — go down with the placer:

1. Run `/otc-place-shape` (admins only). A list of every registered shape opens, with each
   one's footprint size, and the first pick goes straight into your cursor.
2. Click a shape in the list. Its placement item goes to your cursor and a blue footprint box
   follows the mouse, so you can see exactly what you are about to cover.
3. Left-click the map. The shape is built for the **Nauvis** force with its top-left corner at
   the box you were shown, and its hook runs. The tool then leaves your cursor: one placement
   per pick, so a stray second click cannot stack another copy on top. Click the shape in the
   list again to place another.

Build reach is lifted while the tool is in your cursor and restored the moment it leaves, so a
20-tile room can be landed from wherever you happen to be standing.

**Clear the area first** (on by default) destroys whatever is inside the footprint before
building. Turn it off and overlapping entities simply fail to appear instead. Either way the
game prints what was in the way. The footprint marker deliberately collides with nothing, so
placement is never blocked — clobbering is the tool's job, not the collision system's.

### Regenerating the built-in shapes

The shapes that predate this tool were converted from the old procedural generators by
`tools/export_builtin_shapes.lua`, which runs in plain Lua with no game involved:

```sh
lua tools/export_builtin_shapes.lua
```

The generators it renders are vendored under `tools/legacy_shapes/`, and
`test/shape_def_spec.lua` asserts the captured definitions still lay down exactly the same tiles
and walls they used to.

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
| 3 | `busted` | Unit tests in `test/`, including the shape-definition regressions |
| 4 | `--dump-data` (headless) | Prototype definition errors in `data.lua` |
| 5 | `--create` (headless) | Save-creation errors (runtime init) |
| 6 | `--load-game --until-tick 600` (headless) | Runtime errors during the first 10 seconds of gameplay |

The script expects a Factorio binary at `~/.local/share/Steam/steamapps/common/Factorio/bin/x64/factorio` and mods at `~/.factorio/mods`. Adjust paths at the top of `validate.sh` if your setup differs.

**All changes must pass `./validate.sh` before being committed.**

For API reference, consult the official docs: https://lua-api.factorio.com/latest/
