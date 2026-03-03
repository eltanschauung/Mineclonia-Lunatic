# mcl_lun_biomes design spec

1. `mcl_lun_biomes` provides a lightweight “biome tag layer” that is independent of Luanti/Mineclonia engine biomes but can drive colors, weather, and spawning.
2. Tags are stored per mapblock column (16×16 XZ cells) as a compact byte string keyed by `bx,bz` in `mod_storage`, where each cell is one of `{ocean, river, mountain, snowytaiga, plains, forest, darkforest, bamboo, sprucetaiga}`.
3. A public API exposes `get_id(pos)`, `get_name(pos)`, and `set_id(pos, id)` plus `get_palette_index(pos, kind)` for grass/leaves.
4. The main command `/biomecalc <radius> [ymin ymax]` starts a background job that scans chunks with `VoxelManip` and fills tags, with `/biomecalc_stop` and `/biomecalc_status`.
5. Classification is heuristic and deterministic: it first marks exposed surface water as `ocean` or `river` based on connected-area width, then marks high-elevation terrain as `mountain`, then cold/snowy surfaces as `snowytaiga`, then marks columns near `mcl_trees:tree_spruce` (5×5 XZ window) as `sprucetaiga`, then marks columns near bamboo (5×5 XZ window) as `bamboo`, and finally chooses `forest` vs `plains` by nearby leaf/log density.
6. Jobs are incremental: each globalstep processes a bounded number of chunks and writes results immediately to avoid long server stalls and to allow resume after restart.
7. A debug command `/mybiome` prints both engine biome and custom biome for the player position and the palette indices being applied.
8. Integration with Mineclonia is done through narrow wrapper hooks rather than global overrides: patch `mcl_core.get_grass_palette_index` and `mcl_trees.get_biome_color` to consult the tag layer first.
9. Optional hooks can extend to precipitation selection and mob spawn rules by providing small adapter functions that Mineclonia modules call when present.
10. Manual control is supported via `/biomepaint <biome> <radius>` which sets tags directly for quick fixes on custom maps, `/darkforest [radius]` which tags a connected leaf canopy as `darkforest`, and `/bamboo [radius]` which tags XZ columns containing bamboo as `bamboo`.
11. Mappings from custom biome → palette index / fog / precipitation are configured via `minetest.conf` keys under `mcl_lun_biomes.*` and have sensible defaults.
12. The system never edits `map.sqlite` directly and avoids per-node metadata to keep world size and I/O manageable.
