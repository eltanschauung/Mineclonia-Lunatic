local MODNAME = minetest.get_current_modname()

local mcl_lun_sounds = rawget(_G, "mcl_lun_sounds")
local mcl_lun_biomes = rawget(_G, "mcl_lun_biomes")

local abs, floor, sqrt = math.abs, math.floor, math.sqrt
local min, max = math.min, math.max
local random = math.random

local sound_play = minetest.sound_play
local sound_stop = minetest.sound_stop
local sound_fade = minetest.sound_fade
local get_connected_players = minetest.get_connected_players
local registered_nodes = minetest.registered_nodes
local get_node_or_nil = minetest.get_node_or_nil
local get_item_group = minetest.get_item_group

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function roundi(v)
	return floor(v + 0.5)
end

local function key3(x, y, z)
	return x .. "," .. y .. "," .. z
end

local function dist3(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	local dz = a.z - b.z
	return sqrt(dx * dx + dy * dy + dz * dz)
end

local function get_day_quarter()
	local tod = minetest.get_timeofday() or 0
	local t = floor(tod * 24000 + 0.5) % 24000
	if t >= 6000 and t <= 19000 then
		return 1
	end
	return 0
end

local cfg_scan_interval = tonumber(minetest.settings:get("mcl_lun_ambience_scan_interval")) or 3.0
local cfg_update_interval = tonumber(minetest.settings:get("mcl_lun_ambience_update_interval")) or 0.25
local cfg_audible_radius = tonumber(minetest.settings:get("mcl_lun_ambience_audible_radius")) or 24
local cfg_gain_distance = tonumber(minetest.settings:get("mcl_lun_ambience_gain_distance")) or 25
local cfg_min_cluster = tonumber(minetest.settings:get("mcl_lun_ambience_min_cluster")) or 17 -- “more than 16”
local cfg_exclusion_radius = tonumber(minetest.settings:get("mcl_lun_ambience_exclusion_radius")) or 8
local cfg_base_gain = tonumber(minetest.settings:get("mcl_lun_ambience_base_gain")) or 1.0
local cfg_tree_sources = tonumber(minetest.settings:get("mcl_lun_ambience_tree_sources")) or 4
local cfg_tree_leaf_param_samples = tonumber(minetest.settings:get("mcl_lun_ambience_tree_leaf_param_samples")) or 8
local cfg_debug = minetest.settings:get_bool("mcl_lun_ambience_debug", false)
local cfg_stream_refresh_interval = tonumber(minetest.settings:get("mcl_lun_ambience_stream_refresh_interval")) or 20
local cfg_ocean_connected_nodes = tonumber(minetest.settings:get("mcl_lun_ambience_ocean_connected_nodes")) or 33
local cfg_inside_axis_distance = tonumber(minetest.settings:get("mcl_lun_ambience_inside_axis_distance")) or 5
local INSIDE_GAIN_MULT = 0.25 -- reduce by 75% when "inside"

local SOUND_LEAVES = "light-wind"
local SOUND_LEAVES_MOUNTAIN = "leaves_rustling_wind_mountain"
local SOUND_LEAVES_JUNGLE = "ambience_tree_jungle"
local SOUND_LEAVES_JUNGLE_NIGHT = "ambience_tree_jungle_night"
local SOUND_CREEK = "ambience_creek"
local SOUND_OCEAN = "ambience_ocean"
local SOUND_MOUNTAIN = "ambience_mountain"
local SOUND_JUNGLE_BIOME_DAY = "ambience_biome_jungle_day"
local SOUND_JUNGLE_BIOME_NIGHT = "ambience_biome_jungle_night"
local WATERLILY_NODE = "mcl_flowers:waterlily"
local BIOME_MOUNTAIN = "mountain"
local BIOME_JUNGLE = "jungle"
local BIOME_BAMBOO = "bamboo"

local function randf(a, b)
	return a + random() * (b - a)
end

local SOUNDSCAPES = {
	tree = {gain = 0.2, delay = 0, variance = 0},
	tree_mountain = {gain = 0.2, delay = 10, variance = 4},
	tree_jungle = {gain = 0.2, delay = 0, variance = 0},
	tree_jungle_night = {gain = 0.2, delay = 0, variance = 0},
	creek = {gain = 1, delay = 0, variance = 0},
	ocean = {gain = 0.4, delay = 0, variance = 0},
	mountain = {gain = 0.05, delay = 0, variance = 0},
	jungle_biome = {gain = 0.1, delay = 0, variance = 0},
	jungle_biome_night = {gain = 0.2, delay = 0, variance = 0},
}

local function normalize_soundscape(def)
	if type(def) ~= "table" then
		return {gain = 1, delay = 0, variance = 0}
	end
	local gain = tonumber(def.gain) or 1
	local delay = tonumber(def.delay) or 0
	local variance = tonumber(def.variance) or 0
	if variance > delay then
		delay = 0
		variance = 0
	end
	def.gain = gain
	def.delay = delay
	def.variance = variance
	return def
end

for _, def in pairs(SOUNDSCAPES) do
	normalize_soundscape(def)
end

local sounds_modpath = minetest.get_modpath("mcl_lun_sounds")
local duration_cache = {}

local function u32le(s, i)
	local b1, b2, b3, b4 = s:byte(i, i + 3)
	if not (b1 and b2 and b3 and b4) then
		return nil
	end
	return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function u64le(s, i)
	local lo = u32le(s, i)
	local hi = u32le(s, i + 4)
	if not (lo and hi) then
		return nil
	end
	return lo + hi * 4294967296
end

local function ogg_duration_from_bytes(data)
	if type(data) ~= "string" then
		return nil
	end

	local sample_rate
	local opus = data:find("OpusHead", 1, true)
	if opus then
		sample_rate = 48000
	else
		local vorbis = data:find("\1vorbis", 1, true)
		if vorbis then
			sample_rate = u32le(data, vorbis + 12)
		end
	end

	if not sample_rate or sample_rate <= 0 then
		return nil
	end

	local last
	local at = 1
	while true do
		local idx = data:find("OggS", at, true)
		if not idx then
			break
		end
		last = idx
		at = idx + 1
	end

	if not last then
		return nil
	end

	local gp = u64le(data, last + 6)
	if not gp or gp <= 0 then
		return nil
	end

	return gp / sample_rate
end

local function get_sound_duration(soundname)
	if not soundname then
		return nil
	end
	local cached = duration_cache[soundname]
	if cached ~= nil then
		return cached or nil
	end
	if not sounds_modpath then
		duration_cache[soundname] = false
		return nil
	end
	local path = sounds_modpath .. "/sounds/" .. soundname .. ".ogg"
	local f = io.open(path, "rb")
	if not f then
		duration_cache[soundname] = false
		return nil
	end
	local data = f:read("*all")
	f:close()

	local dur = ogg_duration_from_bytes(data)
	if dur and dur > 0 then
		duration_cache[soundname] = dur
		return dur
	end

	duration_cache[soundname] = false
	return nil
end

minetest.log("action", ("[%s] init loaded"):format(MODNAME))

local leaf_names = {}
local function rebuild_leaf_names()
	leaf_names = {}
	local prefix = "mcl_trees:leaves"
	for name, _def in pairs(registered_nodes) do
		if type(name) == "string" and name:sub(1, #prefix) == prefix then
			leaf_names[#leaf_names + 1] = name
		end
	end
	table.sort(leaf_names)
end

rebuild_leaf_names()
minetest.register_on_mods_loaded(function()
	mcl_lun_sounds = rawget(_G, "mcl_lun_sounds")
	mcl_lun_biomes = rawget(_G, "mcl_lun_biomes")
	rebuild_leaf_names()
	minetest.log("action", ("[%s] loaded (leaf_nodes=%d, scan=%.2fs, radius=%d)"):format(
		MODNAME,
		#leaf_names,
		cfg_scan_interval,
		cfg_audible_radius
	))
end)

local function log_debug(msg)
	if cfg_debug then
		minetest.log("action", ("[%s] %s"):format(MODNAME, msg))
	end
end

local function compute_closest_tree_origin_near_player(ppos)
	if #leaf_names == 0 then
		return nil, 0, 0
	end

	local r = cfg_audible_radius + 4
	local minp = {x = roundi(ppos.x - r), y = roundi(ppos.y - r), z = roundi(ppos.z - r)}
	local maxp = {x = roundi(ppos.x + r), y = roundi(ppos.y + r), z = roundi(ppos.z + r)}

	local leaves = minetest.find_nodes_in_area(minp, maxp, leaf_names)
	if not leaves or #leaves == 0 then
		return nil, 0, 0
	end

	local leaf_set = {}
	for i = 1, #leaves do
		local p = leaves[i]
		leaf_set[key3(p.x, p.y, p.z)] = true
	end

	local visited = {}
	local clusters = {}
	local leaf_param_sample_limit = max(1, floor(cfg_tree_leaf_param_samples))

	local qx, qy, qz = {}, {}, {}
	for i = 1, #leaves do
		local p = leaves[i]
		local k = key3(p.x, p.y, p.z)
		if not visited[k] then
			local head, tail = 1, 1
			qx[1], qy[1], qz[1] = p.x, p.y, p.z
			visited[k] = true

				local n = 0
				local sx, sy, sz = 0, 0, 0
				local samples = {}

				while head <= tail do
					local x = qx[head]
				local y = qy[head]
				local z = qz[head]
				head = head + 1

					n = n + 1
					sx = sx + x
					sy = sy + y
					sz = sz + z
					if #samples < leaf_param_sample_limit then
						samples[#samples + 1] = {x = x, y = y, z = z}
					end

					local function try(nx, ny, nz)
					local nk = key3(nx, ny, nz)
					if not visited[nk] and leaf_set[nk] then
						visited[nk] = true
						tail = tail + 1
						qx[tail], qy[tail], qz[tail] = nx, ny, nz
					end
				end

				try(x + 1, y, z)
				try(x - 1, y, z)
				try(x, y + 1, z)
				try(x, y - 1, z)
				try(x, y, z + 1)
				try(x, y, z - 1)
			end

				if n >= cfg_min_cluster then
					local ox = roundi(sx / n)
					local oy = roundi(sy / n)
					local oz = roundi(sz / n)
					clusters[#clusters + 1] = {
						n = n,
						origin = {x = ox + 0.5, y = oy + 0.5, z = oz + 0.5},
						samples = samples,
					}
				end
			end
		end

	if #clusters == 0 then
		return nil, #leaves, 0
	end

	table.sort(clusters, function(a, b)
		return a.n > b.n
	end)

	local selected = {}
	local ex2 = cfg_exclusion_radius * cfg_exclusion_radius
	for i = 1, #clusters do
		local c = clusters[i]
		local o = c.origin
		local ok = true
		for j = 1, #selected do
			local s = selected[j]
			local dx = o.x - s.origin.x
			local dz = o.z - s.origin.z
			if (dx * dx + dz * dz) <= ex2 then
				ok = false
				break
			end
		end
		if ok then
			selected[#selected + 1] = c
		end
	end

	if #selected == 0 then
		return nil, #leaves, #clusters
	end

	local function classify_tree_cluster(cluster)
		if not cluster then
			return "default"
		end
		local dominant_param2 = nil
		local param2_counts = {}
		local samples = cluster.samples or {}
		for i = 1, #samples do
			local node = get_node_or_nil(samples[i])
			if node then
				local p2 = tonumber(node.param2) or 0
				param2_counts[p2] = (param2_counts[p2] or 0) + 1
			end
		end
		local best_n = 0
		for p2, n in pairs(param2_counts) do
			if n > best_n then
				best_n = n
				dominant_param2 = p2
			end
		end

		local o = cluster.origin
		local cx = roundi(o.x - 0.5)
		local cy = roundi(o.y - 0.5)
		local cz = roundi(o.z - 0.5)
		local trunks = minetest.find_nodes_in_area(
			{x = cx - 4, y = cy - 14, z = cz - 4},
			{x = cx + 4, y = cy + 2, z = cz + 4},
			{"mcl_trees:tree_bamboo"}
		)
		local bamboo_trunks = trunks and #trunks or 0
		if dominant_param2 == 26 and bamboo_trunks > 0 then
			return "jungle"
		end
		return "default"
	end

	-- Sort by distance to player and keep a limited number of nearby tree sources.
	table.sort(selected, function(a, b)
		return dist3(ppos, a.origin) < dist3(ppos, b.origin)
	end)
	if cfg_tree_sources and cfg_tree_sources > 0 and #selected > cfg_tree_sources then
		for i = #selected, cfg_tree_sources + 1, -1 do
			selected[i] = nil
		end
	end

	for i = 1, #selected do
		local c = selected[i]
		selected[i] = {
			pos = c.origin,
			profile = classify_tree_cluster(c),
		}
	end

	return selected, #leaves, #clusters
end

local player_state = {}

local function stop_stream(stream)
	if not stream then
		return
	end
	if stream.handle then
		sound_stop(stream.handle)
	end
	stream.handle = nil
	stream.source_pos = nil
	stream.gain = 0
	stream._fadeout_t = nil
	stream._last_gain = nil
	stream.soundkey = nil
	stream.mode = nil
	stream.next_play_t = nil
	stream._play_t = nil
end

local function combined_tree_gain(ppos, sources)
	if not (sources and ppos) then
		return 0
	end
	local total = 0
	for i = 1, #sources do
		local s = sources[i]
		local p = s.pos or s
		local d = dist3(ppos, p)
		local g = 1.0 - (d / cfg_gain_distance)
		if g > 0 then
			total = total + g
			if total >= 1 then
				return 1
			end
		end
	end
	if total < 0 then
		return 0
	end
	if total > 1 then
		return 1
	end
	return total
end

local function combined_tree_gain_for_profile(ppos, sources, profile)
	if not (sources and ppos and profile) then
		return 0
	end
	local total = 0
	for i = 1, #sources do
		local s = sources[i]
		if s.profile == profile then
			local p = s.pos or s
			local d = dist3(ppos, p)
			local g = 1.0 - (d / cfg_gain_distance)
			if g > 0 then
				total = total + g
				if total >= 1 then
					return 1
				end
			end
		end
	end
	if total < 0 then
		return 0
	end
	if total > 1 then
		return 1
	end
	return total
end

local function ensure_stream(name, stream, soundkey, source_pos, gain, def, dtime)
	def = normalize_soundscape(def)

	local delay = def.delay
	local variance = def.variance
	local base_gain = cfg_base_gain * def.gain

	local mapped = mcl_lun_sounds and mcl_lun_sounds.sounds and mcl_lun_sounds.sounds[soundkey] or nil
	local soundname = mapped or soundkey
	local duration = nil
	if delay > 0 then
		duration = get_sound_duration(soundname)
		if not duration then
			delay = 0
			variance = 0
		end
	end

	local want_mode = (delay > 0) and "oneshot" or "loop"
	if stream.mode ~= want_mode then
		stop_stream(stream)
		stream.mode = want_mode
		stream.next_play_t = 0
	end

	local same_source = false
	-- If both are nil we treat it as an "attached" stream to the player and keep it stable.
	if (not stream.source_pos) and (not source_pos) then
		same_source = true
	elseif stream.source_pos and source_pos then
		local dx = stream.source_pos.x - source_pos.x
		local dy = stream.source_pos.y - source_pos.y
		local dz = stream.source_pos.z - source_pos.z
		same_source = (dx * dx + dy * dy + dz * dz) < 0.01
	end
	if stream.soundkey ~= soundkey then
		same_source = false
	end

	local target_gain = clamp(gain, 0, 1) * base_gain

	if want_mode == "oneshot" then
		if not same_source then
			stop_stream(stream)
			stream.mode = want_mode
			stream.next_play_t = 0
			stream.source_pos = source_pos
			stream.soundkey = soundkey
		end

		stream.source_pos = source_pos
		stream.soundkey = soundkey

		stream.next_play_t = (stream.next_play_t or 0) - (dtime or 0)
		if stream._play_t then
			stream._play_t = stream._play_t - (dtime or 0)
			if stream._play_t <= 0 then
				stream.handle = nil
				stream._play_t = nil
				stream._fadeout_t = nil
				stream._last_gain = nil
			end
		end

		if stream.next_play_t <= 0 then
			if stream.handle then
				sound_stop(stream.handle)
				stream.handle = nil
			end

			local start_gain = 0
			if not sound_fade then
				start_gain = target_gain
			end

			stream.gain = start_gain
			local spec = {
				to_player = name,
				gain = start_gain,
				loop = false,
			}
			if source_pos then
				spec.pos = source_pos
				spec.max_hear_distance = cfg_gain_distance
			end
			stream.handle = sound_play(soundname, spec, false)

			stream._play_t = duration or nil

			local delay_actual = delay
			if variance > 0 then
				delay_actual = delay + randf(-variance, variance)
			end
			if delay_actual < 0 then
				delay_actual = 0
			end

			stream.next_play_t = (duration or 0) + delay_actual
		end

		stream.gain = target_gain
		if sound_fade and stream.handle then
			sound_fade(stream.handle, cfg_update_interval, target_gain)
		end

		return
	end

	if not stream.handle or not same_source then
		if stream.handle then
			sound_stop(stream.handle)
		end
		stream.soundkey = soundkey
		stream.source_pos = source_pos
		stream._fadeout_t = nil

		local start_gain = 0
		if not sound_fade then
			start_gain = target_gain
		end

		stream.gain = start_gain
		local spec = {
			to_player = name,
			gain = start_gain,
			loop = true,
		}
		if source_pos then
			spec.pos = source_pos
			spec.max_hear_distance = cfg_gain_distance
		end
		stream.handle = sound_play(soundname, spec, false)
		stream._refresh_t = 0
	end

	-- Positional loops can occasionally go stale client-side after movement.
	-- Periodically refresh the handle to self-heal without changing behavior.
	if stream.handle and source_pos and target_gain > 0 and cfg_stream_refresh_interval > 0 then
		stream._refresh_t = (stream._refresh_t or 0) + (dtime or 0)
		if stream._refresh_t >= cfg_stream_refresh_interval then
			sound_stop(stream.handle)
			local spec = {
				to_player = name,
				gain = target_gain,
				loop = true,
			}
			spec.pos = source_pos
			spec.max_hear_distance = cfg_gain_distance
			stream.handle = sound_play(soundname, spec, false)
			stream._refresh_t = 0
		end
	end

	stream.gain = target_gain
	if sound_fade and stream.handle then
		sound_fade(stream.handle, cfg_update_interval, target_gain)
		else
			local last = stream._last_gain or target_gain
			if stream.handle and abs(target_gain - last) >= 0.15 then
				sound_stop(stream.handle)
				local spec = {
					to_player = name,
					gain = target_gain,
					loop = true,
				}
				if source_pos then
					spec.pos = source_pos
					spec.max_hear_distance = cfg_gain_distance
				end
				stream.handle = sound_play(soundname, spec, false)
			end
		end
		stream._last_gain = target_gain
	end

local function fadeout_or_stop_stream(stream, dtime)
	if not stream then
		return
	end
	-- Leaving range should reset scheduling so re-entering can start immediately.
	stream.next_play_t = 0
	stream._play_t = nil

	if not stream.handle then
		return
	end
	if sound_fade then
		if not stream._fadeout_t then
			stream._fadeout_t = cfg_update_interval
			sound_fade(stream.handle, cfg_update_interval, 0)
		end
		stream._fadeout_t = stream._fadeout_t - dtime
		if stream._fadeout_t <= 0 then
			stop_stream(stream)
		end
	else
		stop_stream(stream)
	end
end

local function get_stream_state(state, key)
	state.streams = state.streams or {}
	local s = state.streams[key]
	if not s then
		s = {}
		state.streams[key] = s
	end
	return s
end

local function stop_all_streams(state)
	if not state or not state.streams then
		return
	end
	for _k, stream in pairs(state.streams) do
		stop_stream(stream)
	end
	state.streams = {}
end

local function compute_closest_node_near_player(ppos, node_name)
	local r = cfg_audible_radius + 4
	local minp = {x = roundi(ppos.x - r), y = roundi(ppos.y - r), z = roundi(ppos.z - r)}
	local maxp = {x = roundi(ppos.x + r), y = roundi(ppos.y + r), z = roundi(ppos.z + r)}

	local nodes = minetest.find_nodes_in_area(minp, maxp, {node_name})
	if not nodes or #nodes == 0 then
		return nil, 0
	end

		-- Some decorative nodes (like lily pads) are effectively “flat”; their audible
		-- origin feels better when anchored lower than the geometric center.
		local y_off = 1.0
		if node_name == WATERLILY_NODE then
			-- Translate origin by -1 on Y (relative to center at +0.5).
			y_off = -0.5
		end

	local best
	local best_d2
	for i = 1, #nodes do
		local p = nodes[i]
		local dx = (p.x + 0.5) - ppos.x
		local dy = (p.y + y_off) - ppos.y
		local dz = (p.z + 0.5) - ppos.z
		local d2 = dx * dx + dy * dy + dz * dz
		if not best_d2 or d2 < best_d2 then
			best = {x = p.x + 0.5, y = p.y + y_off, z = p.z + 0.5}
			best_d2 = d2
		end
	end
	return best, #nodes
end

local function compute_closest_biome_near_player(ppos, biome_name, biome_name_alt)
	local get_name = mcl_lun_biomes and mcl_lun_biomes.get_name
	if type(get_name) ~= "function" then
		return nil, 0
	end

	local r = cfg_audible_radius + 4
	local minx = roundi(ppos.x - r)
	local maxx = roundi(ppos.x + r)
	local minz = roundi(ppos.z - r)
	local maxz = roundi(ppos.z + r)

	local probe = vector.round(ppos)
	local best
	local best_d2
	local matches = 0

	for z = minz, maxz do
		probe.z = z
		for x = minx, maxx do
			probe.x = x
			local tag = get_name(probe)
			if tag == biome_name or (biome_name_alt and tag == biome_name_alt) then
				matches = matches + 1
				local dx = (x + 0.5) - ppos.x
				local dz = (z + 0.5) - ppos.z
				local d2 = dx * dx + dz * dz
				if not best_d2 or d2 < best_d2 then
					best = {x = x + 0.5, y = ppos.y, z = z + 0.5}
					best_d2 = d2
				end
			end
		end
	end

	return best, matches
end

local function compute_ocean_source_from_water_near_player(ppos)
	local needed = max(1, floor(cfg_ocean_connected_nodes))
	local r = cfg_audible_radius + 4
	local minp = {x = roundi(ppos.x - r), y = roundi(ppos.y - r), z = roundi(ppos.z - r)}
	local maxp = {x = roundi(ppos.x + r), y = roundi(ppos.y + r), z = roundi(ppos.z + r)}

	local waters = minetest.find_nodes_in_area(minp, maxp, {"group:water"})
	if not waters or #waters == 0 then
		return nil, 0
	end

	local start
	local best_d2
	for i = 1, #waters do
		local p = waters[i]
		local dx = (p.x + 0.5) - ppos.x
		local dy = (p.y + 0.5) - ppos.y
		local dz = (p.z + 0.5) - ppos.z
		local d2 = dx * dx + dy * dy + dz * dz
		if not best_d2 or d2 < best_d2 then
			start = p
			best_d2 = d2
		end
	end
	if not start then
		return nil, 0
	end

	local function in_bounds(x, y, z)
		return x >= minp.x and x <= maxp.x and y >= minp.y and y <= maxp.y and z >= minp.z and z <= maxp.z
	end

	local function axis_count(dx, dy, dz)
		local total = 1 -- start node
		for dir = -1, 1, 2 do
			for step = 1, needed - 1 do
				local x = start.x + dx * step * dir
				local y = start.y + dy * step * dir
				local z = start.z + dz * step * dir
				if not in_bounds(x, y, z) then
					break
				end
				local node = get_node_or_nil({x = x, y = y, z = z})
				if not (node and get_item_group(node.name, "water") > 0) then
					break
				end
				total = total + 1
				if total >= needed then
					return total
				end
			end
		end
		return total
	end

	local x_count = axis_count(1, 0, 0)
	if x_count >= needed then
		return {x = start.x + 0.5, y = start.y + 0.5, z = start.z + 0.5}, x_count
	end

	local y_count = axis_count(0, 1, 0)
	if y_count >= needed then
		return {x = start.x + 0.5, y = start.y + 0.5, z = start.z + 0.5}, y_count
	end

	local z_count = axis_count(0, 0, 1)
	if z_count >= needed then
		return {x = start.x + 0.5, y = start.y + 0.5, z = start.z + 0.5}, z_count
	end

	return nil, max(x_count, y_count, z_count)
end

local function is_solid_for_inside_check(pos)
	local node = get_node_or_nil(pos)
	if not node then
		return false
	end
	local def = registered_nodes[node.name]
	return def and def.walkable == true
end

local function is_player_inside_axes(ppos, axis_dist)
	if not ppos then
		return false
	end
	local dist = max(1, floor(axis_dist or 5))
	local cx = roundi(ppos.x)
	local cy = roundi(ppos.y)
	local cz = roundi(ppos.z)
	local eye_y = cy + 2

	local function axis_has_solid(dx, dy, dz)
		for step = 1, dist do
			if is_solid_for_inside_check({x = cx + dx * step, y = cy + dy * step, z = cz + dz * step}) then
				return true
			end
			if is_solid_for_inside_check({x = cx - dx * step, y = cy - dy * step, z = cz - dz * step}) then
				return true
			end
		end
		return false
	end

	local has_x = axis_has_solid(1, 0, 0)
	local has_y = axis_has_solid(0, 1, 0)
	local has_z = false
	for step = 1, dist do
		if is_solid_for_inside_check({x = cx, y = eye_y, z = cz + step}) then
			has_z = true
			break
		end
		if is_solid_for_inside_check({x = cx, y = eye_y, z = cz - step}) then
			has_z = true
			break
		end
	end

	return has_x and has_y and has_z
end

minetest.register_on_leaveplayer(function(player)
	local name = player and player:get_player_name() or nil
	if name and player_state[name] then
		stop_all_streams(player_state[name])
		player_state[name] = nil
	end
end)

	minetest.register_chatcommand("ambience_status", {
		description = "Debug mcl_lun_ambience (server-side soundscape) status for your player.",
		func = function(name)
			local player = minetest.get_player_by_name(name)
		if not player then
			return false, "no player"
			end
			local state = player_state[name] or {}
			local ppos = player:get_pos()
			local tree_src = state.closest_tree
			local tree_sources = state.tree_sources
			local creek_src = state.closest_creek
			local ocean_src = state.closest_ocean
			local mountain_src = state.closest_mountain
			local jungle_src = state.closest_jungle
			local tree_dist = (ppos and tree_src) and dist3(ppos, tree_src.pos or tree_src) or nil
			local creek_dist = (ppos and creek_src) and dist3(ppos, creek_src) or nil
			local ocean_dist = (ppos and ocean_src) and dist3(ppos, ocean_src) or nil
			local mountain_dist = (ppos and mountain_src) and dist3(ppos, mountain_src) or nil
			local jungle_dist = (ppos and jungle_src) and dist3(ppos, jungle_src) or nil
			local tree_stream = state.streams and state.streams.tree or nil
			local creek_stream = state.streams and state.streams.creek or nil
			local ocean_stream = state.streams and state.streams.ocean or nil
			local mountain_stream = state.streams and state.streams.mountain or nil
			local jungle_stream = state.streams and state.streams.jungle_biome or nil
			return true, ("inside=%s leaf_nodes=%d tree_clusters=%d tree_sources=%d tree_dist=%s tree_gain=%s creek_lilies=%d creek_dist=%s creek_gain=%s ocean_cells=%d ocean_dist=%s ocean_gain=%s mountain_cells=%d mountain_dist=%s mountain_gain=%s jungle_cells=%d jungle_dist=%s jungle_gain=%s"):format(
				tostring(state._inside == true),
				#leaf_names,
				tonumber(state._clusters or 0) or 0,
				tree_sources and #tree_sources or 0,
				tree_dist and string.format("%.2f", tree_dist) or "nil",
				tree_stream and tree_stream.gain and string.format("%.3f", tree_stream.gain) or "nil",
				tonumber(state._creek_count or 0) or 0,
				creek_dist and string.format("%.2f", creek_dist) or "nil",
				creek_stream and creek_stream.gain and string.format("%.3f", creek_stream.gain) or "nil",
				tonumber(state._ocean_count or 0) or 0,
				ocean_dist and string.format("%.2f", ocean_dist) or "nil",
				ocean_stream and ocean_stream.gain and string.format("%.3f", ocean_stream.gain) or "nil",
				tonumber(state._mountain_count or 0) or 0,
				mountain_dist and string.format("%.2f", mountain_dist) or "nil",
				mountain_stream and mountain_stream.gain and string.format("%.3f", mountain_stream.gain) or "nil",
				tonumber(state._jungle_count or 0) or 0,
				jungle_dist and string.format("%.2f", jungle_dist) or "nil",
				jungle_stream and jungle_stream.gain and string.format("%.3f", jungle_stream.gain) or "nil"
			)
		end,
	})

local scan_accum = 0
local update_accum = 0

minetest.register_globalstep(function(dtime)
	scan_accum = scan_accum + dtime
	update_accum = update_accum + dtime

	local do_scan = scan_accum >= cfg_scan_interval
	local do_update = update_accum >= cfg_update_interval

	if not do_scan and not do_update then
		return
	end

	if do_scan then
		scan_accum = scan_accum - cfg_scan_interval
	end
	if do_update then
		update_accum = update_accum - cfg_update_interval
	end

	local players = get_connected_players()
	for i = 1, #players do
		local player = players[i]
		local name = player:get_player_name()
		local ppos = player:get_pos()
		if name and ppos then
			local state = player_state[name]
			if not state then
				state = {}
				player_state[name] = state
			end

					if do_scan then
						local tree_sources, leaf_count, clusters = compute_closest_tree_origin_near_player(ppos)
						state.tree_sources = tree_sources
						state.closest_tree = tree_sources and tree_sources[1] or nil
						state._leaf_count = leaf_count
						state._clusters = clusters
							local tag = (mcl_lun_biomes and mcl_lun_biomes.get_name) and mcl_lun_biomes.get_name(ppos) or nil
							state._tree_soundkey = (tag == "mountain") and SOUND_LEAVES_MOUNTAIN or SOUND_LEAVES
								state._tree_jungle_soundkey = (get_day_quarter() == 1) and SOUND_LEAVES_JUNGLE or SOUND_LEAVES_JUNGLE_NIGHT
							local creek_closest, creek_count = compute_closest_node_near_player(ppos, WATERLILY_NODE)
							local ocean_closest, ocean_count = compute_ocean_source_from_water_near_player(ppos)
							local mountain_closest, mountain_count = compute_closest_biome_near_player(ppos, BIOME_MOUNTAIN)
							local jungle_closest, jungle_count = compute_closest_biome_near_player(ppos, BIOME_JUNGLE, BIOME_BAMBOO)
							local is_inside = is_player_inside_axes(ppos, cfg_inside_axis_distance)
						state.closest_creek = creek_closest
						state._creek_count = creek_count
						state.closest_ocean = ocean_closest
						state._ocean_count = ocean_count
						state.closest_mountain = mountain_closest
						state._mountain_count = mountain_count
						state.closest_jungle = jungle_closest
						state._jungle_count = jungle_count
						state._inside = is_inside
						state._inside_gain_mul = is_inside and INSIDE_GAIN_MULT or 1
						if cfg_debug then
							local tree_jungle_sources = 0
							if tree_sources then
								for ti = 1, #tree_sources do
									if tree_sources[ti].profile == "jungle" then
										tree_jungle_sources = tree_jungle_sources + 1
									end
								end
							end
								log_debug(("scan player=%s inside=%s leaves=%d clusters=%d tree=%s jungle_sources=%d lilies=%d creek=%s ocean_cells=%d ocean=%s mountain_cells=%d mountain=%s jungle_cells=%d jungle=%s"):format(
									name,
									tostring(is_inside),
									tonumber(leaf_count) or 0,
									tonumber(clusters) or 0,
									(state.closest_tree and minetest.pos_to_string(state.closest_tree.pos or state.closest_tree) or "nil"),
								tree_jungle_sources,
								tonumber(creek_count) or 0,
								creek_closest and minetest.pos_to_string(creek_closest) or "nil",
								tonumber(ocean_count) or 0,
								ocean_closest and minetest.pos_to_string(ocean_closest) or "nil",
								tonumber(mountain_count) or 0,
								mountain_closest and minetest.pos_to_string(mountain_closest) or "nil",
								tonumber(jungle_count) or 0,
								jungle_closest and minetest.pos_to_string(jungle_closest) or "nil"
							))
						end
					end

						if do_update then
						local inside_mul = state._inside_gain_mul or 1
						-- Tree canopy rustle
							local tree_stream = get_stream_state(state, "tree")
							local tree_jungle_stream = get_stream_state(state, "tree_jungle")
							local tree_sources = state.tree_sources
							local g_default = combined_tree_gain_for_profile(ppos, tree_sources, "default") * inside_mul
							local g_jungle = combined_tree_gain_for_profile(ppos, tree_sources, "jungle") * inside_mul
						if g_default > 0 then
							local def = SOUNDSCAPES.tree
							if state._tree_soundkey == SOUND_LEAVES_MOUNTAIN then
								def = SOUNDSCAPES.tree_mountain
							end
							-- Play as a single "attached" stream (no pos) to prevent cutouts when
							-- the dominant tree source changes while walking; gain is computed from
							-- multiple nearby trees for smooth blending.
							ensure_stream(name, tree_stream, state._tree_soundkey or SOUND_LEAVES, nil, g_default, def, dtime)
						else
							fadeout_or_stop_stream(tree_stream, dtime)
						end
							if g_jungle > 0 then
								local jungle_def = SOUNDSCAPES.tree_jungle
								if state._tree_jungle_soundkey == SOUND_LEAVES_JUNGLE_NIGHT then
									jungle_def = SOUNDSCAPES.tree_jungle_night
								end
								ensure_stream(name, tree_jungle_stream, state._tree_jungle_soundkey or SOUND_LEAVES_JUNGLE, nil, g_jungle, jungle_def, dtime)
							else
								fadeout_or_stop_stream(tree_jungle_stream, dtime)
							end

					-- Creek ambience near water lilies
					local creek_stream = get_stream_state(state, "creek")
					local creek_src = state.closest_creek
				local creek_dist = (creek_src and ppos) and dist3(ppos, creek_src) or nil
						if creek_src and creek_dist then
							local g = (1.0 - (creek_dist / cfg_gain_distance)) * inside_mul
							if g > 0 then
							-- Keep creek attached to player to avoid restart churn when nearest
							-- lily source changes while moving through dense lily-pad areas.
							ensure_stream(name, creek_stream, SOUND_CREEK, nil, g, SOUNDSCAPES.creek, dtime)
						else
							fadeout_or_stop_stream(creek_stream, dtime)
						end
				else
					fadeout_or_stop_stream(creek_stream, dtime)
				end

				-- Ocean ambience near tagged ocean biome cells.
				local ocean_stream = get_stream_state(state, "ocean")
				local ocean_src = state.closest_ocean
					local ocean_dist = (ocean_src and ppos) and dist3(ppos, ocean_src) or nil
						if ocean_src and ocean_dist then
							local g = (1.0 - (ocean_dist / cfg_gain_distance)) * inside_mul
							if g > 0 then
							-- Keep ocean attached to player to avoid restart/cutout churn while
							-- nearest ocean/river cell changes during movement.
							ensure_stream(name, ocean_stream, SOUND_OCEAN, nil, g, SOUNDSCAPES.ocean, dtime)
						else
							fadeout_or_stop_stream(ocean_stream, dtime)
						end
				else
					fadeout_or_stop_stream(ocean_stream, dtime)
				end

				-- Mountain ambience near tagged mountain biome cells.
				local mountain_stream = get_stream_state(state, "mountain")
				local mountain_src = state.closest_mountain
				local mountain_dist = (mountain_src and ppos) and dist3(ppos, mountain_src) or nil
					if mountain_src and mountain_dist then
						local g = (1.0 - (mountain_dist / cfg_gain_distance)) * inside_mul
						if g > 0 then
						ensure_stream(name, mountain_stream, SOUND_MOUNTAIN, nil, g, SOUNDSCAPES.mountain, dtime)
					else
						fadeout_or_stop_stream(mountain_stream, dtime)
					end
				else
					fadeout_or_stop_stream(mountain_stream, dtime)
				end

				-- Jungle biome ambience (jungle/bamboo tag): crickets by day/night.
				local jungle_stream = get_stream_state(state, "jungle_biome")
				local jungle_src = state.closest_jungle
				local jungle_dist = (jungle_src and ppos) and dist3(ppos, jungle_src) or nil
				if jungle_src and jungle_dist then
					local g = (1.0 - (jungle_dist / cfg_gain_distance)) * inside_mul
					if g > 0 then
							local jungle_sound = (get_day_quarter() == 1) and SOUND_JUNGLE_BIOME_DAY or SOUND_JUNGLE_BIOME_NIGHT
							local jungle_biome_def = SOUNDSCAPES.jungle_biome
							if jungle_sound == SOUND_JUNGLE_BIOME_NIGHT then
								jungle_biome_def = SOUNDSCAPES.jungle_biome_night
							end
							ensure_stream(name, jungle_stream, jungle_sound, nil, g, jungle_biome_def, dtime)
						else
							fadeout_or_stop_stream(jungle_stream, dtime)
						end
				else
					fadeout_or_stop_stream(jungle_stream, dtime)
				end
			end
		end
	end
end)
