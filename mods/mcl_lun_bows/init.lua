mcl_lun_bows = {}

--Bow
dofile(core.get_modpath("mcl_lun_bows") .. "/arrow.lua")
dofile(core.get_modpath("mcl_lun_bows") .. "/bow.lua")

--Crossbow
dofile(core.get_modpath("mcl_lun_bows") .. "/crossbow.lua")

-- Legacy single-name bow routes to normal rarity
core.register_alias_force("mcl_lun_bows:lunar_bow", "mcl_lun_bows:lunar_bow_normal")
core.register_alias_force("mcl_lun_bows:lunar_bow_enchanted", "mcl_lun_bows:lunar_bow_normal_enchanted")

local wielded_light = rawget(_G, "wielded_light")
if wielded_light and wielded_light.register_item_light then
	local function register_light(name, level)
		if name and level then
			wielded_light.register_item_light(name, level, false)
		end
	end

	-- Determine luminance per rarity.
	local max_lum = 6
	local lum_weakened = 6
	local lum_normal = 8
	local lum_legendary = 10
	if mcl_lun_bows.BOW_RARITIES then
		lum_weakened = mcl_lun_bows.BOW_RARITIES.weakened.luminance or lum_weakened
		lum_normal = mcl_lun_bows.BOW_RARITIES.normal.luminance or lum_normal
		lum_legendary = mcl_lun_bows.BOW_RARITIES.legendary.luminance or lum_legendary
		max_lum = math.max(lum_weakened, lum_normal, lum_legendary)
	end

	-- Base/enchanted/charging variants per rarity.
	for rarity, lum in pairs({
		weakened = lum_weakened,
		normal = lum_normal,
		legendary = lum_legendary,
	}) do
		for _, enchanted in ipairs({false, true}) do
			register_light("mcl_lun_bows:lunar_bow_"..rarity..(enchanted and "_enchanted" or ""), lum)
			for stage=0,2 do
				register_light("mcl_lun_bows:lunar_bow_"..rarity.."_"..stage..(enchanted and "_enchanted" or ""), lum)
			end
		end
	end

	-- Flying/stuck arrow light helper entity.
	wielded_light.register_item_light("mcl_lun_bows:lunar_arrow_light", 18, false)
	core.log("action", string.format("[mcl_lun_bows] registered wielded_light for bows (normal=%d weakened=%d legendary=%d) and lunar_arrow_light=18",
		lum_normal, lum_weakened, lum_legendary))
end
