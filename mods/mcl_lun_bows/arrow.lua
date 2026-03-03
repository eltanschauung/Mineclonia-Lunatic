local S = core.get_translator(core.get_current_modname())
local mcl_lun_sounds = rawget(_G, "mcl_lun_sounds")
local color_fn = rawget(_G, "color") or (rawget(_G, "colors_api") and colors_api and colors_api.color)
local mcl_lun_items_mod = rawget(_G, "mcl_lun_items")
local build_lun_tt = mcl_lun_items_mod and mcl_lun_items_mod.build_lun_tt
local build_lun_description = mcl_lun_items_mod and mcl_lun_items_mod.build_lun_description

local enable_pvp = core.settings:get_bool("enable_pvp")

local GRAVITY = 32.0

-- Time in seconds to despawn an arrow.
local ARROW_LIFETIME = 12
-- Time in seconds after which a stuck arrow is deleted
local STUCK_ARROW_TIMEOUT = 12
-- Time in seconds after which an attached arrow is deleted
local ATTACHED_ARROW_TIMEOUT = 30
-- Time after which stuck arrow is rechecked for being stuck
local STUCK_RECHECK_TIME = 0.25
-- Range for stuck arrow to be collected by player
local PICKUP_RANGE = 2

-- For each DRAG_TICK second, set velocity to DRAG_RATE%
local DRAG_TICK = 0.05
local DRAG_RATE = 0.99
local STUCK_PARTICLE_INTERVAL = 0.5

-- Each block of liquid set velocity to LIQUID_RATE%
local LIQUID_RATE = 0.74 -- Bow arrow lost most horizontal speed at 8 liquid blocks.

--local GRAVITY = 9.81

local YAW_OFFSET = -math.pi/2

local function dir_to_pitch(dir)
	--local dir2 = vector.normalize(dir)
	local xz = math.abs(dir.x) + math.abs(dir.z)
	return -math.atan2(-dir.y, xz)
end

local function fmt_vec(vec)
	return string.format("(%.3f,%.3f,%.3f)", vec.x, vec.y, vec.z)
end

local function log_light(msg)
	core.log("action", "[mcl_lun_bows][light] " .. msg)
end

local function lun_sound(name, params, ephemeral)
	if mcl_lun_sounds and mcl_lun_sounds.play then
		return mcl_lun_sounds.play(name, params, ephemeral)
	end
	return core.sound_play(name, params or {}, ephemeral == nil and true or ephemeral)
end

local wielded_light = rawget(_G, "wielded_light")
local LUNAR_BOW_TRAIL = {
    "lunar_bow_particle_blue.png",
    "lunar_bow_particle_red.png",
}

local spawn_particle_burst
local function fetch_spawn_particle_burst()
	if spawn_particle_burst == nil then
		spawn_particle_burst = rawget(_G, "spawn_particle_burst")
		if not spawn_particle_burst then
			local mod_tbl = rawget(_G, "mcl_lun_items")
			spawn_particle_burst = mod_tbl and mod_tbl.spawn_particle_burst
		end
	end
	return spawn_particle_burst
end

local function normalize_surface_normal(normal)
	if not normal then
		return {x=0, y=1, z=0}
	end
	if type(normal) ~= "table" then
		return {x=0, y=1, z=0}
	end
	if normal.x == nil or normal.y == nil or normal.z == nil then
		return {x=0, y=1, z=0}
	end
	return normal
end

local function stop_stuck_spawner(self)
	if self and self._stuck_particle_id then
		if type(self._stuck_particle_id) == "table" then
			for _, id in ipairs(self._stuck_particle_id) do
				core.delete_particlespawner(id)
			end
		else
			core.delete_particlespawner(self._stuck_particle_id)
		end
		self._stuck_particle_id = nil
	end
end

local function stop_stuck_effects(self)
	stop_stuck_spawner(self)
	if self and self._stuck_light then
		self._stuck_light:remove()
		self._stuck_light = nil
	end
end

local function compute_stuck_center(self_pos, last_vel)
	if last_vel and vector.length(last_vel) > 0 then
		local dir = vector.normalize(last_vel)
		return vector.subtract(self_pos, vector.multiply(dir, 0.3))
	end
	return self_pos
end

local function start_stuck_geyser(self, center, resolved_normal)
	local burst = fetch_spawn_particle_burst()
	if burst then
		self._stuck_particle_id = burst({
			center = center,
			normal = resolved_normal,
			height_offset = 0,
			textures = LUNAR_BOW_TRAIL,
			amount = 6,
			time = 0, -- continuous
			minvel = {x=-0.2, y=0.6, z=-0.2},
			maxvel = {x=0.2, y=1.2, z=0.2},
			minsize = 1.2,
			maxsize = 1.8,
			glow = 15,
			light_entity = "mcl_lun_bows:lunar_arrow_explosion_light",
			return_id = true,
		}) or nil
		return
	end
	self._stuck_particle_id = core.add_particlespawner({
		amount = 6,
		time = 0, -- continuous
		minpos = center,
		maxpos = center,
		minvel = {x=-0.2, y=0.6, z=-0.2},
		maxvel = {x=0.2, y=1.2, z=0.2},
		minsize = 1.2,
		maxsize = 1.8,
		glow = 15,
		texture = LUNAR_BOW_TRAIL[1],
	})
end

