local S = core.get_translator(core.get_current_modname())

-- local arrows = {
-- 	["mcl_lun_bows:arrow"] = "mcl_lun_bows:arrow_entity",
-- }

local GRAVITY = 9.81
local BOW_DURABILITY = 385
-- Simple rarity descriptors, each has its own item registration
local color_fn = rawget(_G, "color") or (rawget(_G, "colors_api") and colors_api and colors_api.color)
local mcl_lun_items_mod = rawget(_G, "mcl_lun_items")
local build_lun_description = mcl_lun_items_mod and mcl_lun_items_mod.build_lun_description
local build_lun_tt = mcl_lun_items_mod and mcl_lun_items_mod.build_lun_tt

local BOW_RARITIES = {
	weakened  = {label = S("Weakened Lunar Bow"),  color = color_fn and color_fn("gray") or "#9e9e9e", luminance = 6},
	-- Lighter blue tones for normal and legendary
	normal    = {label = S("Lunar Bow"),           color = color_fn and color_fn("lightblue") or "#4f83ff", luminance = 8},
	legendary = {label = S("Legendary Lunar Bow"), color = color_fn and color_fn("dodgerblue") or "#3949ab", luminance = 10},
}
mcl_lun_bows.BOW_RARITIES = BOW_RARITIES
local DEFAULT_RARITY_KEY = "normal"

-- Charging time in microseconds
local BOW_CHARGE_TIME_HALF = 200000 -- bow level 1
local BOW_CHARGE_TIME_FULL = 500000 -- bow level 2 (full charge)
mcl_lun_bows.BOW_CHARGE_TIME_HALF = 200000 / 1.0e6
mcl_lun_bows.BOW_CHARGE_TIME_FULL = 500000 / 1.0e6

-- Factor to multiply with player speed while player uses bow
-- This emulates the sneak speed.
local PLAYER_USE_BOW_SPEED = tonumber(core.settings:get("movement_speed_crouch")) / tonumber(core.settings:get("movement_speed_walk"))

local BOW_MAX_SPEED = 3.0 * 20 * 0.8

--[[ Store the charging state of each player.
keys: player name
value:
nil = not charging or player not existing
number: currently charging, the number is the time from core.get_us_time
             in which the charging has started
]]
local bow_load = {}

-- Another player table, this one stores the wield index of the bow being charged
local bow_index = {}

local function colorize_rarity_label(key)
	local def = BOW_RARITIES[key or DEFAULT_RARITY_KEY] or BOW_RARITIES[DEFAULT_RARITY_KEY]
	return core.colorize(def.color or "#ffffff", def.label or "")
end

-- Parse a bow itemstring into rarity/stage/enchanted components
-- Returns rarity_key, stage (0/1/2 or nil), enchanted (boolean)
local function parse_bow_name(name)
	if not name then
		return DEFAULT_RARITY_KEY, nil, false
	end
	-- stage + enchanted
	local rarity, stage = name:match("^mcl_lun_bows:lunar_bow_(%w+)_([0-2])_enchanted$")
	if rarity and stage then
		return rarity, tonumber(stage), true
	end
	-- stage only
	rarity, stage = name:match("^mcl_lun_bows:lunar_bow_(%w+)_([0-2])$")
	if rarity and stage then
		return rarity, tonumber(stage), false
	end
	-- base enchanted
	rarity = name:match("^mcl_lun_bows:lunar_bow_(%w+)_enchanted$")
	if rarity then
		return rarity, nil, true
	end
	-- base
	rarity = name:match("^mcl_lun_bows:lunar_bow_(%w+)$")
	if rarity then
		return rarity, nil, false
	end
	return DEFAULT_RARITY_KEY, nil, false
end

local function format_bow_name(rarity, stage, enchanted)
	rarity = rarity or DEFAULT_RARITY_KEY
	local base = "mcl_lun_bows:lunar_bow_" .. rarity
	if stage ~= nil then
		base = base .. "_" .. stage
	end
	if enchanted then
		base = base .. "_enchanted"
	end
	return base
end

