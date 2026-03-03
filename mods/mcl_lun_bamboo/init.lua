local MODNAME = core.get_current_modname()

local LIME_WOOL = "mcl_wool:lime"
local OAK_LEAVES = "mcl_trees:leaves_oak"
local BAMBOO_SEGMENT = "mcl_bamboo:bamboo_big"
local BAMBOO_BLOCK = "mcl_trees:tree_bamboo"
local BIOME_API = rawget(_G, "mcl_lun_biomes")
local BAMBOO_BIOME_ID = nil

core.register_on_mods_loaded(function()
	BIOME_API = rawget(_G, "mcl_lun_biomes")
	BAMBOO_BIOME_ID = BIOME_API and BIOME_API.resolve_id and BIOME_API.resolve_id("bamboo") or nil
end)

local DEFAULT_RADIUS = 256
local DEFAULT_YSPAN_BELOW = 32
local DEFAULT_YSPAN_ABOVE = 128

local MAX_COLUMN_SCAN = 256
local MAX_BAMBOO_HEIGHT = 48
local MIN_COLUMN_HEIGHT = 1
local SHORT_COLUMN_MAX = 5

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

local function floor_div(a, b)
	return math.floor(a / b)
end

local function get_settings()
	local s = core.settings
	return {
		blocks_per_step = clamp_int(s:get("mcl_lun_bamboo_blocks_per_step"), 1, 256) or 24,
		time_budget_us = (clamp_int(s:get("mcl_lun_bamboo_time_budget_ms"), 1, 100) or 12) * 1000,
	}
end

local function get_pointed_lime_pos(player, range)
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
			if node and node.name == LIME_WOOL then
				return pos
			end
		end
	end
	return nil
end

local function find_column_base(pos)
	pos = vector.round(pos)
	for _ = 1, MAX_COLUMN_SCAN do
		local below = vector.offset(pos, 0, -1, 0)
		local node = core.get_node_or_nil(below)
		if not node or node.name ~= LIME_WOOL then
			return pos
		end
		pos = below
	end
	return pos
end

local function measure_column_height(base_pos, y_max)
	local height = 0
	for dy = 0, MAX_COLUMN_SCAN - 1 do
		local y = base_pos.y + dy
		if y_max and y > y_max then
			break
		end
		local node = core.get_node_or_nil({x = base_pos.x, y = y, z = base_pos.z})
		if not node or node.name ~= LIME_WOOL then
			break
		end
		height = height + 1
	end
	return height
end

local function has_side_lime(base_pos)
	local y = base_pos.y
	local checks = {
		{x = base_pos.x + 1, y = y, z = base_pos.z},
		{x = base_pos.x - 1, y = y, z = base_pos.z},
		{x = base_pos.x, y = y, z = base_pos.z + 1},
		{x = base_pos.x, y = y, z = base_pos.z - 1},
	}
	for _, p in ipairs(checks) do
		local n = core.get_node_or_nil(p)
		if n and n.name == LIME_WOOL then
			return true
		end
	end
	return false
end

local LEAF_OFFSETS = {
	{dx = 1, dz = 0}, {dx = -1, dz = 0}, {dx = 0, dz = 1}, {dx = 0, dz = -1},
	{dx = 1, dz = 1}, {dx = 1, dz = -1}, {dx = -1, dz = 1}, {dx = -1, dz = -1},
	{dx = 2, dz = 0}, {dx = -2, dz = 0}, {dx = 0, dz = 2}, {dx = 0, dz = -2},
}

local function has_oak_leaves_near_top(base_pos, height)
	if height < 1 then
		return false
	end
	local top_y = base_pos.y + height - 1
	local y0 = math.max(base_pos.y, top_y - 6)
	for y = y0, top_y do
		for _, o in ipairs(LEAF_OFFSETS) do
			local p = {x = base_pos.x + o.dx, y = y, z = base_pos.z + o.dz}
			local n = core.get_node_or_nil(p)
			if n and n.name == OAK_LEAVES then
				return true
			end
		end
	end
	return false