local function spawn_stuck_particles(pos, normal)
	if not pos then return end
	local resolved_normal = normalize_surface_normal(normal)
	local burst = fetch_spawn_particle_burst()
	if burst then
		burst({
			center = pos,
			normal = resolved_normal,
			height_offset = 0,
			textures = LUNAR_BOW_TRAIL,
			amount = 8,
			time = 0.1,
			minvel = {x=-0.4, y=0.6, z=-0.4},
			maxvel = {x=0.4, y=1.2, z=0.4},
			minsize = 1.2,
			maxsize = 1.8,
			glow = 15,
			light_entity = "mcl_lun_bows:lunar_arrow_explosion_light",
		})
		return
	end
	local center = vector.add(pos, vector.multiply(resolved_normal, 0.1))
	local minvel = {x=-0.4, y=0.6, z=-0.4}
	local maxvel = {x=0.4, y=1.2, z=0.4}
	for _, texture in ipairs(LUNAR_BOW_TRAIL) do
		core.add_particlespawner({
			amount = 8,
			time = 0.1,
			minpos = center,
			maxpos = center,
			minvel = minvel,
			maxvel = maxvel,
			minsize = 1.2,
			maxsize = 1.8,
			glow = 15,
			texture = texture,
		})
	end
end
local LUNAR_BOW_CROSS = {
	{y = 0.2, z = 0},
	{y = -0.2, z = 0},
	{y = 0, z = 0.2},
	{y = 0, z = -0.2},
}

local LUNAR_BOW_RING = {
	{y = 0.35, z = 0},
	{y = 0.25, z = 0.25},
	{y = 0, z = 0.35},
	{y = -0.25, z = 0.25},
	{y = -0.35, z = 0},
	{y = -0.25, z = -0.25},
	{y = 0, z = -0.35},
	{y = 0.25, z = -0.25},
}

local function random_arrow_positions(positions, placement)
	if positions == "x" then
		return math.random(-4, 4)
	elseif positions == "y" then
		return math.random(0, 10)
	end
	if placement == "front" and positions == "z" then
		return 3
	elseif placement == "back" and positions == "z" then
		return -3
	end
	return 0
end

local arrow_tt_help = build_lun_tt and build_lun_tt({
	lines = {
		{ text = S("Used in Lunar Bows"), color = (color_fn and color_fn("dodgerblue")) or "#1e90ff" },
		S("Ammunition"),
		S("Damage from bow: 1-10"),
		S("Damage from dispenser: 3"),
	},
}) or table.concat({
	core.colorize((color_fn and color_fn("dodgerblue")) or "#1e90ff", S("Used in Lunar Bows")),
	S("Ammunition"),
	S("Damage from bow: 1-10"),
	S("Damage from dispenser: 3"),
}, "\n")

core.register_craftitem("mcl_lun_bows:lunar_arrow", {
	description = build_lun_description and build_lun_description({
		description = S("Lunar Arrow"),
		color = "#b71c1c",
		skip_stats = true,
	}) or core.colorize("#b71c1c", S("Lunar Arrow")),
	_tt_help = arrow_tt_help,
	_doc_items_longdesc = S("Arrows are ammunition for bows and dispensers.").."\n"..
S("An arrow fired from a bow has a regular damage of 1-9. At full charge, there's a 20% chance of a critical hit dealing 10 damage instead. An arrow fired from a dispenser always deals 3 damage.").."\n"..
S("Arrows might get stuck on solid blocks and can be retrieved again. They are also capable of pushing wooden buttons."),
	_doc_items_usagehelp = S("To use arrows as ammunition for a bow, just put them anywhere in your inventory, they will be used up automatically. To use arrows as ammunition for a dispenser, place them in the dispenser's inventory. To retrieve an arrow that sticks in a block, simply walk close to it."),
	inventory_image = "mcl_lun_bows_arrow_inv.png",
	groups = { ammo=1, ammo_lunar_bow=1 },
	_on_dispense = function(itemstack, dispenserpos, _, _, dropdir)
		-- Shoot arrow
		local shootpos = vector.add(dispenserpos, vector.multiply(dropdir, 0.51))
		local yaw = math.atan2(dropdir.z, dropdir.x) + YAW_OFFSET
		mcl_lun_bows.shoot_arrow (itemstack:get_name(), shootpos, dropdir, yaw, "mcl_dispensers:dispenser", 0.366666)
	end,
})

local ARROW_ENTITY={
	initial_properties = {
		physical = true,
		pointable = false,
		visual = "mesh",
		mesh = "mcl_lun_bows_arrow.b3d",
		visual_size = {x=-1, y=1},
		textures = {"mcl_lun_bows_lunar_arrow.png"},
		collisionbox = {-0.01, -0.01, -0.01, 0.01, 0.01, 0.01},
		collide_with_objects = false,
		-- Keep the projectile fully lit while flying.
		light_source = 14,
	},
	_fire_collisionbox = {-0.19, -0.125, -0.39, 0.19, 0.125, -0.01},
	fire_damage_resistant = true,
	_lastpos={},
	_startpos=nil,
	_damage=1,	-- Damage on impact
	_is_critical=false, -- Whether this arrow would deal critical damage
	_stuck=false,   -- Whether arrow is stuck
	_lifetime=0,-- Amount of time (in seconds) the arrow has existed
	_dragtime=0,-- Amount of time (in seconds) the arrow has slowed down
	_stuck_particle_timer=0,
	_stuck_particle_id=nil,
	_stuck_light=nil,
	_stuckrechecktimer=nil,-- An additional timer for periodically re-checking the stuck status of an arrow
	_stuckin=nil,	--Position of node in which arrow is stuck.
	_shooter=nil,	-- ObjectRef of player or mob who shot it.
	_left_shooter = false,
	_is_arrow = true,
	_in_player = false,
	_blocked = nil, -- Name of last player who deflected this arrow with a shield.
	_particle_id=nil,
	_debug_logged=false,
	_particle_logged=false,
	_ignored=nil,
	_animtime = 0.0,
}