-- With distinct items per rarity we don't need meta conversions.
local function ensure_bow_meta(stack)
	return stack
end

-- Unified bow registration helper
-- def = {
--   rarities = table like BOW_RARITIES,
--   base_texture = "mcl_lun_bows_bow.png",
-- }
local function register_lun_bow(def)
	local rarities = def.rarities or BOW_RARITIES
	local base_tex = def.base_texture or "mcl_lun_bows_bow.png"
	local default_tt_color = def.tt_help_color
	local function start_charging(itemstack, player, pointed_thing)
		-- Honor node/entity rightclicks first
		if mcl_util and mcl_util.call_on_rightclick then
			local rc = mcl_util.call_on_rightclick(itemstack, player, pointed_thing)
			-- If a node/object handled rightclick, do NOT arm the bow.
			-- Also clear any stale "active" flag so holding RMB on interactive nodes
			-- can't accidentally start charging from a previous click.
			if rc then
				local meta = rc:get_meta()
				meta:set_string("active", "")
				return rc
			end
		end
		-- Mark as active to start charge/shoot cycle (mirrors vanilla bow)
		local meta = itemstack:get_meta()
		meta:set_string("active", "true")
		return itemstack
	end
	for rarity_key, rdef in pairs(rarities) do
		-- Base + enchanted (only base visible in creative)
		for _, enchanted in ipairs({false, true}) do
			local name = format_bow_name(rarity_key, nil, enchanted)
			local desc = colorize_rarity_label(rarity_key)
			if build_lun_description then
				desc = build_lun_description({
					description = rdef.label,
					color = rdef.color,
					durability = BOW_DURABILITY,
					light_level = rdef.luminance,
				})
			end
			local tt_help
			if build_lun_tt then
				tt_help = build_lun_tt({
					lines = {
						{ text = S("Can fire Lunar Arrows"), color = rdef.tt_help_color or default_tt_color or rdef.color },
						"",
						{ text = S("Pull back fully for a completely accurate shot"), color = "red" },
						"",
						{ text = S("The half moon was also called the 'Drawn-Bow Moon' for its bow-like shape."), color = "lightsteelblue" },
						"",
					},
				})
			else
				local tt_help_lines = { S("Can fire Lunar Arrows") }
				local tt_color = rdef.tt_help_color or default_tt_color or rdef.color
				if tt_color and color_fn then
					local hex = color_fn(tt_color)
					if hex then
						tt_help_lines[1] = core.colorize(hex, tt_help_lines[1])
					end
				end
				local red_hex = color_fn and color_fn("red") or "#ff4040"
				local antique_hex = color_fn and color_fn("lightsteelblue") or "#8f90b4ff"
				table.insert(tt_help_lines, core.colorize(red_hex, S("Pull back fully for a completely accurate shot")))
				table.insert(tt_help_lines, "")
				table.insert(tt_help_lines, core.colorize(antique_hex, S("The half moon was also called the 'Drawn-Bow Moon' for its bow-like shape.")))
				table.insert(tt_help_lines, "")
				tt_help = table.concat(tt_help_lines, "\n")
			end
			core.register_tool(name, {
				description = desc,
				_tt_help = tt_help,
				_doc_items_longdesc = S("Bows are ranged weapons to shoot arrows at your foes.").."\n"..
					S("The speed and damage of the arrow increases the longer you charge. The regular damage of the arrow is between 1 and 9. At full charge, there's also a 20% of a critical hit, dealing 10 damage instead."),
				_doc_items_usagehelp = S("To use the bow, you first need to have at least one arrow anywhere in your inventory (unless in Creative Mode). Hold down the right mouse button (or the zoom key) to charge, release to shoot."),
				_doc_items_durability = BOW_DURABILITY,
				inventory_image = base_tex,
				wield_scale = mcl_vars.tool_wield_scale,
				stack_max = 1,
				range = 4,
				groups = {
					weapon = 2, weapon_ranged = 1, bow = 1, enchantability = 1, offhand_item = 1,
					creative = enchanted and nil or 1,
					not_in_creative_inventory = enchanted and 1 or nil,
				},
				light_source = (rdef.luminance or 0),
				on_use = function() end,
				on_secondary_use = start_charging,
				on_place = start_charging,
				touch_interaction = "short_dig_long_place",
				_mcl_uses = BOW_DURABILITY,
				_mcl_burntime = 15,
			})
		end
		-- Charging stages (hidden)
		for level = 0, 2 do
			for _, enchanted in ipairs({false, true}) do
				local name = format_bow_name(rarity_key, level, enchanted)
				local cdesc = colorize_rarity_label(rarity_key)
				if build_lun_description then
					cdesc = build_lun_description({
						description = rdef.label,
						color = rdef.color,
						durability = BOW_DURABILITY,
						light_level = rdef.luminance,
					})
				end
				core.register_tool(name, {
					description = cdesc,
					_doc_items_create_entry = false,
					inventory_image = "mcl_lun_bows_bow_"..level..".png",
					wield_scale = mcl_vars.tool_wield_scale,
					stack_max = 1,
					range = 0,
					groups = {not_in_creative_inventory=1, not_in_craft_guide=1, bow=1, enchantability=1},
					light_source = (rdef.luminance or 0),
					on_use = function() end,
					on_drop = function(itemstack, dropper, pos)
						reset_bow_state(dropper)
						itemstack:get_meta():set_string("active", "")
						itemstack:set_name(format_bow_name(rarity_key, nil, enchanted))
						core.item_drop(itemstack, dropper, pos)
						itemstack:take_item()
						return itemstack
					end,
					on_place = function(itemstack)
						return itemstack
					end,
					touch_interaction = "short_dig_long_place",
					_mcl_uses = BOW_DURABILITY,
				})
			end
		end
		-- Register drop/held particles & light via mcl_lun_items registry if present
		if mcl_lun_items_mod and mcl_lun_items_mod.register_lun_item then
			mcl_lun_items_mod.register_lun_item({
				name = format_bow_name(rarity_key, nil, false),
				particle_color = "#6ab7ff",
				particle_glow = 10,
				light_level = rdef.luminance or 0,
			})
		end
	end
	-- Aliases for legacy single-name bow to normal rarity
	core.register_alias("mcl_lun_bows:lunar_bow", format_bow_name(DEFAULT_RARITY_KEY, nil, false))
	core.register_alias("mcl_lun_bows:lunar_bow_enchanted", format_bow_name(DEFAULT_RARITY_KEY, nil, true))
