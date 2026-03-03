local MODNAME = core.get_current_modname()
local S = core.get_translator(MODNAME)

local mcl_lun_biomes = rawget(_G, "mcl_lun_biomes")
local mcl_mobs = rawget(_G, "mcl_mobs")
	local wielded_light = rawget(_G, "wielded_light")
	local mcl_lun_sounds = rawget(_G, "mcl_lun_sounds")

	local ENTITY_FIREFLY = MODNAME .. ":firefly"
	local LIGHT_ITEM = MODNAME .. ":firefly_light"
	local ENTITY_BLUE_FIREFLY = MODNAME .. ":blue_firefly"
	local BLUE_LIGHT_ITEM = MODNAME .. ":blue_firefly_light"

local abs, floor, sqrt = math.abs, math.floor, math.sqrt
local cos, sin = math.cos, math.sin
local min, max = math.min, math.max
local random = math.random
local pi = math.pi

local get_node_or_nil = core.get_node_or_nil
local find_node_near = core.find_node_near
local get_objects_inside_radius = core.get_objects_inside_radius
	local get_connected_players = core.get_connected_players
	local add_entity = core.add_entity
	local get_gametime = core.get_gametime
	local get_timeofday = core.get_timeofday
	local sound_play = core.sound_play
	local get_biome_data = core.get_biome_data
	local get_biome_name = core.get_biome_name
	local registered_nodes = core.registered_nodes
	local log = core.log
	local pos_to_string = core.pos_to_string

	----------------------------------------------------------------------
	-- Cached node queries
	----------------------------------------------------------------------

	local passable_cache = { air = true }
	local function node_allows_player_pass_cached(node_name)
		if node_name == "air" then
		return true
	end
	local cached = passable_cache[node_name]
	if cached ~= nil then
		return cached
	end
	local def = registered_nodes[node_name]
	local passable = def and not def.walkable or false
	passable_cache[node_name] = passable
	return passable
end

local function roundi(v)
	return floor(v + 0.5)
end

local TMP_POS = {x = 0, y = 0, z = 0}
local function point_is_free_xyz(x, y, z)
	TMP_POS.x = roundi(x)
	TMP_POS.y = roundi(y)
	TMP_POS.z = roundi(z)
	local node = get_node_or_nil(TMP_POS)
	if not (node and node.name) then
		return false
	end
	return node_allows_player_pass_cached(node.name)
end

	local XZ_KEY_MUL = 262144 -- supports +/-131071 Z without collisions
	local surface_y_cache = {}
	local SURFACE_Y_CACHE_TTL = 2

	-- Returns the first non-walkable surface Y+1 at the rounded X/Z column, scanning
	-- down from the rounded Y position up to max_drop nodes. Cached across entities.
	local function ground_surface_y_cached(x, y, z, max_drop)
		max_drop = max_drop or 24
		local ix = roundi(x)
		local iz = roundi(z)
		local key = ix * XZ_KEY_MUL + iz
		local now = get_gametime()
		local cached = surface_y_cache[key]
		if cached and (now - cached.t) <= SURFACE_Y_CACHE_TTL then
			return cached.y
		end

		local start_y = roundi(y)
		TMP_POS.x = ix
		TMP_POS.z = iz
		for yy = start_y, start_y - max_drop, -1 do
			TMP_POS.y = yy
			local node = get_node_or_nil(TMP_POS)
			if not (node and node.name) then
				surface_y_cache[key] = {t = now, y = nil}
				return nil
			end
			local def = registered_nodes[node.name]
			if def and def.walkable then
				local surface_y = yy + 1
				surface_y_cache[key] = {t = now, y = surface_y}
				return surface_y
			end
		end

		surface_y_cache[key] = {t = now, y = nil}
		return nil
	end

	local COLLECT_STATS = false
	local STATS = {
		spawned = 0,
		removed = {},
}

	local function stats_inc(map, key, amount)
		if not COLLECT_STATS then
			return
		end
	amount = amount or 1
	map[key] = (map[key] or 0) + amount
end

local function debug_log(self, msg)
	if self and self._debug then
		log("action", ("[%s] %s"):format(MODNAME, msg))
	end
end

	local function remove_self(self, reason, extra)
		if not self or not self.object then
			return
		end
		stats_inc(STATS.removed, tostring(reason))
		local pos = self.object:get_pos()
		if self._debug then
			log("action", ("[%s] firefly remove reason=%s spawn_type=%s pos=%s %s"):format(
				MODNAME,
			tostring(reason),
			tostring(self._spawn_type),
			pos and pos_to_string(pos) or "<nil>",
			extra and tostring(extra) or ""
		))
	end
		self.object:remove()
	end

	-- Reuse Mineclonia silverfish hurt/death sounds for fireflies.
	local SILVERFISH_HURT_SOUND = "mobs_mc_silverfish_hurt"
	local SILVERFISH_DEATH_SOUND = "mobs_mc_silverfish_death"

	local function play_firefly_hurt(self)
		if not (self and self.object) then
			return
		end
		sound_play(SILVERFISH_HURT_SOUND, {object = self.object, max_hear_distance = 16, gain = 0.8}, true)
	end

	local function play_firefly_death_if_dead(self)
		if not (self and self.object) then
			return
		end
		-- Delay one tick so HP is updated by the engine.
		minetest.after(0, function()
			if not (self and self.object) then
				return
			end
			if self.object:get_hp() <= 0 then
				sound_play(SILVERFISH_DEATH_SOUND, {object = self.object, max_hear_distance = 16, gain = 0.8}, true)
			end
		end)
	end

local function clamp_int(v, lo, hi)
	v = tonumber(v)
	if not v then
		return nil
	end
	v = math.floor(v)
	if lo and v < lo then
		v = lo
	end
	if hi and v > hi then
		v = hi
	end
	return v
end

	local spawn_interval = tonumber(core.settings:get("mcl_lun_mobs_firefly_spawn_interval")) or 1.0
	local player_cap = clamp_int(core.settings:get("mcl_lun_mobs_firefly_player_cap"), 1, 200) or 48
	local local_cap = clamp_int(core.settings:get("mcl_lun_mobs_firefly_local_cap"), 1, 200) or 48
	local attempts_per_player = clamp_int(core.settings:get("mcl_lun_mobs_firefly_attempts_per_player"), 1, 200) or 6
	local spawns_per_player = clamp_int(core.settings:get("mcl_lun_mobs_firefly_spawns_per_player"), 1, 50) or 1
	local spawn_radius = clamp_int(core.settings:get("mcl_lun_mobs_firefly_spawn_radius"), 8, 256) or 80
	local spawn_player_radius = clamp_int(core.settings:get("mcl_lun_mobs_firefly_spawn_player_radius"), 8, 256) or 80
	local spawn_player_radius2 = spawn_player_radius * spawn_player_radius
	local sample_drop = clamp_int(core.settings:get("mcl_lun_mobs_firefly_sample_drop"), 0, 256) or 80
	local despawn_radius = clamp_int(core.settings:get("mcl_lun_mobs_firefly_despawn_radius"), 16, 256) or 80
	local despawn_radius2 = despawn_radius * despawn_radius
	-- Natural spawns fade quickly during day (configurable).
	local day_despawn_delay = tonumber(core.settings:get("mcl_lun_mobs_firefly_day_despawn_delay")) or 4
	local nightbug_follow_radius = clamp_int(core.settings:get("mcl_lun_mobs_firefly_nightbug_follow_radius"), 4, 64) or 16
	local nightbug_follow_radius2 = nightbug_follow_radius * nightbug_follow_radius
	local NIGHTBUG_ITEM = "mcl_lun_items:nightbug"

		local DEBUG = core.settings:get_bool("mcl_lun_mobs_firefly_debug", false)
		local DEBUG_SAMPLE = tonumber(core.settings:get("mcl_lun_mobs_firefly_debug_sample")) or 0.05
		local DEBUG_STATS_INTERVAL = tonumber(core.settings:get("mcl_lun_mobs_firefly_debug_stats_interval")) or 10
		COLLECT_STATS = DEBUG and DEBUG_STATS_INTERVAL > 0

	local tod_cache_t = -1
	local tod_cache = 0
	local night_cache = false

	local function update_tod_cache()
		local now = get_gametime()
		if tod_cache_t == now then
			return
		end
		tod_cache_t = now
		tod_cache = get_timeofday()
		night_cache = tod_cache < 0.2 or tod_cache > 0.8
	end

	local function is_night()
		update_tod_cache()
		return night_cache
	end

	local function get_tod_cached()
		update_tod_cache()
		return tod_cache
	end

	local FOREST_CACHE_TTL = 15
	local forest_cache = {}

