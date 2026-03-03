local MODNAME = core.get_current_modname()
local storage = core.get_mod_storage()

local UNSET = 255
-- IMPORTANT: append-only to avoid changing existing stored ids.
local BIOME_NAMES = {"ocean", "river", "mountain", "snowytaiga", "plains", "forest", "darkforest", "bamboo", "sprucetaiga"}
local NAME_TO_ID = {}
for id, name in ipairs(BIOME_NAMES) do
	NAME_TO_ID[name] = id - 1
end

local ID_TO_NAME = {}
for k, v in pairs(NAME_TO_ID) do
	ID_TO_NAME[v] = k
end

local DEFAULT_PALETTES = {
	ocean = {grass = 0, leaves = 0},
	river = {grass = 0, leaves = 0},
	mountain = {grass = 6, leaves = 6}, -- close to Mineclonia ExtremeHills
	snowytaiga = {grass = 3, leaves = 3}, -- close to Mineclonia ColdTaiga
	plains = {grass = 0, leaves = 0}, -- Mineclonia Plains
	forest = {grass = 13, leaves = 13}, -- Mineclonia Forest
	darkforest = {grass = 18, leaves = 18}, -- Mineclonia DarkForest
	-- Mineclonia BambooJungle (fallback; updated on_mods_loaded when available).
	bamboo = {grass = 26, leaves = 26},
	-- Mineclonia OldGrowthSpruceTaiga (fallback; can be updated on_mods_loaded).
	sprucetaiga = {grass = 12, leaves = 12},
}

local function clamp_int(v, lo, hi)
	v = tonumber(v)
	if not v then
		return nil
	end
	v = math.floor(v)
	if lo and v < lo then v = lo end
	if hi and v > hi then v = hi end
	return v
end

	local function get_settings()
		local s = core.settings
		return {
			blocks_per_step = clamp_int(s:get("mcl_lun_biomes_blocks_per_step"), 1, 16) or 1,
			-- Multiplier applied to blocks_per_step for biomecalc. Default 4 to better utilize CPU.
			biomecalc_speed = clamp_int(s:get("mcl_lun_biomes_biomecalc_speed"), 1, 64) or 4,
			-- /darkforest is time-sliced to avoid server stalls regardless of canopy size.
			darkforest_nodes_per_step = clamp_int(s:get("mcl_lun_biomes_darkforest_nodes_per_step"), 200, 50000) or 2500,
			darkforest_flush_blocks_per_step = clamp_int(s:get("mcl_lun_biomes_darkforest_flush_blocks_per_step"), 1, 128) or 8,
			darkforest_time_budget_ms = clamp_int(s:get("mcl_lun_biomes_darkforest_time_budget_ms"), 1, 50) or 6,
			-- /bamboo paints a radius area; these control how quickly it progresses.
			bamboo_blocks_per_step = clamp_int(s:get("mcl_lun_biomes_bamboo_blocks_per_step"), 1, 128),
			-- Backward compat for an earlier /bamboo implementation.
			bamboo_nodes_per_step = clamp_int(s:get("mcl_lun_biomes_bamboo_nodes_per_step"), 1, 50000),
			-- Vertical scan for /bamboo bamboo detection.
			bamboo_y_span = clamp_int(s:get("mcl_lun_biomes_bamboo_y_span"), 8, 512) or 128,
			-- /bamboo3 cleanup command.
			bamboo3_blocks_per_step = clamp_int(s:get("mcl_lun_biomes_bamboo3_blocks_per_step"), 1, 256) or 12,
			bamboo3_time_budget_ms = clamp_int(s:get("mcl_lun_biomes_bamboo3_time_budget_ms"), 1, 100) or 10,
			ymin = clamp_int(s:get("mcl_lun_biomes_default_ymin"), -31000, 31000) or -32,
			ymax = clamp_int(s:get("mcl_lun_biomes_default_ymax"), -31000, 31000) or 192,
			-- Treat terrain above this Y as "mountain" (Mineclonia-like ExtremeHills palette).
			mountain_y = clamp_int(s:get("mcl_lun_biomes_mountain_y"), -31000, 31000) or 37,
		ocean_min_depth = clamp_int(s:get("mcl_lun_biomes_ocean_min_depth"), 1, 128) or 5,
		forest_scan = clamp_int(s:get("mcl_lun_biomes_forest_scan"), 1, 32) or 8,
		bamboo_scan = clamp_int(s:get("mcl_lun_biomes_bamboo_scan"), 1, 256) or 64,
		forest_tree_radius = clamp_int(s:get("mcl_lun_biomes_forest_tree_radius"), 1, 24) or 8,
		forest_tree_columns_min = clamp_int(s:get("mcl_lun_biomes_forest_tree_columns_min"), 1, 128) or 10,
	}
end

local function key_for_block(bx, bz)
	return ("%d,%d"):format(bx, bz)
end

local function floor_div(a, b)
	return math.floor(a / b)
end

local function pos_to_block_cell(pos)
	local bx = floor_div(pos.x, 16)
	local bz = floor_div(pos.z, 16)
	local lx = pos.x % 16
	local lz = pos.z % 16
	local idx = lz * 16 + lx + 1
	return bx, bz, idx
end

local block_cache = {}

local function get_block_data(bx, bz)
	local key = key_for_block(bx, bz)
	local cached = block_cache[key]
	if cached ~= nil then
		return cached
	end
	local raw = storage:get_string(key)
	if raw == "" then
		block_cache[key] = false
		return nil
	end
	block_cache[key] = raw
	return raw
end

local function set_block_data(bx, bz, raw)
	local key = key_for_block(bx, bz)
	storage:set_string(key, raw)
	block_cache[key] = raw
end

local function make_filled_block(byte_val)
	local ch = string.char(byte_val)
	return ch:rep(256)
end

local api = rawget(_G, "mcl_lun_biomes") or {}

function api.get_id(pos)
	if not pos then
		return nil
	end
	local bx, bz, idx = pos_to_block_cell(pos)
	local raw = get_block_data(bx, bz)
	if not raw then
		return nil
	end
	local b = raw:byte(idx)
	if not b or b == UNSET then
		return nil
	end
	return b
end

function api.get_name(pos)
	local id = api.get_id(pos)
	return id ~= nil and ID_TO_NAME[id] or nil
end

