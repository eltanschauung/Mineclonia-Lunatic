local S = minetest.get_translator("mcl_lun_items")
local color = rawget(_G, "color") or function(name) return name end
local mcl_enchanting = rawget(_G, "mcl_enchanting")
local mcl_util = rawget(_G, "mcl_util")
local mcl_burning = rawget(_G, "mcl_burning")
local wielded_light = rawget(_G, "wielded_light")
local mcl_lun_homing = rawget(_G, "mcl_lun_homing")
local prefix_api = rawget(_G, "mcl_lun_prefixes")
local mcl_bows = rawget(_G, "mcl_bows")
local mcl_lun_sounds = rawget(_G, "mcl_lun_sounds")
local build_lun_description -- forward declaration to silence early reference warnings
local build_lun_tt -- forward declaration (used in on_mods_loaded overrides)
local build_cone_limits -- forward declaration (used before definition)

local function lun_sound(name, params, ephemeral)
	if mcl_lun_sounds and mcl_lun_sounds.play then
		return mcl_lun_sounds.play(name, params, ephemeral)
	end
	return core.sound_play(name, params or {}, ephemeral == nil and true or ephemeral)
end

if mcl_bows and mcl_bows.set_texture_overrides then
	mcl_bows.set_texture_overrides({
		bow = "mcl_lun_items_bow.png",
		bow_0 = "mcl_lun_items_bow_0.png",
		bow_1 = "mcl_lun_items_bow_1.png",
		bow_2 = "mcl_lun_items_bow_2.png",
		arrow = "mcl_lun_items_arrow.png",
		arrow_entity = "mcl_lun_items_arrow.png",
	})
end

	local LIGHT_DIM_FACTOR = 0.7

	local ROD_SPEED = 25
	local ORB_DEFAULT_MAX_BOUNCES = 3
	local ORB_DEFAULT_MAX_LIFE = 6
	local ROD_FIRE_COOLDOWN = 0.8
	local ROD_META_KEY = "mcl_lun_items:rarity_init"
	local ORB_ROTATION_SPEED = math.rad(35)
local FAN_DEFAULTS = {
	projectile_initial_speed = 28,
	projectile_base_life = 0.9,
	projectile_var_life = 0.4,
	projectile_decay = 1.4,
	projectile_gravity = 22,
	projectile_min_speed = 0.5,
	projectile_damage = 5,
	projectile_offset = 1,
	cooldown = 0.35,
	projectile_light = 3,
	projectile_glow = 3,
}
local FAN_PARTICLE_COLOR = color("darkorange")
local FAN_PARTICLE_GLOW = 3
local FAN_PROJECTILE_LIGHT = 3
local MAPLE_PATTERN = {
	{x = 0, y = 0.5, z = 0},
	{x = 1, y = 0.6, z = 0},
	{x = -1, y = 0.6, z = 0},
	{x = 0, y = 0.7, z = 1},
	{x = 0, y = 0.7, z = -1},
	{x = 1, y = 0.4, z = 1},
	{x = -1, y = 0.4, z = -1},
	{x = 0, y = 0.8, z = 2},
	{x = 0, y = 0.8, z = -2},
}
local DEFAULT_ROD_EXPLOSION_RADIUS = 2
local DEFAULT_ORB_EXPLOSION_RADIUS = 1
local HOMING_ACCEL_DURATION = 1.0
local HOMING_INITIAL_SPEED_FACTOR = 0.2
local HOMING_CLOSE_DISTANCE = 1.0
local HOMING_CLOSE_RADIUS = 3
local TNT_EXPLODE_SOUND = "mcl_tnt_tnt_explode"
local ZOMBIE_COLLISION_VOLUME = 0.6 * 1.95 * 0.6

local rod_variants = {
	{
		name = "mcl_lun_items:purification_rod",
		description = S("Dusty Purification Rod"),
		base_description = S("Purification Rod"),
		prefix = "dusty",
		color = color("white"),
		luminance = 4,
		damage = 2,
		explosion_radius = 2,
	},
	{
		name = "mcl_lun_items:purification_rod_normal",
		description = S("Normal Purification Rod"),
		base_description = S("Purification Rod"),
		prefix = "normal",
		color = color("white"),
		luminance = 5,
		damage = 3,
		explosion_radius = 2,
	},
	{
		name = "mcl_lun_items:purification_rod_legendary",
		description = S("Legendary Purification Rod"),
		base_description = S("Purification Rod"),
		prefix = "legendary",
		luminance = 6,
		damage = 4,
		color = color("crimson"),
	},
}

local rod_index = {}
for _, def in ipairs(rod_variants) do
	rod_index[def.name] = def
end

local rod_descriptions = {}

local orb_variants = {
	{
		name = "mcl_lun_items:yin_yang_orb_precision",
		description = S("Yin Yang Orb - Precision"),
		texture = "yin_yang_orb_inventory.png",
		color = color("crimson"),
		groups = {misc = 1},
		luminance = 6,
		explosion_radius = 1,
		damage = 1,
	},
	{
		name = "mcl_lun_items:yin_yang_orb_homing",
		description = S("Yin Yang Orb - Homing"),
		texture = "yin_yang_orb_inventory_purple.png",
		color = color("purple"),
		groups = {misc = 1},
		luminance = 6,
		explosion_radius = 1,
		damage = 0.5,
	},
	{
		name = "mcl_lun_items:yin_yang_orb_bouncing",
		description = S("Yin Yang Orb - Bouncing"),
		texture = "yin_yang_orb_inventory_green.png",
		color = color("lime"),
		groups = {misc = 1},
		luminance = 6,
		explosion_radius = 1,
		damage = 2,
	},
}
local ORB_PARTICLE_TINTS = {
	homing = color("purple"),
	bouncing = color("lime"),
}

-- Ammo registry
local ammo_registry = {}

local function register_ammo(def)
	-- def.name (string), other fields free-form (type, gravity, damage, particle_color, model_texture, etc.)
	if not def or not def.name then return end
	ammo_registry[def.name] = def
end

-- Register ammo (yin-yang orbs, lunar arrow)
	register_ammo({
		name = "mcl_lun_items:yin_yang_orb_precision",
		type = "precision",
		max_bounces = 5,
		max_life = ORB_DEFAULT_MAX_LIFE,
		rotation_multiplier = 1,
		gravity = 0,
		bounce_damping = 1,
		model_texture = "yin_yang_orb.png",
		damage = 2,
	})
	register_ammo({
		name = "mcl_lun_items:yin_yang_orb_homing",
		type = "homing",
		max_bounces = 2,
		max_life = ORB_DEFAULT_MAX_LIFE,
		rotation_multiplier = 1,
		model_texture = "yin_yang_orb_purple.png",
		damage = 2,
		homing_range = 35,
	homing_fov = 0.85,
	homing_turn_rate = 5.5,
	particle_color = ORB_PARTICLE_TINTS.homing,
})
	register_ammo({
		name = "mcl_lun_items:yin_yang_orb_bouncing",
		type = "bouncing",
		max_bounces = 4,
		max_life = 60, -- So that they may fly into gigantic holes for spectacle
		rotation_multiplier = 2,
		gravity = -12,
		bounce_damping = 0.7,
		extra_vertical = 2,
	model_texture = "yin_yang_orb_green.png",
	damage = 2,
	particle_color = ORB_PARTICLE_TINTS.bouncing,
})
register_ammo({
	name = "mcl_lun_bows:lunar_arrow",
	type = "arrow",
	damage = 0, -- damage is handled in bow/arrow code; registry entry for completeness
})

local ammo_priority = {
	"mcl_lun_items:yin_yang_orb_precision",
	"mcl_lun_items:yin_yang_orb_homing",
	"mcl_lun_items:yin_yang_orb_bouncing",
}

local ammo_labels = {
	["mcl_lun_items:yin_yang_orb_precision"] = S("Precision"),
	["mcl_lun_items:yin_yang_orb_homing"] = S("Homing"),
	["mcl_lun_items:yin_yang_orb_bouncing"] = S("Bouncing"),
}

local player_selected_ammo = {}
local ITEM_STATS = {}
_G.mcl_lun_items_item_stats = ITEM_STATS
_G.item_stats = ITEM_STATS

local DEFAULT_LIGHT = 3

local function register_item_light(name, level)
	if not name or not wielded_light or not wielded_light.register_item_light then
		return
	end
	local val = level or DEFAULT_LIGHT
	wielded_light.register_item_light(name, val, false)
end

local function consume_orb_ammo(user)
	if not user or not user:is_player() then
		return nil
	end
	local inv = user:get_inventory()
	if not inv then
		return nil
	end
	local name = user:get_player_name()
	local preferred = player_selected_ammo[name]
	local creative = false
	if core.is_creative_enabled and name and name ~= "" then
		creative = core.is_creative_enabled(name)
	end
	local function take(name_to_take)
		local size = inv:get_size("main")
		for idx = 1, size do
			local stack = inv:get_stack("main", idx)
			if stack and stack:get_name() == name_to_take then
				player_selected_ammo[name] = name_to_take
				if not creative then
					stack:take_item(1)
					inv:set_stack("main", idx, stack)
				end
				return true
			end
		end
		return false
	end
	if preferred and ammo_registry[preferred] and take(preferred) then
		return ammo_registry[preferred], preferred
	end
	for _, name in ipairs(ammo_priority) do
		if take(name) then
			return ammo_registry[name], name
		end
	end
	return nil
end

local function is_yin_yang_orb(name)
	return name and name:find("mcl_lun_items:yin_yang_orb_", 1, true) == 1
end

local orb_drop_cfg = {
	color = color("grey"),
	texture = "mcl_particles_bonemeal.png",
	radius = 0.25,
	glow = math.max(1, math.floor(6 * LIGHT_DIM_FACTOR)),
	height = 1.2,
}

local DEFAULT_MOD_LIGHT = 3
local ROD_DURABILITY = 300
local light_schema = {}

-- Unified registry for lun items (particles, light, sounds, etc.)
local lun_item_registry = {}
local particle_settings = {}

local fan_tier_particle_names = {
    normal = "mcl_lun_races:hauchiwa_fan_normal",
    greater = "mcl_lun_races:hauchiwa_fan_greater",
}

-- Fan stats registry (damage, cooldown, projectile params)
local fan_stats = {}

local function register_fan_stats(name, stats)
	if not name or not stats then return end
	fan_stats[name] = stats
end

local function get_fan_stats(name)
	local stats = fan_stats[name]
	if stats then return stats end
	return {
		damage = FAN_DEFAULTS.projectile_damage,
		cooldown = FAN_DEFAULTS.cooldown,
		initial_speed = FAN_DEFAULTS.projectile_initial_speed,
		base_life = FAN_DEFAULTS.projectile_base_life,
		var_life = FAN_DEFAULTS.projectile_var_life,
		decay = FAN_DEFAULTS.projectile_decay,
		gravity = FAN_DEFAULTS.projectile_gravity,
		min_speed = FAN_DEFAULTS.projectile_min_speed,
		light = FAN_DEFAULTS.projectile_light,
		glow = FAN_DEFAULTS.projectile_glow,
	}
end

local function register_lun_item(def)
	-- def: {
	--   name = "itemstring" or {list},
	--   particle_color, particle_texture, particle_radius, particle_glow, particle_height,
	--   luminance, color,
	--   sounds = { ... } (reserved for future use)
	-- }
	if not def or not def.name then return end
	local names = type(def.name) == "table" and def.name or {def.name}
	for _, n in ipairs(names) do
		lun_item_registry[n] = {
			particle_color = def.particle_color,
			particle_texture = def.particle_texture,
			particle_radius = def.particle_radius,
			particle_glow = def.particle_glow,
			particle_height = def.particle_height,
			luminance = def.luminance,
			sounds = def.sounds,
			fan_stats = def.fan_stats,
			desc_color = def.color,
		}
		if def.particle_color then
			particle_settings[n] = {color = def.particle_color}
		end
		if def.luminance then
			light_schema[n] = def.luminance
			register_item_light(n, def.luminance)
		end
		if def.fan_stats then
			register_fan_stats(n, def.fan_stats)
		end
	end
end


local function make_orb_particle_cfg(color)
	if not color then
		return nil
	end
	return {
		color = color,
		texture = orb_drop_cfg.texture,
		radius = orb_drop_cfg.radius,
		glow = orb_drop_cfg.glow,
		height = orb_drop_cfg.height,
	}
end

local function build_particle_cfg(entry)
	if not entry or not entry.color then
		return nil
	end
	return make_orb_particle_cfg(entry.color)
end

local function particle_cfg_for_stack(stack)
    if not stack then
        return nil
    end
    if stack:is_empty() then
        return nil
    end
	local reg = lun_item_registry[stack:get_name()]
	if reg and reg.particle_color then
		return {
			color = reg.particle_color,
			texture = reg.particle_texture or orb_drop_cfg.texture,
			radius = reg.particle_radius or orb_drop_cfg.radius,
			glow = reg.particle_glow or orb_drop_cfg.glow,
			height = reg.particle_height or orb_drop_cfg.height,
		}
	end
    local cfg = particle_settings[stack:get_name()]
    if cfg then
        return build_particle_cfg(cfg)
    end
	local tier = stack:get_meta():get_string("mcl_lun_races:fan_tier")
	local fallback_name = tier and fan_tier_particle_names[tier]
	if fallback_name then
        local fallback_cfg = particle_settings[fallback_name]
        local built = build_particle_cfg(fallback_cfg)
        if built then
            return built
        end
	end
	local ammo_cfg = ammo_registry[stack:get_name()]
	if ammo_cfg and ammo_cfg.particle_color then
        return make_orb_particle_cfg(ammo_cfg.particle_color)
    end
    return nil
end

for _, orb in ipairs(orb_variants) do
	light_schema[orb.name] = 4
end