local function in_lun_forest(pos)
	local bx = floor(pos.x / 16)
	local bz = floor(pos.z / 16)
	local key = bx .. "," .. bz
	local now = get_gametime()
	local cached = forest_cache[key]
	if cached and (now - cached.t) < FOREST_CACHE_TTL then
		return cached.v
	end

	local result = false

	-- First: our custom tag layer (fast).
	if mcl_lun_biomes and mcl_lun_biomes.get_name then
		local tag = mcl_lun_biomes.get_name(pos)
		if tag == "forest" or tag == "darkforest" then
			result = true
			forest_cache[key] = {t = now, v = result}
			return result
		end
		if tag ~= nil then
			result = false
			forest_cache[key] = {t = now, v = result}
			return result
		end
	end

	-- If our tag layer hasn't been calculated here yet, fall back to engine biome.
	if get_biome_data and get_biome_name then
		local bd = get_biome_data(pos)
		local id = bd and bd.biome or nil
		if id then
			local bname = get_biome_name(id)
			result = (bname == "Forest" or bname == "DarkForest")
			forest_cache[key] = {t = now, v = result}
			return result
		end
	end

	-- Last resort for imported/custom worlds: leaf canopy nearby.
	result = (find_node_near(pos, 8, {"group:leaves"}) ~= nil)
	forest_cache[key] = {t = now, v = result}
	return result
end