end
	function mcl_lun_bows.shoot_arrow(arrow_item, pos, dir, yaw, shooter, power, damage, is_critical, bow_stack, collectable)
		local entity_name = ItemStack(arrow_item):get_name().."_entity"
		if not core.registered_entities[entity_name] then
			core.log("error", ("[mcl_lun_bows] missing arrow entity=%s (arrow_item=%s)"):format(entity_name, tostring(arrow_item)))
			return
		end
		local obj = core.add_entity({x=pos.x,y=pos.y,z=pos.z}, entity_name)
		if not obj or not obj:get_pos() then return end
	if power == nil then
		power = 1.0
	end
	local inaccuracy = nil
	if type(shooter) == "string" then -- Assume to be dispenser.
		inaccuracy = 6
		shooter = nil
	end
	if is_critical and shooter and shooter:is_player() then
		core.log("action", ("[mcl_lun_bows] crit shot start dir=%s power=%.3f inacc=%s pos=%s"):format(
			minetest.pos_to_string(dir, 3), power or 0, tostring(inaccuracy), minetest.pos_to_string(pos, 2)))
	end
	local speed = power * BOW_MAX_SPEED
	local mob_shooter = shooter and not shooter:is_player ()
	local player_shooter = shooter and shooter:is_player ()

	if damage == nil then
		if mob_shooter then
			-- Randomize arrow damage by difficulty.
			damage = 2.0
			local bonus
				= mcl_util.dist_triangular (mcl_vars.difficulty * 0.11,
								0.57425)
			damage = damage + bonus
		else
			damage = 2.0
		end
	end
	local knockback = 0
	if bow_stack then
		local enchantments = mcl_enchanting.get_enchantments(bow_stack)
		if enchantments.power then
			damage = damage + (enchantments.power / 2) + 0.5
		end
		if enchantments.punch then
			knockback = knockback + enchantments.punch
		end
		if enchantments.flame then
			mcl_burning.set_on_fire(obj, math.huge)
		end
	end
	if not (is_critical and player_shooter) then
		dir = mcl_lun_bows.add_inaccuracy(dir, player_shooter and 1 or inaccuracy, 0.4)
	else
		-- Critical shots from players: zero out inaccuracy.
		dir = vector.normalize(dir)
		inaccuracy = nil
		core.log("action", ("[mcl_lun_bows] crit normalized dir=%s"):format(minetest.pos_to_string(dir, 3)))
	end
	obj:set_velocity({x=dir.x*speed, y=dir.y*speed, z=dir.z*speed})
	if is_critical and player_shooter then
		-- Critical shots fly perfectly straight: no gravity.
		obj:set_acceleration({x=0, y=0, z=0})
	else
		obj:set_acceleration({x=0, y=-GRAVITY, z=0})
	end
	obj:set_yaw(yaw-math.pi/2)
	if is_critical and player_shooter then
		core.log("action", ("[mcl_lun_bows] crit final vel=%s speed=%.3f yaw=%.3f"):format(
			minetest.pos_to_string(obj:get_velocity(), 3), speed, yaw or 0))
		end
		local le = obj:get_luaentity()
		if not le then
			core.log("error", ("[mcl_lun_bows] arrow entity has no luaentity=%s (arrow_item=%s)"):format(entity_name, tostring(arrow_item)))
			obj:remove()
			return
		end
		le._shooter = shooter
		le._source_object = shooter
		le._damage = damage
	le._is_critical = is_critical
	le._startpos = pos
	le._knockback = knockback
	le._collectable = collectable
	le._itemstring = arrow_item
	local sound_pos = nil
	if shooter and shooter:is_player() then
		local dir = shooter:get_look_dir()
		local up = {x = 0, y = 1, z = 0}
		local right = vector.normalize(vector.cross(up, dir))
		if vector.length(right) == 0 then
			right = {x = 1, y = 0, z = 0}
		end
		sound_pos = vector.add(shooter:get_pos(), vector.add(vector.multiply(dir, 1), vector.multiply(right, 1)))
	else
		sound_pos = pos
	end
	local soundparam = {object=shooter, pos=sound_pos, max_hear_distance=32, gain=0.2}
	core.sound_play("se_tan01", soundparam, true)
	if shooter and shooter:is_player() then
		if le.player == "" then
			le.player = shooter
		end
		le.node = shooter:get_inventory():get_stack("main", 1):get_name()
	end
	return obj