function api.set_id(pos, id)
	if not pos then
		return false
	end
	id = clamp_int(id, 0, #BIOME_NAMES - 1)
	if id == nil then
		return false
	end
	local bx, bz, idx = pos_to_block_cell(pos)
	local raw = get_block_data(bx, bz)
	if not raw then
		raw = make_filled_block(UNSET)
	end
	if raw:len() ~= 256 then
		raw = make_filled_block(UNSET)
	end
	local before = raw:byte(idx)
	if before == id then
		return true
	end
	local patched = table.concat({
		raw:sub(1, idx - 1),
		string.char(id),
		raw:sub(idx + 1),
	})
	set_block_data(bx, bz, patched)
	return true
end

function api.resolve_id(name)
	if type(name) ~= "string" then
		return nil
	end
	local n = name:lower():gsub("%s+", "")
	if n == "snowy_taiga" or n == "snowytaiga" or n == "snowtaiga" then
		n = "snowytaiga"
	end
	if n == "dark_forest" or n == "darkforest" then
		n = "darkforest"
	end
	if n == "bamboojungle" or n == "bamboo_jungle" then
		n = "bamboo"
	end
	return NAME_TO_ID[n]
end

function api.set_block(bx, bz, id)
	id = clamp_int(id, 0, #BIOME_NAMES - 1)
	if id == nil then
		return false
	end
	set_block_data(bx, bz, make_filled_block(id))
	return true
end

function api.palette_index(pos, kind)
	local id = api.get_id(pos)
	if id == nil then
		return nil
	end
	local name = ID_TO_NAME[id]
	local pal = name and DEFAULT_PALETTES[name]
	if not pal then
		return nil
	end
	return pal[kind]
end

_G.mcl_lun_biomes = api

local function resolve_biome_id(name)
	if type(name) ~= "string" then
		return nil
	end
	name = name:lower():gsub("%s+", "")
	if name == "snowy_taiga" or name == "snowytaiga" or name == "snowtaiga" then
		name = "snowytaiga"
	end
	if name == "dark_forest" or name == "darkforest" then
		name = "darkforest"
	end
	if name == "bamboojungle" or name == "bamboo_jungle" then
		name = "bamboo"
	end
	if name == "spruce_taiga" or name == "spruce-taiga" then
		name = "sprucetaiga"
	end
	return NAME_TO_ID[name]
end

local function get_engine_biome_name(pos)
	if not (core.get_biome_data and core.get_biome_name) then
		return nil
	end
	local bd = core.get_biome_data(pos)
	if not bd or not bd.biome then
		return nil
	end
	return core.get_biome_name(bd.biome)
end

core.register_chatcommand("mybiome", {
	description = "Show engine biome and mcl_lun_biomes tag at your position.",
	privs = {interact = true},
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local pos = vector.round(player:get_pos())
		local eng = get_engine_biome_name(pos) or "Unknown"
		local custom = api.get_name(pos) or "unset"
		local grass = api.palette_index(pos, "grass")
		local leaves = api.palette_index(pos, "leaves")
		return true, ("Engine=%s | Custom=%s | grass=%s leaves=%s"):format(
			eng, custom, grass ~= nil and tostring(grass) or "-", leaves ~= nil and tostring(leaves) or "-"
		)
	end,
})

core.register_chatcommand("biomepaint", {
	description = "Set mcl_lun_biomes tags in a radius around you: /biomepaint <ocean|river|mountain|snowytaiga|plains|forest|darkforest|bamboo> <radius>",
	params = "<biome> <radius>",
	privs = {server = true},
	func = function(name, param)
		local biome, radius = string.match(param or "", "^%s*(%S+)%s+(%-?%d+)%s*$")
		local id = resolve_biome_id(biome)
		if id == nil then
			return false, "Unknown biome. Valid: ocean, river, mountain, snowytaiga, plains, forest, darkforest, bamboo."
		end
		radius = clamp_int(radius, 16, 4096) or 128

		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local pos = vector.round(player:get_pos())
		local bx_min = floor_div(pos.x - radius, 16)
		local bx_max = floor_div(pos.x + radius, 16)
		local bz_min = floor_div(pos.z - radius, 16)
		local bz_max = floor_div(pos.z + radius, 16)

		local blocks = 0
		for bx = bx_min, bx_max do
			for bz = bz_min, bz_max do
				api.set_block(bx, bz, id)
				blocks = blocks + 1
			end
		end
			core.log("action", ("[%s] /biomepaint %s radius=%d blocks=%d"):format(MODNAME, BIOME_NAMES[id + 1], radius, blocks))
			return true, ("Painted %d mapblocks as %s."):format(blocks, BIOME_NAMES[id + 1])
		end,
})

local job = nil

local function start_biomecalc_job(opts)
	if job then
		return false, "A biomecalc job is already running. Use /biomecalc_status or /biomecalc_stop."
	end
	if not opts then
		return false, "Missing options."
	end
	local bx_min = clamp_int(opts.bx_min, -32768, 32767)
	local bx_max = clamp_int(opts.bx_max, -32768, 32767)
	local bz_min = clamp_int(opts.bz_min, -32768, 32767)
	local bz_max = clamp_int(opts.bz_max, -32768, 32767)
	if not (bx_min and bx_max and bz_min and bz_max) then
		return false, "Invalid bounds."
	end
	if bx_min > bx_max then bx_min, bx_max = bx_max, bx_min end
	if bz_min > bz_max then bz_min, bz_max = bz_max, bz_min end

	local settings = get_settings()
	local ymin = clamp_int(opts.ymin, -31000, 31000) or settings.ymin
	local ymax = clamp_int(opts.ymax, -31000, 31000) or settings.ymax
	if ymin > ymax then ymin, ymax = ymax, ymin end

	local total = (bx_max - bx_min + 1) * (bz_max - bz_min + 1)
	job = {
		start = os.time(),
		kind = opts.kind or "biomecalc",
		bx = bx_min,
		bz = bz_min,
		bx_min = bx_min,
		bx_max = bx_max,
		bz_min = bz_min,
		bz_max = bz_max,
		ymin = ymin,
		ymax = ymax,
		total = total,
		done = 0,
		settings = settings,
	}
	return true, total
end

	local function build_cid_sets()
		local water_cids, leaves_cids, tree_cids, bamboo_cids = {}, {}, {}, {}
		for name, def in pairs(core.registered_nodes) do
			if def and def.groups then
			if (def.groups.water or 0) > 0 then
				water_cids[core.get_content_id(name)] = true
			end
			if (def.groups.leaves or 0) > 0 then
				leaves_cids[core.get_content_id(name)] = true
			end
			if (def.groups.tree or 0) > 0 then
				tree_cids[core.get_content_id(name)] = true
			end
				-- Bamboo detection for biomecalc should only consider the actual bamboo plant nodes
				-- from mcl_bamboo, not bamboo-related decoration/trunks from other mods.
				if name:sub(1, 10) == "mcl_bamboo" and (def.groups.bamboo_tree or 0) > 0 then
					bamboo_cids[core.get_content_id(name)] = true
				end
			end
		end
		-- Optional compatibility: treat Mineclonia's bamboo trunk node as bamboo, too.
		do
			local n = "mcl_trees:tree_bamboo"
			local cid = core.registered_nodes[n] and core.get_content_id(n) or nil
			if cid then
				bamboo_cids[cid] = true
			end
		end
		local snow_cids = {}
		for _, n in ipairs({
			"mcl_core:snow",
			"mcl_core:snowblock",
		"mcl_core:dirt_with_grass_snow",
		"mcl_core:dirt_with_snow",
		"mcl_core:ice",
		"mcl_core:packed_ice",
	}) do
		local cid = core.registered_nodes[n] and core.get_content_id(n) or nil
		if cid then
			snow_cids[cid] = true
		end
	end
	local spruce_cids = {}
	do
		local n = "mcl_trees:tree_spruce"
		local cid = core.registered_nodes[n] and core.get_content_id(n) or nil
		if cid then
			spruce_cids[cid] = true
		end
	end
	return water_cids, leaves_cids, tree_cids, snow_cids, bamboo_cids, spruce_cids
end

local CID_AIR = core.CONTENT_AIR
local CID_IGNORE = core.CONTENT_IGNORE
local CID_SETS = nil

local function get_pointed_leaf_pos(player, range)
	if not (player and player.is_player and player:is_player()) then
		return nil
	end
	range = clamp_int(range, 1, 256) or 48

	local props = player:get_properties() or {}
	local eye_h = tonumber(props.eye_height) or 1.47
	local start = vector.add(player:get_pos(), {x = 0, y = eye_h, z = 0})
	local dir = player:get_look_dir()
	local finish = vector.add(start, vector.multiply(dir, range))

	local ray = core.raycast(start, finish, false, true)
	for pointed in ray do
		if pointed.type == "node" and pointed.under then
			local pos = vector.round(pointed.under)
			local node = core.get_node_or_nil(pos)
			if node and node.name and core.get_item_group(node.name, "leaves") > 0 then
				return pos
			end
		end
	end
	return nil
end

local function get_pointed_bamboo_pos(player, range)
	if not (player and player.is_player and player:is_player()) then
		return nil
	end
	range = clamp_int(range, 1, 256) or 96

	local props = player:get_properties() or {}
	local eye_h = tonumber(props.eye_height) or 1.47
	local start = vector.add(player:get_pos(), {x = 0, y = eye_h, z = 0})
	local dir = player:get_look_dir()
	local finish = vector.add(start, vector.multiply(dir, range))

	local ray = core.raycast(start, finish, false, true)
	for pointed in ray do
		if pointed.type == "node" and pointed.under then
			local pos = vector.round(pointed.under)
			local node = core.get_node_or_nil(pos)
			if node and node.name then
				-- Only accept actual mcl_bamboo plant nodes (avoid bamboo-like decoration/trunks from other mods).
				if node.name:sub(1, 10) == "mcl_bamboo" and core.get_item_group(node.name, "bamboo_tree") > 0 then
					return pos
				end
			end
		end
	end
	return nil
end

local function get_pointed_node_pos(player, range, predicate)
	if not (player and player.is_player and player:is_player()) then
		return nil
	end
	range = clamp_int(range, 1, 256) or 48

	local props = player:get_properties() or {}
	local eye_h = tonumber(props.eye_height) or 1.47
	local start = vector.add(player:get_pos(), {x = 0, y = eye_h, z = 0})
	local dir = player:get_look_dir()
	local finish = vector.add(start, vector.multiply(dir, range))

	local ray = core.raycast(start, finish, false, true)
	for pointed in ray do
		if pointed.type == "node" and pointed.under then
			local pos = vector.round(pointed.under)
			local node = core.get_node_or_nil(pos)
			if node and node.name and (not predicate or predicate(node.name, pos, node)) then
				return pos, node.name, node
			end
		end
	end
	return nil
end

local function collect_connected_nodes(start_pos, want_names, max_nodes)
	if not start_pos then
		return nil
	end
	local want_predicate = nil
	if type(want_names) == "function" then
		want_predicate = want_names
	elseif type(want_names) == "string" then
		local set = {[want_names] = true}
		want_predicate = function(node_name)
			return set[node_name] == true
		end
	elseif type(want_names) == "table" then
		local set = {}
		for _, n in pairs(want_names) do
			if type(n) == "string" then
				set[n] = true
			end
		end
		want_predicate = function(node_name)
			return set[node_name] == true
		end
	else
		return nil
	end
	max_nodes = clamp_int(max_nodes, 1, 500000) or 50000

	local visited = {}
	local found = {}
	local q = {start_pos}
	local qh = 1

	local minp = vector.new(start_pos)
	local maxp = vector.new(start_pos)

	local function update_bounds(p)
		if p.x < minp.x then minp.x = p.x end
		if p.y < minp.y then minp.y = p.y end
		if p.z < minp.z then minp.z = p.z end
		if p.x > maxp.x then maxp.x = p.x end
		if p.y > maxp.y then maxp.y = p.y end
		if p.z > maxp.z then maxp.z = p.z end
	end

	while qh <= #q do
		local p = q[qh]
		q[qh] = nil
		qh = qh + 1

		local h = core.hash_node_position(p)
		if not visited[h] then
			visited[h] = true
			local node = core.get_node_or_nil(p)
			if node and node.name and want_predicate(node.name, p, node) then
				found[#found + 1] = p
				update_bounds(p)
				if #found >= max_nodes then
					return nil, ("Connected blob too large (>%d nodes); aborting."):format(max_nodes)
				end
				-- 26-neighborhood (faces+edges+corners) to match "blob" connectivity expectations.
				for dx = -1, 1 do
					for dy = -1, 1 do
						for dz = -1, 1 do
							if not (dx == 0 and dy == 0 and dz == 0) then
								q[#q + 1] = vector.offset(p, dx, dy, dz)
							end
						end
					end
				end
			end
		end
	end

	return {
		nodes = found,
		minp = minp,
		maxp = maxp,
	}
end

local function set_cells_bulk(cols, id)
	if not cols or not next(cols) then
		return 0, 0
	end

	local updated_cols = 0
	local updated_blocks = 0

	for _key, upd in pairs(cols) do
		local bx = upd.bx
		local bz = upd.bz
		local set = upd.set
		if bx and bz and set and next(set) then
			local raw = get_block_data(bx, bz)
			if not raw or raw:len() ~= 256 then
				raw = make_filled_block(UNSET)
			end
			local bytes = {raw:byte(1, 256)}
			for cell_idx in pairs(set) do
				if bytes[cell_idx] ~= id then
					bytes[cell_idx] = id
				end
			end
			for i = 1, 256 do
				bytes[i] = string.char(bytes[i])
			end
			set_block_data(bx, bz, table.concat(bytes))
			updated_blocks = updated_blocks + 1
			for _ in pairs(set) do
				updated_cols = updated_cols + 1
			end
		end
	end

	return updated_cols, updated_blocks
end

local darkforest_job = nil
local bamboo_job = nil
local bamboo3_job = nil

local function start_darkforest_job(start_leaf_pos, radius)
	if darkforest_job then
		return false, "A /darkforest job is already running. Use /darkforest_status or /darkforest_stop."
	end
	if job then
		return false, "A biomecalc job is running. Stop it with /biomecalc_stop before using /darkforest."
	end
	if bamboo_job then
		return false, "A /bamboo job is running. Stop it with /bamboo_stop before using /darkforest."
	end

	radius = clamp_int(radius, 8, 512) or 256
	start_leaf_pos = vector.round(start_leaf_pos)

	local id = NAME_TO_ID.darkforest
	if id == nil then
		return false, "Dark forest biome id not registered."
	end

	if not CID_SETS then
		CID_SETS = {build_cid_sets()}
	end
	local leaves_cids = CID_SETS[2]
	if not leaves_cids or next(leaves_cids) == nil then
		return false, "Leaf CID set unavailable."
	end

	-- Only consider a narrow canopy band around the clicked leaf.
	local y_span = 24
	local y_min = math.max(-31000, start_leaf_pos.y - y_span)
	local y_max = math.min(31000, start_leaf_pos.y + y_span)

	local cx, cz = start_leaf_pos.x, start_leaf_pos.z
	local r2 = radius * radius

	local feather = math.min(48, math.max(8, math.floor(radius * 0.18)))
	local inner = radius - feather
	if inner < 0 then inner = 0 end
	local inner2 = inner * inner

		local seed = tonumber(core.get_mapgen_setting("seed")) or 0
		local perlin = core.get_perlin(seed + 24680, 2, 0.6, 96)

		local use_hash_queue = not not (core.hash_node_position and core.get_position_from_hash)

		local visited = {}
		local start_hash = core.hash_node_position and core.hash_node_position(start_leaf_pos) or nil
		if start_hash then
			visited[start_hash] = true
		else
			visited[start_leaf_pos.x .. "," .. start_leaf_pos.y .. "," .. start_leaf_pos.z] = true
		end

		local settings = get_settings()

		darkforest_job = {
			start = os.time(),
			start_pos = start_leaf_pos,
			cx = cx,
			cz = cz,
			radius = radius,
			r2 = r2,
			y_min = y_min,
			y_max = y_max,
			id = id,
			leaves_cids = leaves_cids,
			inner = inner,
			inner2 = inner2,
			feather = feather,
			perlin = perlin,
			use_hash_queue = use_hash_queue,
			queue = {use_hash_queue and start_hash or start_leaf_pos},
			qh = 1,
			qt = 1,
			visited = visited,
			seen_cols = {},
			pending = {},
			pending_order = {},
			pending_count = 0,
			flush_i = 1,
			phase = "scan",
			updated_cols = 0,
			updated_blocks = 0,
			nodes_done = 0,
			cols_done = 0,
			max_nodes = 250000,
			nodes_per_step = settings.darkforest_nodes_per_step,
			flush_blocks_per_step = settings.darkforest_flush_blocks_per_step,
			time_budget_us = (settings.darkforest_time_budget_ms or 6) * 1000,
			tmp_hash_pos = {x = 0, y = 0, z = 0},
		}

	return true, ("Queued /darkforest (radius=%d). Use /darkforest_status."):format(radius)
end

	local function darkforest_step(nodes_budget)
		local j = darkforest_job
		if not j then
			return
		end

		nodes_budget = clamp_int(nodes_budget, 200, 50000) or j.nodes_per_step or 2500

		local cx, cz = j.cx, j.cz
		local r2 = j.r2
		local y_min, y_max = j.y_min, j.y_max
		local leaves_cids = j.leaves_cids
		local inner2 = j.inner2
		local feather = j.feather
		local perlin = j.perlin
		local use_hash_queue = j.use_hash_queue

		local function should_paint_column(x, z, d2)
			if feather <= 0 or d2 <= inner2 then
				return true
			end
			-- Use squared distances to avoid sqrt; slightly non-linear feathering is fine for organic edges.
			local denom = (r2 - inner2)
			if denom <= 0 then
				return true
			end
			local t = (d2 - inner2) / denom
			if t < 0 then t = 0 end
			if t > 1 then t = 1 end
			local chance = 1 - t
			chance = chance * chance * (3 - 2 * chance)
			local n = perlin:get_2d({x = x, y = z}) * 0.5 + 0.5
			return n < chance
		end

		local function flush_pending(max_blocks)
			max_blocks = clamp_int(max_blocks, 1, 256) or 8
			local blocks_done = 0
			local snowy_id = NAME_TO_ID.snowytaiga
			while blocks_done < max_blocks do
				local bkey = j.pending_order[j.flush_i]
				if not bkey then
					return true
				end
				j.flush_i = j.flush_i + 1
				local upd = j.pending[bkey]
				if upd and upd.bx and upd.bz and upd.set and next(upd.set) then
					local raw = get_block_data(upd.bx, upd.bz)
					if not raw or raw:len() ~= 256 then
						raw = make_filled_block(UNSET)
					end
					local bytes = {raw:byte(1, 256)}
					local changed_cols = 0
					for cell_idx in pairs(upd.set) do
						-- Never overwrite snowytaiga with darkforest.
						if snowy_id ~= nil and bytes[cell_idx] == snowy_id then
							-- keep
						elseif bytes[cell_idx] ~= j.id then
							bytes[cell_idx] = j.id
						end
						changed_cols = changed_cols + 1
					end
					for i = 1, 256 do
						bytes[i] = string.char(bytes[i])
					end
					set_block_data(upd.bx, upd.bz, table.concat(bytes))
					j.updated_blocks = j.updated_blocks + 1
					j.updated_cols = j.updated_cols + changed_cols
					j.pending[bkey] = nil
					j.pending_count = math.max(0, (j.pending_count or 0) - 1)
					blocks_done = blocks_done + 1
				end
			end
			return false
		end

		if j.phase == "flush" then
			local done = flush_pending(j.flush_blocks_per_step or 8)
			if done then
				local elapsed = os.time() - (j.start or os.time())
				local verb = j.aborted and "aborted" or "complete"
				core.log("action", ("[%s] /darkforest %s cols=%d blocks=%d nodes=%d elapsed=%ds"):format(
					MODNAME, verb, j.updated_cols or 0, j.updated_blocks or 0, j.nodes_done or 0, elapsed
				))
				darkforest_job = nil
			end
			return
		end

		local start_us = core.get_us_time and core.get_us_time() or nil
		local time_budget_us = j.time_budget_us or 6000

		local function push(nx, ny, nz)
			if ny < y_min or ny > y_max then
				return
			end
			local ndx = nx - cx
			local ndz = nz - cz
			if ndx * ndx + ndz * ndz > r2 then
				return
			end

			local h
			if core.hash_node_position then
				local tmp = j.tmp_hash_pos
				tmp.x, tmp.y, tmp.z = nx, ny, nz
				h = core.hash_node_position(tmp)
			else
				h = nx .. "," .. ny .. "," .. nz
			end

			if j.visited[h] then
				return
			end
			j.visited[h] = true

			j.qt = j.qt + 1
			if use_hash_queue and type(h) == "number" then
				j.queue[j.qt] = h
			else
				j.queue[j.qt] = {x = nx, y = ny, z = nz}
			end
		end

			local processed = 0
			while processed < nodes_budget do
				if start_us and (processed % 64) == 0 and (core.get_us_time() - start_us) >= time_budget_us then
					return
				end

			if j.qh > j.qt then
				j.phase = "flush"
				return
			end

			local qv = j.queue[j.qh]
			j.queue[j.qh] = nil
			j.qh = j.qh + 1

			local pos
			if use_hash_queue and type(qv) == "number" then
				pos = core.get_position_from_hash(qv)
			else
				pos = qv
			end

			if j.nodes_done >= (j.max_nodes or 250000) then
				j.aborted = true
				j.phase = "flush"
				return
			end

			local x, y, z = pos.x, pos.y, pos.z
			if y >= y_min and y <= y_max then
				local dx = x - cx
				local dz = z - cz
				local d2 = dx * dx + dz * dz
				if d2 <= r2 then
					-- Important: get_node_or_nil does not force-load mapblocks (avoids server stalls).
					local node = core.get_node_or_nil(pos)
					if node and node.name then
						local cid = core.get_content_id(node.name)
						if leaves_cids[cid] then
							j.nodes_done = j.nodes_done + 1

							local bx = floor_div(x, 16)
							local bz = floor_div(z, 16)
							local cell_idx = (z % 16) * 16 + (x % 16) + 1
							local bkey = key_for_block(bx, bz)
							local seen_block = j.seen_cols[bkey]
							if not seen_block then
								seen_block = {}
								j.seen_cols[bkey] = seen_block
							end

							if seen_block[cell_idx] == nil then
								local paint = should_paint_column(x, z, d2)
								seen_block[cell_idx] = paint
								if paint then
									j.cols_done = j.cols_done + 1
									local upd = j.pending[bkey]
									if not upd then
										upd = {bx = bx, bz = bz, set = {}}
										j.pending[bkey] = upd
										j.pending_count = (j.pending_count or 0) + 1
										j.pending_order[#j.pending_order + 1] = bkey
									end
									upd.set[cell_idx] = true
								end
							end

							push(x + 1, y, z)
							push(x - 1, y, z)
							push(x, y + 1, z)
							push(x, y - 1, z)
							push(x, y, z + 1)
							push(x, y, z - 1)
						end
					end
				end
			end

			processed = processed + 1
		end
end

local function darkforest_from_leaf_cluster(start_leaf_pos, radius)
	return start_darkforest_job(start_leaf_pos, radius)
end

local function start_bamboo_job(start_bamboo_pos, radius)
	if bamboo_job then
		return false, "A /bamboo job is already running. Use /bamboo_status or /bamboo_stop."
	end
	if job then
		return false, "A biomecalc job is running. Stop it with /biomecalc_stop before using /bamboo."
	end
	if darkforest_job then
		return false, "A /darkforest job is running. Stop it with /darkforest_stop before using /bamboo."
	end

	radius = clamp_int(radius, 8, 512) or 256
	start_bamboo_pos = vector.round(start_bamboo_pos)

	local id = NAME_TO_ID.bamboo
	if id == nil then
		return false, "Bamboo biome id not registered."
	end

	if not CID_SETS then
		CID_SETS = {build_cid_sets()}
	end
	local bamboo_cids = CID_SETS[5]
	if not bamboo_cids or next(bamboo_cids) == nil then
		return false, "Bamboo CID set unavailable."
	end

	local cx, cz = start_bamboo_pos.x, start_bamboo_pos.z
	local r2 = radius * radius
	local bx_min = floor_div(cx - radius, 16)
	local bx_max = floor_div(cx + radius, 16)
	local bz_min = floor_div(cz - radius, 16)
	local bz_max = floor_div(cz + radius, 16)

	local total = (bx_max - bx_min + 1) * (bz_max - bz_min + 1)
	local settings = get_settings()
	local cbx = floor_div(cx, 16)
	local cbz = floor_div(cz, 16)
	local y_span = settings.bamboo_y_span or 128
	local y_min = math.max(-31000, start_bamboo_pos.y - y_span)
	local y_max = math.min(31000, start_bamboo_pos.y + y_span)

	-- Process closest mapblocks first so /mybiome updates quickly near the target.
	local order = {}
	for bx = bx_min, bx_max do
		for bz = bz_min, bz_max do
			local dx = bx - cbx
			local dz = bz - cbz
			order[#order + 1] = {bx = bx, bz = bz, d2 = dx * dx + dz * dz}
		end
	end
	table.sort(order, function(a, b)
		return a.d2 < b.d2
	end)

	bamboo_job = {
		start = os.time(),
		cx = cx,
		cz = cz,
		radius = radius,
		r2 = r2,
		y_min = y_min,
		y_max = y_max,
		id = id,
		total = total,
		i = 1,
		order = order,
		bamboo_cids = bamboo_cids,
		updated_cols = 0,
		updated_blocks = 0,
		scanned_blocks = 0,
		blocks_with_bamboo = 0,
		blocks_per_step = clamp_int(settings.bamboo_blocks_per_step, 1, 128)
			or clamp_int(settings.bamboo_nodes_per_step, 1, 50000) -- backward compat with early /bamboo settings
			or 8,
	}

	return true, ("Queued /bamboo (radius=%d). Use /bamboo_status."):format(radius)
end

	local function bamboo_step(blocks_budget)
		local j = bamboo_job
		if not j then
			return
		end

		blocks_budget = clamp_int(blocks_budget, 1, 128) or j.blocks_per_step or 8

		local cx, cz = j.cx, j.cz
		local r2 = j.r2
		local y_min = j.y_min
		local y_max = j.y_max
		local ocean_id = NAME_TO_ID.ocean
		local river_id = NAME_TO_ID.river
		local bamboo_cids = j.bamboo_cids

		local function paint_block(bx, bz)
			local x0 = bx * 16
			local z0 = bz * 16
			local minp = {x = x0, y = y_min, z = z0}
			local maxp = {x = x0 + 15, y = y_max, z = z0 + 15}

			local vm = core.get_voxel_manip()
			local emin, emax = vm:read_from_map(minp, maxp)
			local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
			local data = vm:get_data()

			j.scanned_blocks = (j.scanned_blocks or 0) + 1

			local cells = nil
			for lz = 0, 15 do
				local z = z0 + lz
				local dz = z - cz
				for y = y_min, y_max do
					local vi = area:index(x0, y, z)
					for lx = 0, 15 do
						if bamboo_cids[data[vi]] then
							local x = x0 + lx
							local dx = x - cx
							if dx * dx + dz * dz <= r2 then
								cells = cells or {}
								cells[lz * 16 + lx + 1] = true
							end
						end
						vi = vi + 1
					end
				end
			end

			if not cells then
				return
			end
			j.blocks_with_bamboo = (j.blocks_with_bamboo or 0) + 1

			local raw = get_block_data(bx, bz)
			if not raw or raw:len() ~= 256 then
				raw = make_filled_block(UNSET)
			end
			local bytes = {raw:byte(1, 256)}

			local changed_cols = 0
			for idx in pairs(cells) do
				local cur = bytes[idx]
				if (ocean_id == nil or cur ~= ocean_id)
					and (river_id == nil or cur ~= river_id)
					and cur ~= j.id then
					bytes[idx] = j.id
					changed_cols = changed_cols + 1
				end
			end

			if changed_cols > 0 then
				for i = 1, 256 do
					bytes[i] = string.char(bytes[i])
				end
				set_block_data(bx, bz, table.concat(bytes))
				j.updated_blocks = j.updated_blocks + 1
				j.updated_cols = j.updated_cols + changed_cols
			end
		end

		for _ = 1, blocks_budget do
			if not bamboo_job then
				return
			end
			local entry = j.order and j.order[j.i]
			if not entry then
				local elapsed = os.time() - (j.start or os.time())
				core.log("action", ("[%s] /bamboo complete cols=%d blocks=%d elapsed=%ds"):format(
					MODNAME, j.updated_cols or 0, j.updated_blocks or 0, elapsed
				))
				bamboo_job = nil
				return
			end

			paint_block(entry.bx, entry.bz)

			j.i = j.i + 1

			local done = (j.i or 1) - 1
			if (done % 25) == 0 then
				core.log("action", ("[%s] /bamboo progress %d/%d"):format(MODNAME, done, j.total))
			end
		end
	end

local function bamboo_from_cluster(start_bamboo_pos, radius)
	return start_bamboo_job(start_bamboo_pos, radius)
end

local function start_bamboo3_job(center_pos, radius)
	if bamboo3_job then
		return false, "A /bamboo3 job is already running. Use /bamboo3_status or /bamboo3_stop."
	end
	if job then
		return false, "A biomecalc job is running. Stop it with /biomecalc_stop before using /bamboo3."
	end
	if darkforest_job then
		return false, "A /darkforest job is running. Stop it with /darkforest_stop before using /bamboo3."
	end
	if bamboo_job then
		return false, "A /bamboo job is running. Stop it with /bamboo_stop before using /bamboo3."
	end

	radius = clamp_int(radius, 4, 512) or 64
	center_pos = vector.round(center_pos)

	if not (core.registered_nodes["mcl_bamboo:bamboo_big"] and core.registered_nodes["mcl_core:dirt_with_grass"]) then
		return false, "Required nodes not available (need mcl_bamboo:bamboo_big and mcl_core:dirt_with_grass)."
	end

	local minp = vector.subtract(center_pos, radius)
	local maxp = vector.add(center_pos, radius)

	local bx_min = floor_div(minp.x, 16)
	local bx_max = floor_div(maxp.x, 16)
	local bz_min = floor_div(minp.z, 16)
	local bz_max = floor_div(maxp.z, 16)
	local by_min = floor_div(minp.y, 16)
	local by_max = floor_div(maxp.y, 16)

	local total = (bx_max - bx_min + 1) * (bz_max - bz_min + 1) * (by_max - by_min + 1)
	local settings = get_settings()

	bamboo3_job = {
		start = os.time(),
		center = center_pos,
		radius = radius,
		r2 = radius * radius,
		bx_min = bx_min,
		bx_max = bx_max,
		bz_min = bz_min,
		bz_max = bz_max,
		by_min = by_min,
		by_max = by_max,
		bx = bx_min,
		bz = bz_min,
		by = by_min,
		total = total,
		done = 0,
		checked = 0,
		replaced = 0,
		blocks_per_step = settings.bamboo3_blocks_per_step or 12,
		time_budget_us = (settings.bamboo3_time_budget_ms or 10) * 1000,
	}

	return true, ("Queued /bamboo3 (radius=%d). Use /bamboo3_status."):format(radius)
end

local function bamboo3_advance(j)
	j.bx = j.bx + 1
	if j.bx > j.bx_max then
		j.bx = j.bx_min
		j.bz = j.bz + 1
		if j.bz > j.bz_max then
			j.bz = j.bz_min
			j.by = j.by + 1
		end
	end
end

local function bamboo3_grass_faces(pos)
	local count = 0
	local function is_grass(p)
		local n = core.get_node_or_nil(p)
		return n and n.name == "mcl_core:dirt_with_grass"
	end
	if is_grass(vector.offset(pos, 1, 0, 0)) then count = count + 1 end
	if is_grass(vector.offset(pos, -1, 0, 0)) then count = count + 1 end
	if is_grass(vector.offset(pos, 0, 1, 0)) then count = count + 1 end
	if is_grass(vector.offset(pos, 0, -1, 0)) then count = count + 1 end
	if is_grass(vector.offset(pos, 0, 0, 1)) then count = count + 1 end
	if is_grass(vector.offset(pos, 0, 0, -1)) then count = count + 1 end
	return count
end

local function bamboo3_step()
	local j = bamboo3_job
	if not j then
		return
	end

	local blocks_budget = clamp_int(j.blocks_per_step, 1, 256) or 12
	local start_us = core.get_us_time and core.get_us_time() or nil
	local time_budget_us = j.time_budget_us or 10000

	local mcl_core = rawget(_G, "mcl_core")
	local function grass_param2(pos)
		if mcl_core and mcl_core.get_grass_palette_index then
			return mcl_core.get_grass_palette_index(pos) or 0
		end
		return 0
	end

	for _ = 1, blocks_budget do
		if not bamboo3_job then
			return
		end
		if j.by > j.by_max then
			local elapsed = os.time() - (j.start or os.time())
			core.log("action", ("[%s] /bamboo3 complete checked=%d replaced=%d elapsed=%ds"):format(
				MODNAME, j.checked or 0, j.replaced or 0, elapsed
			))
			bamboo3_job = nil
			return
		end

		local minp = {x = j.bx * 16, y = j.by * 16, z = j.bz * 16}
		local maxp = {x = minp.x + 15, y = minp.y + 15, z = minp.z + 15}

		local nodes = core.find_nodes_in_area(minp, maxp, {"mcl_bamboo:bamboo_big"})
		if nodes and #nodes > 0 then
			for _, pos in ipairs(nodes) do
				local dx = pos.x - j.center.x
				local dy = pos.y - j.center.y
				local dz = pos.z - j.center.z
				if (dx * dx + dy * dy + dz * dz) <= j.r2 then
					j.checked = (j.checked or 0) + 1
					if bamboo3_grass_faces(pos) >= 4 then
						core.swap_node(pos, {name = "mcl_core:dirt_with_grass", param2 = grass_param2(pos)})
						j.replaced = (j.replaced or 0) + 1
					end
				end
			end
		end

		j.done = (j.done or 0) + 1
		bamboo3_advance(j)

		if start_us and (j.done % 2) == 0 and (core.get_us_time() - start_us) >= time_budget_us then
			return
		end
	end
end

local function classify_block(bx, bz, ymin, ymax, settings, water_cids, leaves_cids, tree_cids, snow_cids, bamboo_cids, spruce_cids)
	local x0 = bx * 16
	local z0 = bz * 16
	local r = settings.forest_tree_radius or 0
	-- A 5x5 XZ window around the column center.
	local spruce_r = 2
	-- Bamboo radius for biome tagging (5x5 XZ window).
	local bamboo_r = 2
	local scan_r = r
	local want_spruce = spruce_cids and next(spruce_cids) ~= nil
	if want_spruce then
		scan_r = math.max(scan_r, spruce_r)
	end
	local want_bamboo = bamboo_cids and next(bamboo_cids) ~= nil
	if want_bamboo then
		scan_r = math.max(scan_r, bamboo_r)
	end
	local minp = {x = x0 - scan_r, y = ymin, z = z0 - scan_r}
	local maxp = {x = x0 + 15 + scan_r, y = ymax, z = z0 + 15 + scan_r}

	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()

	local tree_cols = nil
	if r > 0 and next(tree_cids) ~= nil then
		local w = 16 + 2 * r
		tree_cols = {w = w, minx = x0 - r, minz = z0 - r, present = {}}
		local n = w * w
		for i = 1, n do
			tree_cols.present[i] = 0
		end
		for z = tree_cols.minz, tree_cols.minz + w - 1 do
			for x = tree_cols.minx, tree_cols.minx + w - 1 do
				for y = ymax, ymin, -1 do
					local vi = area:index(x, y, z)
					if tree_cids[data[vi]] then
						local idx = (z - tree_cols.minz) * w + (x - tree_cols.minx) + 1
						tree_cols.present[idx] = 1
						break
					end
				end
			end
		end
	end

	local function forest_from_tree_density(x, z)
		if not tree_cols then
			return false
		end
		local w = tree_cols.w
		local cx = x - tree_cols.minx
		local cz = z - tree_cols.minz
		local sum = 0
		for dz = -r, r do
			local zz = cz + dz
			if zz >= 0 and zz < w then
				local row = zz * w
				for dx = -r, r do
					local xx = cx + dx
					if xx >= 0 and xx < w then
						sum = sum + tree_cols.present[row + xx + 1]
						if sum >= settings.forest_tree_columns_min then
							return true
						end
					end
				end
			end
		end
		return false
	end

	local spruce_cols = nil
	local spruce_ps = nil
	local function spruce_in_radius(_x, _z)
		return false
	end
	if want_spruce then
		local w = 16 + 2 * spruce_r
		spruce_cols = {w = w, minx = x0 - spruce_r, minz = z0 - spruce_r, present = {}}
		local n = w * w
		for i = 1, n do
			spruce_cols.present[i] = 0
		end
		for z = spruce_cols.minz, spruce_cols.minz + w - 1 do
			for x = spruce_cols.minx, spruce_cols.minx + w - 1 do
				for y = ymax, ymin, -1 do
					local vi = area:index(x, y, z)
					if spruce_cids[data[vi]] then
						local idx = (z - spruce_cols.minz) * w + (x - spruce_cols.minx) + 1
						spruce_cols.present[idx] = 1
						break
					end
				end
			end
		end

		local w1 = w + 1
		spruce_ps = {}
		for i = 1, w1 * w1 do
			spruce_ps[i] = 0
		end
		local function ps_at(z, x)
			-- z/x are 0..w
			return spruce_ps[z * w1 + x + 1]
		end
		for z = 1, w do
			local row_sum = 0
			local base = (z - 1) * w
			for x = 1, w do
				row_sum = row_sum + spruce_cols.present[base + x]
				spruce_ps[z * w1 + x + 1] = ps_at(z - 1, x) + row_sum
			end
		end

		spruce_in_radius = function(x, z)
			local gx0 = x - spruce_r - spruce_cols.minx + 1
			local gx1 = x + spruce_r - spruce_cols.minx + 1
			local gz0 = z - spruce_r - spruce_cols.minz + 1
			local gz1 = z + spruce_r - spruce_cols.minz + 1
			local sum = ps_at(gz1, gx1)
				- ps_at(gz0 - 1, gx1)
				- ps_at(gz1, gx0 - 1)
				+ ps_at(gz0 - 1, gx0 - 1)
			return sum > 0
		end
	end

	local bamboo_cols = nil
	local bamboo_ps = nil
	local function bamboo_in_radius(_x, _z)
		return false
	end
	if want_bamboo then
		local bamboo_span = settings.bamboo_scan or 64
		local w = 16 + 2 * bamboo_r
		bamboo_cols = {w = w, minx = x0 - bamboo_r, minz = z0 - bamboo_r, present = {}}
		local n = w * w
		for i = 1, n do
			bamboo_cols.present[i] = 0
		end
		for z = bamboo_cols.minz, bamboo_cols.minz + w - 1 do
			for x = bamboo_cols.minx, bamboo_cols.minx + w - 1 do
				local surface_y = nil
				for y = ymax, ymin, -1 do
					local vi = area:index(x, y, z)
					local cid = data[vi]
					if cid ~= CID_AIR and cid ~= CID_IGNORE then
						surface_y = y
						break
					end
				end
				if surface_y then
					local y0 = math.max(ymin, surface_y - bamboo_span)
					local y1 = math.min(ymax, surface_y + bamboo_span)
					for y = y0, y1 do
						local vi = area:index(x, y, z)
						if bamboo_cids[data[vi]] then
							local idx = (z - bamboo_cols.minz) * w + (x - bamboo_cols.minx) + 1
							bamboo_cols.present[idx] = 1
							break
						end
					end
				end
			end
		end

		local w1 = w + 1
		bamboo_ps = {}
		for i = 1, w1 * w1 do
			bamboo_ps[i] = 0
		end
		local function ps_at(z, x)
			return bamboo_ps[z * w1 + x + 1]
		end
		for z = 1, w do
			local row_sum = 0
			local base = (z - 1) * w
			for x = 1, w do
				row_sum = row_sum + bamboo_cols.present[base + x]
				bamboo_ps[z * w1 + x + 1] = ps_at(z - 1, x) + row_sum
			end
		end

		bamboo_in_radius = function(x, z)
			local gx0 = x - bamboo_r - bamboo_cols.minx + 1
			local gx1 = x + bamboo_r - bamboo_cols.minx + 1
			local gz0 = z - bamboo_r - bamboo_cols.minz + 1
			local gz1 = z + bamboo_r - bamboo_cols.minz + 1
			local sum = ps_at(gz1, gx1)
				- ps_at(gz0 - 1, gx1)
				- ps_at(gz1, gx0 - 1)
				+ ps_at(gz0 - 1, gx0 - 1)
			return sum > 0
		end
	end

	local out = {}
	local forest_scan = settings.forest_scan
	local bamboo_scan = settings.bamboo_scan
	local mountain_y = settings.mountain_y
	local ocean_min_depth = settings.ocean_min_depth

	for lz = 0, 15 do
		local z = z0 + lz
		for lx = 0, 15 do
			local x = x0 + lx
			local surface_y = nil
			local surface_cid = nil
			for y = ymax, ymin, -1 do
				local vi = area:index(x, y, z)
				local cid = data[vi]
				if cid ~= CID_AIR and cid ~= CID_IGNORE then
					surface_y = y
					surface_cid = cid
					break
				end
			end

			local id = UNSET
			if surface_y and surface_cid then
				if water_cids[surface_cid] then
					local depth = 1
					for y = surface_y - 1, ymin, -1 do
						local vi = area:index(x, y, z)
						if water_cids[data[vi]] then
							depth = depth + 1
							if depth >= ocean_min_depth then
								break
							end
						else
							break
						end
					end
					id = depth >= ocean_min_depth and NAME_TO_ID.ocean or NAME_TO_ID.river
				elseif surface_y >= mountain_y then
					id = NAME_TO_ID.mountain
				elseif snow_cids[surface_cid] then
					id = NAME_TO_ID.snowytaiga
				else
					-- Decide plains vs forest first, then override to bamboo if bamboo is present.
					local base_id
					if forest_from_tree_density(x, z) then
						base_id = NAME_TO_ID.forest
					else
						local top = math.min(surface_y + (forest_scan or 8), ymax)
						local has_leaves = false
						for y = surface_y + 1, top do
							local vi = area:index(x, y, z)
							if leaves_cids[data[vi]] then
								has_leaves = true
								break
							end
						end
						base_id = has_leaves and NAME_TO_ID.forest or NAME_TO_ID.plains
					end

					if spruce_in_radius(x, z) then
						id = NAME_TO_ID.sprucetaiga
					elseif bamboo_in_radius(x, z) then
						id = NAME_TO_ID.bamboo
					else
						id = base_id
					end
				end

				out[lz * 16 + lx + 1] = id
			end
		end
	end

	local chars = {}
	for i = 1, 256 do
		chars[i] = string.char(out[i] or UNSET)
	end
	return table.concat(chars)
end

local function round_number(v)
	if v >= 0 then
		return math.floor(v + 0.5)
	end
	return math.ceil(v - 0.5)
end

local function get_pointed_water_pos(player, range)
	if not (player and player.is_player and player:is_player()) then
		return nil
	end
	range = clamp_int(range, 1, 256) or 32

	local props = player:get_properties() or {}
	local eye_h = tonumber(props.eye_height) or 1.47
	local start = vector.add(player:get_pos(), {x = 0, y = eye_h, z = 0})
	local dir = player:get_look_dir()
	local finish = vector.add(start, vector.multiply(dir, range))

	local ray = core.raycast(start, finish, false, true)
	for pointed in ray do
		if pointed.type == "node" and pointed.under then
			local pos = vector.round(pointed.under)
			local node = core.get_node_or_nil(pos)
			if node and node.name and core.get_item_group(node.name, "water") > 0 then
				return pos
			end
		end
	end
	return nil
end

	local function fix_river_at(pos, radius)
		radius = clamp_int(radius, 8, 256) or 96
		pos = vector.round(pos)

	local tag = api.get_id({x = pos.x, y = 0, z = pos.z})
	if tag ~= nil and tag ~= NAME_TO_ID.river and tag ~= NAME_TO_ID.ocean then
		return false, "Target is not tagged as river/ocean (run /biomecalc first, then look at water)."
	end

	local settings = get_settings()
	if not CID_SETS then
		CID_SETS = {build_cid_sets()}
	end
	local water_cids = CID_SETS[1]

	local min_depth = 2
	local max_depth_cap = 14
	-- How far inland to smooth the shoreline (caps land height based on distance from water).
	local coast_smooth_radius = 12
	local y_min = math.max(-31000, pos.y - (max_depth_cap + 8))
	-- Read higher than the water surface so we can smooth river/ocean banks.
	local y_max = math.min(31000, pos.y + 16)

	local minx, maxx = pos.x - radius, pos.x + radius
	local minz, maxz = pos.z - radius, pos.z + radius

	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map({x = minx, y = y_min, z = minz}, {x = maxx, y = y_max, z = maxz})
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local param2_data = vm:get_param2_data()

	local w = maxx - minx + 1
	local h = maxz - minz + 1
	local n = w * h
	if n <= 0 then
		return false, "Invalid area."
	end

	local function idx_for(x, z)
		return (z - minz) * w + (x - minx) + 1
	end

	local r2 = radius * radius
	local water_surface = {}
	for z = minz, maxz do
		local dz = z - pos.z
		for x = minx, maxx do
			local dx = x - pos.x
			local idx = idx_for(x, z)
			if dx * dx + dz * dz <= r2 then
				local tag_id = api.get_id({x = x, y = 0, z = z})
				if tag_id == nil or tag_id == NAME_TO_ID.river or tag_id == NAME_TO_ID.ocean then
					local vi = area:index(x, pos.y, z)
					if water_cids[data[vi]] then
						water_surface[idx] = true
					end
				end
			end
		end
	end

	local start_idx = idx_for(pos.x, pos.z)
	if not water_surface[start_idx] then
		return false, "Look at river water (surface)."
	end

	local in_river = {}
	local river_cells = {}
	local q = {}
	local qh, qt = 1, 1
	q[1] = start_idx
	in_river[start_idx] = true
	river_cells[1] = start_idx

	local sumx, sumz, sumx2, sumz2, sumxz = 0, 0, 0, 0, 0

	while qh <= qt do
		local idx = q[qh]
		qh = qh + 1

		local lx = (idx - 1) % w
		local lz = math.floor((idx - 1) / w)
		local x = minx + lx
		local z = minz + lz

		sumx = sumx + x
		sumz = sumz + z
		sumx2 = sumx2 + x * x
		sumz2 = sumz2 + z * z
		sumxz = sumxz + x * z

		local function try_neighbor(nx, nz)
			if nx < minx or nx > maxx or nz < minz or nz > maxz then
				return
			end
			local nidx = idx_for(nx, nz)
			if not in_river[nidx] and water_surface[nidx] then
				in_river[nidx] = true
				qt = qt + 1
				q[qt] = nidx
				river_cells[#river_cells + 1] = nidx
			end
		end

		try_neighbor(x + 1, z)
		try_neighbor(x - 1, z)
		try_neighbor(x, z + 1)
		try_neighbor(x, z - 1)
	end

	if #river_cells < 32 then
		return false, "River surface too small in this radius."
	end

	-- Approximate river direction via principal axis of the connected surface.
	local count = #river_cells
	local meanx = sumx / count
	local meanz = sumz / count
	local cov_xx = sumx2 / count - meanx * meanx
	local cov_zz = sumz2 / count - meanz * meanz
	local cov_xz = sumxz / count - meanx * meanz

	local vx, vz = 1, 0
	if cov_xz ~= 0 then
		local tr = cov_xx + cov_zz
		local det = cov_xx * cov_zz - cov_xz * cov_xz
		local disc = math.max(0, tr * tr / 4 - det)
		local lambda = tr / 2 + math.sqrt(disc)
		vx = lambda - cov_zz
		vz = cov_xz
	elseif cov_zz > cov_xx then
		vx, vz = 0, 1
	end
	local vlen = math.sqrt(vx * vx + vz * vz)
	if vlen > 0 then
		vx = vx / vlen
		vz = vz / vlen
	end

	-- Distance-to-coast field (Manhattan distance in surface grid).
	local dist = {}
	local dq = {}
	local dh, dt = 1, 0
	local max_d = 0

	for _, idx in ipairs(river_cells) do
		local x = minx + ((idx - 1) % w)
		local z = minz + math.floor((idx - 1) / w)
		local is_coast = false
		local function is_water(nx, nz)
			if nx < minx or nx > maxx or nz < minz or nz > maxz then
				return false
			end
			return in_river[idx_for(nx, nz)] == true
		end
		if not is_water(x + 1, z) or not is_water(x - 1, z) or not is_water(x, z + 1) or not is_water(x, z - 1) then
			is_coast = true
		end
		if is_coast then
			dist[idx] = 0
			dt = dt + 1
			dq[dt] = idx
		end
	end

	while dh <= dt do
		local idx = dq[dh]
		dh = dh + 1
		local d = dist[idx] or 0

		local x = minx + ((idx - 1) % w)
		local z = minz + math.floor((idx - 1) / w)

		local function push(nx, nz)
			if nx < minx or nx > maxx or nz < minz or nz > maxz then
				return
			end
			local nidx = idx_for(nx, nz)
			if in_river[nidx] and dist[nidx] == nil then
				dist[nidx] = d + 1
				if d + 1 > max_d then
					max_d = d + 1
				end
				dt = dt + 1
				dq[dt] = nidx
			end
		end

		push(x + 1, z)
		push(x - 1, z)
		push(x, z + 1)
		push(x, z - 1)
	end

	if max_d < 1 then
		return false, "Could not compute river width."
	end

	local max_depth = math.min(max_depth_cap, min_depth + math.floor(max_d * 1.6))

	local seed = tonumber(core.get_mapgen_setting("seed")) or 0
	local perlin_ridge = core.get_perlin(seed + 9103, 3, 0.6, 32)
	local perlin_ridge2 = core.get_perlin(seed + 1337, 2, 0.7, 12)
	local perlin_pool = core.get_perlin(seed + 4242, 2, 0.5, 80)
	local perlin_patch = core.get_perlin(seed + 7777, 2, 0.6, 24)
	local perlin_flow = core.get_perlin(seed + 9001, 2, 0.6, 18)
	local perlin_plants = core.get_perlin(seed + 6061, 2, 0.55, 28)

	local bed_y = {}
	for _, idx in ipairs(river_cells) do
		local lx = (idx - 1) % w
		local lz = math.floor((idx - 1) / w)
		local x = minx + lx
		local z = minz + lz
		local d = dist[idx] or 0
		local c = d / max_d

		local base = min_depth + (max_depth - min_depth) * (c ^ 1.35)
		local base_depth = round_number(base)

		local ridge = 1 - math.abs(perlin_ridge:get_2d({x = x, y = z}))
		ridge = ridge * ridge
		local ridge2 = 1 - math.abs(perlin_ridge2:get_2d({x = x, y = z}))
		ridge2 = ridge2 * ridge2
		local thalweg = math.max(ridge, ridge2 * 0.7)

		local pool_n = perlin_pool:get_2d({x = x, y = z})
		local t = (x - meanx) * vx + (z - meanz) * vz
		local flow_n = perlin_flow:get_2d({x = t, y = 0})

		local var = (thalweg * 2 - 1) * (1 + 3 * c)
			+ pool_n * (0.5 + 2 * c)
			+ flow_n * (0.5 + 2 * c)
		-- Reduce overall noise to avoid jagged steps; keep some variation.
		var = var * 0.65

		local depth = base_depth + round_number(var)
		if depth < min_depth then depth = min_depth end
		if depth > max_depth + 2 then depth = max_depth + 2 end

		bed_y[idx] = pos.y - depth
	end

	-- Smooth out sharp steps while keeping variation.
	-- 1) Clamp local slopes to avoid "stair steps".
	local max_slope = 1
	for _ = 1, 3 do
		local next_bed = {}
		for _, idx in ipairs(river_cells) do
			local y = bed_y[idx]
			local x = minx + ((idx - 1) % w)
			local z = minz + math.floor((idx - 1) / w)
			local function clamp_to(nx, nz)
				if nx < minx or nx > maxx or nz < minz or nz > maxz then
					return
				end
				local nidx = idx_for(nx, nz)
				if in_river[nidx] then
					local ny = bed_y[nidx]
					if ny and y - ny > max_slope then
						y = ny + max_slope
					elseif ny and ny - y > max_slope then
						y = ny - max_slope
					end
				end
			end
			clamp_to(x + 1, z)
			clamp_to(x - 1, z)
			clamp_to(x, z + 1)
			clamp_to(x, z - 1)
			next_bed[idx] = y
		end
		bed_y = next_bed
	end

	-- 2) Gentle neighbor averaging to smooth remaining noise.
	for _ = 1, 2 do
		local next_bed = {}
		for _, idx in ipairs(river_cells) do
			local y = bed_y[idx]
			local x = minx + ((idx - 1) % w)
			local z = minz + math.floor((idx - 1) / w)
			local sum = y * 4
			local cnt = 4

			local function add(nx, nz)
				if nx < minx or nx > maxx or nz < minz or nz > maxz then
					return
				end
				local nidx = idx_for(nx, nz)
				if in_river[nidx] then
					local ny = bed_y[nidx]
					if ny then
						sum = sum + ny
						cnt = cnt + 1
					end
				end
			end

			add(x + 1, z)
			add(x - 1, z)
			add(x, z + 1)
			add(x, z - 1)
			next_bed[idx] = round_number(sum / cnt)
		end
		bed_y = next_bed
	end

	local function cid_or_nil(name)
		if core.registered_nodes[name] then
			return core.get_content_id(name)
		end
		return nil
	end

	local cid_water = cid_or_nil("mcl_core:water_source")
	if not cid_water then
		return false, "Water source node not found."
	end

	local cid_dirt = cid_or_nil("mcl_core:dirt") or cid_or_nil("default:dirt")
	local cid_sand = cid_or_nil("mcl_core:sand") or cid_dirt
	local cid_gravel = cid_or_nil("mcl_core:gravel") or cid_sand
	local cid_clay = cid_or_nil("mcl_core:clay") or cid_sand

	local cid_seagrass_dirt = cid_or_nil("mcl_ocean:seagrass_dirt")
	local cid_seagrass_sand = cid_or_nil("mcl_ocean:seagrass_sand")
	local cid_seagrass_gravel = cid_or_nil("mcl_ocean:seagrass_gravel")

	local replaced = 0
	local planted = 0
	local coast_smoothed = 0

	-- Shoreline smoothing: cap nearby land column heights so the land->water step is usually <= 1.
	-- We only modify "terrain-like" nodes (soil/sand/stone/grass) to avoid destroying builds.
	do
		local terrain_cids = {}
		for name, def in pairs(core.registered_nodes) do
			if def and def.groups then
				if (def.groups.soil or 0) > 0
					or (def.groups.sand or 0) > 0
					or (def.groups.stone or 0) > 0
					or (def.groups.grass_block or 0) > 0 then
					terrain_cids[core.get_content_id(name)] = true
				end
			end
		end
		-- Also allow Mineclonia's common terrain blocks even if group tagging changes.
		for _, n in ipairs({
			"mcl_core:dirt",
			"mcl_core:dirt_with_grass",
			"mcl_core:stone",
			"mcl_core:sand",
			"mcl_core:gravel",
		}) do
			if core.registered_nodes[n] then
				terrain_cids[core.get_content_id(n)] = true
			end
		end

		local land_dist = {}
		local lq = {}
		local lh, lt = 1, 0

		-- Seed from water coast: land cells adjacent to in_river.
		for _, widx in ipairs(river_cells) do
			local x = minx + ((widx - 1) % w)
			local z = minz + math.floor((widx - 1) / w)

			local function try_seed(nx, nz)
				if nx < minx or nx > maxx or nz < minz or nz > maxz then
					return
				end
				local dx = nx - pos.x
				local dz = nz - pos.z
				if dx * dx + dz * dz > r2 then
					return
				end
				local nidx = idx_for(nx, nz)
				if in_river[nidx] or land_dist[nidx] ~= nil then
					return
				end
				-- Avoid smoothing other surface water columns.
				if water_surface[nidx] then
					return
				end
				land_dist[nidx] = 1
				lt = lt + 1
				lq[lt] = nidx
			end

			try_seed(x + 1, z)
			try_seed(x - 1, z)
			try_seed(x, z + 1)
			try_seed(x, z - 1)
		end

		while lh <= lt do
			local idx = lq[lh]
			lh = lh + 1
			local d = land_dist[idx]
			if d and d < coast_smooth_radius then
				local x = minx + ((idx - 1) % w)
				local z = minz + math.floor((idx - 1) / w)

				local function push(nx, nz)
					if nx < minx or nx > maxx or nz < minz or nz > maxz then
						return
					end
					local dx = nx - pos.x
					local dz = nz - pos.z
					if dx * dx + dz * dz > r2 then
						return
					end
					local nidx = idx_for(nx, nz)
					if in_river[nidx] or land_dist[nidx] ~= nil then
						return
					end
					if water_surface[nidx] then
						return
					end
					land_dist[nidx] = d + 1
					lt = lt + 1
					lq[lt] = nidx
				end

				push(x + 1, z)
				push(x - 1, z)
				push(x, z + 1)
				push(x, z - 1)
			end
		end

		for idx, d in pairs(land_dist) do
			local x = minx + ((idx - 1) % w)
			local z = minz + math.floor((idx - 1) / w)
			local max_surface_y = pos.y + d
			if max_surface_y > y_max then
				max_surface_y = y_max
			end

			if max_surface_y > pos.y then
				local surface_y = nil
				local surface_cid = nil
				for y = y_max, pos.y, -1 do
					local vi = area:index(x, y, z)
					local cid = data[vi]
					if cid ~= CID_AIR and cid ~= CID_IGNORE then
						-- Don't treat water columns as land surfaces.
						if not water_cids[cid] then
							surface_y = y
							surface_cid = cid
						end
						break
					end
				end

				if surface_y and surface_cid and terrain_cids[surface_cid] and surface_y > max_surface_y then
					-- Carve down to the capped height.
					for y = surface_y, max_surface_y + 1, -1 do
						data[area:index(x, y, z)] = CID_AIR
						coast_smoothed = coast_smoothed + 1
					end
				end
			end
		end
	end

	for _, idx in ipairs(river_cells) do
		repeat
			local lx = (idx - 1) % w
			local lz = math.floor((idx - 1) / w)
			local x = minx + lx
			local z = minz + lz
			local target_y = bed_y[idx]
			if target_y < y_min then
				target_y = y_min
			end

			local bottom_y = nil
			for y = pos.y, y_min, -1 do
				local vi = area:index(x, y, z)
				local cid = data[vi]
				if cid ~= CID_IGNORE and not water_cids[cid] then
					bottom_y = y
					break
				end
			end
			if not bottom_y then
				break
			end

			local d = dist[idx] or 0
			local c = d / max_d
			local depth = pos.y - target_y
			if depth < 1 then
				break
			end

			local patch_n = perlin_patch:get_2d({x = x, y = z})
			local mat_cid = cid_sand
			if patch_n < -0.45 and c > 0.35 then
				mat_cid = cid_clay
			elseif patch_n > 0.35 or (c < 0.2 and patch_n > 0) then
				mat_cid = cid_gravel
			end

			local deposit = 1
			if mat_cid == cid_clay then
				deposit = 2 + (perlin_pool:get_2d({x = x + 200, y = z - 200}) > 0.25 and 1 or 0)
			elseif mat_cid == cid_gravel then
				deposit = 1 + (perlin_ridge2:get_2d({x = x - 200, y = z + 200}) > 0.5 and 1 or 0)
			end

			-- Raise or carve the bed to the target height.
			if target_y > bottom_y then
				for y = bottom_y + 1, target_y do
					data[area:index(x, y, z)] = mat_cid
				end
				replaced = replaced + (target_y - bottom_y)
			elseif target_y < bottom_y then
				for y = bottom_y - 1, target_y + 1, -1 do
					data[area:index(x, y, z)] = cid_water
				end
				replaced = replaced + (bottom_y - target_y)
			end

			-- Material thickness.
			for y = target_y, math.max(y_min, target_y - (deposit - 1)), -1 do
				data[area:index(x, y, z)] = mat_cid
			end

			-- Ensure a clean water column.
			for y = target_y + 1, pos.y do
				data[area:index(x, y, z)] = cid_water
			end

			-- Seagrass placement: rooted seagrass nodes replace the top substrate block.
			-- Bias towards wider parts of the river and avoid extremely shallow/deep water.
			local plant_n = perlin_plants:get_2d({x = x, y = z})
			if depth >= 2 and depth <= 9 and c > 0.15 and plant_n > -0.15 then
				local seagrass_cid = nil
				if mat_cid == cid_sand or mat_cid == cid_clay then
					seagrass_cid = cid_seagrass_sand
				elseif mat_cid == cid_gravel then
					seagrass_cid = cid_seagrass_gravel
				elseif mat_cid == cid_dirt then
					seagrass_cid = cid_seagrass_dirt
				end
				if seagrass_cid then
					local vi = area:index(x, target_y, z)
					data[vi] = seagrass_cid
					-- More variation: use noise to pick one of a few param2 values.
					local pn = perlin_ridge2:get_2d({x = x + 1000, y = z + 1000})
					local p2 = (pn > 0.35 and 11) or (pn > -0.15 and 7) or 3
					param2_data[vi] = p2
					planted = planted + 1
				end
			end
		until true
	end

	vm:set_data(data)
	vm:set_param2_data(param2_data)
	vm:write_to_map(true)

	return true, ("Fixed riverbed: cells=%d max_width=%d max_depth=%d replaced=%d seagrass=%d coast=%d"):format(
		#river_cells, max_d * 2, max_depth, replaced, planted, coast_smoothed
	)
end

core.register_chatcommand("biomecalc", {
	description = "Calculate custom biome tags in a radius around you (VoxelManip, incremental).",
	params = "<radius> [ymin ymax]",
	privs = {server = true},
	func = function(name, param)
		local p1, p2, p3 = string.match(param or "", "^%s*(%-?%d+)%s*(%-?%d*)%s*(%-?%d*)%s*$")
		local radius = clamp_int(p1, 16, 4096) or 256
		local ymin = clamp_int(p2, -31000, 31000)
		local ymax = clamp_int(p3, -31000, 31000)

		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local pos = vector.round(player:get_pos())

		local bx_min = floor_div(pos.x - radius, 16)
		local bx_max = floor_div(pos.x + radius, 16)
		local bz_min = floor_div(pos.z - radius, 16)
		local bz_max = floor_div(pos.z + radius, 16)

		local ok, res = start_biomecalc_job({
			kind = "radius",
			bx_min = bx_min,
			bx_max = bx_max,
			bz_min = bz_min,
			bz_max = bz_max,
			ymin = ymin,
			ymax = ymax,
		})
		if not ok then
			return false, res
		end
		core.log("action", ("[%s] /biomecalc start radius=%d blocks=%d y=%d..%d"):format(MODNAME, radius, res, job.ymin, job.ymax))
		return true, ("Started biomecalc (%d blocks). Use /biomecalc_status."):format(res)
	end,
})

core.register_chatcommand("darkforest", {
	description = "Convert a connected leaf canopy into the darkforest biome tag: /darkforest [radius] (look at leaves).",
	params = "[radius]",
	privs = {server = true},
	func = function(name, param)
		local radius = clamp_int(param, 8, 512) or 256
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local leaf = get_pointed_leaf_pos(player, 96)
		if not leaf then
			return false, "Look at a leaf node and try again."
		end
		core.log("action", ("[%s] /darkforest start leaf=%s radius=%d"):format(MODNAME, core.pos_to_string(leaf), radius))
		local ok, msg = darkforest_from_leaf_cluster(leaf, radius)
		core.log("action", ("[%s] /darkforest queued ok=%s msg=%s"):format(MODNAME, tostring(ok), tostring(msg)))
		return ok, msg
	end,
})

core.register_chatcommand("bamboo", {
	description = "Tag columns containing bamboo as the bamboo biome: /bamboo [radius] (look at bamboo).",
	params = "[radius]",
	privs = {server = true},
	func = function(name, param)
		local radius = clamp_int(param, 8, 512) or 256
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local pos = get_pointed_bamboo_pos(player, 96)
		if not pos then
			return false, "Look at a bamboo node and try again."
		end
		core.log("action", ("[%s] /bamboo start bamboo=%s radius=%d"):format(MODNAME, core.pos_to_string(pos), radius))
		local ok, msg = bamboo_from_cluster(pos, radius)
		core.log("action", ("[%s] /bamboo queued ok=%s msg=%s"):format(MODNAME, tostring(ok), tostring(msg)))
		return ok, msg
	end,
})

core.register_chatcommand("bamboo3", {
	description = "Replace mcl_bamboo:bamboo_big with grass when surrounded on >=4 faces by grass: /bamboo3 <radius>",
	params = "<radius>",
	privs = {server = true},
	func = function(name, param)
		local radius = clamp_int(param, 4, 512)
		if not radius then
			return false, "Usage: /bamboo3 <radius>"
		end
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local pos = vector.round(player:get_pos())
		core.log("action", ("[%s] /bamboo3 start pos=%s radius=%d"):format(MODNAME, core.pos_to_string(pos), radius))
		return start_bamboo3_job(pos, radius)
	end,
})

core.register_chatcommand("cherry", {
	description = "Convert a connected pink wool blob into cherry leaves and nearby oak trunks into cherry trunks: /cherry (look at pink wool).",
	privs = {server = true},
	func = function(name)
		if not (core.registered_nodes["mcl_wool:pink"]
			and core.registered_nodes["mcl_trees:leaves_cherry_blossom"]
			and core.registered_nodes["mcl_trees:tree_oak"]
			and core.registered_nodes["mcl_trees:tree_cherry_blossom"]) then
			return false, "Missing required nodes (mcl_wool or mcl_trees cherry/oak)."
		end

		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end

		local function is_cherry_connectable_node(n)
			if n == "mcl_wool:pink" then
				return true
			end
			-- Oak variants
			if n == "mcl_trees:tree_oak" or n == "mcl_trees:bark_oak"
				or n == "mcl_trees:stripped_oak" or n == "mcl_trees:bark_stripped_oak"
				or n == "mcl_trees:leaves_oak" or n == "mcl_trees:leaves_oak_orphan" then
				return true
			end
			-- Cherry variants (so re-running /cherry can resume on partially-converted areas)
			if n == "mcl_trees:tree_cherry_blossom" or n == "mcl_trees:bark_cherry_blossom"
				or n == "mcl_trees:stripped_cherry_blossom" or n == "mcl_trees:bark_stripped_cherry_blossom"
				or n == "mcl_trees:leaves_cherry_blossom" or n == "mcl_trees:leaves_cherry_blossom_orphan" then
				return true
			end
			return false
		end

		local pos = get_pointed_node_pos(player, 96, function(n) return is_cherry_connectable_node(n) end)
		if not pos then
			return false, "Look at the pink wool / oak / cherry structure and try again."
		end

		-- Flood-fill the connected structure through both pink wool and oak logs,
		-- so it keeps going until the tree ends.
		local blob, err = collect_connected_nodes(pos, function(node_name)
			return is_cherry_connectable_node(node_name)
		end, 300000)
		if not blob then
			return false, err or "Failed to scan blob."
		end

		local replaced_wool = 0
		local replaced_oak_logs = 0
		local replaced_oak_wood = 0
		local replaced_oak_leaves = 0
		for _, p in ipairs(blob.nodes) do
			local node = core.get_node_or_nil(p)
			if node and node.name == "mcl_wool:pink" then
				core.swap_node(p, {name = "mcl_trees:leaves_cherry_blossom", param2 = 0})
				replaced_wool = replaced_wool + 1
			elseif node and node.name == "mcl_trees:tree_oak" then
				core.swap_node(p, {name = "mcl_trees:tree_cherry_blossom", param2 = node.param2 or 0})
				replaced_oak_logs = replaced_oak_logs + 1
			elseif node and node.name == "mcl_trees:bark_oak" then
				core.swap_node(p, {name = "mcl_trees:bark_cherry_blossom", param2 = node.param2 or 0})
				replaced_oak_wood = replaced_oak_wood + 1
			elseif node and node.name == "mcl_trees:stripped_oak" then
				core.swap_node(p, {name = "mcl_trees:stripped_cherry_blossom", param2 = node.param2 or 0})
				replaced_oak_wood = replaced_oak_wood + 1
			elseif node and node.name == "mcl_trees:bark_stripped_oak" then
				core.swap_node(p, {name = "mcl_trees:bark_stripped_cherry_blossom", param2 = node.param2 or 0})
				replaced_oak_wood = replaced_oak_wood + 1
			elseif node and (node.name == "mcl_trees:leaves_oak" or node.name == "mcl_trees:leaves_oak_orphan") then
				core.swap_node(p, {name = "mcl_trees:leaves_cherry_blossom", param2 = node.param2 or 0})
				replaced_oak_leaves = replaced_oak_leaves + 1
			end
		end

		core.log("action", ("[%s] /cherry at=%s blob=%d oak_logs=%d oak_wood=%d box=%s..%s"):format(
			MODNAME,
			core.pos_to_string(pos),
			(replaced_wool + replaced_oak_logs + replaced_oak_wood + replaced_oak_leaves),
			replaced_oak_logs,
			replaced_oak_wood,
			core.pos_to_string(blob.minp),
			core.pos_to_string(blob.maxp)
		))
		return true, ("Converted pink_wool=%d to cherry leaves; oak_logs=%d to cherry logs; oak_wood=%d to cherry wood; oak_leaves=%d to cherry leaves."):format(
			replaced_wool, replaced_oak_logs, replaced_oak_wood, replaced_oak_leaves
		)
	end,
})

core.register_chatcommand("darkforest_status", {
	description = "Show status of the running /darkforest job.",
	privs = {interact = true},
	func = function()
		if not darkforest_job then
			return true, "No /darkforest job running."
		end
		local j = darkforest_job
		local elapsed = os.time() - (j.start or os.time())
		local phase = j.phase or "scan"
		local qsize = 0
		if phase ~= "flush" then
			local qt = j.qt or 0
			local qh = j.qh or 1
			if qt >= qh then
				qsize = qt - qh + 1
			end
		end
		return true, ("darkforest: phase=%s nodes=%d cols=%d queue=%d pending_blocks=%d elapsed=%ds radius=%d"):format(
			phase,
			j.nodes_done or 0,
			j.cols_done or 0,
			qsize,
			j.pending_count or 0,
			elapsed,
			j.radius or 0
		)
	end,
})

core.register_chatcommand("bamboo3_status", {
	description = "Show status of the running /bamboo3 job.",
	privs = {interact = true},
	func = function()
		if not bamboo3_job then
			return true, "No /bamboo3 job running."
		end
		local j = bamboo3_job
		local elapsed = os.time() - (j.start or os.time())
		return true, ("bamboo3: blocks=%d/%d checked=%d replaced=%d elapsed=%ds radius=%d"):format(
			j.done or 0,
			j.total or 0,
			j.checked or 0,
			j.replaced or 0,
			elapsed,
			j.radius or 0
		)
	end,
})

	core.register_chatcommand("bamboo_status", {
		description = "Show status of the running /bamboo job.",
		privs = {interact = true},
		func = function()
			if not bamboo_job then
				return true, "No /bamboo job running."
			end
			local j = bamboo_job
			local elapsed = os.time() - (j.start or os.time())
			local done = (j.i or 1) - 1
			return true, ("bamboo: %d/%d blocks processed (scanned=%d with_bamboo=%d cols=%d writes=%d elapsed=%ds radius=%d)"):format(
				done,
				j.total or 0,
				j.scanned_blocks or 0,
				j.blocks_with_bamboo or 0,
				j.updated_cols or 0,
				j.updated_blocks or 0,
				elapsed,
				j.radius or 0
			)
		end,
	})

core.register_chatcommand("darkforest_stop", {
	description = "Stop the running /darkforest job.",
	privs = {server = true},
	func = function()
		if not darkforest_job then
			return true, "No /darkforest job running."
		end
		darkforest_job = nil
		return true, "/darkforest stopped."
	end,
})

core.register_chatcommand("fixriver", {
	description = "Improve riverbed depth/variation and add sediments/plants + smoother shoreline: /fixriver [radius] (look at river water).",
	params = "[radius]",
	privs = {server = true},
	func = function(name, param)
		local radius = clamp_int(param, 8, 256) or 96
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local target = get_pointed_water_pos(player, 64)
		if not target then
			return false, "Look at river water and try again."
		end
		core.log("action", ("[%s] /fixriver start pos=%s radius=%d"):format(MODNAME, core.pos_to_string(target), radius))
		local ok, msg = fix_river_at(target, radius)
		core.log("action", ("[%s] /fixriver done ok=%s msg=%s"):format(MODNAME, tostring(ok), tostring(msg)))
		return ok, msg
	end,
})

core.register_chatcommand("fixleaves", {
	description = "Recalculate leaf palette param2 from mcl_lun_biomes tags: /fixleaves [radius].",
	params = "[radius]",
	privs = {server = true},
	func = function(name, param)
		local radius = clamp_int(param, 8, 512) or 128
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local pos = vector.round(player:get_pos())
		local minp = vector.offset(pos, -radius, -radius, -radius)
		local maxp = vector.offset(pos, radius, radius, radius)
		local nodes = core.find_nodes_in_area(minp, maxp, {"group:leaves"})
		local changed = 0
		for _, p in ipairs(nodes) do
			local node = core.get_node(p)
			if core.get_item_group(node.name, "biomecolor") ~= 0 then
				local idx = api.palette_index(p, "leaves")
				if idx ~= nil then
					local base = math.floor((node.param2 or 0) / 32) * 32
					local next_p2 = base + idx
					if node.param2 ~= next_p2 then
						node.param2 = next_p2
						core.swap_node(p, node)
						changed = changed + 1
					end
				end
			end
		end
		return true, ("Updated %d leaf nodes (radius=%d)."):format(changed, radius)
	end,
})

core.register_chatcommand("biomecalc_world", {
	description = "Calculate custom biome tags in an X/Z rectangle without a player: /biomecalc_world <minx maxx minz maxz> [ymin ymax].",
	params = "<minx maxx minz maxz> [ymin ymax]",
	privs = {server = true},
	func = function(_name, param)
		local a, b, c, d, e, f = string.match(param or "", "^%s*(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)%s*(%-?%d*)%s*(%-?%d*)%s*$")
		if not (a and b and c and d) then
			return false, "Usage: /biomecalc_world <minx maxx minz maxz> [ymin ymax]"
		end
		local minx = clamp_int(a, -31000, 31000)
		local maxx = clamp_int(b, -31000, 31000)
		local minz = clamp_int(c, -31000, 31000)
		local maxz = clamp_int(d, -31000, 31000)
		if not (minx and maxx and minz and maxz) then
			return false, "Invalid bounds."
		end
		local ymin = clamp_int(e, -31000, 31000)
		local ymax = clamp_int(f, -31000, 31000)

		local ok, res = start_biomecalc_job({
			kind = "world",
			bx_min = floor_div(minx, 16),
			bx_max = floor_div(maxx, 16),
			bz_min = floor_div(minz, 16),
			bz_max = floor_div(maxz, 16),
			ymin = ymin,
			ymax = ymax,
		})
		if not ok then
			return false, res
		end
		core.log("action", ("[%s] /biomecalc_world start x=%d..%d z=%d..%d blocks=%d y=%d..%d"):format(
			MODNAME, minx, maxx, minz, maxz, res, job.ymin, job.ymax
		))
		return true, ("Started biomecalc_world (%d blocks). Use /biomecalc_status."):format(res)
	end,
})

core.register_chatcommand("biomecalc_status", {
	description = "Show status of the running biomecalc job.",
	privs = {interact = true},
	func = function()
		if not job then
			return true, "No biomecalc job running."
		end
		local elapsed = os.time() - (job.start or os.time())
		local bx = job.bx or 0
		local bz = job.bz or 0
		local kind = job.kind or "biomecalc"
		return true, ("%s: %d/%d blocks processed (elapsed %ds, at bx=%d bz=%d)"):format(kind, job.done, job.total, elapsed, bx, bz)
	end,
})

core.register_chatcommand("biomecalc_stop", {
	description = "Stop the running biomecalc job.",
	privs = {server = true},
	func = function()
		if not job then
			return true, "No biomecalc job running."
		end
		job = nil
		return true, "biomecalc stopped."
	end,
})

core.register_chatcommand("bamboo_stop", {
	description = "Stop the running /bamboo job.",
	privs = {server = true},
	func = function()
		if not bamboo_job then
			return true, "No /bamboo job running."
		end
		bamboo_job = nil
		return true, "/bamboo stopped."
	end,
})

core.register_chatcommand("bamboo3_stop", {
	description = "Stop the running /bamboo3 job.",
	privs = {server = true},
	func = function()
		if not bamboo3_job then
			return true, "No /bamboo3 job running."
		end
		bamboo3_job = nil
		return true, "/bamboo3 stopped."
	end,
})

core.register_globalstep(function(_dtime)
	-- Run /darkforest incrementally to avoid server stalls.
	if darkforest_job then
		local settings = get_settings()
		darkforest_step(settings.darkforest_nodes_per_step)
	end
	-- Run /bamboo incrementally to avoid server stalls.
	if bamboo_job then
		local settings = get_settings()
		bamboo_step(settings.bamboo_blocks_per_step or settings.bamboo_nodes_per_step)
	end
	-- Run /bamboo3 incrementally to avoid server stalls.
	if bamboo3_job then
		bamboo3_step()
	end

	if not job then
		return
	end

	if not CID_SETS then
		CID_SETS = {build_cid_sets()}
	end
	local water_cids, leaves_cids, tree_cids, snow_cids, bamboo_cids, spruce_cids =
		CID_SETS[1], CID_SETS[2], CID_SETS[3], CID_SETS[4], CID_SETS[5], CID_SETS[6]
	local per_step = job.settings.blocks_per_step * (job.settings.biomecalc_speed or 1)

	for _ = 1, per_step do
		if not job then
			return
		end
		if job.bx > job.bx_max then
			core.log("action", ("[%s] /biomecalc complete (%d blocks)"):format(MODNAME, job.done))
			job = nil
			return
		end

		local bx, bz = job.bx, job.bz
		local raw = classify_block(bx, bz, job.ymin, job.ymax, job.settings, water_cids, leaves_cids, tree_cids, snow_cids, bamboo_cids, spruce_cids)
		set_block_data(bx, bz, raw)

		job.done = job.done + 1
		job.bz = job.bz + 1
		if job.bz > job.bz_max then
			job.bz = job.bz_min
			job.bx = job.bx + 1
		end

		if job.done % 25 == 0 then
			core.log("action", ("[%s] /biomecalc progress %d/%d"):format(MODNAME, job.done, job.total))
		end
	end
end)

core.register_on_mods_loaded(function()
	-- Cache CID sets once mods/nodes are registered.
	CID_SETS = {build_cid_sets()}

		-- Prefer Mineclonia's BambooJungle palette indices when available.
		do
			local function resolve_biome_name(requested)
				if requested and core.registered_biomes and core.registered_biomes[requested] then
					return requested
			end
			local req = type(requested) == "string" and requested:lower() or nil
			if not req or not core.registered_biomes then
				return nil
			end
			for name, _ in pairs(core.registered_biomes) do
				if type(name) == "string" and name:lower() == req then
					return name
				end
			end
			return nil
		end

		local biome_name = resolve_biome_name("BambooJungle")
		if biome_name then
			local grass_idx = (DEFAULT_PALETTES.bamboo and DEFAULT_PALETTES.bamboo.grass) or 26
			local leaves_idx = (DEFAULT_PALETTES.bamboo and DEFAULT_PALETTES.bamboo.leaves) or grass_idx or 26

			local levelgen = rawget(_G, "mcl_levelgen")
			if levelgen and levelgen.registered_biomes and levelgen.registered_biomes[biome_name] then
				local def = levelgen.registered_biomes[biome_name]
				if type(def.grass_palette_index) == "number" then
					grass_idx = def.grass_palette_index
				elseif type(def._mcl_palette_index) == "number" then
					grass_idx = def._mcl_palette_index
				end
				if type(def.leaves_palette_index) == "number" then
					leaves_idx = def.leaves_palette_index
				elseif type(def._mcl_palette_index) == "number" then
					leaves_idx = def._mcl_palette_index
				end
			end

			local bdef = core.registered_biomes and core.registered_biomes[biome_name] or nil
			if bdef and type(bdef._mcl_palette_index) == "number" then
				grass_idx = bdef._mcl_palette_index
				leaves_idx = bdef._mcl_palette_index
			end

			grass_idx = math.max(0, math.floor(grass_idx or 0))
			leaves_idx = math.max(0, math.floor(leaves_idx or grass_idx or 0))
			DEFAULT_PALETTES.bamboo = {grass = grass_idx, leaves = leaves_idx}
				core.log("action", ("[%s] bamboo palette from %s (grass=%d leaves=%d)"):format(MODNAME, biome_name, grass_idx, leaves_idx))
			end
		end

		-- Prefer Mineclonia's (OldGrowth) Spruce Taiga palette indices when available.
		do
			local function resolve_biome_name(requested)
				if requested and core.registered_biomes and core.registered_biomes[requested] then
					return requested
				end
				local req = type(requested) == "string" and requested:lower() or nil
				if not req or not core.registered_biomes then
					return nil
				end
				for name, _ in pairs(core.registered_biomes) do
					if type(name) == "string" and name:lower() == req then
						return name
					end
				end
				return nil
			end

			local biome_name = resolve_biome_name("OldGrowthSpruceTaiga") or resolve_biome_name("Taiga")
			if biome_name then
				local grass_idx = (DEFAULT_PALETTES.sprucetaiga and DEFAULT_PALETTES.sprucetaiga.grass) or 12
				local leaves_idx = (DEFAULT_PALETTES.sprucetaiga and DEFAULT_PALETTES.sprucetaiga.leaves) or grass_idx or 12

				local levelgen = rawget(_G, "mcl_levelgen")
				if levelgen and levelgen.registered_biomes and levelgen.registered_biomes[biome_name] then
					local def = levelgen.registered_biomes[biome_name]
					if type(def.grass_palette_index) == "number" then
						grass_idx = def.grass_palette_index
					elseif type(def._mcl_palette_index) == "number" then
						grass_idx = def._mcl_palette_index
					end
					if type(def.leaves_palette_index) == "number" then
						leaves_idx = def.leaves_palette_index
					elseif type(def._mcl_palette_index) == "number" then
						leaves_idx = def._mcl_palette_index
					end
				end

				local bdef = core.registered_biomes and core.registered_biomes[biome_name] or nil
				if bdef and type(bdef._mcl_palette_index) == "number" then
					grass_idx = bdef._mcl_palette_index
					leaves_idx = bdef._mcl_palette_index
				end

				grass_idx = math.max(0, math.floor(grass_idx or 0))
				leaves_idx = math.max(0, math.floor(leaves_idx or grass_idx or 0))
				DEFAULT_PALETTES.sprucetaiga = {grass = grass_idx, leaves = leaves_idx}
				core.log("action", ("[%s] sprucetaiga palette from %s (grass=%d leaves=%d)"):format(MODNAME, biome_name, grass_idx, leaves_idx))
			end
		end

		-- Prevent Mineclonia's runtime "freeze water" ABM from creating ice based on engine biomes
		-- in areas where we have explicit mcl_lun_biomes tags.
		local mcl_biome_dispatch = rawget(_G, "mcl_biome_dispatch")
	if mcl_biome_dispatch and mcl_biome_dispatch.is_position_cold then
		local orig = mcl_biome_dispatch.is_position_cold
		mcl_biome_dispatch.is_position_cold = function(biome_name, pos, ...)
			if api.get_id(pos) ~= nil then
				return false
			end
			return orig(biome_name, pos, ...)
		end
		mcl_biome_dispatch._mcl_lun_biomes_orig_is_position_cold = orig
	end

	-- Hook Mineclonia "pos -> palette index" helper so palette-colored plants (e.g. tallgrass/fern)
	-- and leaves placement consult our biome tags first.
	local mcl_util = rawget(_G, "mcl_util")
	if mcl_util and mcl_util.get_pos_p2 then
		local orig = mcl_util.get_pos_p2
		mcl_util.get_pos_p2 = function(pos, for_trees)
			if type(pos) == "table" and pos.x and pos.z then
				local idx = api.palette_index(pos, for_trees and "leaves" or "grass")
				if idx ~= nil then
					return idx
				end
			end
			return orig(pos, for_trees)
		end
		mcl_util._mcl_lun_biomes_orig_get_pos_p2 = orig
	end

	-- Ensure bone-meal growth for palette-colored plants (tallgrass/fern) uses our palette index.
	local mcl_flowers = rawget(_G, "mcl_flowers")
	if mcl_flowers and mcl_flowers.on_bone_meal and mcl_flowers.get_palette_color_from_pos then
		local orig = mcl_flowers.on_bone_meal
		mcl_flowers.on_bone_meal = function(itemstack, user, pointed_thing, pos, n)
			local def = n and n.name and core.registered_nodes[n.name] or nil
			if def and def.palette and def.paramtype2 == "color" then
				local idx = mcl_flowers.get_palette_color_from_pos(pos)
				if idx ~= nil then
					n = table.copy(n)
					n.param2 = idx
				end
			end
			return orig(itemstack, user, pointed_thing, pos, n)
		end
		mcl_flowers._mcl_lun_biomes_orig_on_bone_meal = orig
	end

	-- Hook Mineclonia grass/leaves palette lookups to consult our tags first.
	local mcl_core = rawget(_G, "mcl_core")
	if mcl_core and mcl_core.get_grass_palette_index then
		local orig = mcl_core.get_grass_palette_index
		mcl_core.get_grass_palette_index = function(pos)
			local idx = api.palette_index(pos, "grass")
			if idx ~= nil then
				return idx
			end
			return orig(pos)
		end
		mcl_core._mcl_lun_biomes_orig_get_grass_palette_index = orig
	end

	local mcl_trees = rawget(_G, "mcl_trees")
	if mcl_trees and mcl_trees.get_biome_color then
		local orig = mcl_trees.get_biome_color
		mcl_trees.get_biome_color = function(x, y, z)
			local idx = api.palette_index({x = x, y = y, z = z}, "leaves")
			if idx ~= nil then
				return idx
			end
			return orig(x, y, z)
		end
		mcl_trees._mcl_lun_biomes_orig_get_biome_color = orig
	end
end)

-- Recolor palette-based nodes on load from our biome tags.
-- This makes already-generated grass/foliage update even after a restart, without requiring re-placement.
core.register_lbm({
	label = "mcl_lun_biomes: recolor grass palette nodes",
	name = "mcl_lun_biomes:recolor_grass_palette",
	nodenames = {"group:grass_palette"},
	run_at_every_load = true,
	action = function(pos, node)
		local idx = api.palette_index(pos, "grass")
		if idx == nil then
			return
		end
		if node.param2 == idx then
			return
		end
		node.param2 = idx
		core.swap_node(pos, node)
	end,
})

core.register_lbm({
	label = "mcl_lun_biomes: recolor grass blocks",
	name = "mcl_lun_biomes:recolor_grass_blocks",
	nodenames = {"group:grass_block"},
	run_at_every_load = true,
	action = function(pos, node)
		local def = core.registered_nodes[node.name]
		if not (def and def.paramtype2 == "color" and def.palette) then
			return
		end
		local idx = api.palette_index(pos, "grass")
		if idx == nil then
			return
		end
		if node.param2 == idx then
			return
		end
		node.param2 = idx
		core.swap_node(pos, node)
	end,
})

core.register_lbm({
	label = "mcl_lun_biomes: recolor leaves",
	name = "mcl_lun_biomes:recolor_leaves",
	nodenames = {"group:leaves"},
	run_at_every_load = true,
	action = function(pos, node)
		if core.get_item_group(node.name, "biomecolor") == 0 then
			return
		end
		local idx = api.palette_index(pos, "leaves")
		if idx == nil then
			return
		end
		local base = math.floor((node.param2 or 0) / 32) * 32
		local next_p2 = base + idx
		if node.param2 == next_p2 then
			return
		end
		node.param2 = next_p2
		core.swap_node(pos, node)
	end,
})
