`mcl_lun_ambience` is a lightweight soundscape system that plays positional ambience to each player based on nearby world features.  
It depends on `mcl_lun_sounds` for mapping logical soundscape keys to actual sound file names.  
The mod runs server-side and uses `to_player`, so streams are per-player (not global).  
A soundscape definition includes `gain`, `delay`, and `variance` parameters (defaults `1, 0, 0`).  
Every `3.0s` (configurable), the mod scans around each player (loaded map only) and stores the closest source position for each soundscape.  
Tree detection collects `mcl_trees:leaves*` nodes in range, flood-fills 6-neighbor clusters, and treats any cluster size `>16` as a tree canopy.  
Each qualifying cluster yields an origin (centroid), and an `8`-node XZ exclusion radius is applied between origins before choosing the closest to the player.  
The tree sound key switches to `leaves_rustling_wind_mountain` when `mcl_lun_biomes.get_name(player_pos)` is `mountain`, otherwise it uses `leaves_rustling_wind`.  
Creek detection uses the closest `mcl_flowers:waterlily` in range as the sound origin.  
Distance gain is computed as `1 - dist/25` (clamped), so it is `1.0` at distance `0` and fades to `0.0` at distance `25`.  
Final gain multiplies distance gain by the soundscape `gain` and `mcl_lun_ambience_base_gain`.  
If `delay` is `0`, the sound plays as a continuous loop; if `delay` is `>0`, it replays after a pause of `delay ± variance` seconds.  
If `variance > delay`, both `delay` and `variance` are treated as `0`.  
Multiple soundscapes can play simultaneously; each maintains its own stream and is faded out and stopped when no source is in range.  
`/ambience_status` prints current detection and gain for debugging.  