end

local function get_arrow(player)
	local inv = player:get_inventory()
	local arrow_stack, arrow_stack_id
	for i=1, inv:get_size("main") do
		local it = inv:get_stack("main", i)
		local is_bow_ammo = core.get_item_group(it:get_name(), "ammo_bow") ~= 0
		local is_lunar_ammo = core.get_item_group(it:get_name(), "ammo_lunar_bow") ~= 0
		if not it:is_empty() and (is_bow_ammo or is_lunar_ammo) then
			arrow_stack = it
			arrow_stack_id = i
			break
		end
	end
	return arrow_stack, arrow_stack_id
end

function mcl_lun_bows.get_arrow_stack_for_bow (player)
	return get_arrow (player)
end

local function player_shoot_arrow (player, power, is_critical)
	local arrow_stack, arrow_stack_id = get_arrow(player)
	local arrow_itemstring
	local has_infinity_enchantment = mcl_enchanting.has_enchantment(player:get_wielded_item(), "infinity")

		if core.is_creative_enabled(player:get_player_name()) then
			if arrow_stack then
				arrow_itemstring = arrow_stack:to_string()
			else
				arrow_itemstring = "mcl_lun_bows:lunar_arrow"
			end
		else
		if not arrow_stack then
			return false
		end
		arrow_itemstring = arrow_stack:to_string()
		if not (has_infinity_enchantment and core.get_item_group(arrow_stack:get_name(), "ammo_bow_regular") > 0) then
			arrow_stack:take_item()
		end
		local inv = player:get_inventory()
		inv:set_stack("main", arrow_stack_id, arrow_stack)
	end
	if not arrow_itemstring then
		return false
	end
	local playerpos = mcl_util.target_eye_pos (player)
	playerpos.y = playerpos.y - 0.1
	local dir = player:get_look_dir()
	local yaw = player:get_look_horizontal()

	arrow_itemstring = ItemStack(arrow_itemstring)
	arrow_itemstring:set_count(1)
	arrow_itemstring = arrow_itemstring:to_string()

	mcl_lun_bows.shoot_arrow (arrow_itemstring, playerpos, dir, yaw, player,
			      power, nil, is_critical, player:get_wielded_item (),
			      not has_infinity_enchantment)
	return true
