local MODNAME = minetest.get_current_modname()
local MODPATH = minetest.get_modpath(MODNAME)

local function clamp_number(v, lo, hi)
	v = tonumber(v)
	if not v then
		return nil
	end
	if lo and v < lo then v = lo end
	if hi and v > hi then v = hi end
	return v
end

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

local function get_bool_setting(name, default)
	local v = minetest.settings:get_bool(name, default)
	if v == nil then
		return default
	end
	return v
end

local settings = {
	enabled = get_bool_setting("mcl_lun_music_enabled", true),
	debug = get_bool_setting("mcl_lun_music_debug", false),
	gain = clamp_number(minetest.settings:get("mcl_lun_music_gain"), 0, 2) or 0.6,
	min_silence = clamp_number(minetest.settings:get("mcl_lun_music_min_silence"), 0, 86400) or 180,
	probability_per_second = clamp_number(minetest.settings:get("mcl_lun_music_probability_per_second"), 0, 1) or 0.002,
	cooldown_min = clamp_number(minetest.settings:get("mcl_lun_music_cooldown_min"), 0, 86400) or 240,
	cooldown_max = clamp_number(minetest.settings:get("mcl_lun_music_cooldown_max"), 0, 86400) or 600,
}

if settings.cooldown_min > settings.cooldown_max then
	settings.cooldown_min, settings.cooldown_max = settings.cooldown_max, settings.cooldown_min
end

do
	local seed = (minetest.get_us_time and minetest.get_us_time() or os.time())
	seed = seed + math.floor(os.clock() * 1000000)
	math.randomseed(seed)
	math.random()
	math.random()
	math.random()
end

local TRACKS = {}
local TRACK_BY_ID = {}

local function is_list(v)
	return type(v) == "table"
end

local function value_in(list_or_value, value)
	if list_or_value == nil then
		return true
	end
	if is_list(list_or_value) then
		for _, v in ipairs(list_or_value) do
			if v == value then
				return true
			end
		end
		return false
	end
	return list_or_value == value
end

local function normalize_track(def)
	if type(def) ~= "table" then
		return nil, "track must be a table"
	end
	if type(def.id) ~= "string" or def.id == "" then
		return nil, "track.id is required"
	end
	if type(def.sound) ~= "string" or def.sound == "" then
		return nil, "track.sound is required"
	end
	local length = clamp_number(def.length, 0.01, 86400)
	if not length then
		return nil, "track.length is required"
	end
	local weight = clamp_number(def.weight, 0, nil) or 1
	local allowed = def.allowed_contexts
	if allowed ~= nil and type(allowed) ~= "table" then
		return nil, "track.allowed_contexts must be a table"
	end
	return {
		id = def.id,
		sound = def.sound,
		length = length,
		weight = weight,
		allowed_contexts = allowed,
	}, nil
end

