local S = core.get_translator(core.get_current_modname())

local mcl_lun_effects = rawget(_G, "mcl_lun_effects") or {}
_G.mcl_lun_effects = mcl_lun_effects

local insanity_state = {}

local function playerphysics_current_fov(player)
	local meta = player and player.get_meta and player:get_meta()
	if not meta then
		return 1, true
	end
	local a = core.deserialize(meta:get_string("playerphysics:physics"))
	if type(a) ~= "table" then
		return 1, true
	end
	if type(a.fov_absolute) == "number" and a.fov_absolute > 0 then
		return a.fov_absolute, false
	end
	local factors = a.fov
	if type(factors) ~= "table" then
		return 1, true
	end
	local product = 1
	for _, factor in pairs(factors) do
		if type(factor) == "number" then
			product = product * factor
		end
	end
	return product, true
end

local function get_player_fov_state(player)
	if player and player.get_fov then
		local ok, fov, is_multiplier = pcall(player.get_fov, player)
		if ok then
			if type(fov) == "table" then
				local tfov = fov.fov or fov[1]
				local tmul = fov.is_multiplier
				if tmul == nil then
					tmul = fov[2]
				end
				if type(tfov) == "number" and type(tmul) == "boolean" then
					return tfov, tmul
				end
				if type(tfov) == "number" then
					return tfov, false
				end
			elseif type(fov) == "number" then
				if type(is_multiplier) == "boolean" then
					return fov, is_multiplier
				end
				return fov, false
			end
		end
	end
	return playerphysics_current_fov(player)
end

local function insanity_clear(player)
	if not player or not player:is_player() then
		return
	end
	player:get_meta():set_string("mcl_lun_effects:insanity", "")
	local name = player:get_player_name()
	local st = insanity_state[name]
	if not st then
		return
	end
	if st.base_fov then
		player:set_fov(st.base_fov, st.base_fov_is_multiplier == true, 0.2)
	else
		player:set_fov(0, false, 0.2)
	end
	player:set_eye_offset({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 0})
	insanity_state[name] = nil
end

local function insanity_begin(player)
	if not player or not player:is_player() then
		return false, "Player required"
	end

	local name = player:get_player_name()
	local st = insanity_state[name]
	if not st then
		st = {phase = math.random() * math.pi * 2}
		insanity_state[name] = st
	end
	if st.base_fov == nil then
		local base_fov, is_mul = get_player_fov_state(player)
		if (not is_mul) and (type(base_fov) ~= "number" or base_fov <= 0) then
			base_fov = 1
			is_mul = true
		end
		st.base_fov = base_fov
		st.base_fov_is_multiplier = is_mul == true
	end
	st.t = st.t or 0
	st.dx = st.dx or 0
	st.dy = st.dy or 0
	st.fov = st.fov
	st.just_started = true
	player:get_meta():set_string("mcl_lun_effects:insanity", "1")
	return true
end

local function insanity_step(player, dtime, intensity)
	if not player or not player:is_player() then
		return
	end
	local name = player:get_player_name()
	local st = insanity_state[name]
	if not st then
		return
	end
	if dtime <= 0 then
		return
	end
	intensity = tonumber(intensity) or 1
	if intensity < 0 then
		intensity = 0
	elseif intensity > 1 then
		intensity = 1
	end

	st.t = (st.t or 0) + dtime
	local t = st.t

	local smooth = 1 - math.exp(-dtime * 12)
	if st.just_started then
		smooth = 1
		st.just_started = false
	end

	local sway = 0.55 * intensity
	local dx_target = math.sin(t * 4 + (st.phase or 0)) * sway
	local dy_target = math.cos(t * 5 + (st.phase or 0)) * sway
	st.dx = (st.dx or 0) + (dx_target - (st.dx or 0)) * smooth
	st.dy = (st.dy or 0) + (dy_target - (st.dy or 0)) * smooth
	player:set_eye_offset({x = st.dx, y = st.dy, z = 0}, {x = st.dx, y = st.dy, z = 0})

	local wave = math.sin(t * 2.0 + (st.phase or 0))
	local base_fov = st.base_fov
	if st.base_fov_is_multiplier then
		local mult_amp = 0.30 * intensity
		local fov_target = (base_fov or 1) * (1 + wave * mult_amp)
		if fov_target < 0.1 then
			fov_target = 0.1
		end
		st.fov = (st.fov or fov_target) + (fov_target - (st.fov or fov_target)) * smooth
		player:set_fov(st.fov, true, 0)
	else
		local deg_amp = 30 * intensity
		local base = (type(base_fov) == "number" and base_fov > 0) and base_fov or 72
		local fov_target = base + wave * deg_amp
		if fov_target < 30 then
			fov_target = 30
		elseif fov_target > 179 then
			fov_target = 179
		end
		st.fov = (st.fov or fov_target) + (fov_target - (st.fov or fov_target)) * smooth
		player:set_fov(st.fov, false, 0)
	end