local function is_mcl_flowers_node_name(name)
	local prefix = "mcl_flowers:"
	return type(name) == "string" and name:sub(1, #prefix) == prefix
end

local flower_nodenames = {}
local function rebuild_flower_nodenames()
	flower_nodenames = {}
	for name, _def in pairs(registered_nodes) do
		if is_mcl_flowers_node_name(name) then
			flower_nodenames[#flower_nodenames + 1] = name
		end
	end
	table.sort(flower_nodenames)
end

-- Build once at load, but also rebuild after all mods are loaded because Mineclonia
-- (and some modpacks) may register nodes late.
rebuild_flower_nodenames()
	core.register_on_mods_loaded(function()
		mcl_lun_biomes = rawget(_G, "mcl_lun_biomes")
		mcl_lun_sounds = rawget(_G, "mcl_lun_sounds")
		rebuild_flower_nodenames()
		log("action", ("[%s] firefly spawn ready: flower_nodes=%d tag_api=%s"):format(
			MODNAME,
			#flower_nodenames,
		tostring(mcl_lun_biomes and mcl_lun_biomes.get_name ~= nil)
	))
end)

local FLOWER_GROUP_QUERY = {"group:place_flowerlike", "group:plant"}
local function find_spawn_flower(sample)
	if #flower_nodenames > 0 then
		return find_node_near(sample, 12, flower_nodenames)
	end
	local fpos = find_node_near(sample, 12, FLOWER_GROUP_QUERY)
	if not fpos then
		return nil
	end
	local node = get_node_or_nil(fpos)
	return (node and is_mcl_flowers_node_name(node.name)) and fpos or nil
end

	if wielded_light and wielded_light.register_item_light then
		wielded_light.register_item_light(LIGHT_ITEM, 9, false)
		wielded_light.register_item_light(BLUE_LIGHT_ITEM, 8, false)
	end

local function count_fireflies(pos, radius, limit)
	local objects = get_objects_inside_radius(pos, radius)
	local n = 0
	for i = 1, #objects do
		local ent = objects[i]:get_luaentity()
		if ent and ent.name == ENTITY_FIREFLY then
			n = n + 1
			if limit and n >= limit then
				return n
			end
		end
	end
	return n
end

local function randf(a, b)
	return a + random() * (b - a)
end

local function rand_unit3()
	local z = randf(-1, 1)
	local t = randf(0, pi * 2)
	local r = sqrt(max(0, 1 - z * z))
	return r * cos(t), z, r * sin(t)
end

local function norm3(x, y, z)
	local l = sqrt(x * x + y * y + z * z)
	if l < 1e-9 then
		return 0, 0, 0
	end
	local inv = 1 / l
	return x * inv, y * inv, z * inv
end

local function cross3(ax, ay, az, bx, by, bz)
	return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function make_basis(ax, ay, az)
	ax, ay, az = norm3(ax, ay, az)

	local tx, ty, tz
	if abs(ay) < 0.9 then
		tx, ty, tz = 0, 1, 0
	else
		tx, ty, tz = 1, 0, 0
	end

	local ux, uy, uz = cross3(ax, ay, az, tx, ty, tz)
	ux, uy, uz = norm3(ux, uy, uz)
	local vx, vy, vz = cross3(ax, ay, az, ux, uy, uz)
	vx, vy, vz = norm3(vx, vy, vz)
	return ux, uy, uz, vx, vy, vz
end

local function reset_orbit_xyz(self, x, y, z)
	local nx = roundi(x)
	local ny = roundi(y)
	local nz = roundi(z)

	local cx = nx + 0.5
	local cy = ny + 0.5
	local cz = nz + 0.5

	local ax, ay, az = rand_unit3()
	local ux, uy, uz, vx, vy, vz = make_basis(ax, ay, az)

	local orbit = self._orbit or {}
	orbit.nx, orbit.ny, orbit.nz = nx, ny, nz
	orbit.cx, orbit.cy, orbit.cz = cx, cy, cz
	orbit.ux, orbit.uy, orbit.uz = ux, uy, uz
	orbit.vx, orbit.vy, orbit.vz = vx, vy, vz
	orbit.theta = randf(0, pi * 2)
	orbit.omega = randf(0.8, 1.9) -- rad/s
	orbit.radius = randf(0.18, 0.44)
	orbit.gain = randf(3.0, 4.5)
	orbit.noise_amp = randf(0.02, 0.08)
	self._orbit = orbit
end

local function reset_orbit(self, pos)
	return reset_orbit_xyz(self, pos.x, pos.y, pos.z)
end

	local function update_noise(self, dtime)
		self._noise_t = (self._noise_t or 0) - dtime
		if self._noise_t <= 0 then
			self._noise_t = randf(0.12, 0.30)
		local nx, ny, nz = rand_unit3()
		self._noise.x = nx
		self._noise.y = ny * 0.7
		self._noise.z = nz
	end
end

	local player_pos_cache_t = -1
	local player_pos_cache = {}
	local function get_player_positions_cached()
		local now = get_gametime()
	if player_pos_cache_t == now then
		return player_pos_cache
	end
	player_pos_cache_t = now

	local players = get_connected_players()
	local list = {}
	for i = 1, #players do
		local ppos = players[i]:get_pos()
		if ppos then
			list[#list + 1] = {player = players[i], x = ppos.x, y = ppos.y, z = ppos.z}
		end
	end
		player_pos_cache = list
			return player_pos_cache
		end

	local nightbug_player_cache = {t = -1000, list = {}}
	local NIGHTBUG_PLAYER_CACHE_TTL = 0.25

	local function get_nightbug_players_cached()
		local now = get_gametime()
		if (now - nightbug_player_cache.t) <= NIGHTBUG_PLAYER_CACHE_TTL then
			return nightbug_player_cache.list
		end
		nightbug_player_cache.t = now

		local players = get_connected_players()
		local list = {}
		for i = 1, #players do
			local player = players[i]
			local wield = player:get_wielded_item()
			if wield and wield:get_name() == NIGHTBUG_ITEM then
				local ppos = player:get_pos()
				if ppos then
					list[#list + 1] = {player = player, x = ppos.x, y = ppos.y, z = ppos.z}
				end
			end
		end
		nightbug_player_cache.list = list
		return list
	end

	local function find_near_nightbug_player(pos, radius)
		local players = get_nightbug_players_cached()
		local r2 = radius * radius
		local best
		local best_d2
		for i = 1, #players do
			local p = players[i]
			local dx = p.x - pos.x
			local dy = p.y - pos.y
			local dz = p.z - pos.z
			local d2 = dx * dx + dy * dy + dz * dz
			if d2 <= r2 and (not best_d2 or d2 < best_d2) then
				best = p.player
				best_d2 = d2
			end
		end
		return best
	end

		local flower_pos_cache = {}
		local FLOWER_POS_CACHE_TTL = 2
		local TMP_SEARCH_POS = {x = 0, y = 0, z = 0}

local function find_near_flower(pos, radius)
	local bx = floor(pos.x / 16)
	local bz = floor(pos.z / 16)
	local key = bx .. "," .. bz
	local now = get_gametime()
	local cached = flower_pos_cache[key]
	if cached and (now - cached.t) <= FLOWER_POS_CACHE_TTL then
		local p = cached.pos
		if p then
			local node = get_node_or_nil(p)
			if node and is_mcl_flowers_node_name(node.name) then
				return p
			end
		end
	end

	TMP_SEARCH_POS.x = roundi(pos.x)
	TMP_SEARCH_POS.y = roundi(pos.y)
	TMP_SEARCH_POS.z = roundi(pos.z)

	local fpos
	if #flower_nodenames > 0 then
		fpos = find_node_near(TMP_SEARCH_POS, radius, flower_nodenames)
	else
		fpos = find_node_near(TMP_SEARCH_POS, radius, FLOWER_GROUP_QUERY)
		if fpos then
			local node = get_node_or_nil(fpos)
			if not (node and is_mcl_flowers_node_name(node.name)) then
				fpos = nil
			end
		end
	end

	flower_pos_cache[key] = {t = now, pos = fpos}
	return fpos
end

local function begin_nightbug_follow(self, player)
	local f = self._follow or {}
	f.player = player
	f.theta = (f.theta ~= nil) and f.theta or randf(0, pi * 2)
	f.omega = (f.omega ~= nil) and f.omega or randf(2.3, 3.2)
	f.radius = (f.radius ~= nil) and f.radius or randf(0.8, 1.4)
	f.yphase = (f.yphase ~= nil) and f.yphase or randf(0, pi * 2)
	f.yomega = (f.yomega ~= nil) and f.yomega or randf(1.2, 1.9)
	f.recheck_t = 0
	self._follow = f
end

local function step_nightbug_follow(self, pos, night, dtime)
	if not night then
		self._follow = nil
		return false
	end

	local f = self._follow
	if not f then
		local player = find_near_nightbug_player(pos, nightbug_follow_radius)
		if not player then
			return false
		end
		begin_nightbug_follow(self, player)
		f = self._follow
	end

	f.recheck_t = (f.recheck_t or 0) - dtime
	if f.recheck_t <= 0 then
		f.recheck_t = 0.25
		local player = find_near_nightbug_player(pos, nightbug_follow_radius)
		if not player then
			self._follow = nil
			return false
		end
		f.player = player
	end

	local player = f.player
	if not (player and player:is_player()) then
		self._follow = nil
		return false
	end

	local ppos = player:get_pos()
	if not ppos then
		self._follow = nil
		return false
	end

	local dxp = ppos.x - pos.x
	local dyp = ppos.y - pos.y
	local dzp = ppos.z - pos.z
	local d2p = dxp * dxp + dyp * dyp + dzp * dzp
	if d2p > nightbug_follow_radius2 * 2.25 then
		self._follow = nil
		return false
	end

	f.theta = f.theta + f.omega * dtime
	if f.theta > (pi * 2) then
		f.theta = f.theta - (pi * 2)
	end
	f.yphase = f.yphase + f.yomega * dtime
	if f.yphase > (pi * 2) then
		f.yphase = f.yphase - (pi * 2)
	end

	local ct = cos(f.theta)
	local st = sin(f.theta)

	local desired_x = ppos.x + (ct * f.radius) + (self._noise.x * 0.06)
	local desired_z = ppos.z + (st * f.radius) + (self._noise.z * 0.06)
	local desired_y = (ppos.y + 0.2) + (sin(f.yphase) * 0.32) + (self._noise.y * 0.05)

	-- Keep following close to the ground surface too.
	local ground_y = ground_surface_y_cached(desired_x, desired_y, desired_z, 24)
	if ground_y then
		local min_y = ground_y + 0.2
		local max_y = ground_y + 2.4
		if desired_y < min_y then
			desired_y = min_y
		elseif desired_y > max_y then
			desired_y = max_y
		end
	end

	if not point_is_free_xyz(desired_x, desired_y, desired_z) then
		f.theta = f.theta + pi
		f.radius = max(0.5, f.radius * 0.9)
		ct = cos(f.theta)
		st = sin(f.theta)
		desired_x = ppos.x + (ct * f.radius)
		desired_z = ppos.z + (st * f.radius)
		if not point_is_free_xyz(desired_x, desired_y, desired_z) then
			self.object:set_velocity({x = 0, y = 0, z = 0})
			return true
		end
	end

	local gain = 4.0
	local vx = (desired_x - pos.x) * gain
	local vy = (desired_y - pos.y) * gain
	local vz = (desired_z - pos.z) * gain

	local vmax = 2.6
	local vlen = sqrt(vx * vx + vy * vy + vz * vz)
	if vlen > vmax and vlen > 1e-9 then
		local inv = vmax / vlen
		vx, vy, vz = vx * inv, vy * inv, vz * inv
	end

	self._approach = nil
	self.object:set_velocity({x = vx, y = vy, z = vz})
	return true
end

local function find_near_player(pos, radius)
	local players = get_player_positions_cached()
	local r2 = radius * radius
	local best
	local best_d2
	for i = 1, #players do
		local p = players[i]
		local dx = p.x - pos.x
		local dy = p.y - pos.y
		local dz = p.z - pos.z
		local d2 = dx * dx + dy * dy + dz * dz
		if d2 <= r2 and (not best_d2 or d2 < best_d2) then
			best = p.player
			best_d2 = d2
		end
	end
	return best
end

local function is_mob_entity(ent)
	return ent and ent._cmi_is_mob == true
end

local mob_pos_cache = {}
local MOB_POS_CACHE_TTL = 1

	local function find_near_mob_object(self, pos, radius)
		local bx = floor(pos.x / 16)
		local bz = floor(pos.z / 16)
		local key = bx .. "," .. bz
	local now = get_gametime()
		local cached = mob_pos_cache[key]
		if cached and (now - cached.t) <= MOB_POS_CACHE_TTL then
			local obj = cached.obj
			if obj == false then
				return nil
			end
			if obj and obj ~= self.object and not obj:is_player() then
				local epos = obj:get_pos()
				if epos then
				local dx = epos.x - pos.x
				local dy = epos.y - pos.y
				local dz = epos.z - pos.z
				if (dx * dx + dy * dy + dz * dz) <= radius * radius then
					local ent = obj:get_luaentity()
					if is_mob_entity(ent) then
						return obj
					end
				end
			end
		end
	end

	local objects = get_objects_inside_radius(pos, radius)
	local best
	local best_d2
	for i = 1, #objects do
		local obj = objects[i]
		if obj ~= self.object and not obj:is_player() then
			local ent = obj:get_luaentity()
			if is_mob_entity(ent) then
				local epos = obj:get_pos()
				if epos then
					local dx = epos.x - pos.x
					local dy = epos.y - pos.y
					local dz = epos.z - pos.z
					local d2 = dx * dx + dy * dy + dz * dz
					if (not best_d2 or d2 < best_d2) then
						best = obj
						best_d2 = d2
					end
				end
				end
			end
		end

		mob_pos_cache[key] = {t = now, obj = best or false}
		return best
	end

	local function start_approach(self, kind, tx, ty, tz)
		local pos = self.object:get_pos()
		if not pos then
			return false
		end
		local px, py, pz = pos.x, pos.y, pos.z
		local dx = tx - px
		local dy = ty - py
		local dz = tz - pz
		local dist = sqrt(dx * dx + dy * dy + dz * dz)
		if dist < 0.25 then
			return false
		end

			local dur = max(0.6, min(3.8, dist / randf(2.8, 4.2)))
			-- Keep arcs low; too-tall arcs look like "sky" fireflies.
			local arc_h = min(2.0, (0.20 + dist * 0.06) * randf(0.7, 1.1))
			local noise_amp = randf(0.03, 0.12)

			self._approach = {
				kind = kind,
				sx = px,
			sy = py,
			sz = pz,
			tx = tx,
			ty = ty,
			tz = tz,
				t = 0,
				dur = dur,
				arc_h = arc_h,
				gain = randf(2.0, 3.4),
				noise_amp = noise_amp,
			}
		debug_log(self, ("firefly approach start kind=%s dist=%.2f dur=%.2f target=(%.2f,%.2f,%.2f)"):format(
			kind, dist, dur, tx, ty, tz
		))
		return true
	end

		local function step_approach(self, px, py, pz, dtime)
			local a = self._approach
			if not a then
				return false
			end

		local t = a.t + (dtime / a.dur)
		if t >= 1 then
			t = 1
		end
		a.t = t

		-- "Parabolic decay": ease-out in time + parabolic arc 4s(1-s)
		local s = 1 - (1 - t) * (1 - t)
		local arc = 4 * s * (1 - s) * a.arc_h

		local base_x = a.sx + (a.tx - a.sx) * s
		local base_y = a.sy + (a.ty - a.sy) * s + arc
		local base_z = a.sz + (a.tz - a.sz) * s

		-- Keep flight near the ground: never exceed 3 nodes above the local surface.
		local ground_y = ground_surface_y_cached(base_x, base_y, base_z, 24)
		if ground_y then
			local max_y = ground_y + 3
			if base_y > max_y then
				base_y = max_y
			end
		end

		if not point_is_free_xyz(base_x, base_y, base_z) then
			debug_log(self, ("firefly approach abort kind=%s blocked=(%.2f,%.2f,%.2f)"):format(a.kind, base_x, base_y, base_z))
			self._approach = nil
			reset_orbit_xyz(self, px, py, pz)
			return true
		end

		local vx = (base_x - px) * a.gain + (self._noise.x * a.noise_amp)
		local vy = (base_y - py) * a.gain + (self._noise.y * a.noise_amp)
		local vz = (base_z - pz) * a.gain + (self._noise.z * a.noise_amp)

		local vmax = 3.0
		local vlen = sqrt(vx * vx + vy * vy + vz * vz)
		if vlen > vmax and vlen > 1e-9 then
			local inv = vmax / vlen
			vx, vy, vz = vx * inv, vy * inv, vz * inv
		end
			self.object:set_velocity({x = vx, y = vy, z = vz})

			if t >= 1 then
				self._approach = nil
				reset_orbit_xyz(self, a.tx, a.ty, a.tz)
				return true
			end
	
				return true
			end

			----------------------------------------------------------------------
			-- Firefly "swarm" behavior around blue fireflies
			----------------------------------------------------------------------
			local SWARM_TRIGGER_RADIUS = 5
			local SWARM_JOIN_RADIUS = 16
			local SWARM_GATHER_SECS = 8
			local SWARM_ATTACK_RADIUS = 16

			local SWARM_DEBUG = core.settings:get_bool("mcl_lun_mobs_firefly_swarm_debug", false)
			local active_swarms = {}

			local function swarm_log(msg)
				if SWARM_DEBUG then
					minetest.log("action", ("[%s][swarm] %s"):format(MODNAME, msg))
				end
			end

			local function obj_id(obj)
				if obj and obj.get_id then
					local id = obj:get_id()
					if id then
						return id
					end
				end
				return tostring(obj)
			end

			local function is_blue_firefly_obj(obj)
				if not obj then
					return false
				end
				local ent = obj:get_luaentity()
				return ent and ent.name == ENTITY_BLUE_FIREFLY
			end

			local function find_near_blue_firefly(pos, radius)
				local objs = get_objects_inside_radius(pos, radius)
				for i = 1, #objs do
					local obj = objs[i]
					if is_blue_firefly_obj(obj) then
						return obj
					end
				end
				return nil
			end

			local function swarm_center_from_node(node_pos)
				return {x = node_pos.x + 0.5, y = node_pos.y + 0.5, z = node_pos.z + 0.5}
			end

			local function ensure_swarm(blue_obj, rally_node, initiator_name)
				local id = obj_id(blue_obj)
				local s = active_swarms[id]
				if s then
					return s
				end
				local now = get_gametime()
				s = {
					id = id,
					blue = blue_obj,
					start_t = now,
					phase = "gather",
					rally_node = {x = rally_node.x, y = rally_node.y, z = rally_node.z},
					rally = swarm_center_from_node(rally_node),
				}
				active_swarms[id] = s
				swarm_log(("start blue=%s rally=%s initiator=%s"):format(
					tostring(id),
					minetest.pos_to_string(s.rally_node),
					tostring(initiator_name)
				))
				return s
			end

			local function clear_swarm_state(self, reason)
				if not self._swarm_id then
					return
				end
				if self._swarm_prev_physical ~= nil and self.object and self.object.set_properties then
					self.object:set_properties({physical = self._swarm_prev_physical})
				end
				self._swarm_id = nil
				self._swarm_prev_physical = nil
				self._swarm_attack_cd = nil
				self._interest_t = randf(0.5, 3.0)
				self._approach = nil
				if self.object and self.object.get_pos then
					local pos = self.object:get_pos()
					if pos then
						reset_orbit_xyz(self, pos.x, pos.y, pos.z)
					end
				end
				debug_log(self, ("swarm leave reason=%s"):format(tostring(reason)))
			end

			local function join_swarm(self, swarm, why)
				if not (self and self.object and swarm and swarm.id) then
					return false
				end
				if self._swarm_id == swarm.id then
					return true
				end

				-- Record and then ignore collision during swarm movement.
				if self._swarm_prev_physical == nil and self.object.get_properties then
					local props = self.object:get_properties()
					self._swarm_prev_physical = props and props.physical or true
				end
				if self.object.set_properties then
					self.object:set_properties({physical = false})
				end

				self._swarm_id = swarm.id
				self._interest_t = 9999
				self._approach = nil
				self._swarm_attack_cd = 0

				debug_log(self, ("swarm join blue=%s why=%s rally=%s"):format(
					tostring(swarm.id),
					tostring(why),
					minetest.pos_to_string(swarm.rally_node)
				))
				return true
			end

			local function step_swarm(self, pos, night, dtime)
				-- Stop swarm system during daytime (default dawn flee handles day behavior).
				if not night then
					if self._swarm_id then
						clear_swarm_state(self, "day")
					end
					return false
				end

				-- If already in a swarm, follow it.
				if self._swarm_id then
					local swarm = active_swarms[self._swarm_id]
					if not swarm then
						clear_swarm_state(self, "swarm_gone")
						return false
					end

					local blue = swarm.blue
					if not (blue and is_blue_firefly_obj(blue)) then
						clear_swarm_state(self, "blue_gone")
						return false
					end

					if swarm.phase == "gather" then
						-- Move to the rally node (once there, normal orbit keeps circling).
						local r = swarm.rally
						local dx = r.x - pos.x
						local dy = r.y - pos.y
						local dz = r.z - pos.z
						local d2 = dx * dx + dy * dy + dz * dz
						if d2 > (0.9 * 0.9) then
							if not self._approach then
								start_approach(self, "swarm_rally", r.x, r.y, r.z)
							end
						else
							-- Stick to circling this node and suppress other interests.
							self._interest_t = 9999
						end
						return false
					end

					if swarm.phase == "attack" then
						-- Fly to the blue firefly and try to damage it.
						local bpos = blue:get_pos()
						if not bpos then
							clear_swarm_state(self, "blue_no_pos")
							return false
						end

						self._interest_t = 9999
						self._approach = nil

						local tx, ty, tz = bpos.x, bpos.y, bpos.z
						local dx = tx - pos.x
						local dy = ty - pos.y
						local dz = tz - pos.z
						local dist2 = dx * dx + dy * dy + dz * dz

						local gain = 5.0
						local vx = dx * gain
						local vy = dy * gain
						local vz = dz * gain
						local vmax = 4.0
						local vlen = sqrt(vx * vx + vy * vy + vz * vz)
						if vlen > vmax and vlen > 1e-9 then
							local inv = vmax / vlen
							vx, vy, vz = vx * inv, vy * inv, vz * inv
						end
						self.object:set_velocity({x = vx, y = vy, z = vz})

						self._swarm_attack_cd = (self._swarm_attack_cd or 0) - dtime
							-- Require a closer approach before damage is applied.
							if dist2 <= (0.1) and self._swarm_attack_cd <= 0 then
							self._swarm_attack_cd = 0.6
							blue:punch(self.object, 1.0, {full_punch_interval = 0.6, damage_groups = {fleshy = 1}}, nil)
							debug_log(self, ("swarm attack punch blue=%s dist=%.2f"):format(tostring(swarm.id), sqrt(dist2)))
						end
						return true
					end

					-- Unknown phase: drop out.
					clear_swarm_state(self, "phase_" .. tostring(swarm.phase))
					return false
				end

				-- Not in a swarm: periodically check for triggers / joins.
				self._swarm_check_t = (self._swarm_check_t or 0) - dtime
				if self._swarm_check_t > 0 then
					return false
				end
				self._swarm_check_t = randf(0.35, 0.75)

				-- Trigger: if we get close to a blue firefly, we "panic-circle" our current node and start a rally.
				local blue = find_near_blue_firefly(pos, SWARM_TRIGGER_RADIUS)
				if blue then
					local rally_node = {x = roundi(pos.x), y = roundi(pos.y), z = roundi(pos.z)}
					local swarm = ensure_swarm(blue, rally_node, "trigger")
					join_swarm(self, swarm, "trigger")
					self._approach = nil
					reset_orbit_xyz(self, pos.x, pos.y, pos.z)
					self._interest_t = 9999
					return false
				end

				-- Join: if we're within 32 nodes of any active rally during gather, go join it.
				for _id, swarm in pairs(active_swarms) do
					if swarm.phase == "gather" then
						local r = swarm.rally
						local dx = r.x - pos.x
						local dy = r.y - pos.y
						local dz = r.z - pos.z
						local d2 = dx * dx + dy * dy + dz * dz
						if d2 <= (SWARM_JOIN_RADIUS * SWARM_JOIN_RADIUS) then
							join_swarm(self, swarm, "near_rally")
							break
						end
					end
				end

				return false
			end

			local function flower_origin_pos(fpos)
				return {x = fpos.x + 0.5, y = fpos.y + 0.1, z = fpos.z + 0.5}
			end

		local NEIGHBORS_6 = {
			{1, 0, 0},
			{-1, 0, 0},
			{0, 1, 0},
			{0, -1, 0},
			{0, 0, 1},
			{0, 0, -1},
		}

		local function node_name_at_int(x, y, z)
			TMP_POS.x = x
			TMP_POS.y = y
			TMP_POS.z = z
			local node = get_node_or_nil(TMP_POS)
			return node and node.name or nil
		end

			local function find_fly_path_to_flower(start_pos, radius, max_nodes)
				radius = radius or 16
				max_nodes = max_nodes or 20000

			local sx = roundi(start_pos.x)
			local sy = roundi(start_pos.y)
			local sz = roundi(start_pos.z)

				local r2 = radius * radius
				local span = radius * 2 + 1

			local function idx(dx, dy, dz)
				return (dx + radius) + span * ((dy + radius) + span * (dz + radius)) + 1
			end

			local qdx, qdy, qdz, parent = {}, {}, {}, {}
			local qh, qt = 1, 1
			qdx[1], qdy[1], qdz[1] = 0, 0, 0
			parent[1] = 0

			local visited = {}
			visited[idx(0, 0, 0)] = 1

				local start_name = node_name_at_int(sx, sy, sz)
				if not start_name then
					return nil
				end
				if is_mcl_flowers_node_name(start_name) then
					return {flower_origin_pos({x = sx, y = sy, z = sz})}
				end
				if not node_allows_player_pass_cached(start_name) and not is_mcl_flowers_node_name(start_name) then
					return nil
				end

			local goal_i
			local goal_pos

				while qh <= qt and qt < max_nodes do
					local cdx = qdx[qh]
					local cdy = qdy[qh]
					local cdz = qdz[qh]

					for i = 1, 6 do
						local ndx = cdx + NEIGHBORS_6[i][1]
						local ndy = cdy + NEIGHBORS_6[i][2]
						local ndz = cdz + NEIGHBORS_6[i][3]

					local d2 = ndx * ndx + ndy * ndy + ndz * ndz
					if d2 <= r2 then
						local key = idx(ndx, ndy, ndz)
							if not visited[key] then
								local nx = sx + ndx
								local ny = sy + ndy
								local nz = sz + ndz

								local nname = node_name_at_int(nx, ny, nz)
								if nname then
									local is_flower = is_mcl_flowers_node_name(nname)
									if node_allows_player_pass_cached(nname) or is_flower then
										qt = qt + 1
										qdx[qt], qdy[qt], qdz[qt] = ndx, ndy, ndz
										parent[qt] = qh
										visited[key] = qt
										if is_flower then
											goal_i = qt
											goal_pos = {x = nx, y = ny, z = nz}
											break
										end
									end
								end
							end
						end
					end
					if goal_i then
						break
					end

					qh = qh + 1
				end

			if not goal_i or not goal_pos then
				return nil
			end

			local rev = {}
			local cur = goal_i
			while cur and cur ~= 0 do
				rev[#rev + 1] = {dx = qdx[cur], dy = qdy[cur], dz = qdz[cur]}
				cur = parent[cur]
			end

			local path_grid = {}
			for i = #rev, 1, -1 do
				path_grid[#path_grid + 1] = rev[i]
			end

			if #path_grid >= 3 then
				local simplified = {path_grid[1]}
				local last = path_grid[1]
				local nextp = path_grid[2]
				local last_dx = nextp.dx - last.dx
				local last_dy = nextp.dy - last.dy
				local last_dz = nextp.dz - last.dz
				for i = 2, #path_grid - 1 do
					local a = path_grid[i]
					local b = path_grid[i + 1]
					local dx = b.dx - a.dx
					local dy = b.dy - a.dy
					local dz = b.dz - a.dz
					if dx ~= last_dx or dy ~= last_dy or dz ~= last_dz then
						simplified[#simplified + 1] = a
						last_dx, last_dy, last_dz = dx, dy, dz
					end
				end
				simplified[#simplified + 1] = path_grid[#path_grid]
				path_grid = simplified
			end

			local path = {}
			for i = 1, #path_grid do
				local p = path_grid[i]
				path[#path + 1] = {x = sx + p.dx + 0.5, y = sy + p.dy + 0.5, z = sz + p.dz + 0.5}
			end
			path[#path] = flower_origin_pos(goal_pos)

			return path
		end

		local function begin_dawn_flee(self, pos)
			if self._flee then
				return true
			end

			local path = find_fly_path_to_flower(pos, 16, 20000)
			if not path then
				debug_log(self, ("firefly dawn flee: no flower within 16 at %s"):format(pos_to_string(pos)))
				remove_self(self, "dawn_no_flower")
				return false
			end

			self._flee = {path = path, i = 1}
			self._approach = nil
			self._orbit = nil
			-- While fleeing at dawn, ignore collisions so we don't get stuck on tiny edge cases
			-- (path is still computed through passable nodes).
			if self.object and self.object.set_properties then
				self.object:set_properties({physical = false})
			end

			debug_log(self, ("firefly dawn flee start: path_len=%d from=%s to=%s"):format(
				#path,
				pos_to_string(pos),
				pos_to_string(path[#path])
			))
			return true
		end

		local function step_dawn_flee(self, pos, dtime)
			local f = self._flee
			local path = f and f.path or nil
			if not path then
				self._flee = nil
				return false
			end

			local i = f.i or 1
			if i > #path then
				remove_self(self, "dawn_flee_done")
				return true
			end

			local target = path[i]
			local px, py, pz = pos.x, pos.y, pos.z
			local dx = target.x - px
			local dy = target.y - py
			local dz = target.z - pz
			local dist = sqrt(dx * dx + dy * dy + dz * dz)

			while dist < 0.25 do
				i = i + 1
				if i > #path then
					remove_self(self, "dawn_flee_done")
					return true
				end
				target = path[i]
				f.i = i
				dx = target.x - px
				dy = target.y - py
				dz = target.z - pz
				dist = sqrt(dx * dx + dy * dy + dz * dz)
			end

			f.i = i

			local gain = 3.8
			local vx = dx * gain
			local vy = dy * gain
			local vz = dz * gain

			local vmax = 2.6
			local vlen = sqrt(vx * vx + vy * vy + vz * vz)
			if vlen > vmax and vlen > 1e-9 then
				local inv = vmax / vlen
				vx, vy, vz = vx * inv, vy * inv, vz * inv
			end

			local dt = min(dtime, 0.2)
			-- Intentionally skip collision checks while fleeing (physical=false).

			self.object:set_velocity({x = vx, y = vy, z = vz})
			return true
		end

				local function play_firefly_ambient(self)
					local sounds = mcl_lun_sounds and mcl_lun_sounds.sounds or nil
					local s1 = sounds and sounds.firefly_ambient_1 or "fireflies_1"
				local s2 = sounds and sounds.firefly_ambient_2 or "fireflies_2"
				local s = (random() < 0.5) and s1 or s2
				sound_play(s, {object = self.object, max_hear_distance = 6, gain = 0.05, pitch = randf(0.95, 1.15)}, true)
			end

		core.register_entity(ENTITY_FIREFLY, {
	initial_properties = {
		hp_max = 1,
		physical = true,
		collide_with_objects = false,
		pointable = true,
		static_save = false,
		visual = "sprite",
		textures = {"mcl_lun_mobs_firefly.png"},
		visual_size = {x = 0.22, y = 0.22},
		collisionbox = {-0.15, -0.15, -0.15, 0.15, 0.15, 0.15},
		glow = 14,
	},

	-- mcl_mobs.register_egg expects this (it sets nametags on spawned entities).
	set_nametag = function(self, name)
		if type(name) ~= "string" or name == "" then
			return false
		end
		self.nametag = name
		if self.object and self.object.set_nametag_attributes then
			self.object:set_nametag_attributes({text = name, color = {a = 255, r = 255, g = 255, b = 255}})
		end
		return true
	end,

		on_activate = function(self)
			self._orbit = nil
			self._approach = nil
			self._interest_t = randf(1, 10)
			self._noise = {x = 0, y = 0, z = 0}
			self._noise_t = 0
			self._anchor = self.object:get_pos()
			self.object:set_hp(1)
			self.object:set_acceleration({x = 0, y = 0, z = 0})
			self._debug = DEBUG and (random() < DEBUG_SAMPLE) or false
			self._spawn_type = self._spawn_type or "player"
			self._ambient_t = randf(0.2, 1.0)
			self._was_night = is_night()
			self._seen_night = self._was_night
			self._flee = nil

		debug_log(self, ("firefly activate spawn_type=%s pos=%s"):format(
			tostring(self._spawn_type),
			self._anchor and core.pos_to_string(self._anchor) or "<nil>"
		))

		if wielded_light and wielded_light.track_item_entity then
			wielded_light.track_item_entity(self.object, "firefly", LIGHT_ITEM)
		end
	end,

		on_punch = function(self)
			play_firefly_hurt(self)
			play_firefly_death_if_dead(self)
			remove_self(self, "punched")
		end,

			on_step = function(self, dtime)
				local pos = self.object:get_pos()
				if not pos then
					remove_self(self, "no_pos")
			return
		end

		if pos.y <= -20 then
			remove_self(self, "y<=-20")
			return
		end

			local night = is_night()
			local was_night = self._was_night
			if was_night == nil then
				was_night = night
			end
			self._was_night = night
			if night then
				self._seen_night = true
			end
	
			-- Dawn: once per night, pathfind a clear (flyable) route to a nearby flower and despawn.
			if was_night and not night then
				begin_dawn_flee(self, pos)
			end
	
			if self._flee then
				step_dawn_flee(self, pos, dtime)
				return
			end

			if night then
				self._ambient_t = (self._ambient_t or 0) - dtime
				if self._ambient_t <= 0 then
					self._ambient_t = randf(2.0, 6.0)
				if random() < 0.10 then
					play_firefly_ambient(self)
				end
			end
				end
	
				update_noise(self, dtime)

				-- Nightbug "temptation": follow players holding the Nightbug.
				if step_nightbug_follow(self, pos, night, dtime) then
					return
				end

				-- Swarm behavior around blue fireflies (runs only at night).
				if step_swarm(self, pos, night, dtime) then
					return
				end

			-- Default: smooth orbit within the current node (a "sphere circumference" loop),
			-- with occasional interest events (flower/player/mob) every 1..10 seconds.
			local orbit = self._orbit
		local px, py, pz = pos.x, pos.y, pos.z
		local nx = roundi(px)
		local ny = roundi(py)
		local nz = roundi(pz)
		if not orbit or orbit.nx ~= nx or orbit.ny ~= ny or orbit.nz ~= nz then
			reset_orbit_xyz(self, px, py, pz)
			orbit = self._orbit
		end

		if self._approach then
			step_approach(self, px, py, pz, dtime)
			return
		end

		self._interest_t = (self._interest_t or 0) - dtime
		if self._interest_t <= 0 then
			self._interest_t = randf(1, 10)
			local pick = random(1, 3)

			if pick == 1 then
				local fpos = find_near_flower(pos, 10)
				if fpos then
					local target = flower_origin_pos(fpos)
					start_approach(self, "flower", target.x, target.y, target.z)
					return
				end
			elseif pick == 2 then
				local player = find_near_player(pos, 32)
				if player then
					local ppos = player:get_pos()
					if ppos then
						start_approach(self, "player", ppos.x, ppos.y + 0.3, ppos.z)
						return
					end
				end
			else
				local mob = find_near_mob_object(self, pos, 32)
				if mob then
					local mpos = mob:get_pos()
					if mpos then
						start_approach(self, "mob", mpos.x, mpos.y + 0.2, mpos.z)
						return
					end
				end
			end
		end

		orbit.theta = orbit.theta + orbit.omega * dtime
		local theta = orbit.theta
		if theta > (pi * 2) then
			theta = theta - (pi * 2)
			orbit.theta = theta
		end

		local ct = cos(theta)
		local st = sin(theta)
		local rct = orbit.radius * ct
		local rst = orbit.radius * st

		local desired_x = orbit.cx + (orbit.ux * rct) + (orbit.vx * rst) + (self._noise.x * orbit.noise_amp)
		local desired_y = orbit.cy + (orbit.uy * rct) + (orbit.vy * rst) + (self._noise.y * orbit.noise_amp)
		local desired_z = orbit.cz + (orbit.uz * rct) + (orbit.vz * rst) + (self._noise.z * orbit.noise_amp)

		-- Keep orbit close to the ground surface at this X/Z column.
		local ground_y = ground_surface_y_cached(desired_x, desired_y, desired_z, 24)
		if ground_y then
			local min_y = ground_y + 0.2
			local max_y = ground_y + 2.2
			if desired_y < min_y then
				desired_y = min_y
			elseif desired_y > max_y then
				desired_y = max_y
			end
		end

		if not point_is_free_xyz(desired_x, desired_y, desired_z) then
			orbit.theta = orbit.theta + pi
			orbit.radius = max(0.12, orbit.radius * 0.85)
			theta = orbit.theta
			ct = cos(theta)
			st = sin(theta)
			rct = orbit.radius * ct
			rst = orbit.radius * st
			desired_x = orbit.cx + (orbit.ux * rct) + (orbit.vx * rst)
			desired_y = orbit.cy + (orbit.uy * rct) + (orbit.vy * rst)
			desired_z = orbit.cz + (orbit.uz * rct) + (orbit.vz * rst)

			ground_y = ground_surface_y_cached(desired_x, desired_y, desired_z, 24)
			if ground_y then
				local min_y = ground_y + 0.2
				local max_y = ground_y + 2.2
				if desired_y < min_y then
					desired_y = min_y
				elseif desired_y > max_y then
					desired_y = max_y
				end
			end
			if not point_is_free_xyz(desired_x, desired_y, desired_z) then
				self.object:set_velocity({x = 0, y = 0, z = 0})
				return
			end
		end

		local vx = (desired_x - px) * orbit.gain
		local vy = (desired_y - py) * orbit.gain
		local vz = (desired_z - pz) * orbit.gain

		local vmax = 1.9
			local vlen = sqrt(vx * vx + vy * vy + vz * vz)
			if vlen > vmax and vlen > 1e-9 then
				local inv = vmax / vlen
				vx, vy, vz = vx * inv, vy * inv, vz * inv
			end
			self.object:set_velocity({x = vx, y = vy, z = vz})
		end,
	})

	-- Minimal "blue firefly" that spawns on waterlilies at night and orbits its spawn node.
		core.register_entity(ENTITY_BLUE_FIREFLY, {
			initial_properties = {
				hp_max = 1,
				-- Decorative: disable collision to avoid getting stuck in edge cases.
				physical = false,
				collide_with_objects = false,
				pointable = true,
				static_save = false,
				visual = "sprite",
			-- Reuse the firefly sprite but tint it blue.
			textures = {"mcl_lun_mobs_firefly.png^[colorize:#2f76ff:200"},
			visual_size = {x = 0.22, y = 0.22},
			collisionbox = {-0.15, -0.15, -0.15, 0.15, 0.15, 0.15},
			glow = 14,
		},

		-- mcl_mobs.register_egg expects this (it sets nametags on spawned entities).
		set_nametag = function(self, name)
			if type(name) ~= "string" or name == "" then
				return false
			end
			self.nametag = name
			if self.object and self.object.set_nametag_attributes then
				self.object:set_nametag_attributes({text = name, color = {a = 255, r = 255, g = 255, b = 255}})
			end
			return true
		end,

				on_activate = function(self, staticdata)
					local pos = self.object:get_pos()
					if not pos then
						self.object:remove()
					return
				end
				self.object:set_hp(1)
				self.object:set_acceleration({x = 0, y = 0, z = 0})
				if self.object and self.object.set_properties then
					self.object:set_properties({physical = false})
				end

			-- If spawned from a waterlily, staticdata carries its node pos.
			local home_lily
			if staticdata and staticdata ~= "" then
				local t = core.deserialize(staticdata)
				local p = t and t.home_lily or nil
				if p and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number" then
					home_lily = {x = p.x, y = p.y, z = p.z}
				end
			end
				self._home_lily = home_lily

						if home_lily then
							-- "Node origin" (center of the waterlily node).
							-- Waterlilies are flat; translate origin by -1 on Y.
							self._origin = {x = home_lily.x, y = home_lily.y - 0.5, z = home_lily.z}
						else
							self._origin = {x = roundi(pos.x), y = roundi(pos.y) + 0.5, z = roundi(pos.z)}
						end
				-- Start exactly at origin to eliminate initial drift.
				self.object:set_pos(self._origin)

				-- Spawn animation: rise ~1 node (±0.4) with an exponential decay, then ease into an XZ orbit.
					self._state = "rise"
					self._rise_t = 0
					self._rise_k = randf(7.0, 10.5)
					self._target_y = self._origin.y + 1 + randf(-0.4, 0.4)

					self._theta = random() * pi * 2
					self._omega = randf(0.45, 0.90)
					self._orbit_t = 0
					self._rmax = randf(0.18, 0.32)
				-- Randomized sinusoidal Y motion during orbit.
				self._y_amp1 = randf(0.02, 0.08)
				self._y_amp2 = randf(0.00, 0.05)
				self._y_mul1 = randf(0.6, 1.4)
				self._y_mul2 = randf(0.15, 0.65)
				self._y_phase1 = randf(0, pi * 2)
				self._y_phase2 = randf(0, pi * 2)
				self._sound_t = randf(0.4, 1.2)

			if wielded_light and wielded_light.track_item_entity then
				wielded_light.track_item_entity(self.object, "blue_firefly", BLUE_LIGHT_ITEM)
			end
		end,

			on_punch = function(self)
				play_firefly_hurt(self)
				play_firefly_death_if_dead(self)
				self.object:remove()
			end,

			on_step = function(self, dtime)
				local pos = self.object:get_pos()
				if not pos then
					return
				end

				local o = self._origin
				if not o then
					self.object:remove()
					return
				end

				local night = is_night()
				if not night then
					if self._home_lily then
						self._state = "return"
					else
						self.object:remove()
						return
					end
				end

				dtime = min(dtime, 0.2)

					local desired_x, desired_y, desired_z
					if self._state == "return" then
						local k = 18.0
						local a = 1.0 - math.exp(-k * dtime)
					desired_x = pos.x + (o.x - pos.x) * a
					desired_y = pos.y + (o.y - pos.y) * a
					desired_z = pos.z + (o.z - pos.z) * a
					local dx = o.x - desired_x
					local dy = o.y - desired_y
					local dz = o.z - desired_z
					if (dx * dx + dy * dy + dz * dz) <= (0.10 * 0.10) then
						self.object:remove()
						return
					end
				elseif self._state == "rise" then
					self._rise_t = (self._rise_t or 0) + dtime
					local k = self._rise_k or 4.4
					local ty = self._target_y or (o.y + 1)
					local e = math.exp(-k * self._rise_t)
					desired_x = o.x
					desired_z = o.z
					desired_y = ty - (ty - o.y) * e
					if abs(desired_y - ty) < 0.03 or self._rise_t > 3.0 then
						self._state = "orbit"
						self._orbit_t = 0
					end
				else
					self._orbit_t = (self._orbit_t or 0) + dtime
					local rmax = self._rmax or 0.25
					local r = rmax * (1 - math.exp(-2.2 * self._orbit_t))
					self._theta = (self._theta or 0) + (self._omega or 0.16) * dtime
					local theta = self._theta
					desired_x = o.x + cos(theta) * r
					desired_z = o.z + sin(theta) * r
					local base_y = (self._target_y or (o.y + 1))
					local wobble =
						sin(theta * (self._y_mul1 or 1.0) + (self._y_phase1 or 0)) * (self._y_amp1 or 0.04) +
						sin(theta * (self._y_mul2 or 0.35) + (self._y_phase2 or 0)) * (self._y_amp2 or 0.02)
					desired_y = base_y + wobble
				end

				-- Apply movement deterministically (avoids rare "stuck" cases from collision/rounding).
				self.object:set_velocity({x = 0, y = 0, z = 0})
				self.object:set_pos({x = desired_x, y = desired_y, z = desired_z})

				-- Soft pixie ambience (3-node radius).
				self._sound_t = (self._sound_t or 0) - dtime
				if self._sound_t <= 0 then
					self._sound_t = randf(2.4, 5.5)
					sound_play("pixie", {object = self.object, max_hear_distance = 3, gain = 0.08, pitch = randf(0.95, 1.05)}, true)
				end
			end,
		})

	-- Mineclonia spawn egg (in creative), using the same colors as the Blaze egg.
	if mcl_mobs and mcl_mobs.register_egg then
		mcl_mobs.register_egg(ENTITY_FIREFLY, S("Firefly"), "#f6b201", "#fff87e", 0)
		mcl_mobs.register_egg(ENTITY_BLUE_FIREFLY, S("Blue Firefly"), "#2f76ff", "#a8d4ff", 0)
	end

	local spawn_accum = 0
	local attempt_radius = min(spawn_radius, spawn_player_radius)
	local spawn_sample = {x = 0, y = 0, z = 0}

	core.register_globalstep(function(dtime)
		spawn_accum = spawn_accum + dtime
		if spawn_accum < spawn_interval then
			return
	end
	spawn_accum = spawn_accum - spawn_interval

	if not is_night() then
		return
	end

	local players = get_player_positions_cached()
	if #players == 0 then
		return
	end

	for i = 1, #players do
		local p = players[i]
		local player = p.player
		if player and p.y > -20 then
			-- Per-player cap (similar to how mob caps limit hostile spawns).
			local existing = count_fireflies(p, spawn_radius, player_cap)
			if existing < player_cap then
				local to_spawn = min(spawns_per_player, player_cap - existing)
				local base_x = roundi(p.x)
				local base_y = roundi(p.y)
				local base_z = roundi(p.z)

				local spawned = 0
				local tries = attempts_per_player * to_spawn
				for _ = 1, tries do
					if spawned >= to_spawn then
						break
					end

					spawn_sample.x = base_x + random(-attempt_radius, attempt_radius)
					-- Scan downwards so this still finds ground flowers if the player is flying.
					spawn_sample.y = base_y - random(0, sample_drop)
					spawn_sample.z = base_z + random(-attempt_radius, attempt_radius)

					local fpos = find_spawn_flower(spawn_sample)
					if fpos and fpos.y > -20 and in_lun_forest(fpos) then
						-- Spawn at the origin of the detected flower node.
						local spawn_pos = flower_origin_pos(fpos)
						if spawn_pos.y > -20 then
							-- Spawn condition: must be within 32 nodes of the player.
							local dxp = spawn_pos.x - p.x
							local dyp = spawn_pos.y - p.y
							local dzp = spawn_pos.z - p.z
							if (dxp * dxp + dyp * dyp + dzp * dzp) <= spawn_player_radius2 then
								local existing_local = count_fireflies(spawn_pos, 12, local_cap)
								local can = local_cap - existing_local
									if can > 0 then
										local burst = min(3, to_spawn - spawned, can)
										local sx, sy, sz = spawn_pos.x, spawn_pos.y, spawn_pos.z

										for _ = 1, burst do
											-- Spawn exactly at the flower origin.
											spawn_pos.x = sx
											spawn_pos.y = sy
											spawn_pos.z = sz

											local obj = add_entity(spawn_pos, ENTITY_FIREFLY)
											if obj then
												spawned = spawned + 1
											if COLLECT_STATS then
												STATS.spawned = STATS.spawned + 1
											end
											local ent = obj:get_luaentity()
											if ent then
												ent._spawn_type = "natural"
											end
										end
										if spawned >= to_spawn then
											break
										end
									end
								end
							end
						end
					end
				end
			end
		end
		end
	end)

	-- Minimal spawner for blue fireflies (waterlilies at night).
	local blue_spawn_accum = 0
	-- 80% less common: 5× slower spawner tick (2s -> 10s).
	local BLUE_SPAWN_INTERVAL = 15.0
	local BLUE_PLAYER_CAP = 12
	local BLUE_LOCAL_CAP = 4
	local BLUE_SEARCH_RADIUS = 32

		local function lily_has_blue_firefly(lily_pos)
			local home = {x = lily_pos.x, y = lily_pos.y - 0.5, z = lily_pos.z}
			local objs = get_objects_inside_radius(home, 1.6)
		for i = 1, #objs do
			local ent = objs[i]:get_luaentity()
			if ent and ent.name == ENTITY_BLUE_FIREFLY then
				local hl = ent._home_lily
				if hl and hl.x == lily_pos.x and hl.y == lily_pos.y and hl.z == lily_pos.z then
					return true
				end
				-- If the entity doesn't have a recorded home, treat it as occupying this lily anyway.
				return true
			end
		end
		return false
	end

		core.register_globalstep(function(dtime)
			blue_spawn_accum = blue_spawn_accum + dtime
			if blue_spawn_accum < BLUE_SPAWN_INTERVAL then
				return
		end
		blue_spawn_accum = blue_spawn_accum - BLUE_SPAWN_INTERVAL

		if not is_night() then
			return
		end

		local players = get_connected_players()
		for i = 1, #players do
			local player = players[i]
			local ppos = player and player:get_pos() or nil
			if ppos and ppos.y > -20 then
				local existing = 0
				local objs = get_objects_inside_radius(ppos, BLUE_SEARCH_RADIUS)
				for j = 1, #objs do
					local ent = objs[j]:get_luaentity()
					if ent and ent.name == ENTITY_BLUE_FIREFLY then
						existing = existing + 1
						if existing >= BLUE_PLAYER_CAP then
							break
						end
					end
				end
				if existing < BLUE_PLAYER_CAP then
					local minp = {
						x = roundi(ppos.x - BLUE_SEARCH_RADIUS),
						y = roundi(ppos.y - 16),
						z = roundi(ppos.z - BLUE_SEARCH_RADIUS),
					}
					local maxp = {
						x = roundi(ppos.x + BLUE_SEARCH_RADIUS),
						y = roundi(ppos.y + 16),
						z = roundi(ppos.z + BLUE_SEARCH_RADIUS),
					}

					local lilies = core.find_nodes_in_area(minp, maxp, {"mcl_flowers:waterlily"})
					if lilies and #lilies > 0 then
						local tries = min(10, #lilies)
					for _ = 1, tries do
								local lily = lilies[random(1, #lilies)]
									if lily and not lily_has_blue_firefly(lily) then
									local spawn_pos = {x = lily.x, y = lily.y - 0.5, z = lily.z}

							local nearby = 0
							local local_objs = get_objects_inside_radius(spawn_pos, 2.0)
							for j = 1, #local_objs do
									local ent = local_objs[j]:get_luaentity()
									if ent and ent.name == ENTITY_BLUE_FIREFLY then
										nearby = nearby + 1
										if nearby >= BLUE_LOCAL_CAP then
											break
										end
									end
								end

								if nearby < BLUE_LOCAL_CAP then
									add_entity(spawn_pos, ENTITY_BLUE_FIREFLY, core.serialize({home_lily = lily}))
								end
								break
							end
						end
					end
				end
				end
			end
		end)

		-- Swarm controller: transitions gather->attack and cleans up finished swarms.
		local swarm_accum = 0
		core.register_globalstep(function(dtime)
			swarm_accum = swarm_accum + dtime
			if swarm_accum < 0.5 then
				return
			end
			swarm_accum = swarm_accum - 0.5

			-- End all swarms at day; day behavior is handled elsewhere.
			if not is_night() then
				if next(active_swarms) ~= nil then
					swarm_log("daybreak: clearing swarms")
				end
				for id, _ in pairs(active_swarms) do
					active_swarms[id] = nil
				end
				return
			end

			local now = get_gametime()
			for id, swarm in pairs(active_swarms) do
				local blue = swarm.blue
				if not (blue and is_blue_firefly_obj(blue)) then
					swarm_log(("end blue=%s reason=blue_gone"):format(tostring(id)))
					active_swarms[id] = nil
				else
					if swarm.phase == "gather" and (now - swarm.start_t) >= SWARM_GATHER_SECS then
						swarm.phase = "attack"
						swarm_log(("phase blue=%s gather->attack"):format(tostring(id)))
					end

					local ent = blue:get_luaentity()
					if not ent then
						swarm_log(("end blue=%s reason=removed"):format(tostring(id)))
						active_swarms[id] = nil
					else
						local hp = blue:get_hp()
						if hp and hp <= 0 then
							swarm_log(("end blue=%s reason=dead"):format(tostring(id)))
							active_swarms[id] = nil
						end
					end
				end
			end
		end)

		if DEBUG and DEBUG_STATS_INTERVAL > 0 then
			local stats_t = 0
			core.register_globalstep(function(dtime)
		stats_t = stats_t + dtime
		if stats_t < DEBUG_STATS_INTERVAL then
			return
		end
		stats_t = stats_t - DEBUG_STATS_INTERVAL

		local removed_parts = {}
		for reason, count in pairs(STATS.removed) do
			removed_parts[#removed_parts + 1] = ("%s=%d"):format(reason, count)
		end
		table.sort(removed_parts)

		core.log("action", ("[%s] firefly stats dt=%.1fs spawned=%d removed={%s}"):format(
			MODNAME,
			DEBUG_STATS_INTERVAL,
			STATS.spawned,
			table.concat(removed_parts, ",")
		))

			STATS.spawned = 0
			STATS.removed = {}
		end)
	end

core.register_chatcommand("firefly_status", {
	params = "[rebuild]",
	description = "Show firefly spawning status (and optionally rebuild flower node list).",
	func = function(_name, param)
		param = (param or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if param == "rebuild" then
			rebuild_flower_nodenames()
			return true, ("rebuilt flower list: %d mcl_flowers nodes"):format(#flower_nodenames)
		end

		local tod = get_tod_cached()
		return true, ("night=%s tod=%.3f flower_nodes=%d tag_api=%s"):format(
			tostring(is_night()),
			tod,
			#flower_nodenames,
			tostring(mcl_lun_biomes and mcl_lun_biomes.get_name ~= nil)
		)
	end,
})