-- Register existing items into the unified registry
-- skip_stats = true tells the description builder not to append the auto-generated stat lines
--  (durability/damage/luminance/explosion radius) to the item’s description
register_lun_item({
	name = {
		"mcl_lun_items:purification_rod",
		"mcl_lun_items:purification_rod_normal",
		"mcl_lun_items:purification_rod_legendary",
	},
	particle_color = color("white"),
	luminance = 4,
})
register_lun_item({
	name = "mcl_lun_items:purification_rod_normal",
	particle_color = color("white"),
})
register_lun_item({
	name = "mcl_lun_items:purification_rod_legendary",
	particle_color = color("crimson"),
})
register_lun_item({
	name = "mcl_lun_races:hauchiwa_fan",
	luminance = 5,
	description = S("Hauchiwa Fan"),
	particle_color = color("purple"),
	color = color("grey"),
	tt_lines = {
		{text = S("Hauchiwa Fan"), color = color("grey")},
		{text = S("Fires a maple-leaf burst"), color = color("orange")},
		{text = S("Left click: arcing gust"), color = color("orange")},
	},
	fan_stats = {
		damage = 5,
		cooldown = FAN_DEFAULTS.cooldown,
		initial_speed = FAN_DEFAULTS.projectile_initial_speed,
		base_life = FAN_DEFAULTS.projectile_base_life,
		var_life = FAN_DEFAULTS.projectile_var_life,
		decay = FAN_DEFAULTS.projectile_decay,
		gravity = FAN_DEFAULTS.projectile_gravity,
		min_speed = FAN_DEFAULTS.projectile_min_speed,
		light = 6,
		glow = FAN_DEFAULTS.projectile_glow,
	},
})
register_lun_item({
	name = "mcl_lun_races:hauchiwa_fan_normal",
	description = S("Hauchiwa Fan"),
	particle_color = color("purple"),
	color = color("purple"),
	tt_lines = {
		{text = S("Hauchiwa Fan"), color = color("purple")},
		{text = S("Fires a maple-leaf burst"), color = color("orange")},
		{text = S("Left click: arcing gust"), color = color("orange")},
	},
	fan_stats = {
		damage = 5,
		cooldown = FAN_DEFAULTS.cooldown,
		initial_speed = FAN_DEFAULTS.projectile_initial_speed,
		base_life = FAN_DEFAULTS.projectile_base_life,
		var_life = FAN_DEFAULTS.projectile_var_life,
		decay = FAN_DEFAULTS.projectile_decay,
		gravity = FAN_DEFAULTS.projectile_gravity,
		min_speed = FAN_DEFAULTS.projectile_min_speed,
		light = 8,
		glow = FAN_DEFAULTS.projectile_glow,
	},
})
register_lun_item({
	name = "mcl_lun_races:hauchiwa_fan_greater",
	description = S("Greater Hauchiwa Fan"),
	particle_color = color("orange"),
	color = color("orange"),
	tt_lines = {
		{text = S("Greater Hauchiwa Fan"), color = color("orange")},
		{text = S("Fires a maple-leaf burst"), color = color("orange")},
		{text = S("Left click: arcing gust"), color = color("orange")},
	},
	fan_stats = {
		damage = 6,
		cooldown = FAN_DEFAULTS.cooldown,
		initial_speed = FAN_DEFAULTS.projectile_initial_speed,
		base_life = FAN_DEFAULTS.projectile_base_life,
		var_life = FAN_DEFAULTS.projectile_var_life,
		decay = FAN_DEFAULTS.projectile_decay,
		gravity = FAN_DEFAULTS.projectile_gravity,
		min_speed = FAN_DEFAULTS.projectile_min_speed,
		light = 10,
		glow = FAN_DEFAULTS.projectile_glow,
	},
})
-- Yin-yang orbs (ammo variants)
for _, orb in ipairs(orb_variants) do
	register_lun_item({
		name = orb.name,
		particle_color = color(orb.particle_color or orb.color or "#9e9e9e"),
		light_level = DEFAULT_LIGHT,
	})
end
register_lun_item({
	name = {
		"mcl_lun_bows:lunar_bow_weakened",
		"mcl_lun_bows:lunar_bow_normal",
		"mcl_lun_bows:lunar_bow_legendary",
	},
	particle_color = color("lightblue"),
	particle_glow = 10,
})
register_lun_item({
	name = "mcl_lun_bows:lunar_arrow",
	particle_color = color("crimson"),
	particle_glow = 10,
	luminance = 6,
})

local function get_mod_light(name)
	return light_schema[name] or DEFAULT_MOD_LIGHT
end

local function register_schema_lighting()
	if not wielded_light or not wielded_light.register_item_light then
		return
	end
	local function reg(name, level)
		if not name or not level then return end
		local dim = math.max(1, math.floor((level or DEFAULT_LIGHT) * LIGHT_DIM_FACTOR))
		register_item_light(name, dim)
	end
	-- Prefer registry entries
	for name, def in pairs(lun_item_registry) do
		if def.luminance then
			reg(name, def.luminance)
		end
	end
end