-- Drop arrow as item at pos
local function spawn_item(self, pos)
	if not core.is_creative_enabled("") then
		local itemstring = "mcl_lun_bows:lunar_arrow"
		if self._itemstring then
			local stack = ItemStack (self.itemstring)
			if stack:get_definition () then
				itemstring = self._itemstring
			end
		end
		local item = core.add_item(pos, itemstring)
		if item then
			local luaentity = item:get_luaentity ()
			item:set_velocity(vector.new(0, 0, 0))
			item:set_yaw(self.object:get_yaw())
			luaentity._insta_collect = true
		end
	end
end

local function damage_particles(pos, is_critical, dir)
	if not is_critical or not pos then return end
	-- Play crit burst sound at impact.
	lun_sound("se_kira00", {pos = pos, gain = 0.6, max_hear_distance = 32})
	dir = dir and vector.normalize(dir) or {x = 0, y = 1, z = 0}
	-- Build a loose cone around the arrow's direction.
	local right = vector.new(-dir.z, 0, dir.x)
	if vector.length(right) == 0 then
		right = {x = 1, y = 0, z = 0}
	else
		right = vector.normalize(right)
	end
	local up = vector.normalize(vector.cross(right, dir))
	local base_speed = 0.8
	local lateral = 0.35
	local minvel = {
		x = dir.x * base_speed - lateral,
		y = dir.y * base_speed - lateral,
		z = dir.z * base_speed - lateral,
	}
	local maxvel = {
		x = dir.x * base_speed + lateral,
		y = dir.y * base_speed + lateral,
		z = dir.z * base_speed + lateral,
	}
	-- Spawn separate spawners for blue and red to avoid combined texture issues.
	for _, tex in ipairs(LUNAR_BOW_TRAIL) do
		core.add_particlespawner({
			amount = 6,
			time = 0.1,
			minpos = vector.offset(pos, -0.4, -0.2, -0.4),
			maxpos = vector.offset(pos, 0.4, 0.6, 0.4),
			minvel = minvel,
			maxvel = maxvel,
			minexptime = 1.0,
			maxexptime = 2.5,
			minsize = 1.6,
			maxsize = 2.6,
			collisiondetection = false,
			vertical = false,
			texture = tex,
			glow = 14,
		})
	end
	-- Spawn a light entity at the impact center, same as stuck arrows.
	minetest.add_entity(pos, "mcl_lun_bows:lunar_arrow_explosion_light")
end

-- Add player bow height to position, which is simply y += 1.5
function mcl_lun_bows.add_bow_height(pos)
	pos = vector.copy(pos)
	pos.y = pos.y + 1.5
	return pos
end

-- Add inaccuracy to a _direction_ vector (before speed is applied).
-- Player has an inaccuracy of 1, dispenser 6, mobs varies by difficulty (input nil)
-- The distribution will form a bell shape, loosely speaking.
function mcl_lun_bows.add_inaccuracy(dir, inaccuracy, accuracy_factor)
	if not inaccuracy then
		inaccuracy = 14 - mcl_vars.difficulty * 4 -- 1:Easy = 10, 2:Normal = 6, 3:Hard = 2
	end
	if accuracy_factor and accuracy_factor ~= 1 then
		inaccuracy = inaccuracy * accuracy_factor
	end
	if inaccuracy == 0 then return dir end
	dir = vector.copy(dir)
	-- Reference: https://midnight.wiki.gg/wiki/Ebonite_Arrow
	dir.x = dir.x + mcl_util.dist_triangular(0, 0.0172275 * inaccuracy)
	dir.y = dir.y + mcl_util.dist_triangular(0, 0.0172275 * inaccuracy)
	dir.z = dir.z + mcl_util.dist_triangular(0, 0.0172275 * inaccuracy)
	return dir
end

function ARROW_ENTITY:get_last_pos()
	return self._lastpos.x and self._lastpos or self._startpos
end

-- Multiply x and z velocity by given factor.
function ARROW_ENTITY:multiply_xz_velocity (factor)
	local vel = self.object:get_velocity ()
	vel.x = vel.x * factor
	vel.z = vel.z * factor
	vel.y = vel.y * factor
	self.object:set_velocity(vel)
end

function ARROW_ENTITY:arrow_knockback (object, damage)
	local entity = object:get_luaentity ()
	local v = self.object:get_velocity ()
	v.y = 0
	local dir = vector.normalize (v)

	-- Utilize different methods of applying knockback for consistency.
	if entity and entity.is_mob then
		entity:projectile_knockback (1, dir)
	elseif object:is_player () then
		mcl_player.player_knockback (object, self.object, dir, nil, damage)
	end

	if self._knockback and self._knockback > 0 then
		local resistance = entity and entity.knockback_resistance or 0
		-- Apply an additional horizontal force of
		-- self._knockback * 0.6 * 20 * 0.546 to the object.
		local total_kb = self._knockback * (1.0 - resistance) * 12 * 0.546
		v = vector.multiply (dir, total_kb)

		-- And a vertical force of 2.0 * 0.91.
		v.y = v.y + 2.0 * 0.91 * (1.0 - resistance)

		if object:is_player () then
			v.x = v.x * 0.25
			v.z = v.z * 0.25
		end
		object:add_velocity (v)
	end
