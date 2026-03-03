This mod exposes an OOP-style registry helper called `register_lun_item(def)` that records particle and light data for any lun item.  
Items call the helper with `name` (string or list) and optional fields: `particle_color/texture/radius/glow/height`, `light_level`, and `sounds`.  
Drop/held particle spawning and wielded_light registration consult the registry first, so you don’t need to touch ad-hoc tables.  
Rods, fans, orbs, and lunar bows are all registered through this helper; adding a new item just means calling `register_lun_item` with its properties.  
Wielded_light is registered only from the registry (no legacy fallback), so light changes are centralized in the helper.  
The registry is defined in `init.lua` and consumed by particle/light code; legacy tables remain only for defaults/constants.  
Lunar bows use their own `register_lun_bow` helper in `mcl_lun_bows` which also calls `register_lun_item` for the bow items.  
Projectile logic is still bespoke; the registry currently covers items, not projectile entities.  
To add a new lun item with particles/light, call `register_lun_item({name = "...", particle_color = "#rrggbb", light_level = N, ...})`.  
After registering, drop/held streams and wielded_light will pick it up automatically when the server loads.