local function cycle_ammo_type(itemstack, user, pointed_thing)
	if not user or not user:is_player() then
		return itemstack
	end
	local inv = user:get_inventory()
	if not inv then
		return itemstack
	end
	local name = user:get_player_name()
	local available = {}
	for _, ammo in ipairs(ammo_priority) do
		if inv:contains_item("main", ItemStack(ammo)) then
			available[#available + 1] = ammo
		end
	end
	if #available == 0 then
		minetest.chat_send_player(name, S("No Yin-Yang Orbs available."))
		return itemstack
	end
	local current = player_selected_ammo[name]
	local next_idx = 1
	for idx, ammo in ipairs(available) do
		if ammo == current then
			next_idx = idx % #available + 1
			break
		end
	end
	local selected = available[next_idx]
	player_selected_ammo[name] = selected
	minetest.chat_send_player(name, S("Selected ammo: @1", ammo_labels[selected] or selected))
	return itemstack
end

local function call_node_rightclick_first(itemstack, user, pointed_thing)
	if mcl_util and mcl_util.call_on_rightclick and pointed_thing and pointed_thing.type == "node" then
		local rc = mcl_util.call_on_rightclick(itemstack, user, pointed_thing)
		if rc then
			return rc
		end
	end
	return nil
end

	local function cycle_ammo_on_place(itemstack, placer, pointed_thing)
		local rc = call_node_rightclick_first(itemstack, placer, pointed_thing)
		if rc then
			return rc
		end
		return cycle_ammo_type(itemstack, placer, pointed_thing)
	end

		local rod_cooldowns = {}
		local lampad_side_toggle = {}

	local FIRE_DEBUG = true
	if minetest.settings then
		FIRE_DEBUG = minetest.settings:get_bool("mcl_lun_items_debug_fire", true)
	end

	local function debug_fire(user, msg)
		if not FIRE_DEBUG then
			return
		end
		local pname = (user and user.get_player_name and user:get_player_name()) or "<unknown>"
		minetest.log("action", ("[mcl_lun_items][fire] %s player=%s"):format(msg or "", pname))
	end

	local function monotonic_us()
		if core.get_us_time then
			return core.get_us_time()
		end
		return core.get_gametime() * 1000000
	end

	local function seconds_to_us(seconds)
		return math.floor((tonumber(seconds) or 0) * 1000000 + 0.5)
	end

	local function rod_ready(user, ctx)
		local name = user and user:get_player_name()
		if not name or name == "" then
			return true
		end
		local now = monotonic_us()
		if type(now) ~= "number" then
			now = core.get_gametime() * 1000000
		end
		local next_allowed = rod_cooldowns[name] or 0
		if now < next_allowed then
			if FIRE_DEBUG then
				debug_fire(user, ("cooldown_block ctx=%s now=%d next=%d wait_us=%d"):format(tostring(ctx or ""), now, next_allowed, next_allowed - now))
			end
			return false
		end
		rod_cooldowns[name] = now + seconds_to_us(ROD_FIRE_COOLDOWN)
		if FIRE_DEBUG then
			debug_fire(user, ("cooldown_allow ctx=%s now=%d next=%d"):format(tostring(ctx or ""), now, rod_cooldowns[name]))
		end
		return true
	end

local function spawn_purification_orb(user, stack_table, ammo_def, ammo_name, rod_stats, homing_target, projectile_count, projectile_delay, projectile_name, fire_sound)
	-- Backwards-compatible signature:
	--   spawn_purification_orb(user, stack, ammo, name, stats, target, projectile_name, fire_sound)
	if type(projectile_count) == "string" or projectile_count == nil then
		projectile_name = projectile_count
		fire_sound = projectile_delay
		projectile_count = nil
		projectile_delay = nil
	end

	projectile_count = math.max(1, math.floor(tonumber(projectile_count) or 1))
	projectile_delay = tonumber(projectile_delay) or 0
	if projectile_delay < 0 then
		projectile_delay = 0
	end

	local function spawn_one()
		if not user or not user:is_player() then
			return
		end
		local pos = user:get_pos()
		if not pos then
			return
		end
		local dir = user:get_look_dir()
		local spawn = vector.add(pos, vector.multiply(dir, 0.8))
		spawn.y = spawn.y + 1.5
		minetest.log("action", "[purif] spawn at "..minetest.pos_to_string(spawn).." dir "..minetest.serialize(dir))
		lun_sound(fire_sound or "se_plst00", {pos = spawn, gain = 0.4, max_hear_distance = 32})
		local entity_name = projectile_name or "mcl_lun_items:purification_rod_projectile"
		local obj = minetest.add_entity(spawn, entity_name)
		if obj then
			local lua = obj:get_luaentity()
			if lua and lua.initialize then
				local stack
				if stack_table then
					stack = ItemStack(stack_table)
				end
				lua:initialize(user, stack, dir, ammo_def, ammo_name, rod_stats, homing_target)
			end
		end
	end

	spawn_one()
	for i = 2, projectile_count do
		minetest.after((i - 1) * projectile_delay, spawn_one)
	end
end

if wielded_light and wielded_light.register_item_light then
	-- Dummy item identifier used purely for wielded_light tracking
	wielded_light.register_item_light("mcl_lun_items:purification_rod_orb_light", 12, false)
	wielded_light.register_item_light("mcl_lun_items:yin_yang_orb_drop_light", 6, false)
	wielded_light.register_item_light("mcl_lun_items:lampad_explosion_light", 14, false)
	wielded_light.register_item_light("mcl_lun_items:flag_corner_light", 14, false)
end

register_schema_lighting()

local orb_particle_textures = {
	"touhou_particle_red_32x_1.png",
	"touhou_particle_red_32x_2.png",
	"touhou_particle_red_32x_3.png",
	"touhou_particle_red_32x_4.png",
	"touhou_particle_red_32x_5.png",
	"touhou_particle_red_32x_6.png",
	"touhou_particle_red_32x_7.png",
	"touhou_particle_red_32x_8.png",
}

	local function apply_explosion_damage(pos, damage, reason, radius)
		if not pos or not damage or damage <= 0 then
			return
		end
	local effective_radius = radius or (DEFAULT_ROD_EXPLOSION_RADIUS + DEFAULT_ORB_EXPLOSION_RADIUS)
	local search_radius = math.max(effective_radius, 0.1)
	local targets = minetest.get_objects_inside_radius(pos, search_radius)
	if not targets or #targets == 0 then
		return
	end
	local final_reason = reason or {type = "projectile"}
	for _, obj in ipairs(targets) do
		if not obj then
			goto continue
		end
		local lua = obj:get_luaentity()
		if lua and lua.name == "__builtin:item" then
			goto continue
		end
		if mcl_util and mcl_util.deal_damage then
			mcl_util.deal_damage(obj, damage, final_reason)
		elseif obj.punch then
			obj:punch(final_reason.source or obj, 0.0, {
				full_punch_interval = 1,
				damage_groups = {fleshy = damage},
			}, nil)
		end
		::continue::
		end
	end

		local function apply_flat_damage(pos, damage, reason, radius, height, already_hit)
			if not pos or not damage or damage <= 0 or not radius or radius <= 0 then
				return
			end
			local half_height = (height or 0.5) * 0.5
			local pos_y = pos.y or 0
			local slab_min_y = pos_y - half_height
			local slab_max_y = pos_y + half_height
			local targets = minetest.get_objects_inside_radius(pos, radius)
			if not targets or #targets == 0 then
				return
			end
		local final_reason = reason or {type = "projectile"}
		for _, obj in ipairs(targets) do
			if not obj then
				goto continue
			end
			local lua = obj:get_luaentity()
			if lua and lua.name == "__builtin:item" then
				goto continue
			end
			if already_hit and already_hit[obj] then
				goto continue
			end
				local op = obj:get_pos()
				if not op then
					goto continue
				end
				local obj_y = op.y or 0
				local obj_min_y = obj_y
				local obj_max_y = obj_y
				local props = obj.get_properties and obj:get_properties() or nil
				local cb = props and props.collisionbox
				if type(cb) == "table" and cb[2] ~= nil and cb[5] ~= nil then
					obj_min_y = obj_y + (cb[2] or 0)
					obj_max_y = obj_y + (cb[5] or 0)
					if obj_min_y > obj_max_y then
						obj_min_y, obj_max_y = obj_max_y, obj_min_y
					end
				end
				if obj_max_y < slab_min_y or obj_min_y > slab_max_y then
					goto continue
				end
				if mcl_util and mcl_util.deal_damage then
					mcl_util.deal_damage(obj, damage, final_reason)
			elseif obj.punch then
				obj:punch(final_reason.source or obj, 0.0, {
					full_punch_interval = 1,
					damage_groups = {fleshy = damage},
				}, nil)
			end
			if already_hit then
				already_hit[obj] = true
			end
			::continue::
		end
	end

	local function spawn_particle_burst(config)
		if not config or not config.center then
			return
		end
	local normal = config.normal or {x = 0, y = 1, z = 0}
	local height_offset = config.height_offset or config.height or 0.5
	local center = vector.add(config.center, vector.multiply(normal, height_offset))
	if config.sound and config.sound.name then
		local sound_params = config.sound.params or {}
		sound_params.object = config.sound.object
		sound_params.pos = config.sound.pos or center
		core.sound_play(config.sound.name, sound_params, true)
	end
	local minvel, maxvel
	if config.cone then
		minvel, maxvel = build_cone_limits(config.cone_dir or normal, config.cone_mag or 1, config.cone_spread or 0.4)
	else
		minvel = config.minvel or {x = -1, y = -1, z = -1}
		maxvel = config.maxvel or {x = 1, y = 1, z = 1}
	end
	local textures = config.textures or orb_particle_textures
	local amount = config.amount or 3
	local spread = config.pos_spread or 0
	local minpos = center
	local maxpos = center
	if spread and spread > 0 then
		minpos = vector.add(center, {x = -spread, y = -spread, z = -spread})
		maxpos = vector.add(center, {x = spread, y = spread, z = spread})
	end
	local return_ids = config.return_id
	local ids
	local tint_choices = config.tint_choices
	local function distribute_amount(total, n)
		if n <= 0 or total <= 0 then
			return {}
		end
		local base = math.floor(total / n)
		if base <= 0 then
			local out = {}
			out[1] = total
			for i = 2, n do
				out[i] = 0
			end
			return out
		end
		local rem = total - base * n
		local out = {}
		for i = 1, n do
			out[i] = base + (i <= rem and 1 or 0)
		end
		return out
	end
	for _, tex in ipairs(textures) do
		if tint_choices and type(tint_choices) == "table" and #tint_choices > 0 then
			local amounts = distribute_amount(amount, #tint_choices)
			for i, tint in ipairs(tint_choices) do
				local amt = amounts[i] or 0
				if amt > 0 then
					local texture = tex .. "^[colorize:" .. tint .. ":180"
					local id = core.add_particlespawner({
						amount = amt,
						time = config.time or 0.1,
						minpos = minpos,
						maxpos = maxpos,
						minvel = minvel,
						maxvel = maxvel,
						minsize = config.minsize or 1,
						maxsize = config.maxsize or 2,
						glow = config.glow or math.max(1, math.floor(8 * LIGHT_DIM_FACTOR)),
						texture = texture,
					})
					if return_ids then
						ids = ids or {}
						table.insert(ids, id)
					end
				end
			end
		else
			local texture = tex
			if config.tint then
				texture = texture .. "^[colorize:" .. config.tint .. ":180"
			end
			local id = core.add_particlespawner({
				amount = amount,
				time = config.time or 0.1,
				minpos = minpos,
				maxpos = maxpos,
				minvel = minvel,
				maxvel = maxvel,
				minsize = config.minsize or 1,
				maxsize = config.maxsize or 2,
				glow = config.glow or math.max(1, math.floor(8 * LIGHT_DIM_FACTOR)),
				texture = texture,
			})
			if return_ids then
				ids = ids or {}
				table.insert(ids, id)
			end
		end
	end
	if config.light_entity then
		minetest.add_entity(center, config.light_entity)
	end
	local damage = config.damage
	if damage then
		apply_explosion_damage(center, damage, config.reason, config.radius)
	end
	if return_ids then
		return ids
	end
end

local ORB_DROP_REFRESH = 0.25
local orb_drop_timer = 0
	local function is_purification_rod(name)
		return name and rod_index[name] ~= nil
	end

	local function ensure_purification_stack(stack)
		if not stack or stack:is_empty() or not is_purification_rod(stack:get_name()) then
			return stack
		end
	-- Disable prefix mutations for rods to keep descriptions stable.
	local meta = stack:get_meta()
	meta:set_string(ROD_META_KEY, "1")
	return stack
end

local function refresh_purification_stack(inv, listname, index)
	if not inv or not listname or not index then
		return
	end
	local stack = inv:get_stack(listname, index)
	if stack:is_empty() or not is_purification_rod(stack:get_name()) then
		return
	end
	local updated = ensure_purification_stack(stack)
	inv:set_stack(listname, index, updated)
end

core.register_on_player_inventory_action(function(player, action, inventory, info)
	if not inventory or type(info) ~= "table" then
		return
	end
	local function handle(listname, index)
		if listname and index then
			refresh_purification_stack(inventory, listname, index)
		end
	end
	if action == "move" then
		handle(info.from_list, info.from_index)
		handle(info.to_list, info.to_index)
	elseif action == "put" or action == "take" then
		handle(info.list, info.index)
	end
end)

local function initialize_purification_inventory(player)
	local inv = player and player:get_inventory()
	if not inv then
		return
	end
	for _, listname in ipairs({"main", "craft", "hand"}) do
		local list = inv:get_list(listname)
		if list then
			for idx, stack in ipairs(list) do
				if not stack:is_empty() and is_purification_rod(stack:get_name()) then
					inv:set_stack(listname, idx, ensure_purification_stack(stack))
				end
			end
		end
	end
end

core.register_on_craft(function(itemstack)
	if itemstack and not itemstack:is_empty() and is_purification_rod(itemstack:get_name()) then
		itemstack = ensure_purification_stack(itemstack)
	end
	return itemstack
end)

if core.register_on_item_drop then
	core.register_on_item_drop(function(player, itemstack, dropper)
		if not itemstack or itemstack:is_empty() then
			return itemstack
		end
		if is_purification_rod(itemstack:get_name()) then
			itemstack = ensure_purification_stack(itemstack)
		end
		return itemstack
	end)
end

core.register_on_joinplayer(function(player)
	initialize_purification_inventory(player)
	local name = player and player:get_player_name()
	if name and name ~= "" then
		lampad_side_toggle[name] = false
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player and player:get_player_name()
	if name and name ~= "" then
		lampad_side_toggle[name] = nil
	end
end)

local inv_refresh_timer = 0
core.register_globalstep(function(dtime)
	inv_refresh_timer = inv_refresh_timer + dtime
	if inv_refresh_timer < 1 then
		return
	end
	inv_refresh_timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		initialize_purification_inventory(player)
	end
end)

build_cone_limits = function(dir, magnitude, spread)
	local base = vector.normalize(dir or {x = 0, y = 1, z = 0})
	local mag = magnitude or 1
	local sp = spread or 0.6
	local minv = {
		x = base.x * mag - sp,
		y = base.y * mag - sp,
		z = base.z * mag - sp,
	}
	local maxv = {
		x = base.x * mag + sp,
		y = base.y * mag + sp,
		z = base.z * mag + sp,
	}
	local function ensure_upward(vec)
		if vec.y < 0 then
			vec.y = -vec.y
		end
		return vec
	end
	return ensure_upward(minv), ensure_upward(maxv)
end

local function play_snowball_effect(pos, color, damage, reason, radius, normal, cone, cone_dir, particle_scale, particle_amount_mult, particle_vel_mult, tint_choices, textures_override, particle_time, pos_spread, glow_override, light_entity_override)
	if not pos then
		return
	end
	local scale = particle_scale or 1
	local amount_mult = particle_amount_mult or 1
	local vel_mult = particle_vel_mult or 1
	if scale < 0.1 then
		scale = 0.1
	end
	if amount_mult < 0.1 then
		amount_mult = 0.1
	end
	if vel_mult < 0.1 then
		vel_mult = 0.1
	end
	local config = {
		center = pos,
		normal = normal,
		height = 0.5,
		textures = textures_override or orb_particle_textures,
		tint = color,
		tint_choices = tint_choices,
		cone = cone,
		cone_dir = cone_dir,
		cone_mag = 1 * vel_mult,
		glow = glow_override or 8,
		amount = math.max(1, math.floor(3 * amount_mult)),
		minsize = 1 * scale,
		maxsize = 2 * scale,
		time = particle_time,
		pos_spread = pos_spread,
		sound = {
			name = "se_kira00",
			params = {gain = 0.9, max_hear_distance = 32},
		},
		light_entity = light_entity_override or "mcl_lun_items:purification_rod_explosion_light",
		damage = damage,
		reason = reason,
		radius = radius,
	}
	spawn_particle_burst(config)
end

local function spawn_bounce_particles(pos, color)
	if not pos then
		return
	end
	local config = {
		center = pos,
		textures = orb_particle_textures,
		height = 0,
		tint = color,
		glow = 8,
		amount = 1,
		time = 0.08,
		minsize = 0.5,
		maxsize = 1.0,
		minvel = {x = -0.1, y = 0.2, z = -0.1},
		maxvel = {x = 0.1, y = 0.45, z = 0.1},
		light_entity = "mcl_lun_items:purification_rod_bounce_light",
	}
	spawn_particle_burst(config)
end

-- mcl_particles textures found in the tree:
-- games/lunatic/mods/ITEMS/mcl_totems/textures/mcl_particles_totem1.png
-- games/lunatic/mods/ITEMS/mcl_totems/textures/mcl_particles_totem2.png
-- games/lunatic/mods/ITEMS/mcl_totems/textures/mcl_particles_totem3.png
-- games/lunatic/mods/ITEMS/mcl_totems/textures/mcl_particles_totem4.png
-- games/lunatic/mods/ITEMS/mcl_portals/textures/mcl_particles_nether_portal.png
-- games/lunatic/mods/ITEMS/mcl_portals/textures/mcl_particles_nether_portal_t.png
-- games/lunatic/mods/ITEMS/mcl_bone_meal/textures/mcl_particles_bonemeal.png
-- games/lunatic/mods/ITEMS/mcl_core/textures/mcl_particles_lava.png
-- games/lunatic/mods/ITEMS/mcl_end/textures/mcl_particles_teleport.png
-- games/lunatic/mods/ITEMS/mcl_sponges/textures/mcl_particles_sponge1.png
-- games/lunatic/mods/ITEMS/mcl_sponges/textures/mcl_particles_sponge2.png
-- games/lunatic/mods/ITEMS/mcl_sponges/textures/mcl_particles_sponge3.png
-- games/lunatic/mods/ITEMS/mcl_sponges/textures/mcl_particles_sponge4.png
-- games/lunatic/mods/ITEMS/mcl_sponges/textures/mcl_particles_sponge5.png
-- games/lunatic/mods/ITEMS/REDSTONE/mcl_noteblock/textures/mcl_particles_note.png
-- games/lunatic/mods/ITEMS/mcl_potions/textures/mcl_particles_droplet_bottle.png
-- games/lunatic/mods/ITEMS/mcl_potions/textures/mcl_particles_effect.png
-- games/lunatic/mods/ITEMS/mcl_potions/textures/mcl_particles_instant_effect.png
-- games/lunatic/mods/ENVIRONMENT/mcl_weather/textures/mcl_particles_nether_dust1.png
-- games/lunatic/mods/ENVIRONMENT/mcl_weather/textures/mcl_particles_nether_dust2.png
-- games/lunatic/mods/ENVIRONMENT/mcl_weather/textures/mcl_particles_nether_dust3.png
-- games/lunatic/mods/CORE/mcl_explosions/textures/mcl_particles_smoke.png
-- games/lunatic/mods/ENTITIES/mobs_mc/textures/mcl_particles_angry_villager.png
-- games/lunatic/mods/ENTITIES/mobs_mc/textures/mcl_particles_dragon_breath_1.png
-- games/lunatic/mods/ENTITIES/mobs_mc/textures/mcl_particles_dragon_breath_2.png
-- games/lunatic/mods/ENTITIES/mobs_mc/textures/mcl_particles_dragon_breath_3.png
-- games/lunatic/mods/ENTITIES/mobs_mc/textures/mcl_particles_fire_flame.png
-- games/lunatic/mods/ENTITIES/mobs_mc/textures/mcl_particles_smoke_anim.png
-- games/lunatic/mods/ENTITIES/mobs_mc/textures/mcl_particles_soul_fire_flame.png
-- games/lunatic/mods/ENTITIES/mobs_mc/textures/mcl_particles_squid_ink.png
-- games/lunatic/mods/ENTITIES/mobs_mc/textures/mcl_particles_squid_ink_1.png
-- games/lunatic/mods/ENTITIES/mobs_mc/textures/mcl_particles_squid_ink_2.png
-- games/lunatic/mods/ENTITIES/mcl_mobs/textures/mcl_particles_mob_death.png
-- games/lunatic/mods/PLAYER/mcl_criticals/textures/mcl_particles_crit.png
-- games/lunatic/mods/PLAYER/mcl_player/textures/mcl_particles_bubble.png
-- games/lunatic/textures/server/FaithfulClone32x/mcl_particles_soul_fire_flame.png
local HAUCHIWA_MAPLE_32 = {"hauchiwa_maple_32px.png"}
local HAUCHIWA_MAPLE_16 = {"hauchiwa_maple_16px.png"}
local HAUCHIWA_PARTICLE_TEXTURE = "mcl_particles_smoke_anim.png"
local function damage_at_position(pos, damage, reason)
	if not pos then return end
	apply_explosion_damage(pos, damage, reason, 1.0)
end

local function random_maple_velocity()
	return {
		x = -0.2 + math.random() * 0.4,
		y = 0.2 + math.random() * 0.4,
		z = -0.2 + math.random() * 0.4,
	}
end

	local function spawn_maple_leaf_particles(pos, light_entity)
		if not pos then
			return
		end
		for _, offset in ipairs(MAPLE_PATTERN) do
		local center = vector.add(pos, offset)
		local count32 = math.random(1, 2)
		local count16 = math.random(2, 3)
		for i = 1, count32 do
			spawn_particle_burst({
				center = center,
				textures = HAUCHIWA_MAPLE_32,
				amount = 1,
				time = 0.12,
				minsize = 0.8,
				maxsize = 1.2,
				glow = 8,
				minvel = random_maple_velocity(),
				maxvel = {
					x = 0.2 + math.random() * 0.2,
					y = 0.8 + math.random() * 0.3,
					z = 0.2 + math.random() * 0.2,
				},
				light_entity = light_entity,
			})
		end
		for i = 1, count16 do
			spawn_particle_burst({
				center = center,
				textures = HAUCHIWA_MAPLE_16,
				amount = 1,
				time = 0.12,
				minsize = 0.4,
				maxsize = 0.7,
				glow = 8,
				minvel = random_maple_velocity(),
				maxvel = {
					x = 0.4 + math.random() * 0.2,
					y = 1.0 + math.random() * 0.3,
					z = 0.4 + math.random() * 0.2,
				},
				light_entity = light_entity,
			})
			end
		end
	end

				local function spawn_us_flag_particles(pole_origin, facing_dir, width, height, spacing, particle_size)
					if not pole_origin then
						return
					end
					width = tonumber(width) or 11
					height = tonumber(height) or 9
					spacing = tonumber(spacing) or 0.4
					particle_size = tonumber(particle_size) or 3.6
					if width < 1 or height < 1 or spacing <= 0 or particle_size <= 0 then
						return
					end

					-- "Stand up" orientation: vertical plane facing the look direction.
					local up = {x = 0, y = 1, z = 0}
					local normal = vector.normalize(facing_dir or {x = 0, y = 0, z = 1})
					normal = {x = normal.x, y = 0, z = normal.z}
					if vector.length(normal) < 0.001 then
						normal = {x = 0, y = 0, z = 1}
					else
						normal = vector.normalize(normal)
					end
					local right = vector.cross(up, normal)
					if vector.length(right) < 0.001 then
						right = {x = 1, y = 0, z = 0}
					else
						right = vector.normalize(right)
					end
					local down = {x = 0, y = -1, z = 0}

					local canton_w = math.max(1, math.min(width, math.floor(width * 0.4 + 0.5) + 2))
					local canton_h = math.max(1, math.floor(height * 7 / 13 + 0.5))

					local lifetime = 2.0
					local pole_len = 4

					-- Clamp pole origin to ground, then translate the whole formation up by one canton.
					do
						local function node_walkable(pos)
							local node = core.get_node_or_nil(pos)
							if not node then
								return false
							end
							local def = core.registered_nodes[node.name]
							return def and def.walkable
						end
						local grounded = false
						local endpos = vector.add(pole_origin, {x = 0, y = -40, z = 0})
						for hit in core.raycast(pole_origin, endpos, false, true) do
							if hit.type == "node" and hit.under and node_walkable(hit.under) then
								pole_origin = {x = pole_origin.x, y = hit.under.y + 1.02, z = pole_origin.z}
								grounded = true
								break
							end
						end
						if not grounded then
							pole_origin = {x = pole_origin.x, y = math.floor(pole_origin.y) + 1.02, z = pole_origin.z}
						end

					end

					-- Flag starts pole_len pixels above the pole origin.
					local bottom_left = vector.add(pole_origin, vector.multiply(up, pole_len * spacing))
					local base = vector.add(bottom_left, vector.multiply(up, (height - 1) * spacing))

					local corners = {
						base, -- top-left
						vector.add(base, vector.multiply(right, (width - 1) * spacing)), -- top-right
						bottom_left, -- bottom-left
						vector.add(bottom_left, vector.multiply(right, (width - 1) * spacing)), -- bottom-right
					}
					for _, pos in ipairs(corners) do
						minetest.add_entity(pos, "mcl_lun_items:flag_corner_light")
					end

					local function add_pixel(pos, tint)
						core.add_particle({
							pos = pos,
							velocity = {x = 0, y = 0, z = 0},
							acceleration = {x = 0, y = 0, z = 0},
							expirationtime = lifetime,
							size = particle_size,
							texture = "mcl_particles_bonemeal.png^[colorize:" .. tint .. ":200",
							glow = 14,
						})
					end

					-- Pole (origin at bottom).
					for i = 0, pole_len - 1 do
						add_pixel(vector.add(pole_origin, vector.multiply(up, i * spacing)), "white")
					end

					for row = 0, height - 1 do
						local stripe_is_red = (row % 2) == 0
						for col = 0, width - 1 do
							local tint
							if row < canton_h and col < canton_w then
								tint = (((row + col) % 2) == 0) and "white" or "blue"
							else
								tint = stripe_is_red and "red" or "white"
							end
							local pos = vector.add(base, vector.add(vector.multiply(right, col * spacing), vector.multiply(down, row * spacing)))
							add_pixel(pos, tint)
						end
					end
					return pole_origin
				end
	local function spawn_geyser_particles(pos, light_entity)
		if not pos then
			return
		end
	for _, offset in ipairs(MAPLE_PATTERN) do
		local center = vector.add(pos, offset)
		for i = 1, 2 do
			spawn_particle_burst({
				center = center,
				textures = HAUCHIWA_MAPLE_32,
				amount = 1,
				time = 0.12,
				minsize = 1.2,
				maxsize = 1.8,
				glow = 10,
				minvel = random_maple_velocity(),
				maxvel = {
					x = 0.6 + math.random() * 0.3,
					y = 1.2 + math.random() * 0.4,
					z = 0.6 + math.random() * 0.3,
				},
				light_entity = light_entity,
			})
		end
		for i = 1, 3 do
			spawn_particle_burst({
				center = center,
				textures = HAUCHIWA_MAPLE_16,
				amount = 1,
				time = 0.12,
				minsize = 0.6,
				maxsize = 0.9,
				glow = 10,
				minvel = random_maple_velocity(),
				maxvel = {
					x = 0.5 + math.random() * 0.2,
					y = 1.3 + math.random() * 0.4,
					z = 0.5 + math.random() * 0.2,
				},
			})
		end
	end
end

local function is_player_grounded(player)
	if not player then
		return false
	end
	local pos = player:get_pos()
	if not pos then
		return false
	end
	local below = vector.floor(vector.subtract(pos, {x = 0, y = 0.2, z = 0}))
	local node = core.get_node_or_nil(below)
	if not node then
		return false
	end
	local def = core.registered_nodes[node.name]
	return def and def.walkable
end

local function is_walkable(pos)
	local node = core.get_node_or_nil(pos)
	if not node then
		return false
	end
	local def = core.registered_nodes[node.name]
	return def and def.walkable
end

local FanProjectilePrototype = {}
FanProjectilePrototype.__index = FanProjectilePrototype

function FanProjectilePrototype.new(entity)
	return setmetatable({
		object = entity,
		lifetime = 0,
		max_life = (FAN_DEFAULTS.projectile_base_life or 0.9) + math.random() * (FAN_DEFAULTS.projectile_var_life or 0.4),
		velocity = vector.zero(),
		light_entity = "mcl_lun_items:purification_rod_explosion_light",
		stats = get_fan_stats(nil),
	}, FanProjectilePrototype)
end

function FanProjectilePrototype:initialize(user, dir, stats)
	if not user or not self.object then
		return
	end
	self.stats = stats or get_fan_stats(nil)
	local base_life = self.stats.base_life or FAN_DEFAULTS.projectile_base_life
	local var_life = self.stats.var_life or FAN_DEFAULTS.projectile_var_life
	self.max_life = (base_life or 0.9) + math.random() * (var_life or 0.4)
	self.user = user
	self.object:set_yaw(user:get_look_horizontal() or 0)
	local forward = vector.normalize(dir)
	if forward.x == 0 and forward.y == 0 and forward.z == 0 then
		forward = {x = 0, y = 0, z = 1}
	end
	self.velocity = vector.multiply(forward, self.stats.initial_speed or FAN_PROJECTILE_INITIAL_SPEED)
	self.object:set_velocity(self.velocity)
	self.damage = self.stats.damage or FAN_PROJECTILE_DAMAGE
	if wielded_light and wielded_light.track_item_entity then
		wielded_light.track_item_entity(self.object, "fan_projectile_light", "mcl_lun_items:purification_rod_orb_light")
	end
	if self.object then
		self.object:set_properties({
			textures = {HAUCHIWA_PARTICLE_TEXTURE},
			visual_size = {x = 0.6, y = 0.6},
			glow = self.stats.glow or FAN_PARTICLE_GLOW,
			light_source = self.stats.light or FAN_PROJECTILE_LIGHT,
		})
	end
end

function FanProjectilePrototype:get_reason()
	return {
		type = "projectile",
		source = self.user,
		direct = self.object,
	}
end

function FanProjectilePrototype:explode(hitpos)
	if not hitpos then
		return
	end
	for _, offset in ipairs(MAPLE_PATTERN) do
		local center = vector.add(hitpos, offset)
		damage_at_position(center, self.damage, self:get_reason())
	end
	spawn_maple_leaf_particles(hitpos, self.light_entity)
lun_sound("se_kira00", {pos = hitpos, gain = 0.5, max_hear_distance = 24})
	if self.object then
		self.object:remove()
	end
end

local function vector_length(v)
	return math.sqrt((v.x * v.x) + (v.y * v.y) + (v.z * v.z))
end

function FanProjectilePrototype:on_step(dtime)
	if not self.object then
		return
	end
	self.lifetime = self.lifetime + dtime
	if self.lifetime >= self.max_life then
		self:explode(self.object:get_pos())
		return
	end
	local decay = self.stats.decay or FAN_PROJECTILE_DECAY
	local gravity = self.stats.gravity or FAN_PROJECTILE_GRAVITY
	local min_speed = self.stats.min_speed or FAN_PROJECTILE_MIN_SPEED
	self.velocity = vector.multiply(self.velocity, math.max(0, 1 - decay * dtime))
	self.velocity.y = self.velocity.y - gravity * dtime
	local speed = vector_length(self.velocity)
	if speed <= min_speed then
		self:explode(self.object:get_pos())
		return
	end
	local pos = self.object:get_pos()
	if not pos then
		return
	end
	local next_pos = vector.add(pos, vector.multiply(self.velocity, dtime))
	for hit in core.raycast(pos, next_pos, true, true) do
		if hit.type == "node" then
			local under = hit.under
			if under and is_walkable(under) then
				self:explode(hit.intersection_point or hit.above or pos)
				return
			end
		elseif hit.type == "object" and hit.ref ~= self.user then
			mcl_util.deal_damage(hit.ref, self.damage, self:get_reason())
			self:explode(hit.intersection_point or hit.ref:get_pos() or pos)
			return
		end
	end
	self.object:set_velocity(self.velocity)
end

	minetest.register_entity("mcl_lun_items:hauchiwa_fan_projectile", {
		initial_properties = {
			physical = false,
			collide_with_objects = true,
			collisionbox = {0, 0, 0, 0, 0, 0},
			pointable = false,
			visual = "sprite",
			textures = {"mcl_particles_bonemeal.png^[colorize:" .. FAN_PARTICLE_COLOR .. ":160"},
			visual_size = {x = 0.4, y = 0.4},
			glow = FAN_PARTICLE_GLOW,
			backface_culling = false,
			light_source = FAN_PROJECTILE_LIGHT,
			automatic_rotate = 0,
		},
	on_activate = function(self)
		self.projectile = FanProjectilePrototype.new(self.object)
	end,
	on_step = function(self, dtime)
		if self.projectile then
			self.projectile:on_step(dtime)
		end
	end,
})

local GroundProjectilePrototype = {}
GroundProjectilePrototype.__index = GroundProjectilePrototype

function GroundProjectilePrototype.new(entity)
	return setmetatable({
		object = entity,
		state = "falling",
		damage = FAN_PROJECTILE_DAMAGE,
		ground_dir = vector.zero(),
		light_entity = "mcl_lun_items:purification_rod_explosion_light",
		stats = get_fan_stats(nil),
	}, GroundProjectilePrototype)
end

function GroundProjectilePrototype:initialize(user, dir, stats)
	if not user or not self.object then
		return
	end
	self.stats = stats or get_fan_stats(nil)
	self.damage = self.stats.damage or FAN_PROJECTILE_DAMAGE
	self.user = user
	self.state = "falling"
	local horizontal = vector.normalize(vector.new(dir.x, 0, dir.z))
	if horizontal.x == 0 and horizontal.z == 0 then
		horizontal = {x = 0, z = 1}
	end
	self.ground_dir = horizontal
	self.object:set_velocity({x = 0, y = -(self.stats.initial_speed or FAN_PROJECTILE_INITIAL_SPEED) * 1.5, z = 0})
end

function GroundProjectilePrototype:get_reason()
	return {
		type = "projectile",
		source = self.user,
		direct = self.object,
	}
end

function GroundProjectilePrototype:explode_ground(pos)
	if not pos then
		return
	end
	spawn_geyser_particles(pos, self.light_entity)
	apply_explosion_damage(pos, self.damage, self:get_reason(), 1.2)
	if self.object then
		self.object:remove()
	end
end

function GroundProjectilePrototype:on_step(dtime)
	if not self.object then
		return
	end
	local pos = self.object:get_pos()
	if not pos then
		return
	end
	if self.state == "falling" then
		local below = vector.floor(vector.subtract(pos, {x = 0, y = 0.2, z = 0}))
		if is_walkable(below) then
			self.state = "rolling"
			self.velocity = vector.multiply(self.ground_dir, (self.stats.initial_speed or FAN_PROJECTILE_INITIAL_SPEED) * 0.8)
			self.velocity.y = 0
			self.object:set_pos({x = pos.x, y = below.y + 0.2, z = pos.z})
			self.object:set_velocity(self.velocity)
			return
		end
		self.object:set_velocity({x = 0, y = -(self.stats.initial_speed or FAN_PROJECTILE_INITIAL_SPEED) * 1.5, z = 0})
		return
	end
	self.velocity = vector.multiply(self.velocity, 0.7)
	if self.velocity.y ~= 0 then
		self.velocity.y = 0
	end
	local speed = vector_length(self.velocity)
	if speed <= FAN_PROJECTILE_MIN_SPEED then
		self:explode_ground(pos)
		return
	end
	self.object:set_velocity(self.velocity)
end

minetest.register_entity("mcl_lun_items:hauchiwa_ground_projectile", {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		collisionbox = {0, 0, 0, 0, 0, 0},
		pointable = false,
		visual = "sprite",
		textures = {"mcl_particles_smoke_anim.png"},
		visual_size = {x = 0.6, y = 0.6},
		glow = FAN_PARTICLE_GLOW,
		light_source = FAN_PROJECTILE_LIGHT,
		backface_culling = false,
		automatic_rotate = 0,
	},
	on_activate = function(self)
		self.projectile = GroundProjectilePrototype.new(self.object)
	end,
	on_step = function(self, dtime)
		if self.projectile then
			self.projectile:on_step(dtime)
		end
	end,
})

local fan_cooldowns = {}

	local function fan_ready(user, itemname)
		if not user then return true end
		local stats = get_fan_stats(itemname)
		local cd = stats.cooldown or FAN_DEFAULT_COOLDOWN
		local name = user:get_player_name()
		if not name or name == "" then return true end
		local now = monotonic_us()
		if type(now) ~= "number" then
			now = core.get_gametime() * 1000000
		end
		local next_allowed = fan_cooldowns[name] or 0
		if now < next_allowed then
			if FIRE_DEBUG then
				debug_fire(user, ("fan_cooldown_block item=%s now=%d next=%d wait_us=%d"):format(tostring(itemname or ""), now, next_allowed, next_allowed - now))
			end
			return false
		end
		fan_cooldowns[name] = now + seconds_to_us(cd)
		if FIRE_DEBUG then
			debug_fire(user, ("fan_cooldown_allow item=%s now=%d next=%d"):format(tostring(itemname or ""), now, fan_cooldowns[name]))
		end
		return true
	end

local function spawn_hauchiwa_projectile(user, itemname)
	if not user then
		return
	end
	if not fan_ready(user, itemname) then
		return
	end
	local stats = get_fan_stats(itemname)
	local pos = user:get_pos()
	if not pos then
		return
	end
	local dir = user:get_look_dir()
	local spawn = vector.add(pos, vector.new(dir.x, 0, dir.z))
	spawn = vector.add(spawn, vector.new(0, 1.2, 0))
	local obj = minetest.add_entity(spawn, "mcl_lun_items:hauchiwa_fan_projectile")
	if not obj then
		return
	end
	lun_sound("se_option", {
		object = obj,
		gain = 0.7,
		max_hear_distance = 32,
	})
	lun_sound("se_plst00", {
		object = obj,
		gain = 0.6,
		max_hear_distance = 32,
	})
	local lua = obj:get_luaentity()
	if lua and lua.projectile and lua.projectile.initialize then
		lua.projectile:initialize(user, dir, stats)
		lua.projectile.light_entity = "mcl_lun_items:purification_rod_explosion_light"
	end
	end
	_G.mcl_lun_items_launch_hauchiwa_projectile = spawn_hauchiwa_projectile

	local LampadFlagProjectilePrototype = {}
	LampadFlagProjectilePrototype.__index = LampadFlagProjectilePrototype
	setmetatable(LampadFlagProjectilePrototype, {__index = FanProjectilePrototype})

	function LampadFlagProjectilePrototype.new(entity)
		local base = FanProjectilePrototype.new(entity)
		return setmetatable(base, LampadFlagProjectilePrototype)
	end

	function LampadFlagProjectilePrototype:initialize(user, dir, stats, texture, damage)
		FanProjectilePrototype.initialize(self, user, dir, stats)
		self.damage = tonumber(damage) or 0
		self.flag_dir = vector.normalize(dir or {x = 0, y = 0, z = 1})
		if vector.length(self.flag_dir) < 0.001 then
			self.flag_dir = {x = 0, y = 0, z = 1}
		end

		local tex = texture or "mcl_lun_star_projectile_red.png"
		if self.object then
			self.object:set_properties({
				visual = "mesh",
				mesh = "mcl_lun_star_projectile.obj",
				textures = {tex},
				visual_size = {x = 1.2, y = 1.2},
				glow = 14,
				light_source = 0,
				automatic_rotate = 0,
			})
			self.object:set_rotation({x = 0, y = 0, z = 0})
		end
	end

		function LampadFlagProjectilePrototype:explode(hitpos)
			if not hitpos then
				return
			end
			local lifetime = 3.0
			local spacing = 0.4 * 1.1
			local particle_size = 3.6
			local origin = spawn_us_flag_particles(hitpos, self.flag_dir or self.velocity, 11, 9, spacing, particle_size) or hitpos
	
			-- 16-particle red circular burst to 9-node diameter over lifetime.
			do
				-- Exponential decay simulation: Start fast, slow down to stop at max radius.
				-- v(t) = v0 + at. v(3.0) = 0 => a = -v0/3
				-- d(t) = v0*t + 0.5*a*t^2. d(3.0) = 4.5 => 4.5 = 1.5*v0 => v0=3.0, a=-1.0
				local speed = 3.0
				local accel = -1.0
				
				for i = 0, 15 do
					local ang = (math.pi * 2) * (i / 16)
					local dir = {x = math.cos(ang), y = 0, z = math.sin(ang)}
					core.add_particle({
						pos = origin,
						velocity = vector.multiply(dir, speed),
						acceleration = vector.multiply(dir, accel),
						expirationtime = lifetime,
						size = particle_size,
						texture = "mcl_particles_bonemeal.png^[colorize:red:200",
						glow = 4,
					})
				end
			end
			lun_sound("se_kira00", {pos = origin, gain = 0.6, max_hear_distance = 32})
	
			-- Spawn damage zone
			local obj = minetest.add_entity(origin, "mcl_lun_items:lampad_flag_zone")
			if obj then
				local lua = obj:get_luaentity()
				if lua and lua.initialize then
					lua:initialize(tonumber(self.damage) or 0, self.shooter)
				end
			end
	
			if self.object then
				self.object:remove()
			end
		end

	local LampadFlagZone = {
		initial_properties = {
			physical = false,
			pointable = false,
			visual = "sprite",
			textures = {"blank.png"}, -- Invisible
			visual_size = {x = 0, y = 0},
			visual_size = {x = 0, y = 0},
			collisionbox = {0, 0, 0, 0, 0, 0},
			armor_groups = {immortal = 1},
		},
		lifetime = 0,
		max_life = 3.0,
		damage = 0,
		shooter = nil,
		last_hit = nil, -- table: element -> float (timestamp)
	}
	LampadFlagZone.__index = LampadFlagZone

	function LampadFlagZone:initialize(damage, shooter)
		self.damage = damage
		self.shooter = shooter
		self.last_hit = {}
		self:damage_pulse()
	end

	function LampadFlagZone:damage_pulse()
		if not self.object then return end

		-- Match particle kinematics: d = v0*t + 0.5*a*t^2
		-- v0=3.0, a=-1.0. Ends at 4.5m at 3.0s.
		local t = self.lifetime or 0
		local r_math = 3.0 * t - 0.5 * t * t
		local radius = math.max(1.0, r_math) -- Minimum 1.0 to hit point-blank target
		
		-- Height linear progression 1.0 -> 3.0
		local height = 1.0 + (t / 3.0) * 2.0

		local pos = self.object:get_pos()
		if not pos then return end
		local reason = {type = "projectile", source = self.shooter}
		local now = monotonic_us() / 1000000 -- seconds

		-- Using apply_flat_damage logic but inline to check timestamps
		local search_radius = radius
		local targets = minetest.get_objects_inside_radius(pos, search_radius)
		if not targets then return end

		local half_height = height * 0.5
		local slab_min_y = pos.y - half_height
		local slab_max_y = pos.y + half_height

		for _, obj in ipairs(targets) do
			if not obj or not obj:get_pos() or obj == self.object then goto continue end
			local lua = obj:get_luaentity()
			if lua and lua.name == "__builtin:item" then goto continue end
			
			-- Check height bounds
			local op = obj:get_pos()
			local obj_y = op.y
			local obj_min_y = obj_y
			local obj_max_y = obj_y
			local props = obj:get_properties()
			local cb = props and props.collisionbox
			if type(cb) == "table" and cb[2] and cb[5] then
				obj_min_y = obj_y + cb[2]
				obj_max_y = obj_y + cb[5]
				if obj_min_y > obj_max_y then
					obj_min_y, obj_max_y = obj_max_y, obj_min_y
				end
			end
			if obj_max_y < slab_min_y or obj_min_y > slab_max_y then
				goto continue
			end

			-- Check pulse timer
			local last = self.last_hit[obj] or 0
			if (now - last) >= 0.5 then
				if mcl_util and mcl_util.deal_damage then
					mcl_util.deal_damage(obj, self.damage, reason)
				elseif obj.punch then
					obj:punch(reason.source or obj, 0.0, {
						full_punch_interval = 1,
						damage_groups = {fleshy = self.damage},
					}, nil)
				end
				self.last_hit[obj] = now
			end

			::continue::
		end
	end

	function LampadFlagZone:on_step(dtime)
		if not self.object then
			return
		end
		self.lifetime = self.lifetime + dtime
		if self.lifetime >= self.max_life then
			self.object:remove()
			return
		end

		self:damage_pulse()
	end

	minetest.register_entity("mcl_lun_items:lampad_flag_zone", LampadFlagZone)
	


	minetest.register_entity("mcl_lun_items:lampad_flag_projectile", {
		initial_properties = {
			physical = false,
			collide_with_objects = false,
			collisionbox = {0, 0, 0, 0, 0, 0},
			pointable = false,
			visual = "mesh",
			mesh = "mcl_lun_star_projectile.obj",
			textures = {"mcl_lun_star_projectile_red.png"},
			visual_size = {x = 1.2, y = 1.2},
			glow = 14,
			light_source = 0,
			backface_culling = false,
			automatic_rotate = 0,
		},
		on_activate = function(self)
			self.projectile = LampadFlagProjectilePrototype.new(self.object)
		end,
		on_step = function(self, dtime)
			if self.projectile then
				self.projectile:on_step(dtime)
			end
		end,
	})

	local function spawn_ground_projectile(user, itemname)
		if not user then
			return
		end
	if not fan_ready(user, itemname) then
		return
	end
	local stats = get_fan_stats(itemname)
	local pos = user:get_pos()
	if not pos then
		return
	end
	local dir = user:get_look_dir()
	local spawn = vector.add(pos, vector.multiply(dir, 0.5))
	spawn.y = math.ceil(pos.y) + 1.5
	local obj = minetest.add_entity(spawn, "mcl_lun_items:hauchiwa_ground_projectile")
	if not obj then
		return
	end
	local lua = obj:get_luaentity()
	if lua and lua.projectile and lua.projectile.initialize then
		lua.projectile:initialize(user, dir, stats)
		lua.projectile.light_entity = "mcl_lun_items:purification_rod_explosion_light"
	end
end
_G.mcl_lun_items_launch_hauchiwa_ground_projectile = spawn_ground_projectile
_G.mcl_lun_items_is_grounded = is_player_grounded

local function spawn_particles_at(pos, cfg, opts)
	if not pos or not cfg then
		return
	end
	local radius = (opts and opts.radius) or cfg.radius or 0.2
	local texture = (opts and opts.texture) or cfg.texture or "mcl_particles_bonemeal.png"
	if cfg.color then
		texture = texture .. "^[colorize:" .. cfg.color .. ":180"
	end
	local height = (opts and opts.height) or cfg.height or 1
	local amount = (opts and opts.amount) or math.floor(6 + height * 4)
	core.add_particlespawner({
		amount = amount,
		time = 0.15,
		minpos = {x = pos.x - radius, y = pos.y, z = pos.z - radius},
		maxpos = {x = pos.x + radius, y = pos.y + height, z = pos.z + radius},
		minvel = {x = 0, y = 0.5, z = 0},
		maxvel = {x = 0, y = 0.9, z = 0},
		minsize = 0.3,
		maxsize = 0.5,
		glow = cfg.glow or 6,
		texture = texture,
	})
end

local function spawn_orb_drop_particles(obj, cfg)
	if not obj then
		return
	end
	local pos = obj:get_pos()
	if not pos then
		return
	end
	local stack = obj:get_luaentity() and ItemStack(obj:get_luaentity().itemstring or "")
	local stack_cfg = stack and particle_cfg_for_stack(stack)
	local final_cfg = cfg or stack_cfg
	if not final_cfg then
		return
	end
    spawn_particles_at(pos, final_cfg)
	if final_cfg.glow and obj.set_properties and obj:get_luaentity() then
		obj:set_properties({glow = final_cfg.glow})
	end
end

core.register_globalstep(function(dtime)
	if orb_drop_timer < ORB_DROP_REFRESH then
		orb_drop_timer = orb_drop_timer + dtime
		return
	end
	orb_drop_timer = 0
	local processed = {}
	for _, player in ipairs(core.get_connected_players()) do
		local ppos = player:get_pos()
		if not ppos then
			goto continue_player
		end
			for _, obj in ipairs(core.get_objects_inside_radius(ppos, 20)) do
			if obj and not processed[obj] then
				processed[obj] = true
				local ent = obj:get_luaentity()
				if ent and ent.name == "__builtin:item" then
					local stack = ItemStack(ent.itemstring or "")
					if not stack:is_empty() then
						local cfg = particle_cfg_for_stack(stack)
							if cfg and not ent._mcl_lun_items_orb_particles_spawned then
								if wielded_light and wielded_light.track_item_entity and not ent._mcl_lun_items_orb_light then
									wielded_light.track_item_entity(obj, "orb_drop", "mcl_lun_items:yin_yang_orb_drop_light")
									ent._mcl_lun_items_orb_light = true
								end
								local stack_name = stack:get_name()
								local keep_spawning =
									(stack_name:find("^mcl_lun_bows:lunar_bow_") ~= nil)
									or is_purification_rod(stack_name)
									or (stack_name:find("^mcl_lun_items:miko_stick_") ~= nil)
								-- For selected items, keep spawning so the stream stays visible
								if keep_spawning then
									spawn_orb_drop_particles(obj, cfg)
								else
									spawn_orb_drop_particles(obj, cfg)
									ent._mcl_lun_items_orb_particles_spawned = true
								end
							elseif cfg then
								local stack_name = stack:get_name()
								local keep_spawning =
									(stack_name:find("^mcl_lun_bows:lunar_bow_") ~= nil)
									or is_purification_rod(stack_name)
									or (stack_name:find("^mcl_lun_items:miko_stick_") ~= nil)
								if keep_spawning then
									spawn_orb_drop_particles(obj, cfg)
								end
							end
					end
				end
			end
		end
	::continue_player::
	end
end)


local wield_particle_timer = 0
local function wield_particle_position(player)
	local pos = player:get_pos()
	if not pos then
		return
	end
	local dir = player:get_look_dir()
	local up = {x = 0, y = 1, z = 0}
	local right = vector.cross(up, dir)
	right = vector.normalize(right)
	local forward = vector.multiply(dir, 0.4)
	local right_offset = vector.multiply(right, 0.3)
	local target = vector.add(pos, vector.add(forward, right_offset))
	target.y = target.y + 0.8
	return target
end

core.register_globalstep(function(dtime)
	wield_particle_timer = wield_particle_timer + dtime
	if wield_particle_timer < 0.25 then
		return
	end
	wield_particle_timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local stack = player:get_wielded_item()
		if stack and not stack:is_empty() then
		local cfg = particle_cfg_for_stack(stack)
		if cfg then
			local pos = wield_particle_position(player)
			if pos then
				local height = cfg.height or 1
					local wield_opts = {
						radius = (cfg.radius or 0.2) * 0.4,
						amount = math.floor(height),
						height = height * 0.6,
					}
					spawn_particles_at(pos, cfg, wield_opts)
				end
			else
			end
		end
	end
end)

		local function purification_shoot(stack, user, pointed_thing)
			if not user then
				return stack
			end
			local itemname = stack and stack.get_name and stack:get_name() or "<unknown>"
			debug_fire(user, ("attempt_left item=%s"):format(itemname))
			if not rod_ready(user, ("left item=%s"):format(itemname)) then
				debug_fire(user, ("blocked_left item=%s"):format(itemname))
				return stack
			end
			stack = ensure_purification_stack(stack)
			local ammo, ammo_name = consume_orb_ammo(user)
			if not ammo then
				if user and user:get_player_name() then
					minetest.chat_send_player(user:get_player_name(), S("No Yin-Yang orbs available."))
				end
				return stack
			end
			debug_fire(user, ("fire_left item=%s ammo=%s"):format(itemname, tostring(ammo_name or "")))
			local homing_target
			if ammo.type == "homing" then
				if not mcl_lun_homing then
					return stack
			end
			local range = ammo.homing_range or 35
			local fov = ammo.homing_fov or 0.8
			homing_target = mcl_lun_homing.find_best_target(user, range, fov)
				if not homing_target then
					lun_sound("se_ophide", {
						pos = user:get_pos(),
						gain = 0.6,
						max_hear_distance = 24,
					})
					return stack
				end
			end
			lun_sound("se_option", {
				pos = user:get_pos(),
				gain = 0.6,
				max_hear_distance = 32,
			})
			local stack_table = stack and stack:to_table() or nil
			local stats = stack_table and ITEM_STATS[stack_table.name]
			spawn_purification_orb(user, stack_table, ammo, ammo_name, stats, homing_target, 3, 0.15)
			if not core.is_creative_enabled(user:get_player_name()) then
				stack:add_wear_by_uses(300)
			end
			return stack
		end

			local function lampad_shoot(stack, user, pointed_thing)
				if not user then
					return stack
				end
				local itemname = stack and stack.get_name and stack:get_name() or "<unknown>"
				debug_fire(user, ("attempt_left item=%s"):format(itemname))
				if not rod_ready(user, ("left item=%s"):format(itemname)) then
					debug_fire(user, ("blocked_left item=%s"):format(itemname))
					return stack
				end
				debug_fire(user, ("fire_left item=%s"):format(itemname))

				local stack_table = stack and stack:to_table() or nil
				local stats = stack_table and ITEM_STATS[stack_table.name]
				local pname = user:get_player_name()
				local go_right = pname and lampad_side_toggle[pname] or false
				local sign = go_right and 1 or -1
				if pname and pname ~= "" then
					lampad_side_toggle[pname] = not go_right
				end
				debug_fire(user, ("lampad_side=%s sign=%d"):format(go_right and "right" or "left", sign))
				local ammo1 = {lampad_side_sign = sign, lampad_texture = "mcl_lun_star_projectile_red.png"}
				local ammo2 = {lampad_side_sign = sign, lampad_texture = "mcl_lun_star_projectile_white.png"}
				local ammo3 = {lampad_side_sign = sign, lampad_texture = "mcl_lun_star_projectile_blue.png"}
			spawn_purification_orb(user, stack_table, ammo1, nil, stats, nil, "mcl_lun_items:lampad_star_projectile", "se_option")
			minetest.after(0.15, function()
				spawn_purification_orb(user, stack_table, ammo2, nil, stats, nil, "mcl_lun_items:lampad_star_projectile", "se_option")
			end)
			minetest.after(0.30, function()
				spawn_purification_orb(user, stack_table, ammo3, nil, stats, nil, "mcl_lun_items:lampad_star_projectile", "se_option")
			end)

			if not core.is_creative_enabled(user:get_player_name()) then
				stack:add_wear_by_uses(300)
			end
		return stack
	end

					local function lampad_flag_shoot(stack, user, pointed_thing)
						if not user then
							return stack
						end
						local itemname = stack and stack.get_name and stack:get_name() or "<unknown>"
						debug_fire(user, ("attempt_right item=%s"):format(itemname))
						if not rod_ready(user, ("right item=%s"):format(itemname)) then
							debug_fire(user, ("blocked_right item=%s"):format(itemname))
							return stack
						end
						debug_fire(user, ("fire_right item=%s"):format(itemname))

						local stack_table = stack and stack:to_table() or nil
						local stats = stack_table and ITEM_STATS[stack_table.name]
						local damage = (stats and stats.damage) or 0

						local textures = {
							"mcl_lun_star_projectile_red.png",
							"mcl_lun_star_projectile_white.png",
							"mcl_lun_star_projectile_blue.png",
						}
						local tex = textures[math.random(#textures)]

						local pos = user:get_pos()
						if pos then
							local dir = user:get_look_dir()
							local spawn = vector.add(pos, vector.multiply(dir, 0.8))
							spawn.y = spawn.y + 1.5
							local obj = minetest.add_entity(spawn, "mcl_lun_items:lampad_flag_projectile")
							if obj then
								lun_sound("se_option", {object = obj, gain = 0.7, max_hear_distance = 32})
								local lua = obj:get_luaentity()
								if lua and lua.projectile and lua.projectile.initialize then
									lua.projectile:initialize(user, dir, get_fan_stats(nil), tex, damage)
								end
							end
						end

						if not core.is_creative_enabled(user:get_player_name()) then
							stack:add_wear_by_uses(300)
					end
				return stack
			end

	local MIKO_STICK_DEFAULT_NAME = "mcl_lun_items:miko_stick_normal"

	local function miko_wind_fire(stack, user, pointed_thing)
		if not user then
			return stack
		end
			local itemname = stack and stack.get_name and stack:get_name() or MIKO_STICK_DEFAULT_NAME
		debug_fire(user, ("attempt_left item=%s"):format(itemname))
		if not fan_ready(user, itemname) then
			debug_fire(user, ("blocked_left item=%s"):format(itemname))
			return stack
		end
		debug_fire(user, ("fire_left item=%s"):format(itemname))
		local stats = get_fan_stats(itemname)
		local pos = user:get_pos()
		if pos then
			local dir = user:get_look_dir()
			local spawn = vector.add(pos, vector.new(dir.x, 0, dir.z))
			spawn = vector.add(spawn, vector.new(0, 1.2, 0))
			local obj = minetest.add_entity(spawn, "mcl_lun_items:hauchiwa_fan_projectile")
			if obj then
				lun_sound("se_option", {object = obj, gain = 0.7, max_hear_distance = 32})
				lun_sound("se_plst00", {object = obj, gain = 0.6, max_hear_distance = 32})
				local lua = obj:get_luaentity()
				if lua and lua.projectile and lua.projectile.initialize then
					lua.projectile:initialize(user, dir, stats)
					lua.projectile.light_entity = "mcl_lun_items:purification_rod_explosion_light"
				end
			end
		end
		if not core.is_creative_enabled(user:get_player_name()) then
			stack:add_wear_by_uses(300)
		end
		return stack
	end

	local function miko_rain_target(user, range)
		local pos = user:get_pos()
		if not pos then
			return nil, nil
		end
		local dir = user:get_look_dir()
		local start = vector.add(pos, {x = 0, y = 1.6, z = 0})
		local finish = vector.add(start, vector.multiply(dir, range or 14))
		local hitpos = nil
		for hit in core.raycast(start, finish, true, true) do
			if hit.type == "node" then
				hitpos = hit.intersection_point or hit.above or hit.under
				break
			end
			if hit.type == "object" and hit.ref and hit.ref ~= user then
				hitpos = hit.ref:get_pos()
				break
			end
		end
		return hitpos or finish, dir
	end

		local function spawn_miko_rain(center, dir)
			if not center then
				return
			end
		local wind = vector.normalize(vector.new(dir and dir.x or 0, 0, dir and dir.z or 0))
		if not wind or (wind.x == 0 and wind.z == 0) then
			wind = {x = 0, y = 0, z = 0}
		end
			wind = vector.multiply(wind, 0.9)
			core.add_particlespawner({
				amount = 140,
				time = 0.55,
				minpos = vector.add(center, {x = -3.0, y = 3.0, z = -3.0}),
				maxpos = vector.add(center, {x = 3.0, y = 6.8, z = 3.0}),
				minvel = {x = wind.x - 0.25, y = -7.5, z = wind.z - 0.25},
				maxvel = {x = wind.x + 0.25, y = -9.0, z = wind.z + 0.25},
				minacc = {x = 0, y = -10, z = 0},
				maxacc = {x = 0, y = -12, z = 0},
				minexptime = 0.35,
				maxexptime = 0.55,
				minsize = 1.6,
				maxsize = 2.4,
				collisiondetection = true,
				collision_removal = true,
				glow = 10,
				texture = "mcl_particles_bonemeal.png^[colorize:" .. color("lightblue") .. ":220",
			})
			spawn_particle_burst({
				center = center,
				textures = {HAUCHIWA_PARTICLE_TEXTURE},
				amount = 10,
				time = 0.15,
				minsize = 1.2,
				maxsize = 1.8,
				glow = 10,
				minvel = {x = wind.x - 0.4, y = 0.1, z = wind.z - 0.4},
				maxvel = {x = wind.x + 0.4, y = 0.9, z = wind.z + 0.4},
				tint = color("white"),
			})
		end

	local function miko_rain_fire(stack, user, pointed_thing)
		if not user then
			return stack
		end
			local itemname = stack and stack.get_name and stack:get_name() or MIKO_STICK_DEFAULT_NAME
		debug_fire(user, ("attempt_right item=%s"):format(itemname))
		if not fan_ready(user, itemname) then
			debug_fire(user, ("blocked_right item=%s"):format(itemname))
			return stack
		end
		debug_fire(user, ("fire_right item=%s"):format(itemname))

		local target, dir = miko_rain_target(user, 14)
		if target then
			spawn_miko_rain(target, dir)
			lun_sound("se_option", {pos = target, gain = 0.5, max_hear_distance = 24})
		end

		if not core.is_creative_enabled(user:get_player_name()) then
			stack:add_wear_by_uses(300)
		end
		return stack
	end

	local function miko_rain_on_place(itemstack, placer, pointed_thing)
		local rc = call_node_rightclick_first(itemstack, placer, pointed_thing)
		if rc then
			return rc
		end
		return miko_rain_fire(itemstack, placer, pointed_thing)
	end

	local function annotate_explosion_desc(desc, radius, color)
		if not radius or radius <= 0 then
			return desc
	end
	local text = S("Explosion radius: @1", radius)
	if color then
		text = core.colorize(color, text)
	end
	return ("%s\n%s"):format(desc, text)
end

	local function build_lun_description(def)
		if not def then return "" end
		local lines = {}
		if def.description then
			if def.color then
				lines[#lines + 1] = core.colorize(def.color, def.description)
			else
				lines[#lines + 1] = def.description
			end
		end
	if not def.skip_stats then
		if def.explosion_radius then
			lines[#lines + 1] = S("Explosion radius: @1", def.explosion_radius)
		end
	end
	if def.flavor then
		lines[#lines + 1] = def.flavor
	end
	return table.concat(lines, "\n")
end

-- Build a tooltip (_tt_help) string from a list of lines.
-- lines may contain strings or tables { text = "...", color = "red" }.
	build_lun_tt = function(def)
		if not def or not def.lines then return "" end
		local lines = {}
		for _, entry in ipairs(def.lines) do
		if entry == "" then
			lines[#lines + 1] = ""
			elseif type(entry) == "table" then
				local text = entry.text or ""
				local col = entry.color
				if col then
					text = core.colorize(col, text)
				end
				lines[#lines + 1] = text
			else
				lines[#lines + 1] = tostring(entry)
			end
	end
	return table.concat(lines, "\n")
end
-- Export API after helpers are defined
local mcl_lun_items_mod = rawget(_G, "mcl_lun_items") or {}
mcl_lun_items_mod.spawn_particle_burst = spawn_particle_burst
mcl_lun_items_mod.build_lun_description = build_lun_description
mcl_lun_items_mod.build_lun_tt = build_lun_tt
mcl_lun_items_mod.get_item_def = function(name)
	return name and lun_item_registry[name] or nil
end
_G.mcl_lun_items = mcl_lun_items_mod

local function register_mcl_lun_item(def)
	if not def or not def.name then
		return
	end
	local kind = def.kind or "tool"
	local luminance = def.luminance or DEFAULT_LIGHT
	register_item_light(def.name, luminance)
	if kind == "tool" then
		local tt_help = def._tt_help or ""
		if build_lun_tt and def.tt_lines then
			tt_help = build_lun_tt({ lines = def.tt_lines })
		elseif def.tt_lines then
			tt_help = table.concat(def.tt_lines, "\n")
		end
		local desc = build_lun_description({
			description = def.description or S("Purification Rod"),
			color = def.color,
			durability = def.durability or def.uses or ROD_DURABILITY,
			explosion_radius = def.explosion_radius or DEFAULT_ROD_EXPLOSION_RADIUS,
			damage = def.damage,
			luminance = luminance,
			skip_stats = def.skip_stats,
		})
		local tool_caps = def.tool_capabilities or {
			full_punch_interval = 1.0,
				max_drop_level = 0,
				groupcaps = {
					swordy = {times = {[1]=1.6, [2]=1.6, [3]=1.6}, uses = 300, maxlevel = 1},
					swordy_cobweb = {times = {[1]=0.5}, uses = 300, maxlevel = 1},
					swordy_bamboo = {times = {[1]=0.3}, uses = 300, maxlevel = 1},
				},
				damage_groups = def.damage_groups or {fleshy = 6},
			}
		rod_descriptions[def.name] = desc
		minetest.register_tool(def.name, {
			description = desc,
			mcl_lun_base_description = def.base_description or def.description or S("Purification Rod"),
			_doc_items_longdesc = def.longdesc or S("A ceremonial wand."),
			inventory_image = def.inventory_image or "gohei.png",
			wield_image = def.wield_image or def.inventory_image or "gohei.png",
			wield_scale = def.wield_scale or {x = 2, y = 2, z = 2},
			stack_max = def.stack_max or 1,
			light_source = luminance,
			_tt_help = tt_help ~= "" and tt_help or nil,
			_tt_help = tt_help,
			groups = def.groups or {tool = 1, weapon = 1, sword = 1, handy = 1, stick = 1, flammable = 1},
			_mcl_toollike_wield = def.mcl_toollike_wield ~= false,
			_mcl_uses = def.uses or def.durability or ROD_DURABILITY,
			sound = def.sound or {breaks = "default_tool_breaks"},
			tool_capabilities = tool_caps,
			on_secondary_use = def.on_secondary_use,
			on_place = def.on_place,
			on_use = def.on_use,
		})
	else
		local tt_help = def._tt_help or ""
		if build_lun_tt and def.tt_lines then
			tt_help = build_lun_tt({ lines = def.tt_lines })
		elseif def.tt_lines then
			tt_help = table.concat(def.tt_lines, "\n")
		end
		local craft_desc = build_lun_description({
			description = def.description or def.name,
			color = def.color,
			explosion_radius = def.explosion_radius or DEFAULT_ORB_EXPLOSION_RADIUS,
			damage = def.damage,
			luminance = luminance,
			skip_stats = def.skip_stats,
		})
		minetest.register_craftitem(def.name, {
			description = craft_desc,
			inventory_image = def.texture or def.inventory_image,
			stack_max = def.stack_max or 16,
			groups = def.groups or {misc = 1},
			light_source = luminance,
			_tt_help = tt_help ~= "" and tt_help or nil,
		})
	end
	ITEM_STATS[def.name] = {damage = def.damage, explosion_radius = def.explosion_radius}
end

register_mcl_lun_item({
	name = "mcl_lun_items:nightbug",
	kind = "craftitem",
	description = S("Nightbug"),
	texture = "nightbug.png",
	color = "#FFD700",
	luminance = 5,
	stack_max = 1,
	skip_stats = true,
})

for _, orb in ipairs(orb_variants) do
	orb.kind = "craftitem"
	orb.luminance = orb.luminance or DEFAULT_LIGHT
	orb.explosion_radius = orb.explosion_radius or DEFAULT_ORB_EXPLOSION_RADIUS

	local ammo = ammo_registry[orb.name]
	if ammo then
		if orb.damage then
			ammo.damage = orb.damage
		end
		local style_val = ammo.type or "Unknown"
		local style = style_val:gsub("^%l", string.upper)
		local dmg_val = orb.damage or ammo.damage or 0
		local radius_val = orb.explosion_radius or DEFAULT_ORB_EXPLOSION_RADIUS
		orb.tt_lines = {
			{text = S("Damage: @1", dmg_val), color = "red"},
			{text = S("Style: @1", style), color = orb.color or "purple"},
			{text = S("Explosion radius: @1", radius_val), color = "orange"},
			{text = S("Bounces: @1", ammo.max_bounces or ORB_DEFAULT_MAX_BOUNCES), color = orb.color or "purple"},
			{text = S("Lifetime: @1s", ammo.max_life or ORB_DEFAULT_MAX_LIFE), color = orb.color or "purple"},
		}

		register_mcl_lun_item(orb)
	end
						end
						local function lampad_shoot_on_place(itemstack, placer, pointed_thing)
							local rc = call_node_rightclick_first(itemstack, placer, pointed_thing)
							if rc then
								return rc
							end
							return lampad_flag_shoot(itemstack, placer, pointed_thing)
						end

						local function lampad_flag_on_place(itemstack, placer, pointed_thing)
							local rc = call_node_rightclick_first(itemstack, placer, pointed_thing)
							if rc then
								return rc
							end
							return lampad_flag_shoot(itemstack, placer, pointed_thing)
						end

	local lampad_torch_variants = {
			{
				name = "mcl_lun_items:lampad_torch_fading",
				description = S("Fading Lampad Torch"),
					inventory_image = "mcl_lun_items_lampad_torch.png",
					wield_image = "mcl_lun_items_lampad_torch.png",
					luminance = 4,
					damage = 4,
					color = color("grey"),
					groups = {tool = 1, handy = 1, flammable = 1},
					stack_max = 1,
					uses = 300,
		},
			{
				name = "mcl_lun_items:lampad_torch_normal",
				description = S("Normal Lampad Torch"),
					inventory_image = "mcl_lun_items_lampad_torch.png",
					wield_image = "mcl_lun_items_lampad_torch.png",
					luminance = 8,
					damage = 6,
					color = color("white"),
					groups = {tool = 1, handy = 1, flammable = 1},
					stack_max = 1,
					uses = 300,
		},
			{
				name = "mcl_lun_items:lampad_torch_lunatic",
				description = S("Lunatic Lampad Torch"),
					inventory_image = "mcl_lun_items_lampad_torch.png",
					wield_image = "mcl_lun_items_lampad_torch.png",
					luminance = 12,
					damage = 8,
					color = color("darkorange"),
					groups = {tool = 1, handy = 1, flammable = 1},
					stack_max = 1,
					uses = 300,
		},
	}

			for _, variant in ipairs(lampad_torch_variants) do
				variant.kind = "tool"
				variant.on_use = lampad_shoot
				variant.on_secondary_use = lampad_flag_on_place
				variant.on_place = lampad_shoot_on_place
				register_mcl_lun_item(variant)
			end

			local miko_stick_variants = {
				{
					name = "mcl_lun_items:miko_stick_fading",
					description = S("Fading Miko Stick"),
					color = color("grey"),
					particle_color = color("lightsteelblue"),
					luminance = 4,
					damage = 4,
					uses = 300,
					fan_stats = {
						damage = 4,
						cooldown = 0.60,
						initial_speed = 28,
						base_life = 0.95,
						var_life = 0.25,
						decay = 1.30,
						gravity = 20,
						min_speed = 0.6,
						light = 6,
						glow = 6,
					},
				},
				{
					name = MIKO_STICK_DEFAULT_NAME,
					description = S("Normal Miko Stick"),
					color = color("lightblue"),
					particle_color = color("lightblue"),
					luminance = 6,
					damage = 5,
					uses = 300,
					fan_stats = {
						damage = 5,
						cooldown = 0.55,
						initial_speed = 30,
						base_life = 1.0,
						var_life = 0.25,
						decay = 1.25,
						gravity = 18,
						min_speed = 0.6,
						light = 7,
						glow = 7,
					},
				},
				{
					name = "mcl_lun_items:miko_stick_lunatic",
					description = S("Lunatic Miko Stick"),
					color = color("cyan"),
					particle_color = color("aqua"),
					luminance = 8,
					damage = 6,
					uses = 300,
					fan_stats = {
						damage = 6,
						cooldown = 0.50,
						initial_speed = 32,
						base_life = 1.05,
						var_life = 0.25,
						decay = 1.20,
						gravity = 16,
						min_speed = 0.6,
						light = 9,
						glow = 9,
					},
				},
			}

			for _, variant in ipairs(miko_stick_variants) do
				register_fan_stats(variant.name, variant.fan_stats)
				register_lun_item({
					name = variant.name,
					particle_color = variant.particle_color,
					particle_glow = 10,
					luminance = variant.luminance,
				})
				register_mcl_lun_item({
					name = variant.name,
					kind = "tool",
					description = variant.description,
					inventory_image = "mcl_lun_items_miko_stick.png",
					wield_image = "mcl_lun_items_miko_stick.png",
					wield_scale = {x = 1.6, y = 1.6, z = 1.6},
					stack_max = 1,
					luminance = variant.luminance,
					damage = variant.damage,
					color = variant.color,
					uses = variant.uses,
					tt_lines = {
						{text = S("Wind / Rain"), color = variant.color},
						{text = S("Left click: Wind gust"), color = color("white")},
						{text = S("Right click: Rain shower"), color = color("white")},
					},
					groups = {tool = 1, weapon = 1, handy = 1, stick = 1, flammable = 1},
					on_use = miko_wind_fire,
					on_secondary_use = miko_rain_on_place,
					on_place = miko_rain_on_place,
				})
			end

for _, variant in ipairs(rod_variants) do
	variant.kind = "tool"
	variant.durability = variant.durability or ROD_DURABILITY
	variant.uses = variant.uses or ROD_DURABILITY
	variant.luminance = variant.luminance or DEFAULT_LIGHT
	variant.explosion_radius = variant.explosion_radius or DEFAULT_ROD_EXPLOSION_RADIUS
	-- Tooltip lines via shared builder
	do
			local tint = variant.color
			variant.tt_lines = {
				{text = S("Fires Yin-Yang Orbs, which come in several types"), color = tint},
				{text = S("Orbs deal damage upon hitting a target, or upon exploding in a radius."), color = tint},
				{text = S("Style: Triple-Volley"), color = tint},
			}
		end
		variant.inventory_image = variant.inventory_image or "gohei.png"
		variant.wield_image = variant.wield_image or variant.inventory_image
		variant.groups = variant.groups or {tool = 1, weapon = 1, sword = 1, handy = 1, stick = 1, flammable = 1}
		variant.tool_capabilities = variant.tool_capabilities or {
			full_punch_interval = 1.0,
			max_drop_level = 0,
			groupcaps = {
				swordy = {times = {[1]=1.6, [2]=1.6, [3]=1.6}, uses = variant.uses or ROD_DURABILITY, maxlevel = 1},
				swordy_cobweb = {times = {[1]=0.5}, uses = variant.uses or ROD_DURABILITY, maxlevel = 1},
				swordy_bamboo = {times = {[1]=0.3}, uses = variant.uses or ROD_DURABILITY, maxlevel = 1},
			},
			damage_groups = {fleshy = variant.damage or 6},
		}
		variant.on_use = purification_shoot
		variant.on_secondary_use = cycle_ammo_type
		variant.on_place = cycle_ammo_on_place
		register_mcl_lun_item(variant)
	end

	local purification_projectile = {
	initial_properties = {
		physical = false,
		collide_with_objects = true,
		collisionbox = {0, 0, 0, 0, 0, 0},
		pointable = false,
		visual = "mesh",
		mesh = "mcl_lun_items_purification_orb.obj",
		textures = {"yin_yang_orb.png"},
		visual_size = {x = 4.0, y = 4.0},
		glow = 8,
		automatic_rotate = 0,
		backface_culling = false,
		pointlight = {
			radius = 6,
			intensity = 0.5,
			color = color("crimson"),
		},
	},
	velocity = {x = 0, y = 0, z = 0},
		last_pos = nil,
		lifetime = 0,
		max_life = ORB_DEFAULT_MAX_LIFE,
		bounces_left = ORB_DEFAULT_MAX_BOUNCES,
		shooter = nil,
		shooter_name = "",
		ignore_until = 0,
	damage = 2,
	knockback = 0,
	flame = false,
	rotation_angle = 0,
	base_pitch = 0,
	base_yaw = 0,
	last_node_hit = nil,
	last_node_time = 0,
	left_shooter = false,
	homing_enabled = false,
	homing_target = nil,
	homing_range = 0,
	homing_fov = 0,
	homing_turn_rate = 0,
	homing_size_factor = 1,
	base_speed = ROD_SPEED,
	homing_current_speed = 0,
	homing_ramp = 0,
	homing_has_target = false,
}

function purification_projectile:initialize(user, stack, dir, ammo_def, ammo_name, rod_stats, initial_target)
	self.shooter = user
	self.shooter_name = user:get_player_name() or ""
	self.ignore_until = core.get_gametime() + 0.2
	local base_velocity = vector.multiply(dir, ROD_SPEED)
	self.base_speed = ROD_SPEED
	self.homing_current_speed = self.base_speed
	self.homing_ramp = 0
	self.homing_has_target = false
	if self.homing_enabled then
		self.homing_current_speed = self.base_speed * HOMING_INITIAL_SPEED_FACTOR
		self.velocity = vector.multiply(vector.normalize(base_velocity), self.homing_current_speed)
	else
		self.velocity = base_velocity
	end
	self.object:set_velocity(self.velocity)
		self.object:set_yaw(user:get_look_horizontal() or 0)
		self.last_pos = self.object:get_pos()
		self.lifetime = 0
		local rod_damage = (rod_stats and rod_stats.damage) or 0
		local orb_damage = (ammo_def and ammo_def.damage) or 0
		self.damage = rod_damage + orb_damage
	local rod_radius = (rod_stats and rod_stats.explosion_radius) or DEFAULT_ROD_EXPLOSION_RADIUS
	local orb_radius = (ammo_def and ammo_def.explosion_radius) or DEFAULT_ORB_EXPLOSION_RADIUS
	self.rod_explosion_radius = rod_radius
	self.orb_explosion_radius = orb_radius
	self.explosion_radius = rod_radius + orb_radius
	self.knockback = 0
	self.flame = false
	self.rotation_angle = 0
	local dir = user:get_look_dir()
	local horiz = math.sqrt(dir.x * dir.x + dir.z * dir.z)
	local pitch = math.atan2(dir.y, horiz)
	local yaw = math.atan2(dir.z, dir.x)
	self.base_pitch = -pitch
	self.base_yaw = yaw + math.pi / 2
		self.object:set_rotation({x = self.base_pitch, y = self.base_yaw, z = 0})
		self.left_shooter = false
		self.ammo = ammo_def or ammo_registry["mcl_lun_items:yin_yang_orb_precision"]
		self.ammo_name = ammo_name
		self.bounces_left = (self.ammo and self.ammo.max_bounces) or ORB_DEFAULT_MAX_BOUNCES
		self.max_life = (self.ammo and self.ammo.max_life) or ORB_DEFAULT_MAX_LIFE
		self.rotation_rate = ORB_ROTATION_SPEED * (self.ammo.rotation_multiplier or 1)
		self.gravity_accel = self.ammo.gravity or 0
		self.is_bouncing = self.ammo.type == "bouncing"
		self.bounce_damping = self.ammo.bounce_damping or 1
	self.particle_color = self.ammo.particle_color
	self.homing_enabled = self.ammo.type == "homing" and mcl_lun_homing
	if self.homing_enabled then
		self.homing_range = self.ammo.homing_range or 30
		self.homing_fov = self.ammo.homing_fov or 0.8
		self.homing_turn_rate = self.ammo.homing_turn_rate or 4
		self.homing_target = initial_target
	end
	local tex = self.ammo.model_texture or "yin_yang_orb.png"
	if tex and self.object and self.object.set_properties then
		self.object:set_properties({textures = {tex}})
	end

	if stack and mcl_enchanting and mcl_enchanting.get_enchantments then
		local ench = mcl_enchanting.get_enchantments(stack)
		if ench then
			if ench.power then
				self.damage = self.damage + (ench.power / 2) + 0.5
			end
			if ench.punch then
				self.knockback = ench.punch
			end
			if ench.flame then
				self.flame = true
			end
		end
	end
	if wielded_light and wielded_light.track_item_entity then
		wielded_light.track_item_entity(self.object, "purification_orb", "mcl_lun_items:purification_rod_orb_light")
	end
end

local function reflect_velocity(vel, normal)
	normal = vector.normalize(normal)
	local dot = vel.x * normal.x + vel.y * normal.y + vel.z * normal.z
	return {
		x = vel.x - 2 * dot * normal.x,
		y = vel.y - 2 * dot * normal.y,
		z = vel.z - 2 * dot * normal.z,
	}
end

local function should_ignore(self, obj)
	if not obj then
		return true
	end
	if obj == self.shooter and (self.ignore_until >= core.get_gametime() or not self.left_shooter) then
		minetest.log("action", "[purif] ignoring shooter (left="..tostring(self.left_shooter)..")")
		return true
	end
	return false
end

function purification_projectile:get_reason()
	return {
		type = "yinyangorb",
		source = self.shooter,
		direct = self.object,
	}
end

		function purification_projectile:explode(pos, normal)
			minetest.log("action", "[purif] explode at "..minetest.pos_to_string(pos or self.object:get_pos()))
			local dir = vector.normalize(self.velocity or {x = 0, y = 1, z = 0})
			play_snowball_effect(pos or self.object:get_pos(), self.particle_color, self.damage, self:get_reason(), self.explosion_radius, normal, true, dir, 1, 1, 1, nil, nil, nil, nil, nil, nil)
			self.object:remove()
		end

function purification_projectile:close_range_detonation(pos)
	if not pos then
		return
	end
		core.sound_play(TNT_EXPLODE_SOUND, {pos = pos, gain = 1.0, max_hear_distance = 64}, true)
	local prev_radius = self.explosion_radius
	self.explosion_radius = HOMING_CLOSE_RADIUS
	self:explode(pos)
	self.explosion_radius = prev_radius
end

local function round_pos(pos)
	if not pos then
		return nil
	end
	return {
		x = math.floor(pos.x + 0.5),
		y = math.floor(pos.y + 0.5),
		z = math.floor(pos.z + 0.5),
	}
end

local function pos_equal(a, b)
	if not a or not b then
		return false
	end
	return a.x == b.x and a.y == b.y and a.z == b.z
end

function purification_projectile:bounce(normal, hitpos)
	minetest.log("action", "[purif] bounce normal "..minetest.serialize(normal).." remaining "..self.bounces_left)
	self.bounces_left = self.bounces_left - 1
	self.velocity = reflect_velocity(self.velocity, normal or {x = 0, y = 1, z = 0})
	if self.is_bouncing then
		local damp = self.bounce_damping or 1
		self.velocity = vector.multiply(self.velocity, damp)
		local extra_y = self.ammo.extra_vertical or 0
		if extra_y > 0 then
			self.velocity.y = self.velocity.y + extra_y
		end
		local variation = 1 + (math.random() * 0.1 - 0.05)
		self.velocity = vector.multiply(self.velocity, variation)
	end
	self.object:set_velocity(self.velocity)
	if hitpos and normal then
		self.object:set_pos(vector.add(hitpos, vector.multiply(normal, 0.05)))
	elseif hitpos then
		self.object:set_pos(hitpos)
	end
lun_sound("se_graze", {pos = hitpos or self.object:get_pos(), gain = 0.4, max_hear_distance = 32})
	self.last_node_hit = round_pos(hitpos or self.object:get_pos())
	self.last_node_time = core.get_gametime()
	local particle_origin = vector.add((hitpos or self.object:get_pos()) or {x=0,y=0,z=0}, vector.multiply(normal or {x=0,y=1,z=0}, 0.15))
	spawn_bounce_particles(particle_origin, self.particle_color)
end

local function axis_to_normal(axis)
	if axis == "x+" then return {x = 1, y = 0, z = 0} end
	if axis == "x-" then return {x = -1, y = 0, z = 0} end
	if axis == "y+" then return {x = 0, y = 1, z = 0} end
	if axis == "y-" then return {x = 0, y = -1, z = 0} end
	if axis == "z+" then return {x = 0, y = 0, z = 1} end
	if axis == "z-" then return {x = 0, y = 0, z = -1} end
	return nil
end

local function entity_center(obj)
	if not obj then
		return nil
	end
	local pos = obj:get_pos()
	if not pos then
		return nil
	end
	local props = obj:get_properties()
	if not props or not props.collisionbox then
		return pos
	end
	local cb = props.collisionbox
	if #cb < 6 then
		return pos
	end
	local height = math.abs(cb[5] - cb[2])
	local center_offset = {x = 0, y = height * 0.5, z = 0}
	return vector.add(pos, center_offset)
end

function purification_projectile:hit_entity(obj, hitpos)
	if not obj or should_ignore(self, obj) then
		return
	end
	minetest.log("action", "[purif] hit entity "..(obj:get_luaentity() and obj:get_luaentity().name or "unknown").." pos "..minetest.pos_to_string(hitpos or obj:get_pos()))
	local lua = obj:get_luaentity()
	if lua and lua._hittable_by_projectile == false then
		return
	end
	mcl_util.deal_damage(obj, self.damage, self:get_reason())
	if self.knockback > 0 and obj.add_velocity then
		obj:add_velocity(vector.multiply(vector.normalize(self.velocity), self.knockback * 2))
	end
	if self.flame and mcl_burning then
		mcl_burning.set_on_fire(obj, 5)
	end
	local center_pos = entity_center(obj)
	self:explode(center_pos or hitpos)
end

function purification_projectile:update_homing(dtime)
	if not self.homing_enabled or not mcl_lun_homing or not self.object then
		return
	end
	local target = self.homing_target
	local valid = target and target.get_pos and target:get_pos()
	if valid and target.get_hp then
		local hp = target:get_hp()
		if hp and hp <= 0 then
			valid = nil
		end
	end
	if not valid then
		target = mcl_lun_homing.find_best_target(self.shooter, self.homing_range, self.homing_fov)
		self.homing_target = target
	end
	if not target then
		self.homing_has_target = false
		self.homing_ramp = math.max(0, self.homing_ramp - dtime / HOMING_ACCEL_DURATION)
		local speed_factor = HOMING_INITIAL_SPEED_FACTOR + (1 - HOMING_INITIAL_SPEED_FACTOR) * self.homing_ramp
		local direction = vector.normalize(self.velocity)
		self.homing_current_speed = self.base_speed * speed_factor
		if vector.length(direction) > 0 then
			self.velocity = vector.multiply(direction, self.homing_current_speed)
		end
		return
	end
	local target_pos = target:get_pos()
	if not target_pos then
		return
	end

	local current_pos = self.object:get_pos()
	if current_pos and vector.distance(current_pos, target_pos) <= HOMING_CLOSE_DISTANCE then
		self:close_range_detonation(current_pos)
		return
	end

	local target_volume = 0
	local props = target:get_properties()
	local box = props and props.collisionbox
	if box and #box >= 6 then
		local w = math.max(0, box[4] - box[1])
		local h = math.max(0, box[5] - box[2])
		local d = math.max(0, box[6] - box[3])
		target_volume = w * h * d
	end
	if target_volume > 0 then
		local ratio = target_volume / ZOMBIE_COLLISION_VOLUME
		self.homing_size_factor = math.min(math.max(ratio, 0.5), 2.0)
	else
		self.homing_size_factor = 1
	end

	self.homing_has_target = true
	self.homing_ramp = math.min(1, self.homing_ramp + dtime / HOMING_ACCEL_DURATION)
	local direction = vector.normalize(self.velocity)
	local steer_vel = mcl_lun_homing.steer(self.velocity, self.object:get_pos(), target_pos, self.homing_turn_rate, dtime)
	local new_dir = (steer_vel and vector.normalize(steer_vel)) or direction
	if vector.length(new_dir) == 0 then
		new_dir = direction
	end
	local speed_factor = (HOMING_INITIAL_SPEED_FACTOR + (1 - HOMING_INITIAL_SPEED_FACTOR) * self.homing_ramp) * (self.homing_size_factor or 1)
	self.homing_current_speed = self.base_speed * speed_factor
	self.velocity = vector.multiply(new_dir, self.homing_current_speed)
end

function purification_projectile:on_step(dtime)
	local obj = self.object
	if not obj then
		return
	end
	local rate = self.rotation_rate or 0
	self.rotation_angle = (self.rotation_angle + rate * dtime) % (math.pi * 2)
	obj:set_rotation({x = self.base_pitch + self.rotation_angle, y = self.base_yaw, z = 0})
	self.lifetime = self.lifetime + dtime
	if self.lifetime >= self.max_life then
		self:explode(obj:get_pos())
		return
	end
	local pos = obj:get_pos()
	if not pos then
		self:explode(self.last_pos)
		return
	end
	local last = self.last_pos or pos
	local collided = false
	local shooter_detected = false
	if self.gravity_accel and self.gravity_accel ~= 0 then
		self.velocity = vector.add(self.velocity, {x = 0, y = self.gravity_accel * dtime, z = 0})
	end
	self:update_homing(dtime)
	local collided_pos = nil
	for hit in core.raycast(last, pos, true, true) do
		if hit.type == "object" then
			if hit.ref == self.shooter then
				shooter_detected = true
			end
			if hit.ref and hit.ref ~= obj and not should_ignore(self, hit.ref) then
				self:hit_entity(hit.ref, hit.intersection_point or pos)
				collided = true
				break
			end
		elseif hit.type == "node" then
			local under = hit.under
			if under and is_walkable(under) then
				minetest.log("action", "[purif] node hit at "..minetest.pos_to_string(under).." bounces_left="..self.bounces_left)
				local node_pos = under
				local rounded = round_pos(node_pos)
				local now = core.get_gametime()
				if rounded and self.last_node_hit and self.last_node_time and now - self.last_node_time < 0.08 and pos_equal(rounded, self.last_node_hit) then
					goto continue_hit
				end
				local normal = hit.intersection_normal or axis_to_normal(hit.axis) or vector.normalize(vector.subtract(hit.above, under))
				if self.bounces_left > 0 then
					self:bounce(normal, hit.intersection_point or hit.above or pos)
				else
					self:explode(hit.intersection_point or hit.above or pos, normal)
				end
				collided = true
				collided_pos = (self.object and self.object:get_pos()) or self.last_pos
				break
			end
		end
	::continue_hit::
	end
	if not shooter_detected then
		if not self.left_shooter then
			self.left_shooter = true
			self.ignore_until = 0
		end
	end
	if not collided then
		obj:set_velocity(self.velocity)
		self.last_pos = pos
	else
		self.last_pos = collided_pos or self.object:get_pos() or self.last_pos
	end
end

minetest.register_entity("mcl_lun_items:purification_rod_projectile", purification_projectile)

local explosion_light = {
	initial_properties = {
		physical = false,
		pointable = false,
		visual = "sprite",
		textures = {"wieldhand.png"}, -- hidden via zero size
		visual_size = {x = 0, y = 0},
		light_source = 2,
	},
	timer = 0,
	lifetime = 0.3,
	start_light = 2,
	end_light = 6,
}

function explosion_light:on_activate()
	self.timer = 0
	if wielded_light and wielded_light.track_item_entity then
		wielded_light.track_item_entity(self.object, "purification_explosion", "mcl_lun_items:purification_rod_orb_light")
	end
end

function explosion_light:on_step(dtime)
	self.timer = self.timer + dtime
	local life = self.lifetime or 0.3
	local progress = math.min(1, self.timer / life)
	local desired = math.floor(self.start_light + (self.end_light - self.start_light) * progress)
	if desired < 1 then
		desired = 1
	end
	if self.object then
		self.object:set_properties({light_source = desired})
	end
	if self.timer >= (self.lifetime or 0.3) then
		self.object:remove()
	end
end

minetest.register_entity("mcl_lun_items:purification_rod_explosion_light", explosion_light)

local lampad_explosion_light = table.copy(explosion_light)
lampad_explosion_light.initial_properties = table.copy(explosion_light.initial_properties)
lampad_explosion_light.initial_properties.light_source = 14
lampad_explosion_light.lifetime = 0.35
lampad_explosion_light.start_light = 14
lampad_explosion_light.end_light = 14

function lampad_explosion_light:on_activate()
	self.timer = 0
	if wielded_light and wielded_light.track_item_entity then
		wielded_light.track_item_entity(self.object, "lampad_explosion", "mcl_lun_items:lampad_explosion_light")
	end
end

minetest.register_entity("mcl_lun_items:lampad_explosion_light", lampad_explosion_light)

local flag_corner_light = {
	initial_properties = {
		physical = false,
		pointable = false,
		visual = "sprite",
		textures = {"wieldhand.png"}, -- hidden via zero size
		visual_size = {x = 0, y = 0},
		light_source = 14,
	},
	timer = 0,
	lifetime = 2.05,
}

function flag_corner_light:on_activate()
	self.timer = 0
	if wielded_light and wielded_light.track_item_entity then
		wielded_light.track_item_entity(self.object, "flag_corner", "mcl_lun_items:flag_corner_light")
	end
end

function flag_corner_light:on_step(dtime)
	self.timer = self.timer + dtime
	if self.timer >= (self.lifetime or 2.05) then
		self.object:remove()
	end
end

minetest.register_entity("mcl_lun_items:flag_corner_light", flag_corner_light)

local gohei_projectile = table.copy(purification_projectile)
gohei_projectile.initial_properties = table.copy(purification_projectile.initial_properties)
gohei_projectile.initial_properties.textures = {"gohei.png"}
gohei_projectile.initial_properties.pointlight = {
    radius = 18,
    intensity = 0.5,
    color = color("crimson"),
}

	function gohei_projectile:initialize(user, stack, dir, ammo_def, ammo_name, rod_stats, initial_target)
	    purification_projectile.initialize(self, user, stack, dir, ammo_def, ammo_name, rod_stats, initial_target)
	    self.light_entity = "mcl_lun_items:purification_rod_explosion_light"
	end

	minetest.register_entity("mcl_lun_items:gohei_projectile", gohei_projectile)

		local function lampad_exp_ease_in(t, k)
			if t <= 0 then
				return 0
			end
			if t >= 1 then
				return 1
			end
			k = k or 4
			local denom = math.exp(k) - 1
			if denom == 0 then
				return t
			end
			return (math.exp(k * t) - 1) / denom
		end

	local lampad_star_projectile = table.copy(purification_projectile)
	lampad_star_projectile.initial_properties = table.copy(purification_projectile.initial_properties)
	lampad_star_projectile.initial_properties.mesh = "mcl_lun_star_projectile.obj"
	lampad_star_projectile.initial_properties.textures = {"mcl_lun_star_projectile_red.png"}
	lampad_star_projectile.initial_properties.pointlight = {
	radius = 8,
	intensity = 0.6,
	color = color("darkorange"),
}

			function lampad_star_projectile:initialize(user, stack, dir, ammo_def, ammo_name, rod_stats, initial_target)
				purification_projectile.initialize(self, user, stack, dir, ammo_def, ammo_name, rod_stats, initial_target)
				local tex = (ammo_def and ammo_def.lampad_texture) or "mcl_lun_star_projectile_red.png"
				if self.object then
					self.object:set_properties({textures = {tex}})
					self.object:set_velocity({x = 0, y = 0, z = 0})
					self.object:set_rotation({x = 0, y = 0, z = 0})
				end
			self.base_pitch = 0
			self.base_yaw = 0
			self.rotation_angle = 0
			self.lampad_base_damage = self.damage or 0
			self.velocity = {x = 0, y = 0, z = 0}
			self.last_pos = self.object and self.object:get_pos() or self.last_pos
			self.lampad_origin = self.last_pos
			self.lampad_distance = 0
			self.lampad_speed = self.base_speed or ROD_SPEED
			self.lampad_max_distance = 33
			self.lampad_side_amplitude = self.lampad_max_distance
			self.lampad_ease_k = 6
			self.lampad_side_sign = (ammo_def and ammo_def.lampad_side_sign) or 1
			self.explosion_radius = 2
			self.rod_explosion_radius = 0
			self.orb_explosion_radius = 0

			local forward = vector.normalize(dir or {x = 0, y = 0, z = 1})
			if vector.length(forward) < 0.001 then
				forward = {x = 0, y = 0, z = 1}
			end
			self.lampad_forward_dir = forward
			local side = vector.cross({x = 0, y = 1, z = 0}, forward)
			if vector.length(side) < 0.001 then
				side = vector.cross({x = 1, y = 0, z = 0}, forward)
			else
				side = vector.normalize(side)
			end
			if vector.length(side) < 0.001 then
				side = {x = 1, y = 0, z = 0}
			end
			self.lampad_side_dir = side
		end

		function lampad_star_projectile:current_damage()
			local base = self.lampad_base_damage or self.damage or 0
			local max_life = self.max_life or ORB_DEFAULT_MAX_LIFE
			local life = self.lifetime or 0
			local progress = 0
			if max_life and max_life > 0 then
				progress = math.min(1, math.max(0, life / max_life))
			end
			local bonus = math.floor(3 * progress)
			return base + bonus
		end

			function lampad_star_projectile:explode(pos, normal)
				minetest.log("action", "[lampad] explode at "..minetest.pos_to_string(pos or self.object:get_pos()))
				local dir = vector.normalize(self.velocity or {x = 0, y = 1, z = 0})
				local damage = self:current_damage()
				-- Keep particles fully lit via glow override (like Yin-Yang orbs), but using the original spawner system.
				play_snowball_effect(
					pos or self.object:get_pos(),
					self.particle_color,
					damage,
					self:get_reason(),
					self.explosion_radius,
					normal,
					true,
					dir,
					3,
					2.5,
					5,
					{"red", "white", "blue"},
					{"mcl_particles_bonemeal.png"},
					0.25,
					0.8,
					14,
					"mcl_lun_items:lampad_explosion_light"
				)
				self.object:remove()
			end

		function lampad_star_projectile:on_step(dtime)
			local obj = self.object
			if not obj then
			return
		end
		if dtime <= 0 then
			return
		end

			self.lifetime = (self.lifetime or 0) + dtime
			self.damage = self:current_damage()
			if self.lifetime >= (self.max_life or ORB_DEFAULT_MAX_LIFE) then
				self:explode(obj:get_pos())
				return
			end

		local origin = self.lampad_origin
		local forward = self.lampad_forward_dir
		local side = self.lampad_side_dir
		if not origin or not forward or not side then
			self:explode(obj:get_pos())
			return
		end

		local pos = obj:get_pos()
		if not pos then
			self:explode(origin)
			return
		end
		local last = self.last_pos or pos

		local max_distance = self.lampad_max_distance or 10
		local distance = self.lampad_distance or 0
		local remaining = max_distance - distance
		if remaining <= 0 then
			self:explode(pos)
			return
		end

		local speed = self.lampad_speed or ROD_SPEED
		local ds = speed * dtime
		if ds > remaining then
			ds = remaining
		end

			local target_distance = distance + ds
			self.lampad_distance = target_distance

			local t = target_distance / max_distance
			local x = target_distance
			local sign = self.lampad_side_sign or 1
			local y = lampad_exp_ease_in(t, self.lampad_ease_k) * (self.lampad_side_amplitude or max_distance) * sign
			local target_pos = vector.add(origin, vector.multiply(forward, x))
			target_pos = vector.add(target_pos, vector.multiply(side, y))

		local inv_dt = 1 / dtime
		self.velocity = vector.multiply(vector.subtract(target_pos, pos), inv_dt)

		local shooter_detected = false
		for hit in core.raycast(last, target_pos, true, true) do
			if hit.type == "object" then
				if hit.ref == self.shooter then
					shooter_detected = true
				end
				if hit.ref and hit.ref ~= obj and not should_ignore(self, hit.ref) then
					self:hit_entity(hit.ref, hit.intersection_point or target_pos)
					return
				end
			elseif hit.type == "node" then
				local under = hit.under
				if under and is_walkable(under) then
					local normal = hit.intersection_normal or axis_to_normal(hit.axis) or vector.normalize(vector.subtract(hit.above, under))
					self:explode(hit.intersection_point or hit.above or target_pos, normal)
					return
				end
			end
		end

		if not shooter_detected then
			if not self.left_shooter then
				self.left_shooter = true
				self.ignore_until = 0
			end
		end

		obj:set_velocity(self.velocity)
		self.last_pos = pos

		if self.lampad_distance >= max_distance then
			self:explode(pos)
			return
		end
	end

	minetest.register_entity("mcl_lun_items:lampad_star_projectile", lampad_star_projectile)

local bounce_light = {
	initial_properties = {
		physical = false,
		pointable = false,
		visual = "sprite",
		textures = {"wieldhand.png"},
		visual_size = {x = 0, y = 0},
	},
	timer = 0,
	lifetime = 0.15,
}

function bounce_light:on_activate()
	self.timer = 0
	if wielded_light and wielded_light.track_item_entity then
		wielded_light.track_item_entity(self.object, "purification_bounce", "mcl_lun_items:purification_rod_orb_light")
	end
end

function bounce_light:on_step(dtime)
	self.timer = self.timer + dtime
	if self.timer >= (self.lifetime or 0.15) then
		self.object:remove()
	end
end

minetest.register_entity("mcl_lun_items:purification_rod_bounce_light", bounce_light)

	do
		local mcl_potions = rawget(_G, "mcl_potions")
		local eat = minetest.item_eat(6)
		local function on_eat(itemstack, user, pointed_thing)
		local before_count = itemstack:get_count()
		local before_name = itemstack:get_name()
		itemstack = eat(itemstack, user, pointed_thing)
		local consumed = itemstack:get_name() ~= before_name or itemstack:get_count() < before_count
		if consumed and mcl_potions and mcl_potions.give_effect and user and user.is_player and user:is_player() then
			mcl_potions.give_effect("fire_resistance", user, 1, 60)
		end
			return itemstack
		end

		register_mcl_lun_item({
			name = "mcl_lun_items:hourai_eda",
			kind = "tool",
			description = S("Hourai Eda"),
			longdesc = S("A sacred branch from the Hourai tree."),
			inventory_image = "houraiEda.png",
			wield_image = "houraiEda.png",
			color = color("mediumpurple"),
			luminance = 0,
			stack_max = 1,
			uses = 300,
			skip_stats = true,
			groups = {tool = 1, handy = 1},
			tool_capabilities = {
				full_punch_interval = 1.0,
				max_drop_level = 0,
				groupcaps = {},
				damage_groups = {fleshy = 1},
			},
		})

		minetest.register_craftitem("mcl_lun_items:cooked_chicken", {
			description = build_lun_description({
				description = S("Chicken Yakitori"),
				color = color("axis"),
			skip_stats = true,
		}),
		_doc_items_longdesc = S("Chicken yakitori is a hearty food item which can be eaten. Provides fire resistance."),
		inventory_image = "mcl_lun_items_yakitori.png",
		wield_image = "mcl_lun_items_yakitori.png",
		stack_max = 16,
		on_place = on_eat,
		on_secondary_use = on_eat,
		groups = {food = 2, eatable = 6, can_eat_when_full = 1},
		_mcl_saturation = 7.2,
	})

	minetest.register_craftitem("mcl_lun_items:yakitori_tare", {
		description = build_lun_description({
			description = S("Chicken Yakitori (+Tare)"),
			color = color("orchid"),
			skip_stats = true,
		}),
		_doc_items_longdesc = S("Chicken yakitori with tare sauce is a hearty food item which can be eaten. Provides fire resistance."),
		inventory_image = "mcl_lun_items_yakitori_tare.png",
		wield_image = "mcl_lun_items_yakitori_tare.png",
		stack_max = 16,
		on_place = on_eat,
		on_secondary_use = on_eat,
		groups = {food = 2, eatable = 6, can_eat_when_full = 1},
		_mcl_saturation = 10.8,
	})
end

do
	local mcl_colors = rawget(_G, "mcl_colors")
	local poison_tip = S("30% chance of food poisoning")
	if mcl_colors and mcl_colors.YELLOW then
		poison_tip = core.colorize(mcl_colors.YELLOW, poison_tip)
	end

	minetest.register_craftitem("mcl_lun_items:yakitori_uncooked", {
		description = build_lun_description({
			description = S("Uncooked Skewered Chicken"),
			skip_stats = true,
		}),
		_tt_help = poison_tip,
		_doc_items_longdesc = S("Uncooked skewered chicken is not safe to consume. You can eat it to restore a few hunger points, but there's a 30% chance to suffer from food poisoning, which increases your hunger rate for a while. Cooking it will make it safe to eat and increases its nutritional value."),
		inventory_image = "mcl_lun_items_yakitori_uncooked.png",
		wield_image = "mcl_lun_items_yakitori_uncooked.png",
		on_place = core.item_eat(2),
		on_secondary_use = core.item_eat(2),
		groups = {food = 2, eatable = 2, smoker_cookable = 1, campfire_cookable = 1},
		_mcl_saturation = 1.2,
		_mcl_cooking_output = "mcl_lun_items:cooked_chicken",
	})
end