end

function ARROW_ENTITY:calculate_damage (v)
	if not v then v = self.object:get_velocity() end
	local crit_bonus = 0
	local multiplier = vector.length (v) / 20
	local damage = (self._damage or 2) * multiplier

	if self._is_critical then
		crit_bonus = math.random (damage / 2 + 2)
	end
	return math.ceil (damage + crit_bonus)
end

function ARROW_ENTITY:do_particle()
	if self._particle_id then return end
	local per_spawner = math.floor(ARROW_LIFETIME * 3)
	self._particle_id = {}
	local pattern = self._is_critical and LUNAR_BOW_RING or LUNAR_BOW_CROSS
	
	-- For attached particles in Minetest, the arrow mesh has a -90 degree yaw offset (YAW_OFFSET)
	-- This means the arrow's local coordinate system is rotated:
	-- - Arrow points in local -X direction (not +Z as you'd expect)
	-- - Local +Z is actually the arrow's left
	-- - Local +Y is still up
	
	local velocity = {x=-1.0, y=0, z=0}  -- Backward drift in arrow's local space (arrow points in -X)
	
	if not self._debug_logged then
		self._debug_logged = true
	end
	
    -- Max out glow so the trail is always fully lit.
    local glow = 14
	for idx, offset in ipairs(pattern) do
		local texture = LUNAR_BOW_TRAIL[((idx - 1) % #LUNAR_BOW_TRAIL) + 1]
		
		local offset_vec = {x = 0, y = offset.y or 0, z = offset.z or 0}
		
		local base_pos = {x=-0.5 + offset_vec.x, y=offset_vec.y, z=offset_vec.z}
		
		self._particle_id[#self._particle_id + 1] = core.add_particlespawner({
			amount = per_spawner,
			time = ARROW_LIFETIME,
			minpos = base_pos,
			maxpos = base_pos,
			minvel = velocity,
			maxvel = velocity,
			minexptime = 0.15,
			maxexptime = 0.25,
			minsize = 1.8,
			maxsize = 2.2,
			attached = self.object,
			collisiondetection = true,
			collision_removal = true,
			vertical = false,
			glow = glow,
			texture = texture,
		})
	end
	self._particle_logged = true
end

-- Calculate damage, knockback, burning, and tipped effect to target.
function ARROW_ENTITY:apply_effects(obj)
	local dmg = self:calculate_damage()
	local reason = {
		type = "arrow",
		source = self._shooter,
		direct = self.object,
	}
	local damage = mcl_util.deal_damage(obj, dmg, reason)
	self:arrow_knockback(obj, damage)
	if mcl_burning.is_burning(self.object) then
		mcl_burning.set_on_fire(obj, 5)
	end
	if self._extra_hit_func then
		self:_extra_hit_func(obj)
	end
end

-- Remove critical partical effects.
function ARROW_ENTITY:stop_particle()
	if not self._particle_id then return end
	for _, id in ipairs(self._particle_id) do
		core.delete_particlespawner(id)
	end
	self._particle_id = nil
	-- Also stop any stuck visuals when particle teardown is requested
	stop_stuck_effects(self)
end

-- Remove particle effect, clear most object fields, extinguish fire (optional), and optionally set remaining life.
function ARROW_ENTITY:cut_off(lifetime, keep_fire)
	if not keep_fire then mcl_burning.extinguish(self.object) end
	self._startpos, self._ignored = nil, nil -- last pos is used by stuck step to spawn arrow item
	self:stop_particle()
	stop_stuck_spawner(self)
	if lifetime then
		self._lifetime = ARROW_LIFETIME - lifetime
	end
end

-- Remove burning status, crit particle effect, and finally the arrow object.
function ARROW_ENTITY:remove()
	self:cut_off()
	self.object:remove()
end

local function play_despawn_sound(pos)
	lun_sound("se_ophide", {
		pos = pos,
		gain = 0.8,
		pitch = 1.0 + (math.random(-5, 5) * 0.01),
		max_hear_distance = 24,
	})
end

-- Process hitting a non-player object.  Return true to play damage particle and sound.
function ARROW_ENTITY:on_hit_object(obj, lua, _)
	if not lua or (not lua.is_mob and not lua._hittable_by_projectile)
	or lua.name == "mobs_mc:enderman" then
		return false
	end
	self:apply_effects(obj)
	return true
end

-- Process hitting a player, deflect if shield blocked, or attach if not piercing.
function ARROW_ENTITY:on_hit_player(obj, _, ray_hit)
	if not enable_pvp then return false end
	local piercing = self._piercing or 0
	if piercing > 0 then -- Piercing ignore shield.
		self:apply_effects(obj)
		return true
	end

	local dot_attack = mcl_shields.find_angle(self:get_last_pos(), obj)
	local can_block, stack = mcl_shields.can_block(obj, dot_attack)
	if can_block then
		local vec = self.object:get_velocity()
		local damage = self:calculate_damage(vec)
		mcl_shields.add_wear(obj, damage, stack)
		self._blocked = obj:get_player_name()
		self:arrow_knockback (obj, damage)
		self.object:set_velocity(vector.multiply(vec, -0.15))
		-- Intersection point can be in the past or future.
		self.object:set_pos(ray_hit.intersection_point or mcl_lun_bows.add_bow_height(obj:get_pos()))
		return "break"-- Stop further collision check as the arrow has changed direction.
	end

	self:apply_effects(obj)
	self._in_player = true
	local placement = dot_attack < 0 and "front" or "back"
	self._rotation_station = placement == "front" and -90 or 90
	self._y_position = random_arrow_positions("y", placement)
	self._x_position = random_arrow_positions("x", placement)
	if self._y_position > 6 and self._x_position < 2 and self._x_position > -2 then
		self._attach_parent = "Head"
		self._y_position = self._y_position - 6
	elseif self._x_position > 2 then
		self._attach_parent = "Arm_Right"
		self._y_position = self._y_position - 3
		self._x_position = self._x_position - 2
	elseif self._x_position < -2 then
		self._attach_parent = "Arm_Left"
		self._y_position = self._y_position - 3
		self._x_position = self._x_position + 2
	else
		self._attach_parent = "Body"
	end
	self._z_rotation = math.random(-30, 30)
	self._y_rotation = math.random( -30, 30)
	self.object:set_attach(
		obj, self._attach_parent,
		vector.new(self._x_position, self._y_position, random_arrow_positions("z", placement)),
		vector.new(0, self._rotation_station + self._y_rotation, self._z_rotation)
	)
	self:cut_off(ATTACHED_ARROW_TIMEOUT)
	return "stop"
end

local STUCK_COLLISIONBOX = {
	-0.25, -0.25, -0.25,
	0.25, 0.25, 0.25,
}

function ARROW_ENTITY:update_collisionbox ()
	-- When stuck, slightly expand the collisionbox to prevent
	-- this arrow from being rendered as completely unlit.
	if self._stuck then
		self.object:set_properties ({
			collisionbox = STUCK_COLLISIONBOX,
		})
	else
		self.object:set_properties ({
			collisionbox = ARROW_ENTITY.initial_properties.collisionbox,
		})
	end
end

function ARROW_ENTITY:set_stuck (new_pos, node)
	local selfobj = self.object
	local self_pos = selfobj:get_pos()
	local back_pos = self_pos
	if self._last_vel and vector.length(self._last_vel) > 0.001 then
		local dir = vector.normalize(self._last_vel)
		back_pos = vector.subtract(self_pos, vector.multiply(dir, 0.3))
	end
	self:cut_off(STUCK_ARROW_TIMEOUT, "keep fire")
	self._stuck = true
	self._is_critical = false
	self._dragtime = 0
	self._stuckrechecktimer = 0
	self._piercing = 0
	self._ignored = nil
	self._stuck_particle_timer = 0
	-- If there was a previous geyser spawner, stop it
	stop_stuck_effects(self)
	self._stuck_particle_timer = 0
	if not self._stuckin then
		self._stuckin = core.get_nodepos (new_pos)
	end
	selfobj:set_velocity(vector.new(0, 0, 0))
	selfobj:set_acceleration(vector.new(0, 0, 0))
	-- Ensure the stuck arrow itself keeps emitting light
	if self._projectile_light then
		selfobj:set_properties({light_source = self._projectile_light})
	end
	-- Spawn a persistent light helper while stuck
	if self._stuck_light then
		self._stuck_light:remove()
	end
	local light_ent = minetest.add_entity(back_pos or new_pos, "mcl_lun_bows:lunar_arrow_fly_light")
	if light_ent then
		local le = light_ent:get_luaentity()
		if le then
			le.timer = 0
			le.lifetime = STUCK_ARROW_TIMEOUT
		end
		self._stuck_light = light_ent
	end
	lun_sound("mcl_lun_bows_hit_other", {pos=self_pos, max_hear_distance=16, gain=0.6})
	lun_sound("se_kira00", {pos=self_pos, gain = 0.7, max_hear_distance = 32})
	selfobj:set_animation ({x = 10, y = 60,}, 210, 1.0, false)
	self._animtime = 0.0
	-- Start a continuous geyser spawner while stuck
	local center = back_pos or new_pos
	local resolved_normal = normalize_surface_normal(node and node.normal or {x=0,y=1,z=0})
	start_stuck_geyser(self, center, resolved_normal)

	local new_pos = mcl_util.get_nodepos (new_pos)
	local new_node = core.get_node (new_pos)
	local def = core.registered_nodes[new_node.name]
	if (def and def._on_arrow_hit) then   -- Entities: Button, Candle etc.
		def._on_arrow_hit(new_pos, self)
	else                                  -- Nodes: TNT, Campfire, Target etc.
		def = core.registered_nodes[node.name]
		if (def and def._on_arrow_hit) then
			def._on_arrow_hit(self._stuckin, self)
		end
	end
	self:update_collisionbox ()

	return "stop"
end

-- Hit a non-liquid node.  Either arrow could be stopped by engine or on its way to target.
function ARROW_ENTITY:on_solid_hit (node_pos, node, collisiondata)
	if not node then
		node = core.get_node(node_pos)
	end
	if node.name == "air" or node.name == "ignore" then return end
	local dir = vector.normalize (collisiondata.old_vel)
	local movement = vector.multiply (dir, 0.15)
	local pos = vector.add (collisiondata.new_pos, movement)
	self.object:move_to (pos)
	local collision_node = core.get_node (collisiondata.collision_pos)
	return self:set_stuck (collisiondata.new_pos, collision_node)
end

function ARROW_ENTITY:on_liquid_passthrough (node, def) ---@diagnostic disable-line: unused-local
	-- Slow down arrow in liquids. 8 water blocks shall kill most horizontal velocity.
	-- Water visco = 1, Lava visco = 7, but mc lava seems to not slowdown arrows a lot?
	--local v = def.liquid_viscosity or 0
	if not self._is_critical then
		self:multiply_xz_velocity (LIQUID_RATE)
	end
end

-- Handle "arrow hitting things".  Return "stop" if arrow is stopped by this thing.
function ARROW_ENTITY:on_intersect(ray_hit)
	local selfobj = self.object
	local result
	local ignored = self._ignored or {}
	local attach = self._shooter and self._shooter:get_attach ()
	if ray_hit.type == "object" then
		local obj = ray_hit.ref
		if obj:is_valid() and obj:get_hp() > 0
			and (obj ~= self._shooter or self._left_shooter)
			and (obj ~= attach or self._left_shooter)
			and table.indexof(ignored, obj) == -1 then
			if obj:is_player() then
				result = self:on_hit_player(obj, obj:get_luaentity(), ray_hit)
			else
				result = self:on_hit_object(obj, obj:get_luaentity(), ray_hit)
			end
			if result and result ~= "break" then
				table.insert(ignored, obj)
				local shooter = self._shooter
				local self_pos = selfobj:get_pos()
				local hit_pos = (ray_hit.intersection_point and ray_hit.intersection_point) or obj:get_pos() or self_pos
				if obj:is_player() and shooter and shooter:is_valid() and shooter:is_player() then
					-- "Ding" sound for hitting another player
					lun_sound("mcl_lun_bows_hit_player", {to_player=shooter:get_player_name(), gain=0.1})
				end
				damage_particles(hit_pos, self._is_critical, selfobj:get_velocity())
				lun_sound("mcl_lun_bows_hit_other", {pos=self_pos, max_hear_distance=16, gain=0.3})
				-- Reduce piercing if not stopped
				if result ~= "stop" then
					local piercing = self._piercing or 0
					if piercing <= 1 then
						self:remove()
						result = "stop"
					elseif piercing > 1 then
						self._piercing = piercing - 1
					end
				end
			end
		end
	elseif ray_hit.type == "node" then
		local hit_node_pos = core.get_pointed_thing_position(ray_hit)
		local hit_node_hash = core.hash_node_position (hit_node_pos)
		if table.indexof(ignored, hit_node_hash) == -1 then
			local hit_node = core.get_node (hit_node_pos)
			local def = core.registered_nodes[hit_node.name or ""]
			-- Set fire when passing through lava or fire, or put out fire when passing through water.
			if core.get_item_group(hit_node.name, "set_on_fire") > 0 then
				mcl_burning.set_on_fire(selfobj, ARROW_LIFETIME)
			elseif core.get_item_group(hit_node.name, "puts_out_fire") > 0 then
				mcl_burning.extinguish(selfobj)
			end

			if def and def.liquidtype ~= "none" then
				result = self:on_liquid_passthrough(hit_node, def)
			elseif def and def.walkable then
				self._stuckin = hit_node_pos
				result = self:on_solid_hit (hit_node_pos, hit_node, {
					old_vel = self.object:get_velocity (),
					new_pos = ray_hit.intersection_point or self.object:get_pos (),
					collision_pos = hit_node_pos,
			})
			end
			table.insert(ignored, hit_node_hash)
		end
	end
	if not self._ignored and #ignored > 0 then
		self._ignored = ignored
	end
	return result
end

function ARROW_ENTITY:find_first_collision (moveresult)
	local first_collision
	local max_len = -math.huge

	for _, collision in ipairs (moveresult.collisions) do
		local len = vector.length (collision.old_velocity)
		if max_len < len then
			first_collision = collision
			max_len = len
		end
	end
	if first_collision then
		return first_collision.old_velocity,
			first_collision.new_pos,
			first_collision.node_pos
	end
	return nil
end

function ARROW_ENTITY:on_step(dtime, moveresult)
	local selfobj = self.object
	local self_pos = selfobj:get_pos()
	if not self_pos then return end
	local last_pos = self:get_last_pos()

	self._lifetime = self._lifetime + dtime
	if self._lifetime > ARROW_LIFETIME then
		play_despawn_sound(self_pos)
		self:remove()
		return
	end

	if self._in_player or self._stuck then
		mcl_burning.tick(selfobj, dtime, self)
		if self._stuck then
			self:step_on_stuck(last_pos, dtime)
		end
		return
	end

	self:do_particle()

	-- Apply drag (skip for critical shots)
	if (not self._is_critical) and self._lifetime >= self._dragtime + DRAG_TICK then
		repeat
			self:multiply_xz_velocity(DRAG_RATE)
			self._dragtime = self._dragtime + DRAG_TICK
		until self._lifetime < self._dragtime + DRAG_TICK
	end

	local result = nil
	local shooter_located = false
	-- Raycasting movement during dtime to handle lava, water, and hits.
	local attach = self._shooter and self._shooter:get_attach ()
	for ray_hit in core.raycast(last_pos, self_pos, true, true) do
		if (self._shooter and ray_hit.ref == self._shooter)
			or (attach and ray_hit.ref == attach) then
			shooter_located = true
		end
		result = self:on_intersect(ray_hit)
		if result == "stop" or result == "break" then break end
	end
	if not shooter_located then
		self._left_shooter = true
	end

	-- Put out fire if exposed to rain, or if burning expires.
	mcl_burning.tick(selfobj, dtime, self)

	-- Look for colliding nodes within moveresult.
	if result ~= "stop" then
		local old_vel, new_pos, collision_pos
			= self:find_first_collision (moveresult)
		if collision_pos then
			self._stuckin = collision_pos
			local stuck_node = core.get_node (collision_pos)
			self:on_solid_hit (collision_pos, stuck_node, {
				old_vel = old_vel,
				new_pos = new_pos,
				collision_pos = collision_pos,
			})
		end
	end

	-- Predicting froward motion in anticipation of lag.  Pos and vel could be changed by shield.
	if result ~= "stop" then
		local vel = selfobj:get_velocity()
		self_pos = selfobj:get_pos()
		local predict = vector.add(self_pos, vector.multiply(vector.copy(vel), 0.05))
		for ray_hit in core.raycast(self_pos, predict, true, true) do
			if ray_hit.type == "node" then
				local hit_node_pos
					= core.get_pointed_thing_position (ray_hit)
				local hit_node = core.get_node (hit_node_pos)
				local def = core.registered_nodes[hit_node.name]
				if def and def.walkable then
					break -- Hit a node, stop prediction and defer to next step.
				end
			end
			result = self:on_intersect(ray_hit) -- Hit mob or player.
			if result == "stop" then break end
		end
	end

	-- Update yaw and internal variable.
	if not self._stuck then
		local vel = selfobj:get_velocity()
		if vel then
			if vector.length(vel) > 0.001 then
				self._last_vel = vel
			end
			local yaw = core.dir_to_yaw(vel)+YAW_OFFSET
			local pitch = dir_to_pitch(vel)
			selfobj:set_rotation({ x = 0, y = yaw, z = pitch })
		end
	end
	self._lastpos = self_pos
end

function ARROW_ENTITY:step_on_stuck(last_pos, dtime)
	local timer = ( self._stuckrechecktimer or 0 ) + dtime
	-- Drop arrow when it is no longer stuck
	if timer < STUCK_RECHECK_TIME then
		self._stuckrechecktimer = timer
		return
	end
	local t = self._animtime or 0.0
	self._animtime = t + dtime
	if t + dtime >= 0.30 then
		self.object:set_animation ({x = 0, y = 0,})
	end
	self._stuckrechecktimer = 0

	local self_pos = self.object:get_pos()
	-- Convert to a collectable item if a player is nearby (not in Creative Mode)
	for obj in core.objects_inside_radius(self_pos, PICKUP_RANGE) do
		if obj and obj:is_valid() and obj:is_player() and self._collectable then
			if not core.is_creative_enabled(obj:get_player_name()) then
				spawn_item(self, self_pos)
			end
					lun_sound("se_bonus2", {
						pos = self_pos,
						gain = 0.35 + (math.random(-1, 1) * 0.0025),
						max_hear_distance = 24,
						pitch = 1.0 + (math.random(-1, 1) * 0.025),
					})
			stop_stuck_spawner(self)
			self:remove()
			return
		end
	end

	if self._stuckin then
		local stuckin_name = core.get_node(self._stuckin).name
		if stuckin_name == "air" then
		-- local stuckin_def = core.registered_nodes[stuckin_name]
		-- if stuckin_def and stuckin_def.walkable == false then
			stop_stuck_spawner(self)
			self._stuck = false
			self._stuckin = nil
			self._startpos = self_pos
			self._lastpos = self_pos
			self._lifetime = 0
			self._dragtime = 0
			self._is_critical = false
			self.object:set_animation ({x = 0, y = 0,})
			self.object:set_acceleration({x=0, y=-GRAVITY, z=0})
			self:update_collisionbox ()
		end
	end
end

-- Force recheck of stuck arrows when punched.
-- Otherwise, punching has no effect.
function ARROW_ENTITY:on_punch()
	if self._stuck then
		self._stuckrechecktimer = STUCK_RECHECK_TIME
	end
end

function ARROW_ENTITY:get_staticdata()
	local out = {
		lastpos = self._lastpos,
		startpos = self._startpos,
		dragtime = self._dragtime,
		damage = self._damage,
		piercing = self._piercing,
		blocked = self._blocked,
		is_critical = self._is_critical,
		stuck = self._stuck,
		stuckin = self._stuckin,
		stuckin_player = self._in_player,
		itemstring = self._itemstring,
		projectile_light = self._projectile_light,
	}
	-- If _lifetime is missing for some reason, assume the maximum
	if not self._lifetime then
		self._lifetime = ARROW_LIFETIME
	end
	out.starttime = core.get_gametime() - self._lifetime
	if self._shooter and self._shooter:is_player() then
		out.shootername = self._shooter:get_player_name()
	end
	return core.serialize(out)
end

function ARROW_ENTITY:on_activate(staticdata)
	local data = core.deserialize(staticdata)
	if data then
		-- First, check if the arrow is already past its life timer. If
		-- yes, delete it. If starttime is nil always delete it.
		self._lifetime = core.get_gametime() - (data.starttime or 0)
		if self._lifetime > ARROW_LIFETIME or data.stuckin_player then
			self:remove()
			return
		end
		self._stuck = data.stuck
		if data.stuck then
			-- Perform a stuck recheck on the next step.
			self._stuckrechecktimer = STUCK_RECHECK_TIME
			self._stuckin = data.stuckin
		end

		-- Get the remaining arrow state
		self._lastpos = data.lastpos
		self._startpos = data.startpos or self.object:get_pos()
		self._dragtime = data.dragtime or 0
		self._damage = data.damage or 0
		self._piercing = data.piercing or 0
		self._blocked = data.blocked or false
		self._is_critical = data.is_critical or false
		self._itemstring = data.itemstring
		self._projectile_light = data.projectile_light or self._projectile_light
		self._is_arrow = true
		if data.shootername then
			local shooter = core.get_player_by_name(data.shootername)
			if shooter and shooter:is_player() then
				self._shooter = shooter
			end
		end
		self:update_collisionbox ()
		self:do_particle ()
	end
	if self._projectile_light then
		self.object:set_properties({light_source = self._projectile_light})
	end
	-- Restore gravity setting (critical arrows should stay perfectly straight).
	if self._is_critical then
		self.object:set_acceleration({x=0, y=0, z=0})
	else
		self.object:set_acceleration({x=0, y=-GRAVITY, z=0})
	end
	local tracked = false
    if wielded_light and wielded_light.track_item_entity then
        wielded_light.track_item_entity(self.object, "lunar_arrow", "mcl_lun_bows:lunar_arrow_light")
		tracked = true
		log_light("tracked arrow with wielded_light")
    else
		log_light("wielded_light unavailable for arrow tracking")
	end
	-- Fallback light entity if wielded_light is unavailable
	if not tracked then
		local light = minetest.add_entity(self.object:get_pos(), "mcl_lun_bows:lunar_arrow_fly_light")
		if light then
			light:set_attach(self.object, "", {x=0,y=0,z=0}, {x=0,y=0,z=0})
			log_light("spawned fallback fly light entity")
		end
	end
    self.object:set_armor_groups({ immortal = 1 })
end

function ARROW_ENTITY:on_deactivate()
	stop_stuck_spawner(self)
	self:stop_particle()
end

core.register_on_respawnplayer(function(player)
	for _, obj in pairs(player:get_children()) do
		local ent = obj:get_luaentity()
		if ent and ent.name and string.find(ent.name, "mcl_lun_bows:lunar_arrow_entity") then
			obj:remove()
		end
	end
end)

core.register_entity("mcl_lun_bows:lunar_arrow_entity", ARROW_ENTITY)

local lunar_arrow_explosion_light = {
    initial_properties = {
        physical = false,
        pointable = false,
        visual = "sprite",
        -- Use a transparent texture so no stray sprite appears.
        textures = {"mcl_potions_effect_invisible.png"},
        visual_size = {x = 0.01, y = 0.01},
        use_texture_alpha = true,
        light_source = 2,
    },
    timer = 0,
    lifetime = 0.35,
    start_light = 2,
    end_light = 5,
}

function lunar_arrow_explosion_light:on_activate()
    self.timer = 0
    if wielded_light and wielded_light.track_item_entity then
        wielded_light.track_item_entity(self.object, "lunar_arrow_explosion", "mcl_lun_bows:lunar_arrow_light")
        log_light("explosion light tracked via wielded_light")
    else
        log_light("explosion light fallback (wielded_light unavailable)")
    end
end

function lunar_arrow_explosion_light:on_step(dtime)
    self.timer = self.timer + dtime
    local life = self.lifetime or 0.35
    local progress = math.min(1, self.timer / life)
    local desired = math.floor(self.start_light + (self.end_light - self.start_light) * progress)
    if desired < 1 then
        desired = 1
    end
    if self.object then
        self.object:set_properties({light_source = desired})
    end
    if self.timer >= life then
        self.object:remove()
    end
end

minetest.register_entity("mcl_lun_bows:lunar_arrow_explosion_light", lunar_arrow_explosion_light)

-- Fallback light entity that follows the flying arrow when wielded_light tracking is unavailable
local lunar_arrow_fly_light = {
	initial_properties = {
		physical = false,
		pointable = false,
		visual = "sprite",
		textures = {"mcl_potions_effect_invisible.png"},
		visual_size = {x = 0.01, y = 0.01},
		use_texture_alpha = true,
		light_source = 8,
	},
	timer = 0,
	lifetime = 10,
}

function lunar_arrow_fly_light:on_activate()
	self.timer = 0
end

function lunar_arrow_fly_light:on_step(dtime)
	self.timer = self.timer + dtime
	if self.timer >= (self.lifetime or 10) then
		self.object:remove()
	end
end

minetest.register_entity("mcl_lun_bows:lunar_arrow_fly_light", lunar_arrow_fly_light)

if core.get_modpath("mcl_core") and core.get_modpath("mcl_mobitems") then
	core.register_craft({
		output = "mcl_lun_bows:lunar_arrow 4",
		recipe = {
			{"mcl_core:flint"},
			{"mcl_core:stick"},
			{"mcl_mobitems:feather"}
		}
	})
end

if core.get_modpath("doc_identifier") then
	doc.sub.identifier.register_object("mcl_lun_bows:lunar_arrow_entity", "craftitems", "mcl_lun_bows:lunar_arrow")
end
