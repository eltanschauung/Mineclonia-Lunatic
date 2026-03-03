# `mcl_lun_nodes` Grill (`mcl_lun_nodes:grill`)

This document explains how the Grill block is implemented in `mods/mcl_lun_nodes/init.lua` so another LLM (or you) can modify it safely.

## What it is (current behavior)

The Grill is a decorative/fuel-burning node that:

- Accepts **fuel** in a 3×2 internal inventory grid.
- When fuel is burning, swaps to an **active** node variant and emits **campfire-style smoke particles**.
- Can display **one “grill item”** (currently limited to `mcl_lun_cooking:chicken_drumstick` and `mcl_lun_items:yakitori_uncooked`) on top of the grill using an entity.
- Does **not** currently cook items; the displayed food is visual only.

## Node definitions

- Inactive node: `mcl_lun_nodes:grill`
- Active node: `mcl_lun_nodes:grill_active`
  - `groups.not_in_creative_inventory = 1`
  - `light_source = 13`

Both share the same base definition (`grill_def`), then `grill_def_active` is derived from it.

## Metadata + inventories

Stored in node meta:

- `fuel_time` (float): remaining burn time (seconds).
- `fuel_totaltime` (float): duration of the current fuel “unit” (seconds), used to compute UI percent.
- `formspec` (string): the GUI string shown on right-click.
- `grill_item` (string): item name to display on top (e.g. `mcl_lun_cooking:chicken_drumstick`).

Node inventory lists:

- `fuel` (size 6): a 3×2 grid shown in the formspec.

### Fuel acceptance rules

The grill only allows putting items into `fuel` if `core.get_craft_result({method="fuel"})` returns a positive `time`.

Special case:

- If the fuel stack is `mcl_core:charcoal_lump`, burn time is multiplied by **3**.

## Formspect / UI flow

### `get_grill_formspec(fuel_percent)`

Builds a formspec that shows:

- A fire icon with a fill percent (`fuel_percent`).
- A 3×2 `list[context;fuel;...]` grid.
- Player inventory and listrings.

### Right click

`on_rightclick`:

1. If `grill_item` is empty and the player is holding one of the allowed items, it stores that item name in `meta.grill_item`, spawns/updates the display entity, and consumes 1 from the player (unless creative).
2. Otherwise, it opens the node’s formspec via `core.show_formspec(...)` using a formname that includes the position.

## Burning logic / timers

### Starting the burn

When something is placed/moved into the `fuel` list, `grill_on_metadata_inventory_put` starts the node timer with `core.get_node_timer(pos):start(1.0)`.

### `grill_node_timer(pos, elapsed)`

This is the burn loop. It:

1. Reads `fuel_time` / `fuel_totaltime`.
2. Ensures `fuel` list size is 6 (migration).
3. Decrements `fuel_time` based on `elapsed`.
4. If `fuel_time` hits 0, searches `fuel` slots for the first valid fuel:
   - Consumes fuel according to the `afterfuel` stack returned by the fuel craft.
   - Sets `fuel_time` and `fuel_totaltime` based on the fuel burn time (plus charcoal multiplier).
5. Updates meta and the stored formspec (with new percent).
6. Swaps node between inactive/active depending on `fuel_time > 0`.
7. When burn ends and it swaps from active → inactive, it calls `mcl_campfires.clear_smoke(pos)` (if available) to stop persistent smoke particles.

Notes:

- The timer function calls `mcl_furnaces.give_xp(pos)` when it loads a new fuel “unit”. The grill itself does not generate XP in this file; this call is effectively a no-op unless some other code sets `meta.xp`.

## Smoke effects

- Active grill smoke is driven by an ABM:
  - Runs every 4 seconds with `chance = 1`
  - Calls `mcl_campfires.generate_smoke(pos)` on `mcl_lun_nodes:grill_active`.

- On destruction (and when the burn ends), the mod calls `mcl_campfires.clear_smoke(pos)` to stop particles.

## Displayed “grill item” entity

Entity name: `mcl_lun_nodes:grill_item`

Key points:

- Visual type: `wielditem`
- It stores `_item` and `_pos` so it can persist across reloads (via `get_staticdata()`).
- It is spawned slightly above the grill (`pos + {x=0,y=0.52,z=0}`) and rotated to lay flat.
- Punching the entity drops the item and clears `meta.grill_item`.

### Keeping entities consistent

`update_grill_entity(pos)`:

- Removes any existing `mcl_lun_nodes:grill_item` entity within radius 0.5.
- If `meta.grill_item` is set, spawns a new entity and sets its texture to the item name.

An LBM (`mcl_lun_nodes:restore_grill_items`) runs **at every load** for both grill nodes to call `update_grill_entity(pos)` so the displayed item returns after chunk reload/server restart.

## Destruction / drops

`on_destruct`:

- Clears smoke.
- Removes nearby grill item entities.
- Calls `drop_items(pos, core.get_node(pos))`.

Important detail: `drop_items` in this file is created with `mcl_util.drop_items_from_meta_container("main")`.
The grill uses the `fuel` inventory list, not `main`, so this may **not** drop fuel contents as written.

## Craft recipe

The grill is craftable as:

```
iron ingot, iron ingot, iron ingot
(empty),    mcl_loom:loom, (empty)
(empty),    stick,         (empty)
```

## If you extend it (common changes)

- To actually cook the displayed food, you’d add:
  - A “cook progress” timer/state in meta (similar to `mcl_furnaces`), and
  - Logic to transform `grill_item` into an output item after time, potentially tied to `fuel_time`.
- To allow more grillable items, extend the allowlist in `grill_on_rightclick`.
- To ensure fuel drops on break, change `drop_items_from_meta_container("main")` to include the `fuel` list (or drop fuel manually in `on_destruct`).