end

local function leaf_is_adjacent_to_lime(pos)
	local adj = {
		vector.offset(pos, 1, 0, 0),
		vector.offset(pos, -1, 0, 0),
		vector.offset(pos, 0, 1, 0),
		vector.offset(pos, 0, -1, 0),
		vector.offset(pos, 0, 0, 1),
		vector.offset(pos, 0, 0, -1),
	}
	for _, p in ipairs(adj) do
		local n = core.get_node_or_nil(p)
		if n and n.name == LIME_WOOL then
			return true
		end
	end
	return false
end

local function clear_fake_leaves(base_pos, height)
	for dy = 0, height - 1 do
		local y = base_pos.y + dy
		for _, o in ipairs(LEAF_OFFSETS) do
			local p = {x = base_pos.x + o.dx, y = y, z = base_pos.z + o.dz}
			local n = core.get_node_or_nil(p)
			if n and n.name == OAK_LEAVES and leaf_is_adjacent_to_lime(p) then
				core.set_node(p, {name = "air"})
			end
		end
	end
end

local function clear_top_leaves(base_pos, height)
	if height < 1 then
		return
	end
	local top_y = base_pos.y + height - 1
	for _, y in ipairs({top_y, top_y + 1}) do
		for _, o in ipairs(LEAF_OFFSETS) do
			local p = {x = base_pos.x + o.dx, y = y, z = base_pos.z + o.dz}
			local n = core.get_node_or_nil(p)
			if n and n.name == OAK_LEAVES then
				core.set_node(p, {name = "air"})
			end
		end
	end
end

local function replace_column_with_bamboo(base_pos, height)
	local target_h = math.min(height, MAX_BAMBOO_HEIGHT)
	local param2 = math.random(0, 3)

	clear_fake_leaves(base_pos, height)
	clear_top_leaves(base_pos, height)

	for dy = 0, height - 1 do
		local p = {x = base_pos.x, y = base_pos.y + dy, z = base_pos.z}
		if dy < target_h then
			core.set_node(p, {name = BAMBOO_SEGMENT, param2 = param2})
		else
			core.set_node(p, {name = "air"})
		end
	end

	if mcl_bamboo and mcl_bamboo.check_structure then
		mcl_bamboo.check_structure(base_pos)
	end

	if BIOME_API and BAMBOO_BIOME_ID ~= nil then
		for dx = -1, 1 do
			for dz = -1, 1 do
				BIOME_API.set_id({x = base_pos.x + dx, y = 0, z = base_pos.z + dz}, BAMBOO_BIOME_ID)
			end
		end
	end
end

local job = nil
local replace_job = nil

local function start_job(center_pos, radius, ymin, ymax)
	if job then
		return false, "A bamboo conversion job is already running. Use /lun_bamboo_status or /lun_bamboo_stop."
	end
	if not (core.registered_nodes[LIME_WOOL] and core.registered_nodes[BAMBOO_SEGMENT]) then
		return false, ("Missing nodes: need %s and %s loaded."):format(LIME_WOOL, BAMBOO_SEGMENT)
	end
	if not (mcl_bamboo and mcl_bamboo.check_structure) then
		return false, "mcl_bamboo.check_structure not available (is mcl_bamboo loaded?)."
	end

	radius = clamp_int(radius, 8, 4096) or DEFAULT_RADIUS
	ymin = clamp_int(ymin, -31000, 31000) or (center_pos.y - DEFAULT_YSPAN_BELOW)
	ymax = clamp_int(ymax, -31000, 31000) or (center_pos.y + DEFAULT_YSPAN_ABOVE)
	if ymin > ymax then
		ymin, ymax = ymax, ymin
	end

	local bx_min = floor_div(center_pos.x - radius, 16)
	local bx_max = floor_div(center_pos.x + radius, 16)
	local bz_min = floor_div(center_pos.z - radius, 16)
	local bz_max = floor_div(center_pos.z + radius, 16)
	local by_min = floor_div(ymin, 16)
	local by_max = floor_div(ymax, 16)

	job = {
		start = os.time(),
		center = vector.round(center_pos),
		radius = radius,
		r2 = radius * radius,
		ymin = ymin,
		ymax = ymax,
		cx = center_pos.x,
		cz = center_pos.z,
		bx_min = bx_min,
		bx_max = bx_max,
		bz_min = bz_min,
		bz_max = bz_max,
		by_min = by_min,
		by_max = by_max,
		bx = bx_min,
		bz = bz_min,
		by = by_min,
		visited = {},
		blocks_scanned = 0,
		columns_found = 0,
		columns_replaced = 0,
		columns_skipped = 0,
	}

	return true, ("Queued bamboo conversion: radius=%d y=%d..%d. Use /lun_bamboo_status."):format(radius, ymin, ymax)
