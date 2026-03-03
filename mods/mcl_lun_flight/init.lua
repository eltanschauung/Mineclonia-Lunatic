local playerphysics = rawget(_G, "playerphysics")
local state = {}

local DOUBLE_JUMP_BOOST = 8.05
local SLOWFALL_GRAVITY = 0.25

local races = rawget(_G, "mcl_lun_races")
local mcl_lun_sounds = rawget(_G, "mcl_lun_sounds")

local function lun_sound(name, params, ephemeral)
	if mcl_lun_sounds and mcl_lun_sounds.play then
		return mcl_lun_sounds.play(name, params, ephemeral)
	end
	return core.sound_play(name, params or {}, ephemeral == nil and true or ephemeral)
end

local function can_float(player)
	if not races or not races.get_race then
		return false
	end
	local race = races.get_race(player)
	local def = races.get_definition and races.get_definition(race)
	return def and def.flight_mode == "float"
end

local function airborne(player)
	local pos = player:get_pos()
	local node = core.get_node_or_nil({ x = pos.x, y = pos.y - 0.6, z = pos.z })
	if not node then
		return true
	end
	local def = core.registered_nodes[node.name]
	return not def or not def.walkable
end

local function set_slowfall(player, enabled)
	if not playerphysics then return end
	local st = state[player]
	if not st then return end
	if enabled then
		if not st.slowfall then
			playerphysics.add_physics_factor(player, "gravity", "mcl_lun_flight:slowfall", SLOWFALL_GRAVITY)
			st.slowfall = true
		end
	else
		if st.slowfall then
			playerphysics.remove_physics_factor(player, "gravity", "mcl_lun_flight:slowfall")
		end
		st.slowfall = false
	end
end

local function get_state(player)
	local st = state[player]
	if not st then
		st = {
			double_jump_used = false,
			slowfall = false,
			ascending = false,
			last_vel_y = 0,
			prev_jump = false,
		}
		state[player] = st
	end
	return st
end

core.register_globalstep(function(dtime)
	for _, player in ipairs(core.get_connected_players()) do
		local st = get_state(player)
		local ctrl = player:get_player_control()
		local vel = player:get_velocity()

		local floating = can_float(player)
		local in_air = airborne(player)
		if not floating or not in_air then
			set_slowfall(player, false)
			st.double_jump_used = false
			st.ascending = false
			st.last_vel_y = vel and vel.y or 0
			st.prev_jump = ctrl.jump
			goto continue
			end

			if ctrl.jump and not st.prev_jump then
				if not st.double_jump_used then
					set_slowfall(player, false)
					player:add_velocity({ x = 0, y = DOUBLE_JUMP_BOOST, z = 0 })
					lun_sound("se_kira02", {
						pos = player:get_pos(),
						gain = 0.6,
						max_hear_distance = 24,
					})
					st.double_jump_used = true
					st.ascending = true
				elseif st.slowfall then
					set_slowfall(player, false)
					lun_sound("se_ophide", {
						pos = player:get_pos(),
						gain = 0.55,
						max_hear_distance = 24,
					})
				end
			end

		if st.ascending and (not vel or vel.y <= st.last_vel_y) then
			st.ascending = false
			set_slowfall(player, true)
		end

		st.last_vel_y = vel and vel.y or 0
		st.prev_jump = ctrl.jump

		::continue::
	end
end)

core.register_on_leaveplayer(function(player)
	set_slowfall(player, false)
	state[player] = nil
end)
