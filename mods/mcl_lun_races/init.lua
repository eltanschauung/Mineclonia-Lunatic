
local mcl_player = rawget(_G, "mcl_player")
local mcl_lun_sounds = rawget(_G, "mcl_lun_sounds")
local mcl_lun_items_mod = rawget(_G, "mcl_lun_items")
local build_lun_description = mcl_lun_items_mod and mcl_lun_items_mod.build_lun_description
local get_lun_item_def = mcl_lun_items_mod and mcl_lun_items_mod.get_item_def
local color_fn = rawget(_G, "color") or (rawget(_G, "colors_api") and colors_api.color)
local races_api = {}
_G.mcl_lun_races = races_api

local function lun_sound(name, params, ephemeral)
	if mcl_lun_sounds and mcl_lun_sounds.play then
		return mcl_lun_sounds.play(name, params, ephemeral)
	end
	return core.sound_play(name, params or {}, ephemeral == nil and true or ephemeral)
end

-- --- Constants & Metadata Keys ---
local KB_RACE = "mcl_lun_races:race"
local KB_SKIN = "mcl_lun_races:skin"
local KB_LAST_RACE = "mcl_lun_races:last_race"
local KB_GRANTED_FLY = "mcl_lun_races:granted_fly"
local KB_FLY_SPEED = "mcl_lun_races:fly_speed"
local KB_FLOAT_CAP = "mcl_lun_races:float_cap"
local KB_ELYTRA_CAP = "mcl_lun_races:elytra_cap"
local KB_KIT_AWARDED = "mcl_lun_races:last_kit_race"
local KB_FACTION = "mcl_lun_races:faction"
local KB_FIRST_SPAWNED = "mcl_lun_races:first_spawned"
local KB_DIRECTIONS_GIVEN = "mcl_lun_races:rinnosuke_directions_given"
local RINNOSUKE_DIRECTIONS_ITEM = "mcl_lun_barriers:rinnosukes_directions"

local FLY_SPEED = 0.15

-- --- Utility Functions ---

local function round_int(x)
	return math.floor((tonumber(x) or 0) + 0.5)
end

local function parse_pos(s)
	if type(s) ~= "string" or s == "" then
		return nil
	end
	local p = core.string_to_pos(s)
	if p then
		return p
	end
	-- Some configs omit parentheses: "x,y,z"
	if not s:match("^%s*%(") and s:find(",", 1, true) then
		return core.string_to_pos("(" .. s .. ")")
	end
	return nil
end

local function default_spawnpoint()
	local s = core.settings and core.settings:get("static_spawnpoint") or nil
	local p = parse_pos(s)
	if not p then
		p = {x = 0, y = 10, z = 0}
	end
	return vector.round(p)
end

local function normalize_spawnpoint(pos)
	if type(pos) == "table" then
		if pos.x and pos.y and pos.z then
			return vector.round(pos)
		end
		if pos[1] and pos[2] and pos[3] then
			return vector.round({x = pos[1], y = pos[2], z = pos[3]})
		end
	elseif type(pos) == "string" then
		local p = parse_pos(pos)
		if p then
			return vector.round(p)
		end
	end
	return nil
end