end

local function advance_block_cursor(j)
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

local function pos_hash(pos)
	if core.hash_node_position then
		return core.hash_node_position(pos)
	end
	return ("%d,%d,%d"):format(pos.x, pos.y, pos.z)
end

local function process_block(j)
	local minp = {x = j.bx * 16, y = j.by * 16, z = j.bz * 16}
	local maxp = {x = minp.x + 15, y = minp.y + 15, z = minp.z + 15}

	local nodes = core.find_nodes_in_area(minp, maxp, {LIME_WOOL})
	j.blocks_scanned = (j.blocks_scanned or 0) + 1
	if not nodes or #nodes == 0 then
		return
	end

	for _, pos in ipairs(nodes) do
		local below = vector.offset(pos, 0, -1, 0)
		local below_node = core.get_node_or_nil(below)
		-- Only process bases (node below is known and not lime wool).
		if below_node and below_node.name ~= LIME_WOOL then
			local dx = pos.x - (j.cx or 0)
			local dz = pos.z - (j.cz or 0)
			if (dx * dx + dz * dz) <= (j.r2 or 0) then
				local base = vector.round(pos)
				local hkey = pos_hash(base)
				if not j.visited[hkey] then
					j.visited[hkey] = true

					local height = measure_column_height(base, j.ymax)
					if height < MIN_COLUMN_HEIGHT then
						j.columns_skipped = (j.columns_skipped or 0) + 1
					elseif has_side_lime(base) then
						j.columns_skipped = (j.columns_skipped or 0) + 1
					elseif height > SHORT_COLUMN_MAX and not has_oak_leaves_near_top(base, height) then
						j.columns_skipped = (j.columns_skipped or 0) + 1
					else
						j.columns_found = (j.columns_found or 0) + 1
						replace_column_with_bamboo(base, height)
						j.columns_replaced = (j.columns_replaced or 0) + 1
					end
				end
			end
		end
	end
end

local function step_job()
	local j = job
	if not j then
		return
	end

	local settings = get_settings()
	local blocks_budget = settings.blocks_per_step or 8
	local time_budget_us = settings.time_budget_us or 6000
	local start_us = core.get_us_time and core.get_us_time() or nil

	local blocks_done = 0
	while blocks_done < blocks_budget do
		if j.by > j.by_max then
			local elapsed = os.time() - (j.start or os.time())
			core.log("action", ("[%s] lun_bamboo complete blocks=%d found=%d replaced=%d skipped=%d elapsed=%ds"):format(
				MODNAME,
				j.blocks_scanned or 0,
				j.columns_found or 0,
				j.columns_replaced or 0,
				j.columns_skipped or 0,
				elapsed
			))
			job = nil
			return
		end

		process_block(j)
		advance_block_cursor(j)
		blocks_done = blocks_done + 1

		if start_us and (blocks_done % 2) == 0 and (core.get_us_time() - start_us) >= time_budget_us then
			return
		end
	end
end

