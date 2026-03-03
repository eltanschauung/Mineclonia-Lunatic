local MODNAME = core.get_current_modname()

local override = {
	enabled = false,
	grass_idx = 0,
	leaves_idx = 0,
}

local function retint_area(minp, maxp, leaves_idx, grass_idx)
	local vm = core.get_voxel_manip()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local param2 = vm:get_param2_data()

	local changed = 0

	-- Leaves: anything in group:leaves AND biomecolor gets forced param2.
	-- We don't have groups in voxel data directly, so we build a cid whitelist.
	local leaves_cids = {}
	for name, def in pairs(core.registered_nodes) do
		if def and def.groups and def.groups.leaves and def.groups.biomecolor and def.groups.biomecolor > 0 then
			local cid = core.get_content_id(name)
			if cid then
				leaves_cids[cid] = true
			end
		end
	end
	local cid_grass = core.get_content_id("mcl_core:dirt_with_grass")

	for z = emin.z, emax.z do
		for y = emin.y, emax.y do
			local vi = area:index(emin.x, y, z)
			for x = emin.x, emax.x do
				local cid = data[vi]
				if cid == cid_grass then
					if param2[vi] ~= grass_idx then
						param2[vi] = grass_idx
						changed = changed + 1
					end
				elseif leaves_cids[cid] then
					if param2[vi] ~= leaves_idx then
						param2[vi] = leaves_idx
						changed = changed + 1
					end
				end
				vi = vi + 1
			end
		end
	end

	if changed > 0 then
		vm:set_param2_data(param2)
		vm:write_to_map()
	end
	return changed
end

core.register_chatcommand("retint", {
	description = "Retint loaded map area to the biome override palette (leaves/grass).",
	params = "[radius] [ymin] [ymax]",
	privs = {server = true},
	func = function(name, param)
		if not override.enabled then
			return false, "Biome override not enabled (set mcl_lun_biome_override in minetest.conf)."
		end
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		local radius, ymin, ymax = string.match(param or "", "^%s*(%-?%d+)%s*(%-?%d*)%s*(%-?%d*)%s*$")
		radius = tonumber(radius) or 80
		ymin = tonumber(ymin)
		ymax = tonumber(ymax)
		if radius < 16 then radius = 16 end
		if radius > 512 then radius = 512 end

		local pos = vector.round(player:get_pos())
		ymin = ymin or (pos.y - 32)
		ymax = ymax or (pos.y + 32)
		if ymin > ymax then ymin, ymax = ymax, ymin end

		local minp = {x = pos.x - radius, y = ymin, z = pos.z - radius}
		local maxp = {x = pos.x + radius, y = ymax, z = pos.z + radius}

		local chunk = 80
		local total_changed = 0
		local steps = 0
		for x0 = minp.x, maxp.x, chunk do
			for z0 = minp.z, maxp.z, chunk do
				local cmin = {x = x0, y = minp.y, z = z0}
				local cmax = {x = math.min(x0 + chunk - 1, maxp.x), y = maxp.y, z = math.min(z0 + chunk - 1, maxp.z)}
				total_changed = total_changed + retint_area(cmin, cmax, override.leaves_idx, override.grass_idx)
				steps = steps + 1
				if steps % 4 == 0 then
					core.log("action", ("[%s] /retint progress: %d chunks, %d nodes updated"):format(MODNAME, steps, total_changed))
				end
			end
		end
		return true, ("Retint complete: %d nodes updated in radius %d."):format(total_changed, radius)
	end,
})

-- Register this at mod load time (register_lbm requires a current modname).
core.register_lbm({
	name = MODNAME .. ":recolor_grass_and_leaves",
	label = "Biome override recolor",
	run_at_every_load = false,
	nodenames = {"mcl_core:dirt_with_grass", "group:leaves"},
	action = function(pos, node)
		if not override.enabled or not pos or not node then
			return
		end
		local grass_idx = override.grass_idx
		local leaves_idx = override.leaves_idx
		if node.name == "mcl_core:dirt_with_grass" then
			if node.param2 ~= grass_idx then
				core.swap_node(pos, {name = node.name, param2 = grass_idx})
			end
			return
		end
		-- Leaves: only recolor Mineclonia biome-tinted leaves.
		if core.get_item_group(node.name, "biomecolor") > 0 then
			if node.param2 ~= leaves_idx then
				core.swap_node(pos, {name = node.name, param2 = leaves_idx})
			end
		end
	end,
})

local function get_setting()
	-- Example: mcl_lun_biome_override = forest
	local s = core.settings and core.settings:get("mcl_lun_biome_override") or ""
	if type(s) ~= "string" then
		return ""
	end
	s = s:match("^%s*(.-)%s*$")
	return s
end

local function resolve_biome_name(requested)
	if requested == "" then
		return nil
	end
	local req = requested:lower()
	-- Exact key match first (case-sensitive).
	if core.registered_biomes[requested] then
		return requested
	end
	-- Case-insensitive match.
	for name, _ in pairs(core.registered_biomes) do
		if type(name) == "string" and name:lower() == req then
			return name
		end
	end
	return nil
end

local function get_palette_indices(biome_name)
	-- Returns grass_idx, leaves_idx
	local grass_idx, leaves_idx = 0, 0

	-- Mineclonia levelgen table (preferred when present).
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

	-- Engine biome definition fallback.
	local bdef = core.registered_biomes[biome_name]
	if bdef then
		if type(bdef._mcl_palette_index) == "number" then
			grass_idx = grass_idx ~= 0 and grass_idx or bdef._mcl_palette_index
			leaves_idx = leaves_idx ~= 0 and leaves_idx or bdef._mcl_palette_index
		end
	end

	return math.max(0, math.floor(grass_idx or 0)), math.max(0, math.floor(leaves_idx or 0))
end

core.register_on_mods_loaded(function()
	local requested = get_setting()
	if requested == "" then
		return
	end

	local biome_name = resolve_biome_name(requested)
	if not biome_name then
		core.log("warning", ("[%s] Unknown biome override '%s'"):format(MODNAME, requested))
		return
	end

	local grass_idx, leaves_idx = get_palette_indices(biome_name)
	override.enabled = true
	override.grass_idx = grass_idx
	override.leaves_idx = leaves_idx
	core.log("action", ("[%s] Overriding grass/leaves palette to biome '%s' (grass=%d leaves=%d)"):format(
		MODNAME, biome_name, grass_idx, leaves_idx
	))

	-- Hook grass palette selection.
	local mcl_core = rawget(_G, "mcl_core")
	if mcl_core and mcl_core.get_grass_palette_index then
		local orig = mcl_core.get_grass_palette_index
		mcl_core.get_grass_palette_index = function(_pos)
			return grass_idx
		end
		mcl_core._mcl_lun_biome_override_grass_palette_index = orig
	end

	-- Hook leaves palette selection used by Mineclonia tree placement.
	local mcl_trees = rawget(_G, "mcl_trees")
	if mcl_trees and mcl_trees.get_biome_color then
		local orig = mcl_trees.get_biome_color
		mcl_trees.get_biome_color = function(_x, _y, _z)
			return leaves_idx
		end
		mcl_trees._mcl_lun_biome_override_leaves_palette_index = orig
	end
end)
