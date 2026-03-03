local gettext = minetest.get_translator("mcl_lun_npcs")
local races_api = rawget(_G, "mcl_lun_races")
local mobs_mc = rawget(_G, "mobs_mc")

if not races_api then
	minetest.log("action", "[mcl_lun_npcs] mcl_lun_races missing; NPC metadata unavailable")
	return
end

local race_index = races_api.race_index or {}
if not next(race_index) then
	minetest.log("action", "[mcl_lun_npcs] race index empty; nothing to register")
	return
end

if not mcl_mobs then
	minetest.log("action", "[mcl_lun_npcs] mcl_mobs missing; cannot register NPCs")
	return
end

if not mobs_mc or not mobs_mc.villager_base then
	minetest.log("action", "[mcl_lun_npcs] mobs_mc villager base unavailable")
	return
end

local villager_base = mobs_mc.villager_base
local race_meshes = {
	female = "mcl_armor_character_female.b3d",
	default = "mcl_armor_character.b3d",
}

local base_collision = villager_base.collisionbox or { -0.25, 0.0, -0.25, 0.25, 1.90, 0.25 }
local base_selection = villager_base.selectionbox or base_collision

local function sanitize(name)
	return name:gsub("%s+", "_")
end

local function scale_box(box, scale)
	local sx = scale.x or 1
	local sy = scale.y or 1
	return {
		box[1] * sx,
		box[2] * sy,
		box[3] * sx,
		box[4] * sx,
		box[5] * sy,
		box[6] * sx,
	}
end

local function compute_visual(scale)
	local sx = scale.x or 1
	local sy = scale.y or 1
	return { x = sx, y = sy }
end

local languages = {
	female = true,
	["fairy"] = true,
	["taller fairy"] = true,
	["village boy"] = true,
	["crow tengu"] = true,
	["sin sack"] = false,
}

local RaceTemplate = {}
RaceTemplate.__index = RaceTemplate

function RaceTemplate:new(name)
	local def = race_index[name]
	if not def then
		return nil
	end
	local base_scale = def.scale or { x = 1, y = 1 }
	local eye = def.eye_height or 1.2 * base_scale.y
	local eye_crouch = def.eye_height_crouching or 0.8 * base_scale.y
	-- Build texture variants; the character model expects 3 layers
	-- (skin + two optional overlays). We explicitly fill unused
	-- layers with blank textures to avoid stray cape/boot overlays.
	local textures = {}
	local skins = (def.skins and #def.skins > 0) and def.skins or { "character.png" }
	for _, skin in ipairs(skins) do
		table.insert(textures, { skin, "blank.png", "blank.png" })
	end
	local mesh = race_meshes.female
	if languages[name] == false then
		mesh = race_meshes.default
	end
	local sounds = def.sounds
	return setmetatable({
		name = name,
		def = def,
		mesh = mesh,
		textures = textures,
		sounds = sounds,
		base_scale = base_scale,
		base_eye = eye,
		base_eye_crouch = eye_crouch,
	}, self)
end

local function merge_tables(base, overrides)
	local merged = table.copy(base)
	for k, v in pairs(overrides) do
		merged[k] = v
	end
	return merged
end

function RaceTemplate:build_mob_def()
	local collision = scale_box(base_collision, self.base_scale)
	local selection = scale_box(base_selection, self.base_scale)
	local visual_size = compute_visual(self.base_scale)
	local overrides = {
		animation = self.def.animation,
		movement_speed = self.def.movement_speed,
		_inventory_size = self.def.inventory_size,
		_trades = self.def.trades,
		_villager_type = self.def.villager_type,
		_profession = self.def.profession,
		passive = self.def.passive,
		hp_min = self.def.hp_min,
		hp_max = self.def.hp_max,
		floats = self.def.floats,
		can_despawn = self.def.can_despawn,
		armor_groups = self.def.armor_groups,
	}
	local mob_def = merge_tables(villager_base, {
		description = gettext("@1", self.name),
		mesh = self.mesh,
		textures = self.textures,
		animation = overrides.animation,
		movement_speed = overrides.movement_speed,
		_inventory_size = overrides._inventory_size,
		_trades = overrides._trades,
		_villager_type = overrides._villager_type,
		_profession = overrides._profession,
		passive = overrides.passive,
		hp_min = overrides.hp_min,
		hp_max = overrides.hp_max,
		floats = overrides.floats,
		can_despawn = overrides.can_despawn,
		armor_groups = overrides.armor_groups,
		sounds = self.sounds,
		collisionbox = collision,
		selectionbox = selection,
		visual_size = visual_size,
		initial_properties = merge_tables(villager_base.initial_properties or {}, {
			visual_size = visual_size,
			collisionbox = collision,
			selectionbox = selection,
			eye_height = self.base_eye,
			eye_height_crouching = self.base_eye_crouch,
		}),
		_race_name = self.name,
	})
	return mob_def
end

for name, _ in pairs(race_index) do
	local race = RaceTemplate:new(name)
	if not race then
		minetest.log("warning", "[mcl_lun_npcs] race '" .. name .. "' undefined")
	else
		local mobname = "mcl_lun_npcs:" .. sanitize(name)
		mcl_mobs.register_mob(mobname, race:build_mob_def())
		minetest.log("action", "[mcl_lun_npcs] registered mob " .. mobname)
		mcl_mobs.register_egg(mobname, gettext("@1 spawn egg", race.name), "#c7c6d4", "#2e257b", 0)
		minetest.log("action", "[mcl_lun_npcs] registered spawn egg for " .. mobname)
	end
end