core.register_globalstep(function()
	if job then
		step_job()
	end
	if replace_job then
		local j = replace_job
		local settings = get_settings()
		local blocks_budget = settings.blocks_per_step or 8
		local time_budget_us = settings.time_budget_us or 6000
		local start_us = core.get_us_time and core.get_us_time() or nil
		local biome_radius = 4 -- 9x9 XZ tagging around each replaced column.

		local blocks_done = 0
		while blocks_done < blocks_budget do
			if j.by > j.by_max then
				local elapsed = os.time() - (j.start or os.time())
				core.log("action", ("[%s] lun_bamboo2 complete blocks=%d replaced=%d elapsed=%ds"):format(
					MODNAME,
					j.blocks_scanned or 0,
					j.nodes_replaced or 0,
					elapsed
				))
				replace_job = nil
				return
			end

			local minp = {x = j.bx * 16, y = j.by * 16, z = j.bz * 16}
			local maxp = {x = minp.x + 15, y = minp.y + 15, z = minp.z + 15}

			local nodes = core.find_nodes_in_area(minp, maxp, {LIME_WOOL})
			j.blocks_scanned = (j.blocks_scanned or 0) + 1
			if nodes and #nodes > 0 then
				local tagged = j.tagged_cols or {}
				local replaced_here = 0
				for _, p in ipairs(nodes) do
					local dx = p.x - (j.cx or 0)
					local dz = p.z - (j.cz or 0)
					if (dx * dx + dz * dz) <= (j.r2 or 0) then
						core.swap_node(p, {name = BAMBOO_BLOCK})
						replaced_here = replaced_here + 1
						if BIOME_API and BAMBOO_BIOME_ID ~= nil then
							local key = p.x .. "," .. p.z
							if not tagged[key] then
								tagged[key] = true
								for dx2 = -biome_radius, biome_radius do
									for dz2 = -biome_radius, biome_radius do
										BIOME_API.set_id({x = p.x + dx2, y = 0, z = p.z + dz2}, BAMBOO_BIOME_ID)
									end
								end
							end
						end
					end
				end
				j.tagged_cols = tagged
				j.nodes_replaced = (j.nodes_replaced or 0) + replaced_here
			end

			advance_block_cursor(j)
			blocks_done = blocks_done + 1

			if start_us and (blocks_done % 2) == 0 and (core.get_us_time() - start_us) >= time_budget_us then
				return
			end
		end
	end
end)

