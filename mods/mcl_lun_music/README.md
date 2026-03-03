# mcl_lun_music

Silence-first, probability-gated ambient music controller inspired by Minecraft’s ambient music behavior.

This mod does not include music files. Add `.ogg` files to `mods/mcl_lun_music/sounds/` and register them via `mods/mcl_lun_music/tracks.lua` or `mcl_lun_music.register_track(...)`.

## Tracks

Each track is data-only:

- `id` (string, unique)
- `sound` (sound name without extension)
- `length` (seconds)
- `weight` (optional, default `1`)
- `allowed_contexts` (optional)
  - `dimension` (string or list)
  - `biome` (string or list of engine biome names)
  - `y_min`, `y_max` (numbers)
  - `states` (table of required flags)

Example `tracks.lua` entry:

```lua
{id="taiga", sound="mcl_lun_music_taiga_1", length=210, weight=2, allowed_contexts={biome={"Taiga","OldGrowthSpruceTaiga"}}}
```

## Overrides (boss/credits/scripted music)

Other mods can immediately stop ambient music and play an override track:

- `mcl_lun_music.play_override(playername, {sound=..., length=..., gain=...})`
- `mcl_lun_music.stop_override(playername)`

After an override ends, the controller returns to silence and applies a long cooldown.