local function sound_random(...)
	local sounds = {}
	for _, sound in ipairs({...}) do
		if sound and sound ~= "" then
			table.insert(sounds, sound)
		end
	end
	if #sounds == 0 then return "" end
	return sounds[math.random(#sounds)]
end

-- --- Race Class ---

local Race = {}
Race.__index = Race

function Race.new(name, def)
	local self = setmetatable({}, Race)
	self.name = name
	self.rarity = def.rarity or "normal"
	self.model = def.model
	-- Per-race first-join spawn and faction assignment.
	self.spawnpoint = normalize_spawnpoint(def.spawnpoint or default_spawnpoint())
	self.faction = def.faction or "default"
	-- HP scaling: default is Mineclonia's 20 HP (10 hearts).
	-- Use `hp_factor` to scale from base, or `hp_max` for an explicit value.
	self.hp_factor = tonumber(def.hp_factor) or 1.0
	self.hp_max = tonumber(def.hp_max)
	self.scale = def.scale or {x = 1, y = 1}
	self.color_name = def.color or "white"
	self.color = color_fn and color_fn(self.color_name) or def.color or "#ffffff"
	self.eye_height = def.eye_height or (1.0 * self.scale.y)
	self.eye_height_crouching = def.eye_height_crouching or (0.8 * self.scale.y)
	self.skins = def.skins or {}
	self.flight_mode = def.flight_mode
	self.fly = def.fly
	self.elytra = def.elytra
	self.sounds = def.sounds or {
		random = "mobs_mc_villager",
		damage = "mobs_mc_villager_hurt",
		distance = 10,
		accept = "mobs_mc_villager_accept",
		deny = "mobs_mc_villager_deny",
		trade = "mobs_mc_villager_trade",
	}
	self.kit_func = def.kit_func
	return self
end

function Race:apply_model(player)
	if not (self.model and mcl_player and mcl_player.player_set_model) then
		return
	end
	mcl_player.player_set_model(player, self.model)
end

function Race:apply_visuals(player)
	local cb_half = 0.3 * self.scale.x
	local cb_height = 1.8 * self.scale.y
	local collisionbox = {-cb_half, 0, -cb_half, cb_half, cb_height, cb_half}
	local selectionbox = {-cb_half, 0, -cb_half, cb_half, cb_height, cb_half}

	player:set_properties({
		visual_size = self.scale,
		collisionbox = collisionbox,
		selectionbox = selectionbox,
		eye_height = self.eye_height,
		eye_height_crouching = self.eye_height_crouching,
	})

	local eye_offset = vector.new(0, self.eye_height, 0)
	if mcl_player and mcl_player.player_set_eye_offset then
		mcl_player.player_set_eye_offset(player, eye_offset, eye_offset)
	else
		player:set_eye_offset(eye_offset, eye_offset)
	end
end

local function get_health_boost_bonus(player)
	local potions = rawget(_G, "mcl_potions")
	if not (potions and potions.get_effect) then
		return 0
	end
	local eff = potions.get_effect(player, "health_boost")
	if type(eff) ~= "table" then
		return 0
	end
	return tonumber(eff.factor) or 0
end

function Race:get_base_hp_max()
	local hp_max = tonumber(self.hp_max)
	if not hp_max then
		hp_max = round_int((core.PLAYER_MAX_HP_DEFAULT or 20) * (tonumber(self.hp_factor) or 1.0))
	end
	hp_max = math.floor(hp_max)
	if hp_max < 1 then hp_max = 1 end
	return hp_max
end

	function Race:apply_health(player, opts)
		if not (player and player.is_player and player:is_player()) then
			return
		end
		opts = opts or {}
		local base = self:get_base_hp_max()
		local target = base + get_health_boost_bonus(player)

		local props = player:get_properties()
		local current_max = props and props.hp_max or nil
		if current_max ~= target then
			player:set_properties({hp_max = target})
		end

		-- Clamp engine HP and Mineclonia's internal mcl_health float to the new max,
		-- or heal fully when requested (race assignment).
		local meta = player:get_meta()
		if opts.heal_full then
			player:set_hp(target, {type = "set_hp", mcl_damage = true})
			if meta then
				meta:set_float("mcl_health", target)
			end
		elseif player:get_hp() > target then
			player:set_hp(target, {type = "set_hp", mcl_damage = true})
		end
		local internal = meta and meta:get_float("mcl_health") or 0
		if internal > 0 and internal > target then
			meta:set_float("mcl_health", target)
		end
	local serverplayer = rawget(_G, "mcl_serverplayer")
	if serverplayer and serverplayer.update_vitals then
		serverplayer.update_vitals(player)
	end
end

function Race:apply_capabilities(player)
	local meta = player:get_meta()
	local name = player:get_player_name()
	local privs = core.get_player_privs(name)
	
	local flight_mode = self.flight_mode
	local allow_fly_priv = self.fly and flight_mode ~= "float"

	local had_race_fly = meta:get_int(KB_GRANTED_FLY) == 1
	local had_speed_override = meta:get_int(KB_FLY_SPEED) == 1
	local had_float_cap = meta:get_int(KB_FLOAT_CAP) == 1
	local had_elytra_cap = meta:get_int(KB_ELYTRA_CAP) == 1

	-- Flight ability handling
	if allow_fly_priv then
		if not privs.fly then
			privs.fly = true
			core.set_player_privs(name, privs)
			meta:set_int(KB_GRANTED_FLY, 1)
		end
		
		-- Set flight speed
		local updater = rawget(_G, "update_speed")
		if updater then
			updater(name, FLY_SPEED)
		else
			player:set_physics_override({ speed = FLY_SPEED })
		end
		meta:set_int(KB_FLY_SPEED, 1)
	else
		if had_race_fly and privs.fly then
			privs.fly = nil
			core.set_player_privs(name, privs)
		end
		meta:set_int(KB_GRANTED_FLY, 0)
		if had_speed_override then
			local updater = rawget(_G, "update_speed")
			if updater then
				updater(name, nil)
			else
				player:set_physics_override({ speed = 1 })
			end
			meta:set_int(KB_FLY_SPEED, 0)
		end
	end

	-- Floating capability
	if had_float_cap then
		meta:set_int(KB_FLOAT_CAP, 0)
		if mcl_serverplayer and mcl_serverplayer.set_fall_flying_capable then
			mcl_serverplayer.set_fall_flying_capable(player, false)
		end
	end

	-- Elytra capability
	if self.elytra and mcl_serverplayer and mcl_serverplayer.set_fall_flying_capable then
		if not had_elytra_cap then
			mcl_serverplayer.set_fall_flying_capable(player, true)
			meta:set_int(KB_ELYTRA_CAP, 1)
		end
	else
		if had_elytra_cap and mcl_serverplayer and mcl_serverplayer.set_fall_flying_capable then
			mcl_serverplayer.set_fall_flying_capable(player, false)
		end
		meta:set_int(KB_ELYTRA_CAP, 0)
	end

	self:apply_health(player)
end

function Race:give_kit(player)
	if not self.kit_func then return end
	local meta = player:get_meta()
	if meta:get_string(KB_KIT_AWARDED) == self.name then return end
	
	local inv = player:get_inventory()
	if not inv then return end
	
	self.kit_func(inv)
	meta:set_string(KB_KIT_AWARDED, self.name)
end

function Race:get_random_skin()
	if #self.skins == 0 then return nil end
	return self.skins[math.random(#self.skins)]
end

function Race:has_skin(texture)
	for _, tex in ipairs(self.skins) do
		if tex == texture then return true end
	end
	return false
end

-- --- Race Registry ---

local Registry = {
	races = {},
	weights = {
		common = 5,
		normal = 3,
		rare = 1,
		["very rare"] = 0.5,
	}
}

function Registry.register(name, def)
	local race = Race.new(name, def)
	Registry.races[name] = race
end

function Registry.get(name)
	if not name or name == "" then
		return nil
	end
	local race = Registry.races[name]
	if race then
		return race
	end
end

function Registry.roll()
	local list = {}
	local total_weight = 0
	for name, race in pairs(Registry.races) do
		local w = Registry.weights[race.rarity] or 1
		total_weight = total_weight + w
		table.insert(list, {race = race, weight = w})
	end
	
	local roll = math.random() * total_weight
	local cumulative = 0
	for _, item in ipairs(list) do
		cumulative = cumulative + item.weight
		if roll <= cumulative then
			return item.race
		end
	end
	-- Fallback
	for _, item in ipairs(list) do return item.race end
end

-- --- Helper Functions (Prefixes & Soulbound) ---

local prefix_api = rawget(_G, "mcl_lun_prefixes")

	local function apply_item_prefix(stack, prefix_id)
		if not stack or stack:is_empty() then return stack end
		if prefix_api and prefix_api.apply_prefix then
			return prefix_api.apply_prefix(stack, prefix_id)
		end
		return stack
	end
	
	local function clear_soulbound_custom_name(stack)
		if not stack or stack.is_empty and stack:is_empty() then
			return
		end
		local meta = stack:get_meta()
		if not meta then
			return
		end
		-- Older versions used `meta.name` which is rendered with tt.NAME_COLOR (yellow).
		-- Clear it so soulbound doesn't force a name color.
		local n = meta:get_string("name")
		if type(n) == "string" and n:sub(1, 10) == "Soulbound " then
			meta:set_string("name", "")
		end
	end

	local function ensure_soulbound_display(stack)
		-- Keep the soulbound marker persistent, and rebuild the prefix-based description
		-- (Mineclonia may clear item meta descriptions on join).
		clear_soulbound_custom_name(stack)
		return apply_item_prefix(stack, "soulbound")
	end

	local function make_soulbound(stack)
		stack:get_meta():set_string("mcl_lun_races:soulbound", "1")
		return ensure_soulbound_display(stack)
	end

local function is_soulbound_stack(stack)
	if type(stack) ~= "userdata" or not stack.is_empty or not stack.get_meta then
		return false
	end
	if stack:is_empty() then
		return false
	end
	local meta = stack:get_meta()
	return meta and meta:get_string("mcl_lun_races:soulbound") == "1"
end

local function purge_soulbound_items(player)
	local inv = player:get_inventory()
	if not inv then return end
	local list = inv:get_list("main") or {}
	local changed = false
	for idx, stack in ipairs(list) do
		if is_soulbound_stack(stack) then
			inv:set_stack("main", idx, ItemStack())
			changed = true
		end
	end
end

local function is_chestlike_pos(pos)
	local node = core.get_node_or_nil(pos)
	if not node or not node.name then
		return false
	end
	local name = node.name
	if name:sub(1, 10) == "mcl_chests:" then
		return true
	end
	if core.get_item_group(name, "chest_entity") > 0 then
		return true
	end
	if core.get_item_group(name, "shulker_box") > 0 then
		return true
	end
	return false
end

local function destroy_soulbound_in_list(inv, listname)
	local list = inv and listname and inv:get_list(listname) or nil
	if not list then
		return
	end
	for i, stack in ipairs(list) do
		if is_soulbound_stack(stack) then
			inv:set_stack(listname, i, ItemStack())
		end
	end
end

local function play_soulbound_destroy_sound(pos, player)
	if not pos then
		return
	end
	if player and player.is_player and player:is_player() then
		-- Don't play on death; player HP is typically 0 during death-drop processing.
		local hp = player.get_hp and player:get_hp() or 0
		if hp <= 0.1 then
			return
		end
	else
		-- Only play the sound when we can associate it with a living player
		-- (avoids playing it during death-drop cleanup).
		return
	end
	core.sound_play("default_tool_breaks", {pos = pos, max_hear_distance = 16, gain = 1.0}, true)
end

	-- Soulbound drops must be handled *after* Mineclonia overrides `core.item_drop`,
	-- otherwise our wrapper gets clobbered and you get client inventory flicker/desync.
	core.register_on_mods_loaded(function()
		if core._mcl_lun_races_item_drop_wrapped then
			return
		end
		core._mcl_lun_races_item_drop_wrapped = true

		local orig_item_drop = core.item_drop
		if orig_item_drop and not core._mcl_lun_races_orig_item_drop then
			core._mcl_lun_races_orig_item_drop = orig_item_drop
		end

		if not orig_item_drop then
			return
		end

		core.item_drop = function(itemstack, dropper, pos)
			if not is_soulbound_stack(itemstack) then
				return orig_item_drop(itemstack, dropper, pos)
			end

			-- Destroy instead of spawning an item entity (no flicker; deterministic).
			local count = itemstack:get_count()

			if dropper and dropper.is_player and dropper:is_player() then
				local hp = dropper.get_hp and dropper:get_hp() or 0
				if hp > 0.1 then
					local controls = dropper:get_player_control()
					-- Mineclonia drops 1 item when sneaking.
					if controls and controls.sneak then
						count = 1
					end
					play_soulbound_destroy_sound(pos, dropper)
				else
					-- Death drops: destroy everything, and don't play sounds.
					count = itemstack:get_count()
				end
			end

			itemstack:take_item(count)
			return itemstack
		end
	end)

-- --- Kits Configuration ---

local fairy_flower_pool = {
	"mcl_flowers:poppy", "mcl_flowers:dandelion", "mcl_flowers:cornflower",
	"mcl_flowers:blue_orchid", "mcl_flowers:allium", "mcl_flowers:azure_bluet",
	"mcl_flowers:tulip_red", "mcl_flowers:tulip_orange", "mcl_flowers:tulip_white",
	"mcl_flowers:tulip_pink", "mcl_flowers:oxeye_daisy", "mcl_flowers:lily_of_the_valley",
	"mcl_flowers:peony", "mcl_flowers:rose_bush", "mcl_flowers:sunflower",
}

-- --- Fan Logic (Preserved & Adapted) ---
-- Kept separate as it's item logic, but adapted to interact with Race system

local fan_tier_meta_key = "mcl_lun_races:fan_tier"
local fan_stats_meta_key = "mcl_lun_races:fan_stats"

local fan_tiers = {
	standard = {force_multiplier = 1.0, upward_multiplier = 1.0, cooldown = 4, durability = 150},
	weak = {force_multiplier = 0.8, upward_multiplier = 0.8, cooldown = 5, durability = 100, prefix = "weak"},
	normal = {force_multiplier = 0.9, upward_multiplier = 0.9, cooldown = 4, durability = 150, prefix = "normal"},
	greater = {force_multiplier = 1.0, upward_multiplier = 1.0, cooldown = 3, durability = 200, prefix = "greater"},
}

local DEFAULT_FAN_TIER = "standard"
local fan_item_defaults = {
	["mcl_lun_races:hauchiwa_fan"] = "weak",
	["mcl_lun_races:hauchiwa_fan_normal"] = "normal",
	["mcl_lun_races:hauchiwa_fan_greater"] = "greater",
}

local function ensure_stack_object(stack)
	if not stack then return ItemStack("") end
	if getmetatable(stack) == ItemStack then return stack end
	if type(stack) == "userdata" and stack.get_meta then return stack end
	return ItemStack(stack)
end

local function set_fan_tier(stack, tier)
	stack = ensure_stack_object(stack)
	if stack:is_empty() or not fan_tiers[tier] then return stack end
	local meta = stack:get_meta()
	meta:set_string(fan_tier_meta_key, tier)
	meta:set_string(fan_stats_meta_key, "")
	local tier_def = fan_tiers[tier]
	if tier_def.prefix then stack = apply_item_prefix(stack, tier_def.prefix) end
	if prefix_api and prefix_api.set_extra_lines then prefix_api.set_extra_lines(stack, {}) end
	return stack
end

local function get_fan_tier(stack)
	stack = ensure_stack_object(stack)
	if stack:is_empty() then return DEFAULT_FAN_TIER, stack end
	local tier = stack:get_meta():get_string(fan_tier_meta_key)
	if tier == "" or not fan_tiers[tier] then
		local default = fan_item_defaults[stack:get_name()]
		if default and fan_tiers[default] then
			local updated = set_fan_tier(stack, default)
			return default, updated
		end
		return DEFAULT_FAN_TIER, stack
	end
	return tier, stack
end

local function roll_variation(base)
	if not base then return 0 end
	return base * (0.9 + math.random() * 0.2)
end

local function update_fan_description(stack, stats)
	if not stack or stack:is_empty() or not stats then return end
	local lines = {
		("Force Boost: %+0.1f"):format(stats.force or 0),
		("Lift Bonus: %+0.1f"):format(stats.upward or 0),
		("Cooldown: %0.1fs"):format(stats.cooldown or 0),
		("Durability: %d uses"):format(stats.uses or 0),
	}
	if prefix_api and prefix_api.set_extra_lines then
		prefix_api.set_extra_lines(stack, lines)
	else
		local def = core.registered_items[stack:get_name()]
		local base_desc = def and def.description or stack:get_name()
		stack:get_meta():set_string("description", base_desc .. "\n" .. table.concat(lines, "\n"))
	end
end

local CROW_BASE_BOOST_FORCE = 24
local CROW_BASE_BOOST_UPWARD = 6
local CROW_BASE_BOOST_COOLDOWN = 10
local CROW_DISTANCE_BONUS = 3
local crow_last_boost = {}

local function get_fan_stats(stack)
	stack = ensure_stack_object(stack)
	if stack:is_empty() then return nil, stack end
	local tier, updated_stack = get_fan_tier(stack)
	stack = updated_stack
	
	local tier_def = fan_tiers[tier] or fan_tiers[DEFAULT_FAN_TIER]
	local meta = stack:get_meta()
	local raw = meta:get_string(fan_stats_meta_key)
	local stats = raw ~= "" and core.deserialize(raw) or nil
	
	if type(stats) ~= "table" then
		local base_force = CROW_BASE_BOOST_FORCE * roll_variation(tier_def.force_multiplier or 1)
		stats = {
			force = base_force * 1.3,
			upward = CROW_BASE_BOOST_UPWARD * roll_variation(tier_def.upward_multiplier or tier_def.force_multiplier or 1),
			cooldown = math.max(0.5, roll_variation(tier_def.cooldown or CROW_BASE_BOOST_COOLDOWN)),
			uses = math.max(1, math.floor(roll_variation(tier_def.durability or 150))),
			tier = tier,
		}
		meta:set_string(fan_stats_meta_key, core.serialize(stats))
	end
	update_fan_description(stack, stats)
	return stats, stack
end

local function ensure_fan_stack_initialized(stack)
	if not stack or stack:is_empty() then return stack end
	if not fan_item_defaults[stack:get_name()] and not stack:get_name():find("mcl_lun_races:hauchiwa_fan", 1, true) then return stack end
	local _, initialized = get_fan_stats(stack)
	return initialized
end

local function ensure_rinnosuke_directions(player)
	if not (player and player.is_player and player:is_player()) then
		return
	end
	if not (core.registered_items and core.registered_items[RINNOSUKE_DIRECTIONS_ITEM]) then
		return
	end
	local inv = player:get_inventory()
	if not inv then
		return
	end
	-- Don't spam duplicates; also makes this safe across rerolls (we purge soulbound items).
	local list = inv:get_list("main") or {}
	for _, stack in ipairs(list) do
		if not stack:is_empty() and stack:get_name() == RINNOSUKE_DIRECTIONS_ITEM then
			return
		end
	end
	local stack = make_soulbound(ItemStack(RINNOSUKE_DIRECTIONS_ITEM))
	local leftover = inv:add_item("main", stack)
	if leftover and leftover.is_empty and not leftover:is_empty() then
		local pname = player:get_player_name()
		if pname and pname ~= "" then
			core.chat_send_player(pname, "Inventory full; couldn't give Rinnosuke's Directions yet.")
		end
		return
	end
end

local HOURAI_YAKITORI_ITEM = "mcl_lun_items:cooked_chicken"
local HOURAI_YAKITORI_FALLBACK = "mcl_mobitems:cooked_chicken"

local function ensure_hourai_yakitori(player)
	if not (player and player.is_player and player:is_player()) then
		return
	end
	local item = nil
	if core.registered_items and core.registered_items[HOURAI_YAKITORI_ITEM] then
		item = HOURAI_YAKITORI_ITEM
	elseif core.registered_items and core.registered_items[HOURAI_YAKITORI_FALLBACK] then
		item = HOURAI_YAKITORI_FALLBACK
	end
	if not item then
		return
	end
	local inv = player:get_inventory()
	if not inv then
		return
	end
	local list = inv:get_list("main") or {}
	for _, stack in ipairs(list) do
		if not stack:is_empty() and stack:get_name() == item then
			return
		end
	end
	local stack = make_soulbound(ItemStack(item .. " 8"))
	local leftover = inv:add_item("main", stack)
	if leftover and leftover.is_empty and not leftover:is_empty() then
		local pname = player:get_player_name()
		if pname and pname ~= "" then
			core.chat_send_player(pname, "Inventory full; couldn't give Chicken Yakitori yet.")
		end
	end
end

-- --- Register Races ---

Registry.register("Ice Fairy", {
	rarity = "common",
	spawnpoint = {x = 347, y = -23, z = 953},
	faction = "default",
	hp_factor = 0.8,
	scale = {x = 0.7, y = 0.7},
	skins = {"cirno.png"},
	flight_mode = "float",
	color = "lightblue",
	sounds = {
		random = "mobs_mc_bat_idle",
		damage = "mobs_mc_bat_hurt",
		distance = 10,
		accept = "mobs_mc_bat_idle",
		deny = sound_random("mobs_mc_bat_hurt.1.ogg", "mobs_mc_bat_hurt.2.ogg", "mobs_mc_bat_hurt.3.ogg"),
		trade = "mobs_mc_bat_idle",
	},
	kit_func = function(inv)
		for i = 1, 3 do
			local flower = fairy_flower_pool[math.random(#fairy_flower_pool)]
			local count = math.random(1, 4)
			inv:add_item("main", make_soulbound(ItemStack(flower .. " " .. count)))
		end
		inv:add_item("main", make_soulbound(ItemStack("mcl_farming:cookie 16")))
	end
})

Registry.register("Greater Fairy", {
	rarity = "common",
	spawnpoint = default_spawnpoint(),
	faction = "default",
	hp_factor = 0.8,
	scale = {x = 0.75, y = 0.75},
	skins = {"daiyousei.png"},
	flight_mode = "float",
	color = "lightgreen",
	sounds = {
		random = "mobs_mc_bat_idle",
		damage = "mobs_mc_bat_hurt",
		distance = 10,
		accept = "mobs_mc_bat_idle",
		trade = "mobs_mc_bat_idle",
	},
	kit_func = function(inv)
		for i = 1, 3 do
			local flower = fairy_flower_pool[math.random(#fairy_flower_pool)]
			local count = math.random(1, 4)
			inv:add_item("main", make_soulbound(ItemStack(flower .. " " .. count)))
		end
		inv:add_item("main", make_soulbound(ItemStack("mcl_farming:cookie 16")))
	end
})

--[[Registry.register("Flower Fairy", {
	rarity = "common",
	spawnpoint = default_spawnpoint(),
	faction = "default",
	hp_factor = 0.8,
	scale = {x = 0.65, y = 0.65},
	skins = {"daiyousei.png"},
	flight_mode = "float",
	color = "pink",
	sounds = {
		random = "mobs_mc_bat_idle",
		damage = "mobs_mc_bat_hurt",
		distance = 10,
		accept = "mobs_mc_bat_idle",
		trade = "mobs_mc_bat_idle",
	},
})]]

Registry.register("Human Villager", {
	rarity = "normal",
	spawnpoint = default_spawnpoint(),
	faction = "default",
	scale = {x = 0.8, y = 0.8},
	skins = {"village_boy_1.png", "village_boy_2.png"},
	fly = false,
	color = "beige",
	kit_func = function(inv)
		inv:add_item("main", make_soulbound(ItemStack("mcl_core:stick 3")))
		inv:add_item("main", make_soulbound(ItemStack("mcl_mobitems:cooked_porkchop 2")))
		end
	})

Registry.register("Hourai Immortal (Mokou)", {
	rarity = "rare",
	spawnpoint = {x = 978, y = 2.5, z = 1024},
	faction = "default",
	hp_factor = 2.0,
	scale = {x = 1.0, y = 1.0},
	model = "mcl_armor_character_female_lun.b3d",
	skins = {"mokou.png"},
	color = "crimson",
	kit_func = function(inv)
		inv:add_item("main", make_soulbound(ItemStack("mcl_lun_items:cooked_chicken 8")))
		inv:add_item("main", make_soulbound(ItemStack("mcl_lun_items:yakitori_tare 4")))
	end
})

Registry.register("Hourai Immortal (Kaguya)", {
	rarity = "rare",
	spawnpoint = {x = 1588, y = -1.5, z = 1394},
	faction = "default",
	hp_factor = 2.0,
	scale = {x = 1.0, y = 1.0},
	model = "mcl_armor_character_female_lun.b3d",
	skins = {"kaguya.png"},
	color = "purple",
	kit_func = function(inv)
		inv:add_item("main", make_soulbound(ItemStack("mcl_lun_items:hourai_eda")))
	end
})

--[[Registry.register("Kappa", {
	rarity = "normal",
	spawnpoint = default_spawnpoint(),
	faction = "default",
	scale = {x = 0.65, y = 0.65},
	skins = {"village_boy_1.png"},
	fly = false,
	color = "teal",
})

Registry.register("Sin Sack", {
	rarity = "rare",
	spawnpoint = default_spawnpoint(),
	faction = "default",
	scale = {x = 1.0, y = 1.0},
	skins = {"sin_sack.png"},
	fly = false,
	color = "darkred",
	kit_func = function(inv)
		inv:add_item("main", "mcl_flowers:rose_bush")
		inv:add_item("main", make_soulbound(ItemStack("mcl_mobitems:cooked_beef 8")))
	end
})]]

Registry.register("Crow Tengu", {
	rarity = "normal",
	spawnpoint = default_spawnpoint(),
	faction = "default",
	hp_factor = 0.7,
	scale = {x = 0.9, y = 0.9},
	skins = {"crow_tengu.png"},
	elytra = true,
	color = "darkorange",
	kit_func = function(inv)
		inv:add_item("main", make_soulbound(ItemStack("mcl_fishing:fish_cooked")))
		inv:add_item("main", make_soulbound(ItemStack("mcl_core:stick 2")))
		local fan = ItemStack("mcl_lun_races:hauchiwa_fan")
		fan = set_fan_tier(fan, "weak")
		fan = make_soulbound(fan)
		fan = ensure_fan_stack_initialized(fan)
		inv:add_item("main", fan)
	end
})

--[[Registry.register("Wolf Tengu", {
	rarity = "normal",
	spawnpoint = default_spawnpoint(),
	faction = "default",
	hp_factor = 1.1,
	skins = {"crow_tengu.png"},
	fly = false,
	color = "slategray",
})]]


-- --- API Logic ---

local function apply_skin_texture(player, texture)
	if not texture then return end
	if not mcl_skins or not mcl_skins.texture_to_simple_skin then return end
	if not mcl_skins.texture_to_simple_skin[texture] then return end

	local skin_state = mcl_skins.player_skins[player]
	if not skin_state then
		skin_state = table.copy(mcl_skins.alex)
		mcl_skins.player_skins[player] = skin_state
	end
	skin_state.simple_skins_id = texture
	skin_state.base = nil
	skin_state.slim_arms = mcl_skins.texture_to_simple_skin[texture].slim_arms
	mcl_skins.save(player)
	mcl_skins.update_player_skin(player)
end

function races_api.get_race(player)
	if not player then return nil end
	return player:get_meta():get_string(KB_RACE)
end

function races_api.get_race_color(name)
	local race = Registry.get(name)
	return race and race.color or nil
end

function races_api.get_definition(name)
	return Registry.get(name)
end

function races_api.get_faction(player)
	if not player then return nil end
	local meta = player.get_meta and player:get_meta()
	if meta then
		local f = meta:get_string(KB_FACTION)
		if f ~= "" then
			return f
		end
	end
	local race_name = races_api.get_race(player)
	local race = race_name and Registry.get(race_name) or nil
	return race and race.faction or nil
end

	local function apply_race_full(player, race_name, forced_texture)
		local race = Registry.get(race_name)
		if not race then return end
	
	-- Transition Logic
	local meta = player:get_meta()
	local last_race = meta:get_string(KB_LAST_RACE)
	if last_race ~= race.name then
		purge_soulbound_items(player)
		meta:set_string(KB_LAST_RACE, race.name)
		meta:set_string(KB_KIT_AWARDED, "")
	end

	-- Skin
	local texture = forced_texture
	if not texture then
		local current = meta:get_string(KB_SKIN)
		if current ~= "" and race:has_skin(current) then
			texture = current
		else
			-- Check mcl_skins match
			if mcl_skins and mcl_skins.player_skins and mcl_skins.player_skins[player] then
				local s = mcl_skins.player_skins[player].simple_skins_id
				if s and race:has_skin(s) then texture = s end
			end
		end
	end
	if not texture then texture = race:get_random_skin() end
	
	if texture then
		apply_skin_texture(player, texture)
		meta:set_string(KB_SKIN, texture)
	end

		-- Visuals & Caps
		race:apply_model(player)
		race:apply_visuals(player)
		race:apply_capabilities(player)
		-- When a race is assigned, heal to the new max HP immediately (matches expectation when rerolling).
		race:apply_health(player, {heal_full = true})
		race:give_kit(player)
		ensure_rinnosuke_directions(player)

	-- Persist faction for other mods/UI.
	meta:set_string(KB_FACTION, tostring(race.faction or "default"))
end

local function maybe_apply_first_spawn(player, race)
	if not (player and player.is_player and player:is_player()) then
		return
	end
	if not race then
		return
	end
	local meta = player:get_meta()
	if meta:get_int(KB_FIRST_SPAWNED) == 1 then
		return
	end
	meta:set_int(KB_FIRST_SPAWNED, 1)
	local spawn = normalize_spawnpoint(race.spawnpoint)
	if not spawn then
		return
	end
	local pname = player:get_player_name()
	core.after(0, function()
		local p = core.get_player_by_name(pname)
		if not p then
			return
		end
		core.load_area(spawn)
		p:set_pos(vector.add(spawn, {x = 0, y = 0.5, z = 0}))
		-- If the player has no personal spawn set, face south (+Z) at the spawn.
		local m = p:get_meta()
		local has_custom_spawn = m and m:get_string("mcl_beds:spawn") ~= ""
		if not has_custom_spawn and p.set_look_horizontal then
			p:set_look_horizontal(math.pi)
		end
		if not has_custom_spawn and p.set_look_vertical then
			p:set_look_vertical(0)
		end
	end)
end

local RACE_SELECT_FORMNAME = "mcl_lun_races:race_select"
local race_select_sessions = {}

local function get_race_select_session(name)
	if not name or name == "" then
		return nil
	end
	local s = race_select_sessions[name]
	if not s then
		s = {page = 1}
		race_select_sessions[name] = s
	end
	return s
end

local function build_race_skin_options()
	local opts = {}
	for race_name, race in pairs(Registry.races) do
		local skins = race and race.skins or nil
		if skins and #skins > 0 then
			for _, tex in ipairs(skins) do
				opts[#opts + 1] = {race = race_name, texture = tex}
			end
		else
			opts[#opts + 1] = {race = race_name, texture = nil}
		end
	end
	table.sort(opts, function(a, b)
		if a.race == b.race then
			return (a.texture or "") < (b.texture or "")
		end
		return a.race < b.race
	end)
	return opts
end

local function freeze_player_for_race_select(player)
	if not (player and player.is_player and player:is_player()) then
		return
	end
	local pname = player:get_player_name()
	local sess = get_race_select_session(pname)
	if not sess or sess.frozen then
		return
	end
	sess.frozen = true
	if player.get_physics_override then
		sess.prev_physics = player:get_physics_override()
	end
	-- Freeze in place while selecting a race.
	if player.set_physics_override then
		player:set_physics_override({speed = 0, jump = 0, gravity = 0})
	end
end

local function unfreeze_player_after_race_select(player)
	if not (player and player.is_player and player:is_player()) then
		return
	end
	local pname = player:get_player_name()
	local sess = pname and race_select_sessions[pname] or nil
	if not sess or not sess.frozen then
		return
	end
	sess.frozen = false
	if player.set_physics_override then
		if type(sess.prev_physics) == "table" and next(sess.prev_physics) ~= nil then
			player:set_physics_override(sess.prev_physics)
		else
			player:set_physics_override({speed = 1, jump = 1, gravity = 1})
		end
	end
	sess.prev_physics = nil
end

local function mesh_for_texture(texture)
	local skins = rawget(_G, "mcl_skins")
	if skins and texture and skins.texture_to_simple_skin and skins.texture_to_simple_skin[texture] then
		local slim = skins.texture_to_simple_skin[texture].slim_arms
		if slim then
			return "mcl_armor_character_female.b3d"
		end
	end
	return "mcl_armor_character.b3d"
end

local function show_race_select_formspec(player)
	if not (player and player.is_player and player:is_player()) then
		return
	end

	local pname = player:get_player_name()
	local sess = get_race_select_session(pname)
	if not sess then
		return
	end

	if not sess.options then
		sess.options = build_race_skin_options()
	end

	local opts = sess.options
	local per_page = 8
	local page_count = math.max(1, math.ceil(#opts / per_page))
	local page = tonumber(sess.page) or 1
	page = math.floor(page)
	if page < 1 then page = 1 end
	if page > page_count then page = page_count end
	sess.page = page

	local fs_escape = core.formspec_escape or function(s) return s end

	local formspec = "formspec_version[3]size[14.2,11]"
		.. "label[0.4,0.3;" .. fs_escape("Choose your race") .. "]"
		.. "textarea[0.4,0.7;4.0,2.9;;;"
		.. fs_escape("Pick a race/skin to begin. You will spawn after selecting.") .. "]"
		.. "image_button[0.4,9.8;4.0,0.9;mcl_skins_button.png;race_random;" .. fs_escape("Random") .. "]"
		-- Make the race pick buttons transparent over the 3D previews.
		.. "style_type[button;bgcolor=#00000000]"

	local start = (page - 1) * per_page + 1
	local finish = math.min(start + per_page - 1, #opts)

	for idx = start, finish do
		local opt = opts[idx]
		local k = idx - start
		local col = k % 4
		local row = math.floor(k / 4)
		local x = 4.5 + col * 1.6
		local y = 0.7 + row * 3.1

		local texture = opt.texture or "blank.png"
		local mesh = mesh_for_texture(opt.texture)
		local btn = "pick_" .. idx
		local tip = (opt.race or "Unknown")

		formspec = formspec
			.. "model[" .. x .. "," .. y .. ";1.5,3;player_mesh;" .. mesh .. ";"
			.. texture .. ",blank.png,blank.png;0,180;false;true;0,0]"
			.. "tooltip[" .. btn .. ";" .. fs_escape(tip) .. "]"
			.. "button[" .. x .. "," .. y .. ";1.5,3;" .. btn .. ";]"
	end

	if page > 1 then
		formspec = formspec .. "image_button[4.5,6.9;1,1;mcl_skins_arrow.png^[transformFX;race_prev;]"
	end
	if page < page_count then
		formspec = formspec .. "image_button[9.8,6.9;1,1;mcl_skins_arrow.png;race_next;]"
	end
	if page_count > 1 then
		formspec = formspec .. "label[7.3,7.4;" .. page .. " / " .. page_count .. "]"
	end

	core.show_formspec(pname, RACE_SELECT_FORMNAME, formspec)
end

local function begin_race_select(player, opts)
	if not (player and player.is_player and player:is_player()) then
		return
	end
	local pname = player:get_player_name()
	local sess = get_race_select_session(pname)
	if not sess then
		return
	end
	sess.force = opts and opts.force == true or false
	freeze_player_for_race_select(player)
	sess.options = sess.options or build_race_skin_options()

	if sess.force then
		show_race_select_formspec(player)
		return
	end

	core.after(0, function()
		local p = core.get_player_by_name(pname)
		if not p then
			return
		end
		-- Still unassigned? Keep the selection open.
		local current = p:get_meta():get_string(KB_RACE)
		if current == "" or not Registry.get(current) then
			show_race_select_formspec(p)
		end
	end)
end

local function teleport_to_race_spawn(player, race)
	if not (player and player.is_player and player:is_player()) then
		return
	end
	if not race then
		return
	end
	local spawn = normalize_spawnpoint(race.spawnpoint)
	if not spawn then
		return
	end
	local pname = player:get_player_name()
	core.after(0, function()
		local p = core.get_player_by_name(pname)
		if not p then
			return
		end
		core.load_area(spawn)
		p:set_pos(vector.add(spawn, {x = 0, y = 0.5, z = 0}))
		-- For /reroll2: if the player has no personal spawn set, face south (+Z).
		local m = p:get_meta()
		local has_custom_spawn = m and m:get_string("mcl_beds:spawn") ~= ""
		if not has_custom_spawn and p.set_look_horizontal then
			p:set_look_horizontal(math.pi)
		end
		if not has_custom_spawn and p.set_look_vertical then
			p:set_look_vertical(0)
		end
	end)
end

local function finalize_race_select(player, race_name, texture, opts)
	if not (player and player.is_player and player:is_player()) then
		return
	end
	local race = Registry.get(race_name)
	if not race then
		return
	end

	local meta = player:get_meta()
	meta:set_string(KB_RACE, race.name)
	meta:set_string("race", race.name) -- legacy key?
	meta:set_string(KB_SKIN, texture or "")

	unfreeze_player_after_race_select(player)
	apply_race_full(player, race.name, texture)
	maybe_apply_first_spawn(player, race)
	if opts and opts.spawn == true then
		teleport_to_race_spawn(player, race)
	end

	local race_label = race.name:gsub("^%l", string.upper)
	local colored_name = race.color and core.colorize(race.color, race_label) or race_label
	core.chat_send_player(player:get_player_name(), "Your race: " .. colored_name)

	local pname = player:get_player_name()
	race_select_sessions[pname] = nil
	if core.close_formspec then
		core.close_formspec(pname, RACE_SELECT_FORMNAME)
	end
end

local function ensure_player_race(player)
	local meta = player:get_meta()
	local current = meta:get_string(KB_RACE)
	local race = current ~= "" and Registry.get(current) or nil
	if not race then
		begin_race_select(player)
		return
	end
	apply_race_full(player, current)
	local race_label = current:gsub("^%l", string.upper)
	local colored_name = race.color and core.colorize(race.color, race_label) or race_label
	core.chat_send_player(player:get_player_name(), "Your race: " .. colored_name)
end

	local function play_hauchiwa_attack_animation(player)
		if not player or not player:is_player() then
			return
		end
		if mcl_player and mcl_player.force_swing_animation then
			mcl_player.force_swing_animation(player, 0.4)
		elseif mcl_player and mcl_player.player_set_animation then
			mcl_player.player_set_animation(player, "mine")
		else
			player:set_animation({x = 189, y = 198}, 30, 0)
		end
	end

-- --- Fan Item Registration ---

	local function register_hauchiwa_fan(itemname, def)
		local tier = def.tier
		local function is_fall_flying(player)
			local serverplayer = rawget(_G, "mcl_serverplayer")
			if serverplayer and serverplayer.is_csm_capable and serverplayer.is_csm_capable(player) then
				local state = serverplayer.client_states and serverplayer.client_states[player]
				if state and type(state.is_fall_flying) == "boolean" then
					return state.is_fall_flying
				end
			end

			-- Fallback path (same pattern as Mineclonia fireworks): use the server-side
			-- elytra state if the client-side movement state handshake isn't available.
			local player_api = rawget(_G, "mcl_player")
			local pdata = player_api and player_api.players and player_api.players[player]
			local elytra = pdata and pdata.elytra
			return elytra and elytra.active == true
		end

		local function try_crow_boost(user, stack)
			if not user or not user:is_player() then
				return false, stack
			end
			if races_api and races_api.get_race and races_api.get_race(user) ~= "Crow Tengu" then
				return false, stack
			end
			if not is_fall_flying(user) then
				return false, stack
			end

			local stats = get_fan_stats(stack)
			if not stats then
				return false, stack
			end
			local pname = user:get_player_name()
			local now = core.get_us_time and core.get_us_time() or (core.get_gametime() * 1000000)
			local last = crow_last_boost[pname] or 0
			local cd = tonumber(stats.cooldown) or CROW_BASE_BOOST_COOLDOWN
			if now - last < cd * 1000000 then
				return true, stack
			end

			local function use_rocket_boost(duration)
				local serverplayer = rawget(_G, "mcl_serverplayer")
				if serverplayer and serverplayer.is_csm_capable and serverplayer.is_csm_capable(user)
					and serverplayer.use_rocket then
					return serverplayer.use_rocket(user, duration) == true
				end
				local player_api = rawget(_G, "mcl_player")
				local pdata = player_api and player_api.players and player_api.players[user]
				local elytra = pdata and pdata.elytra
				if elytra and elytra.active then
					elytra.rocketing = duration
					return true
				end
				return false
			end

			local duration_by_tier = {
				weak = 0.6,
				normal = 0.8,
				greater = 1.0,
			}
			local duration = duration_by_tier[tier] or 0.8
			if not use_rocket_boost(duration) then
				return true, stack
			end

			crow_last_boost[pname] = now
			core.sound_play("power1", {object = user, gain = 0.6, max_hear_distance = 24}, true)

			-- Wear as a tool (Mineclonia-style durability is still 200 uses for the item).
			if stack and stack.add_wear_by_uses then
				stack:add_wear_by_uses(200)
			end
			return true, stack
	end

	local function fire_projectile(user)
		if rawget(_G, "mcl_lun_items_launch_hauchiwa_projectile") then
			mcl_lun_items_launch_hauchiwa_projectile(user, itemname)
		end
		play_hauchiwa_attack_animation(user)
	end
		-- Use mcl_lun_items description API (no overrides).
		local lun_items = rawget(_G, "mcl_lun_items")
		local build_desc = lun_items and lun_items.build_lun_description
		local build_tt = lun_items and lun_items.build_lun_tt
		local get_def = lun_items and lun_items.get_item_def

		local color_by_tier = {
			weak = "#9e9e9e",
			normal = "#a347ff",
			greater = "#ffb347",
		}
		local reg = get_def and get_def(itemname) or nil
		if reg and reg.desc_color then
			color_by_tier[tier] = reg.desc_color
		end

		local base_name = def.description or "Hauchiwa Fan"
		local description = base_name
		if build_desc then
			description = build_desc({
				description = base_name,
				color = color_by_tier[tier],
				skip_stats = true,
				flavor = "Fires a maple-leaf burst\nLeft click: arcing gust\nRight click while gliding as a Crow Tengu to boost",
			})
		end
		local tt_help = nil
		if build_tt then
			tt_help = build_tt({
				lines = {
					{text = "Right click while gliding as a Crow Tengu to boost", color = "orange"},
				},
			})
		end
			core.register_tool(itemname, {
					description = description,
					_tt_help = tt_help,
					_doc_items_longdesc = "A tengu fan that channels burst winds while gliding.",
					_doc_items_usagehelp = "Left click: Fire a gust projectile. Right click while gliding as a Crow Tengu to boost.",
					_doc_items_durability = 200,
					inventory_image = "hauchiwa_fan.png",
					wield_image = "hauchiwa_fan.png",
				wield_scale = { x = 1.5, y = 1.5, z = 1.5 },
				stack_max = 1,
				groups = {stick = 1, flammable = 2, tool = 1, handy = 1},
				_mcl_toollike_wield = true,
				_mcl_uses = 200,
				mcl_lun_base_description = "Hauchiwa Fan",
				sound = {breaks = "default_tool_breaks"},
				on_use = function(stack, user, pointed_thing)
					fire_projectile(user)
				return stack
		end,
			on_secondary_use = function(stack, user, pointed_thing)
				if user and user:is_player()
					and races_api and races_api.get_race and races_api.get_race(user) == "Crow Tengu"
					and is_fall_flying(user) then
					_, stack = try_crow_boost(user, stack)
					return stack
				end

				fire_projectile(user)
				return stack
			end,
			tool_capabilities = {
				full_punch_interval = 1.0, max_drop_level = 0, uses = 200,
				time = {[1]=3.0, [2]=3.0, [3]=3.0}, damage_groups = {fleshy = 1}
			},
	})
end

register_hauchiwa_fan("mcl_lun_races:hauchiwa_fan", {description="Weak Hauchiwa Fan", tier="weak"})
register_hauchiwa_fan("mcl_lun_races:hauchiwa_fan_normal", {description="Normal Hauchiwa Fan", tier="normal"})
register_hauchiwa_fan("mcl_lun_races:hauchiwa_fan_greater", {description="Greater Hauchiwa Fan", tier="greater"})

-- Crafts & Inventory Hooks for Fans
core.register_on_craft(function(itemstack)
	if not itemstack or itemstack:is_empty() then return itemstack end
	return ensure_fan_stack_initialized(itemstack)
end)

local function refresh_inventory_fan(inv, listname, index)
	if not inv or not listname or not index then return end
	local stack = inv:get_stack(listname, index)
	if stack:is_empty() then return end
	inv:set_stack(listname, index, ensure_fan_stack_initialized(stack))
end

core.register_on_player_inventory_action(function(player, action, inventory, info)
	if not inventory or type(info) ~= "table" then return end
	local function handle(listname, index)
		if listname and index then refresh_inventory_fan(inventory, listname, index) end
	end
	if action == "put" or action == "take" then
		handle(info.list, info.index)
	elseif action == "move" then
		handle(info.from_list, info.from_index)
		handle(info.to_list, info.to_index)
	end
	if action == "move" then -- Also check source
		handle(info.from_list, info.from_index) 
	end
end)

if core.register_on_item_drop then
	core.register_on_item_drop(function(player, itemstack, dropper)
		-- Defensive: some engines/modpacks may pass different args; never crash here.
		if type(itemstack) == "userdata" and itemstack.is_empty and itemstack.get_meta then
			if itemstack:is_empty() then
				return itemstack
			end
			return ensure_fan_stack_initialized(itemstack)
		end
		return itemstack
	end)
end

-- --- Commands & Callbacks ---

core.register_chatcommand("reroll", {
	description = "Re-roll your race",
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then return false, "Player not found." end
		local meta = player:get_meta()
		local race = Registry.roll()
		local rname = race.name
		meta:set_string(KB_RACE, rname)
		meta:set_string("race", rname)
		meta:set_string(KB_SKIN, "") -- Clear skin to force re-roll
		apply_race_full(player, rname)
		core.chat_send_player(name, "Race re-rolled to: " .. rname)
		return true
	end
})

core.register_chatcommand("reroll2", {
	description = "Re-open the race selection menu",
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "Player not found."
		end
		begin_race_select(player, {force = true})
		return true, "Race selection opened."
	end,
})

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= RACE_SELECT_FORMNAME then
		return false
	end
	if not (player and player.is_player and player:is_player()) then
		return true
	end

	local pname = player:get_player_name()
	local sess = pname and race_select_sessions[pname] or nil
	if not sess then
		-- Recreate session if player still has no race.
		local current = player:get_meta():get_string(KB_RACE)
		if current == "" or not Registry.get(current) then
			begin_race_select(player)
		end
		return true
	end

	if fields.quit then
		-- Don't allow closing without choosing a race.
		local current = player:get_meta():get_string(KB_RACE)
		if current == "" or not Registry.get(current) then
			begin_race_select(player)
		end
		return true
	end

	if fields.race_prev then
		sess.page = math.max(1, (sess.page or 1) - 1)
		show_race_select_formspec(player)
		return true
	end
	if fields.race_next then
		sess.page = (sess.page or 1) + 1
		show_race_select_formspec(player)
		return true
	end

	if fields.race_random then
		local race = Registry.roll()
		local tex = race and race:get_random_skin() or nil
		finalize_race_select(player, race and race.name, tex, {spawn = sess.force == true})
		return true
	end

	for f in pairs(fields) do
		local idx = f:match("^pick_(%d+)$")
		if idx then
			idx = tonumber(idx)
			local opt = idx and sess.options and sess.options[idx] or nil
			if opt then
				finalize_race_select(player, opt.race, opt.texture, {spawn = sess.force == true})
			end
			return true
		end
	end

	return true
end)

	core.register_on_joinplayer(function(player)
		-- Freeze immediately if the player has no assigned race yet.
		do
			local current = player:get_meta():get_string(KB_RACE)
		if current == "" or not Registry.get(current) then
			freeze_player_for_race_select(player)
		end
	end

		local pname = player:get_player_name()
		core.after(0, function()
			local p = core.get_player_by_name(pname)
			if not p then
				return
			end
			ensure_player_race(p)
			local inv = p:get_inventory()
			if inv then
					for _, list in ipairs({"main", "craft", "hand"}) do
						for i = 1, inv:get_size(list) do refresh_inventory_fan(inv, list, i) end
					end
					-- Mineclonia's join-time effect/enchant refresh may wipe `meta.description` for items.
					-- Soulbound items should keep their "Soulbound <name>" label across reconnects, so
					-- rebuild their display name + tooltip from persistent metadata here.
					if inv.get_lists and inv.set_lists then
						local lists = inv:get_lists()
						local touched = false
						for _, list in pairs(lists) do
							for i, stack in ipairs(list) do
								if is_soulbound_stack(stack) then
									list[i] = ensure_soulbound_display(stack)
									touched = true
								end
							end
						end
						if touched then
							inv:set_lists(lists)
						end
					end
				end
			end)
		end)

core.register_on_respawnplayer(function(player)
	core.after(0, function()
		if not player or not player:is_player() then
			return
		end
		local rname = races_api.get_race(player)
		local race = rname and Registry.get(rname) or nil
		if not race then
			ensure_player_race(player)
			rname = races_api.get_race(player)
			race = rname and Registry.get(rname) or nil
		end
		if not race then
			return
		end
		player:get_meta():set_string(KB_KIT_AWARDED, "")
		race:give_kit(player)
		local inv = player:get_inventory()
		if inv then
			for _, list in ipairs({"main", "hand"}) do
				for i=1, inv:get_size(list) do refresh_inventory_fan(inv, list, i) end
			end
		end
	end)
end)

-- Destroy soulbound items when they are put into or moved within chests/shulker boxes.
-- This engine build doesn't have global `register_on_metadata_inventory_*` hooks, so we wrap container node callbacks.
core.register_on_mods_loaded(function()
	for nodename, def in pairs(core.registered_nodes) do
		local groups = def and def.groups or nil
		local is_container = groups and ((groups.container or 0) > 0 or (groups.chest_entity or 0) > 0 or (groups.shulker_box or 0) > 0)
		if is_container or (type(nodename) == "string" and nodename:sub(1, 10) == "mcl_chests:") then
			if not def._mcl_lun_races_wrapped_container then
				def._mcl_lun_races_wrapped_container = true

				local orig_put = def.on_metadata_inventory_put
				def.on_metadata_inventory_put = function(pos, listname, index, stack, player)
					if orig_put then
						orig_put(pos, listname, index, stack, player)
					end
					if is_soulbound_stack(stack) and is_chestlike_pos(pos) then
						play_soulbound_destroy_sound(pos, player)
						local inv = core.get_meta(pos):get_inventory()
						if inv then
							inv:set_stack(listname, index, ItemStack())
							destroy_soulbound_in_list(inv, "main")
							destroy_soulbound_in_list(inv, "input")
						end
					end
				end

				local orig_move = def.on_metadata_inventory_move
				def.on_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
					if orig_move then
						orig_move(pos, from_list, from_index, to_list, to_index, count, player)
					end
					if is_chestlike_pos(pos) then
						local inv = core.get_meta(pos):get_inventory()
						if inv then
							destroy_soulbound_in_list(inv, to_list)
							destroy_soulbound_in_list(inv, "main")
							destroy_soulbound_in_list(inv, "input")
						end
					end
				end
			end
		end
	end
end)

core.register_globalstep(function(dtime)
	-- Periodic inventory refresh for fans? Original had it every 1s.
	-- We'll keep it simple to avoid lag, relying on hooks mostly.
end)

-- While the race selection menu is open, keep the player frozen even if other mods
-- attempt to change physics overrides.
local race_select_freeze_timer = 0
core.register_globalstep(function(dtime)
	race_select_freeze_timer = race_select_freeze_timer + (dtime or 0)
	if race_select_freeze_timer < 0.2 then
		return
	end
	race_select_freeze_timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local pname = player:get_player_name()
		local sess = pname and race_select_sessions[pname] or nil
		if sess and sess.frozen and player.set_physics_override then
			player:set_physics_override({speed = 0, jump = 0, gravity = 0})
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	crow_last_boost[name] = nil
	race_select_sessions[name] = nil
end)

mcl_player.register_on_visual_change(function(player)
	local rname = races_api.get_race(player)
    local race = Registry.get(rname)
	if race then
		race:apply_model(player)
		race:apply_visuals(player)
		race:apply_capabilities(player)
	end
end)

-- Initialize fan refresh timer if strictly needed, mimicking original:
local fan_refresh_timer = 0
core.register_globalstep(function(dtime)
	fan_refresh_timer = fan_refresh_timer + dtime
	if fan_refresh_timer < 1 then return end
	fan_refresh_timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		do
			local rname = races_api.get_race(player)
			local race = rname and Registry.get(rname) or nil
			if race then
				race:apply_health(player)
			end
		end
		local inv = player:get_inventory()
		if inv then
			for _, list in ipairs({"main", "hand"}) do
				for i=1, inv:get_size(list) do refresh_inventory_fan(inv, list, i) end
			end
		end
	end
end)

return races_api