end

-- Base bows for each rarity (visible in creative)
-- Iterates through player inventory and resets all the bows in "charging" state back to their original stage
local function reset_bows(player)
	local inv = player:get_inventory()
	local list = inv:get_list("main")
	for place, stack in pairs(list) do
		local rarity, stage, enchanted = parse_bow_name(stack:get_name())
		-- Always clear the "active" flag so bows don't start charging from stale state
		stack:get_meta():set_string("active", "")
		if stage then
			stack:set_name(format_bow_name(rarity, nil, enchanted))
			list[place] = stack
		end
	end
	inv:set_list("main", list)
end

-- Resets the bow charging state and player speed. To be used when the player is no longer charging the bow
local function reset_bow_state(player, also_reset_bows)
	playerphysics.remove_physics_factor(player, "fov", "mcl_lun_bows:lunar_bow_zoom")
	bow_load[player:get_player_name()] = nil
	bow_index[player:get_player_name()] = nil
	if core.get_modpath("playerphysics") then
		playerphysics.remove_physics_factor(player, "speed", "mcl_lun_bows:use_bow")
	end
	-- Clear active flag on wielded bow so node rightclick doesn't accidentally start charging later
	local wield = player and player:get_wielded_item()
	if wield and wield:get_name():find("^mcl_lun_bows:lunar_bow_") then
		wield:get_meta():set_string("active", "")
		player:set_wielded_item(wield)
	end
	if also_reset_bows then
		reset_bows(player)
	end
end

-- Register the bow family once
register_lun_bow({rarities = BOW_RARITIES, base_texture = "mcl_lun_bows_bow.png"})

function mcl_lun_bows.player_shoot (player, wielditem, usetime_us)
	local rarity, _, enchanted = parse_bow_name(wielditem:get_name())
	local enchanted_flag = mcl_enchanting.is_enchanted(wielditem:get_name()) or enchanted
	local charge = math.max(math.min(usetime_us, BOW_CHARGE_TIME_FULL), 0)
	local charge_ratio = charge / BOW_CHARGE_TIME_FULL
	charge_ratio = math.max(math.min(charge_ratio, 1), 0)

	-- Calculate damage and power.
	local is_critical = false
	if charge >= BOW_CHARGE_TIME_FULL then
		is_critical = true
	end

	local has_shot = player_shoot_arrow (player, charge_ratio, is_critical)

	wielditem:set_name(format_bow_name(rarity, nil, enchanted_flag))

	if has_shot and not core.is_creative_enabled(player:get_player_name()) then
		local durability = BOW_DURABILITY
		local unbreaking = mcl_enchanting.get_enchantment(wielditem, "unbreaking")
		if unbreaking > 0 then
			durability = durability * (unbreaking + 1)
		end
		wielditem:add_wear(65535/durability)
	end
	player:set_wielded_item (wielditem)
end

