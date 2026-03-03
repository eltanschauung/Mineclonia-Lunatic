# mcl_lun_items: “proper” item name colors

In Mineclonia/Luanti, the most consistent way to color an item’s displayed name (works the same in inventories + creative, survives reconnects, doesn’t depend on per-stack metadata) is to colorize the *registered item definition* `description`, not `ItemStack` meta.

`mcl_lun_items` already has a helper used by the yin-yang orbs: `build_lun_description`.

## The pattern

- Use `color("<name>")` to resolve a palette color (provided by `colors_api`).
- Use `build_lun_description({ description=..., color=..., ... })` to produce the final `description` string with the first line colorized via `core.colorize`.
- Put that string directly into your item/node registration.

Example (Yakitori):

```lua
minetest.register_craftitem("mcl_lun_items:cooked_chicken", {
  description = build_lun_description({
    description = S("Chicken Yakitori"),
    color = color("axis"),
    skip_stats = true,
  }),
  -- ...
})
```

Variant:

```lua
minetest.register_craftitem("mcl_lun_items:yakitori_tare", {
  description = build_lun_description({
    description = S("Chicken Yakitori (+Tare)"),
    color = color("orchid"),
    skip_stats = true,
  }),
  -- ...
})
```

## Why not `ItemStack` meta coloring?

Avoid using `itemstack:get_meta():set_string("name", ...)` / `set_string("description", ...)` just to color names:

- It can be overridden or reset by other systems that rebuild item descriptions on join (e.g. enchantment/potion metadata refresh).
- `meta.name` in particular can force a separate “custom name” color style, which may not match the game’s normal tooltip coloring.

## Reference implementation

- Helper definition: `mods/mcl_lun_items/init.lua` (`build_lun_description`).
- Yakitori usage: `mods/mcl_lun_items/init.lua` (yakitori registrations).