core.register_chatcommand("lun_bamboo", {
	description = "Replace Lunatic lime-wool 'bamboo' columns (with oak leaves) with Mineclonia bamboo. Look at lime wool: /lun_bamboo [radius] [ymin] [ymax]",
	params = "[radius] [ymin] [ymax]",
	privs = {server = true},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local start = get_pointed_lime_pos(player, 96)
		if not start then
			return false, "Look at a lime wool bamboo column and try again."
		end

		local args = {}
		for w in (param or ""):gmatch("%S+") do
			args[#args + 1] = w
		end
		local radius = args[1]
		local ymin = args[2]
		local ymax = args[3]

		local base = find_column_base(start)
		core.log("action", ("[%s] /lun_bamboo start=%s base=%s param=%q"):format(
			MODNAME,
			core.pos_to_string(vector.round(start)),
			core.pos_to_string(vector.round(base)),
			param or ""
		))

		return start_job(base, radius, ymin, ymax)
	end,
})

core.register_chatcommand("lun_bamboo_status", {
	description = "Show status of the running /lun_bamboo job.",
	privs = {interact = true},
	func = function()
		if not job then
			return true, "No /lun_bamboo job running."
		end
		local j = job
		local elapsed = os.time() - (j.start or os.time())
		return true, ("lun_bamboo: blocks=%d found=%d replaced=%d skipped=%d at=(%d,%d,%d) elapsed=%ds"):format(
			j.blocks_scanned or 0,
			j.columns_found or 0,
			j.columns_replaced or 0,
			j.columns_skipped or 0,
			j.bx or 0, j.by or 0, j.bz or 0,
			elapsed
		)
	end,
})

core.register_chatcommand("lun_bamboo_stop", {
	description = "Stop the running /lun_bamboo job.",
	privs = {server = true},
	func = function()
		if not job then
			return true, "No /lun_bamboo job running."
		end
		job = nil
		return true, "/lun_bamboo stopped."
	end,
})

local function start_replace_job(center_pos, radius, ymin, ymax)
	if replace_job then
		return false, "A /lun_bamboo2 job is already running. Use /lun_bamboo2_status or /lun_bamboo2_stop."
	end
	if job then
		return false, "A /lun_bamboo job is running. Stop it with /lun_bamboo_stop before using /lun_bamboo2."
	end
	if not (core.registered_nodes[LIME_WOOL] and core.registered_nodes[BAMBOO_BLOCK]) then
		return false, ("Missing nodes: need %s and %s loaded."):format(LIME_WOOL, BAMBOO_BLOCK)
	end

	center_pos = vector.round(center_pos)
	radius = clamp_int(radius, 8, 4096) or DEFAULT_RADIUS
	ymin = clamp_int(ymin, -31000, 31000) or (center_pos.y - DEFAULT_YSPAN_BELOW)
	ymax = clamp_int(ymax, -31000, 31000) or (center_pos.y + DEFAULT_YSPAN_ABOVE)
	if ymin > ymax then
		ymin, ymax = ymax, ymin
	end

	local bx_min = floor_div(center_pos.x - radius, 16)
	local bx_max = floor_div(center_pos.x + radius, 16)
	local bz_min = floor_div(center_pos.z - radius, 16)
	local bz_max = floor_div(center_pos.z + radius, 16)
	local by_min = floor_div(ymin, 16)
	local by_max = floor_div(ymax, 16)

	replace_job = {
		start = os.time(),
		center = center_pos,
		radius = radius,
		r2 = radius * radius,
		ymin = ymin,
		ymax = ymax,
		cx = center_pos.x,
		cz = center_pos.z,
		bx_min = bx_min,
		bx_max = bx_max,
		bz_min = bz_min,
		bz_max = bz_max,
		by_min = by_min,
		by_max = by_max,
		bx = bx_min,
		bz = bz_min,
		by = by_min,
		blocks_scanned = 0,
		nodes_replaced = 0,
	}

	return true, ("Queued /lun_bamboo2: radius=%d y=%d..%d. Use /lun_bamboo2_status."):format(radius, ymin, ymax)
end

core.register_chatcommand("lun_bamboo2", {
	description = "Replace all mcl_wool:lime in a radius with mcl_trees:tree_bamboo: /lun_bamboo2 [radius] [ymin] [ymax]",
	params = "[radius] [ymin] [ymax]",
	privs = {server = true},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local pos = vector.round(player:get_pos())

		local args = {}
		for w in (param or ""):gmatch("%S+") do
			args[#args + 1] = w
		end
		local radius = args[1]
		local ymin = args[2]
		local ymax = args[3]

		core.log("action", ("[%s] /lun_bamboo2 start pos=%s param=%q"):format(MODNAME, core.pos_to_string(pos), param or ""))
		return start_replace_job(pos, radius, ymin, ymax)
	end,
})

core.register_chatcommand("lun_bamboo2_status", {
	description = "Show status of the running /lun_bamboo2 job.",
	privs = {interact = true},
	func = function()
		if not replace_job then
			return true, "No /lun_bamboo2 job running."
		end
		local j = replace_job
		local elapsed = os.time() - (j.start or os.time())
		return true, ("lun_bamboo2: blocks=%d replaced=%d at=(%d,%d,%d) elapsed=%ds"):format(
			j.blocks_scanned or 0,
			j.nodes_replaced or 0,
			j.bx or 0, j.by or 0, j.bz or 0,
			elapsed
		)
	end,
})

core.register_chatcommand("lun_bamboo2_stop", {
	description = "Stop the running /lun_bamboo2 job.",
	privs = {server = true},
	func = function()
		if not replace_job then
			return true, "No /lun_bamboo2 job running."
		end
		replace_job = nil
		return true, "/lun_bamboo2 stopped."
	end,
})