controls.register_on_release(function(player, key)
	if mcl_serverplayer.is_csm_capable (player) then
		return
	end
	if key~="RMB" and key~="zoom" then return end
	local wielditem = ensure_bow_meta(player:get_wielded_item())
	if not wielditem:get_name():find("^mcl_lun_bows:lunar_bow_") then
		return
	end
	local rarity, stage = parse_bow_name(wielditem:get_name())
	if stage ~= nil then

		local p_load = bow_load[player:get_player_name()]
		local charge
		-- Type sanity check
		if type(p_load) == "number" then
			charge = core.get_us_time() - p_load
		else
			-- In case something goes wrong ...
			-- Just assume minimum charge.
			charge = 0
			core.log("warning", "[mcl_lun_bows] Player "..player:get_player_name().." fires arrow with non-numeric bow_load!")
		end
		mcl_lun_bows.player_shoot (player, wielditem, charge)
		reset_bow_state(player, true)
	end
end)

controls.register_on_hold(function(player, key)
	if mcl_serverplayer.is_csm_capable (player) then
		return
	end
	local name = player:get_player_name()
	local creative = core.is_creative_enabled(name)
	if (key ~= "RMB" and key ~= "zoom") or not (creative or get_arrow(player)) then
		return
	end
	local wielditem = ensure_bow_meta(player:get_wielded_item())
	if not wielditem:get_name():find("^mcl_lun_bows:lunar_bow_") then
		return
	end
	local rarity, stage, enchanted = parse_bow_name(wielditem:get_name())
	local active = wielditem:get_meta():get("active")
	if bow_load[name] == nil
		and stage == nil
		and (active or key == "zoom")
		and (creative or get_arrow(player)) then
		local new_name = format_bow_name(rarity, 0, enchanted)
		wielditem:set_name(new_name)
		player:set_wielded_item(wielditem)
		if core.get_modpath("playerphysics") then
			-- Slow player down when using bow
			playerphysics.add_physics_factor(player, "speed", "mcl_lun_bows:use_bow", PLAYER_USE_BOW_SPEED)
		end
		bow_load[name] = core.get_us_time()
		bow_index[name] = player:get_wield_index()

		playerphysics.add_physics_factor(player, "fov", "mcl_lun_bows:lunar_bow_zoom", 0.8)
	elseif player:get_wield_index() == bow_index[name] then
		if type(bow_load[name]) == "number" then
			local elapsed = core.get_us_time() - bow_load[name]
			if stage == 0 and elapsed >= BOW_CHARGE_TIME_HALF then
				wielditem:set_name(format_bow_name(rarity, 1, enchanted))
			elseif stage == 1 and elapsed >= BOW_CHARGE_TIME_FULL then
				wielditem:set_name(format_bow_name(rarity, 2, enchanted))
			end
		else
			-- failed charge, normalize back to base
			wielditem:set_name(format_bow_name(rarity, nil, enchanted))
		end
		player:set_wielded_item(wielditem)
	else
		reset_bow_state(player, true)
	end
end)

mcl_player.register_globalstep(function(player)
	if not mcl_serverplayer.is_csm_capable (player) then
		local name = player:get_player_name()
		local wielditem = player:get_wielded_item()
		local wieldindex = player:get_wield_index()
		local _, stage = parse_bow_name(wielditem:get_name())
		if type(bow_load[name]) == "number" and ((stage == nil) or wieldindex ~= bow_index[name]) then
			reset_bow_state(player, true)
		end
	end
end)

core.register_on_joinplayer(function(player)
	reset_bows(player)
end)

core.register_on_leaveplayer(function(player)
	reset_bow_state(player, true)
end)

-- Add entry aliases for the Help
if core.get_modpath("doc") then
	for rarity_key in pairs(BOW_RARITIES) do
		doc.add_entry_alias("tools", format_bow_name(rarity_key, nil, false), "tools", format_bow_name(rarity_key, 0, false))
		doc.add_entry_alias("tools", format_bow_name(rarity_key, nil, false), "tools", format_bow_name(rarity_key, 1, false))
		doc.add_entry_alias("tools", format_bow_name(rarity_key, nil, false), "tools", format_bow_name(rarity_key, 2, false))
	end
end