local function register_track(def)
	local track, err = normalize_track(def)
	if not track then
		return false, err
	end
	if TRACK_BY_ID[track.id] then
		return false, "track id already registered: " .. track.id
	end
	TRACK_BY_ID[track.id] = track
	TRACKS[#TRACKS + 1] = track
	return true
end

local function unregister_track(id)
	local t = TRACK_BY_ID[id]
	if not t then
		return false
	end
	TRACK_BY_ID[id] = nil
	for i, v in ipairs(TRACKS) do
		if v == t then
			table.remove(TRACKS, i)
			break
		end
	end
	return true
end

local function track_matches(track, ctx)
	local allowed = track.allowed_contexts
	if not allowed then
		return true
	end

	if not value_in(allowed.dimension, ctx.dimension) then
		return false
	end
	if not value_in(allowed.biome, ctx.biome) then
		return false
	end

	local y_min = allowed.y_min
	local y_max = allowed.y_max
	if y_min ~= nil and ctx.y < y_min then
		return false
	end
	if y_max ~= nil and ctx.y > y_max then
		return false
	end

	local states = allowed.states
	if states ~= nil then
		if type(states) ~= "table" then
			return false
		end
		for k, required in pairs(states) do
			if required ~= nil then
				if (ctx.states and ctx.states[k]) ~= required then
					return false
				end
			end
		end
	end

	return true
end

local function pick_weighted(candidates)
	local total = 0
	for _, t in ipairs(candidates) do
		total = total + (t.weight or 1)
	end
	if total <= 0 then
		return nil
	end
	local r = math.random() * total
	local acc = 0
	for _, t in ipairs(candidates) do
		acc = acc + (t.weight or 1)
		if r <= acc then
			return t
		end
	end
	return candidates[#candidates]
end

local function select_track(ctx)
	if #TRACKS == 0 then
		return nil
	end
	local candidates = {}
	for _, t in ipairs(TRACKS) do
		if track_matches(t, ctx) then
			candidates[#candidates + 1] = t
		end
	end
	if #candidates == 0 then
		return nil
	end
	return pick_weighted(candidates)
end

local PLAYER_STATE = {}

local function set_state(playername, key, value)
	if type(playername) ~= "string" or playername == "" then
		return false
	end
	if type(key) ~= "string" or key == "" then
		return false
	end
	if value == nil then
		if PLAYER_STATE[playername] then
			PLAYER_STATE[playername][key] = nil
		end
		return true
	end
	if type(value) ~= "boolean" then
		return false
	end
	PLAYER_STATE[playername] = PLAYER_STATE[playername] or {}
	PLAYER_STATE[playername][key] = value
	return true
end

local function get_context(player)
	local pos = player:get_pos()
	if not pos then
		return nil
	end
	pos = vector.round(pos)

	local dimension = "overworld"
	local mcl_worlds = rawget(_G, "mcl_worlds")
	if mcl_worlds and mcl_worlds.pos_to_dimension then
		dimension = mcl_worlds.pos_to_dimension(pos) or dimension
	end

	local biome = nil
	if minetest.get_biome_data and minetest.get_biome_name then
		local bd = minetest.get_biome_data(pos)
		if bd and bd.biome then
			biome = minetest.get_biome_name(bd.biome)
		end
	end

	local name = player:get_player_name()
	return {
		x = pos.x,
		y = pos.y,
		z = pos.z,
		dimension = dimension,
		biome = biome,
		states = name and PLAYER_STATE[name] or nil,
	}
end

local function rand_range(lo, hi)
	if hi <= lo then
		return lo
	end
	return lo + (hi - lo) * math.random()
end

local function probability_chance(p_per_sec, dt)
	if p_per_sec <= 0 then
		return 0
	end
	if dt <= 0 then
		return 0
	end
	if p_per_sec >= 1 then
		return 1
	end
	return 1 - math.pow(1 - p_per_sec, dt)
end

local CONTROLLERS = {}

local function stop_handle(handle)
	if handle ~= nil then
		minetest.sound_stop(handle)
	end
end

local function finish_track(ctrl)
	stop_handle(ctrl.current_handle)
	ctrl.current = nil
	ctrl.current_handle = nil
	ctrl.current_end_time = 0
	ctrl.silence = 0
	ctrl.cooldown = rand_range(settings.cooldown_min, settings.cooldown_max)
end

local function play_sound_to_player(playername, sound, gain)
	local handle = minetest.sound_play(sound, {to_player = playername, gain = gain, loop = false})
	return handle
end

local function play_track(ctrl, player, track)
	local name = player:get_player_name()
	if not name or name == "" then
		return false
	end
	local now = minetest.get_gametime()

	ctrl.current = track
	ctrl.current_handle = play_sound_to_player(name, track.sound, settings.gain)
	ctrl.current_end_time = now + track.length
	ctrl.silence = 0
	ctrl.cooldown = 0
	minetest.log("action", ("[%s] Now playing %s..."):format(MODNAME, track.id))
	return true
end

local function stop_current(ctrl)
	if ctrl.override and ctrl.override.handle then
		stop_handle(ctrl.override.handle)
	end
	ctrl.override = nil
	if ctrl.current_handle then
		stop_handle(ctrl.current_handle)
	end
	ctrl.current = nil
	ctrl.current_handle = nil
	ctrl.current_end_time = 0
end

local function controller_step(player, dt)
	local name = player:get_player_name()
	if not name or name == "" then
		return
	end
	local ctrl = CONTROLLERS[name]
	if not ctrl then
		ctrl = {silence = 0, cooldown = 0, current = nil, current_end_time = 0, current_handle = nil, override = nil}
		CONTROLLERS[name] = ctrl
	end

	local now = minetest.get_gametime()

	if ctrl.override then
		if ctrl.override.end_time and now >= ctrl.override.end_time then
			stop_handle(ctrl.override.handle)
			ctrl.override = nil
			ctrl.silence = 0
			ctrl.cooldown = rand_range(settings.cooldown_min, settings.cooldown_max)
		end
		return
	end

	if ctrl.current then
		if ctrl.current_end_time and now >= ctrl.current_end_time then
			finish_track(ctrl)
		end
		return
	end

	ctrl.silence = ctrl.silence + dt
	if ctrl.silence < settings.min_silence then
		return
	end
	if ctrl.cooldown > 0 then
		ctrl.cooldown = math.max(0, ctrl.cooldown - dt)
		return
	end

	local chance = probability_chance(settings.probability_per_second, dt)
	if chance <= 0 then
		return
	end
	if math.random() >= chance then
		return
	end

	local ctx = get_context(player)
	if not ctx then
		return
	end
	local track = select_track(ctx)
	if not track then
		return
	end
	play_track(ctrl, player, track)
end

local function play_override(playername, def)
	if type(playername) ~= "string" or playername == "" then
		return false, "playername required"
	end
	if type(def) ~= "table" then
		return false, "override def required"
	end
	local sound = def.sound
	local length = clamp_number(def.length, 0.01, 86400)
	if type(sound) ~= "string" or sound == "" or not length then
		return false, "override requires sound and length"
	end
	local gain = clamp_number(def.gain, 0, 2) or settings.gain

	local ctrl = CONTROLLERS[playername]
	if not ctrl then
		ctrl = {silence = 0, cooldown = 0, current = nil, current_end_time = 0, current_handle = nil, override = nil}
		CONTROLLERS[playername] = ctrl
	end

	stop_current(ctrl)

	local now = minetest.get_gametime()
	local handle = play_sound_to_player(playername, sound, gain)
	ctrl.override = {sound = sound, handle = handle, end_time = now + length}
	ctrl.silence = 0
	ctrl.cooldown = 0
	minetest.log("action", ("[%s] Now playing %s..."):format(MODNAME, sound))
	return true
end

local function stop_override(playername)
	local ctrl = playername and CONTROLLERS[playername] or nil
	if not ctrl or not ctrl.override then
		return false
	end
	if ctrl.override.handle then
		stop_handle(ctrl.override.handle)
	end
	ctrl.override = nil
	ctrl.silence = 0
	ctrl.cooldown = rand_range(settings.cooldown_min, settings.cooldown_max)
	return true
end

local function controller_for(playername)
	return playername and CONTROLLERS[playername] or nil
end

local function load_tracks()
	local ok, data = pcall(dofile, MODPATH .. "/tracks.lua")
	if not ok then
		minetest.log("error", ("[%s] failed to load tracks.lua: %s"):format(MODNAME, tostring(data)))
		return
	end
	if type(data) ~= "table" then
		return
	end
	for _, def in ipairs(data) do
		local ok2, err2 = register_track(def)
		if not ok2 then
			minetest.log("warning", ("[%s] track skipped: %s"):format(MODNAME, tostring(err2)))
		end
	end
end

load_tracks()

minetest.register_on_joinplayer(function(player)
	local name = player and player:get_player_name() or nil
	if not name or name == "" then
		return
	end
	CONTROLLERS[name] = {silence = 0, cooldown = 0, current = nil, current_end_time = 0, current_handle = nil, override = nil}
end)

minetest.register_on_leaveplayer(function(player)
	local name = player and player:get_player_name() or nil
	if not name or name == "" then
		return
	end
	local ctrl = CONTROLLERS[name]
	if ctrl then
		stop_current(ctrl)
	end
	CONTROLLERS[name] = nil
	PLAYER_STATE[name] = nil
end)

minetest.register_globalstep(function(dt)
	if not settings.enabled then
		return
	end
	local players = minetest.get_connected_players()
	if not players or #players == 0 then
		return
	end
	dt = clamp_number(dt, 0, 5) or 0
	if dt <= 0 then
		return
	end
	for _, player in ipairs(players) do
		controller_step(player, dt)
	end
end)

minetest.register_chatcommand("playrandom", {
	description = "Force a random ambient music track to play now (uses normal controller state).",
	privs = {server = true},
	func = function(name)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end

		local ctrl = CONTROLLERS[name]
		if not ctrl then
			ctrl = {silence = 0, cooldown = 0, current = nil, current_end_time = 0, current_handle = nil, override = nil}
			CONTROLLERS[name] = ctrl
		end

		stop_current(ctrl)

		local ctx = get_context(player)
		local track = ctx and select_track(ctx) or nil
		if not track and #TRACKS > 0 then
			track = TRACKS[math.random(#TRACKS)]
		end
		if not track then
			return false, "No tracks available."
		end

		play_track(ctrl, player, track)
		return true, ("Now playing %s..."):format(track.id)
	end,
})

if settings.debug then
	minetest.register_chatcommand("music_status", {
		privs = {server = true},
		func = function(name)
			local ctrl = controller_for(name)
			if not ctrl then
				return true, "No controller."
			end
			local now = minetest.get_gametime()
			if ctrl.override then
				local rem = math.max(0, (ctrl.override.end_time or now) - now)
				return true, ("override sound=%s remaining=%ds silence=%.1fs cooldown=%.1fs"):format(
					tostring(ctrl.override.sound), math.floor(rem + 0.5), ctrl.silence or 0, ctrl.cooldown or 0
				)
			end
			if ctrl.current then
				local rem = math.max(0, (ctrl.current_end_time or now) - now)
				return true, ("track=%s remaining=%ds silence=%.1fs cooldown=%.1fs"):format(
					tostring(ctrl.current.id), math.floor(rem + 0.5), ctrl.silence or 0, ctrl.cooldown or 0
				)
			end
			return true, ("idle silence=%.1fs cooldown=%.1fs tracks=%d"):format(ctrl.silence or 0, ctrl.cooldown or 0, #TRACKS)
		end,
	})

	minetest.register_chatcommand("music_skip", {
		privs = {server = true},
		func = function(name)
			local ctrl = controller_for(name)
			if not ctrl then
				return false, "No controller."
			end
			stop_current(ctrl)
			ctrl.silence = settings.min_silence
			ctrl.cooldown = 0
			return true, "Stopped current music."
		end,
	})
end

local API = rawget(_G, "mcl_lun_music") or {}
API.register_track = register_track
API.unregister_track = unregister_track
API.play_override = play_override
API.stop_override = stop_override
API.set_state = set_state
API.get_controller = controller_for
API.get_settings = function()
	return settings
end

_G.mcl_lun_music = API