end

local function insanity_apply(player, duration)
	if not player or not player:is_player() then
		return false, "Player required"
	end
	duration = tonumber(duration) or 5
	if duration <= 0 then
		return false, "Duration must be > 0"
	end

	local name = player:get_player_name()
	local now = core.get_gametime()
	local until_time = now + duration

	local ok, err = insanity_begin(player)
	if not ok then
		return false, err
	end
	local st = insanity_state[name]
	st.until_time = until_time
	st.t = 0
	st.dx = 0
	st.dy = 0
	st.fov = nil
	st.driven_by_potions = false

	-- Apply immediately (globalstep might not run until next tick).
	insanity_step(player, 0.001, 1)
	return true
end

core.register_chatcommand("insanity", {
	params = "[seconds]",
	description = "Apply the insanity effect to yourself (debug).",
	privs = {interact = true},
	func = function(name, param)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found"
		end
		local ok, err = insanity_apply(player, param ~= "" and param or 5)
		if not ok then
			return false, err or "Failed"
		end
		return true, "Insanity applied."
	end,
})

core.register_on_joinplayer(function(player)
	player:get_meta():set_string("mcl_lun_effects:insanity", "")
end)

core.register_on_leaveplayer(function(player)
	insanity_clear(player)
end)

core.register_globalstep(function(dtime)
	if dtime <= 0 then
		return
	end
	local now = core.get_gametime()
	for name, st in pairs(insanity_state) do
		local player = core.get_player_by_name(name)
		if not player then
			insanity_state[name] = nil
			goto continue
		end
		if st.driven_by_potions then
			goto continue
		end
		if not st.until_time or now >= st.until_time then
			insanity_clear(player)
			goto continue
		end

		local remaining = math.max(0, st.until_time - now)

		local fade_out = 1
		if remaining < 0.35 then
			fade_out = math.max(0, remaining / 0.35)
		end
		local intensity = fade_out * fade_out * (3 - 2 * fade_out) -- smoothstep
		insanity_step(player, dtime, intensity)
		::continue::
	end
end)

function mcl_lun_effects.insanity_clear(player)
	return insanity_clear(player)
end

function mcl_lun_effects.insanity_apply(player, duration)
	return insanity_apply(player, duration)
end

function mcl_lun_effects.insanity_begin(player)
	return insanity_begin(player)
end

function mcl_lun_effects.insanity_step(player, dtime, intensity)
	return insanity_step(player, dtime, intensity)
end

local function register_potions_effect()
	if not mcl_potions or type(mcl_potions.register_effect) ~= "function" then
		return
	end
	if mcl_potions.registered_effects and mcl_potions.registered_effects.insanity then
		return
	end
	mcl_potions.register_effect({
		name = "insanity",
		description = S("Insanity"),
		icon = "mcl_potions_effect_food_poisoning.png",
		get_tt = function(_)
			return S("distorts your senses")
		end,
		on_start = function(object, _)
			if not (object and object.is_player and object:is_player()) then
				return
			end
			local ok = insanity_begin(object)
			if ok then
				local st = insanity_state[object:get_player_name()]
				if st then
					st.driven_by_potions = true
				end
				insanity_step(object, 0.001, 1)
			end
		end,
		on_load = function(object, _)
			if not (object and object.is_player and object:is_player()) then
				return
			end
			local ok = insanity_begin(object)
			if ok then
				local st = insanity_state[object:get_player_name()]
				if st then
					st.driven_by_potions = true
				end
				insanity_step(object, 0.001, 1)
			end
		end,
		on_step = function(dtime, object, _, _)
			if not (object and object.is_player and object:is_player()) then
				return
			end
			local st = insanity_state[object:get_player_name()]
			if not st then
				local ok = insanity_begin(object)
				if not ok then
					return
				end
				st = insanity_state[object:get_player_name()]
				if st then
					st.driven_by_potions = true
				end
			end
			if st then
				st.driven_by_potions = true
			end
			insanity_step(object, dtime, 1)
		end,
		on_end = function(object)
			if not (object and object.is_player and object:is_player()) then
				return
			end
			insanity_clear(object)
		end,
		particle_color = "#AA00FF",
		uses_factor = false,
	})
end

core.register_on_mods_loaded(register_potions_effect)
