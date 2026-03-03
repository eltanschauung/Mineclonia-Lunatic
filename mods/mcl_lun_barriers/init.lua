local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)
local cfg_path = modpath .. "/regions.cfg"
local factions = rawget(_G, "mcl_lun_factions")

local function ensure_cfg()
	if minetest.safe_file_write and not io.open(cfg_path, "r") then
		local default_cfg = {
			regions = {
				{
					name = "Hakurei Shrine",
					x1 = 100, y1 = 0, z1 = 1850,
					x2 = 190, y2 = 0, z2 = 1927,
					color = "red",
					protected = false,
					mobs = true,
					unlisted = false,
				},
				{
					name = "Moriya Shrine",
					x1 = 200, y1 = 0, z1 = 1950,
					x2 = 390, y2 = 0, z2 = 2027,
					color = "green",
					protected = false,
					mobs = true,
					unlisted = false,
				},
				{
					name = "Myouren Temple",
					x1 = 444, y1 = 0, z1 = 1980,
					x2 = 826, y2 = 0, z2 = 1800,
					color = "blue",
					protected = false,
					mobs = true,
					unlisted = false,
				},
				{
					name = "Human Village",
					x1 = 700, y1 = 0, z1 = 1385,
					x2 = 1302, y2 = 0, z2 = 1820,
					color = "green",
					protected = false,
					mobs = true,
					unlisted = false,
				},
				{
					name = "Scarlet Devil Mansion",
					x1 = 248, y1 = 0, z1 = 112,
					x2 = 650, y2 = 0, z2 = -447,
					color = "red",
					faction = "Scarlet Devil Mansion",
					protected = false,
					mobs = true,
					unlisted = false,
				},
				{
					name = "Misty Lake",
					x1 = 305, y1 = 0, z1 = 458,
					x2 = 812, y2 = 0, z2 = 937,
					color = "blue",
					protected = false,
					mobs = true,
					unlisted = false,
				},
				{
					name = "Prismriver Mansion",
					x1 = 868, y1 = 0, z1 = 756,
					x2 = 1052, y2 = 0, z2 = 544,
					color = "blue",
					protected = false,
					mobs = true,
					unlisted = false,
				},
				{
					name = "Mokou's House",
					x1 = 972, y1 = 0, z1 = 996,
					x2 = 1023, y2 = 0, z2 = 1051,
					color = "red",
					protected = false,
					mobs = true,
					unlisted = false,
				},
				{
					name = "Marisa's House",
					x1 = 600, y1 = 0, z1 = 1430,
					x2 = 640, y2 = 0, z2 = 1368,
					color = "yellow",
					protected = false,
					mobs = true,
					unlisted = false,
				},
				{
					name = "Alice's House",
					x1 = 500, y1 = 0, z1 = 1111,
					x2 = 570, y2 = 0, z2 = 1170,
					color = "yellow",
					protected = false,
					mobs = true,
					unlisted = false,
				},
				{
					name = "Cirno's Igloo",
					x1 = 386, y1 = 0, z1 = 968,
					x2 = 320, y2 = 0, z2 = 910,
					color = "blue",
					protected = false,
					mobs = true,
					unlisted = false,
				},
				{
					name = "Underground Geyser",
					x1 = -210, y1 = 0, z1 = 968,
					x2 = -141, y2 = 0, z2 = 800,
					color = "green",
					protected = false,
					mobs = true,
					unlisted = false,
				},
			},
		}
		minetest.safe_file_write(cfg_path, minetest.serialize(default_cfg))
	end
end

ensure_cfg()

local regions = {}
do
	local fh = io.open(cfg_path, "r")
	if fh then
		local data = fh:read("*all")
		fh:close()
		local des = minetest.deserialize(data)
		if type(des) == "table" and des.regions then
			regions = des.regions
		end
	end
end

-- Assign stable integer IDs to regions (1..N) and expose wilderness (id=0)
local REGION_BY_ID = {}
local REGION_WILDERNESS = {id = 0, name = "Wilderness", color = "green"}
for idx, reg in ipairs(regions) do
	reg.id = idx
	REGION_BY_ID[idx] = reg
end

local function is_inside(region, pos)
	if not region or not pos then return false end
	local minx = math.min(region.x1, region.x2)
	local maxx = math.max(region.x1, region.x2)
	local minz = math.min(region.z1, region.z2)
	local maxz = math.max(region.z1, region.z2)
	if not (pos.x >= minx and pos.x <= maxx and pos.z >= minz and pos.z <= maxz) then
		return false
	end

	-- Optional vertical bounds. Convention: y1=0,y2=0 means "no Y restriction" (keep legacy behavior).
	if type(region.y1) == "number" and type(region.y2) == "number" then
		if not (region.y1 == 0 and region.y2 == 0) then
			local miny = math.min(region.y1, region.y2)
			local maxy = math.max(region.y1, region.y2)
			return pos.y >= miny and pos.y <= maxy
		end
	end
	return true
end

local function find_region(pos)
	for _, reg in ipairs(regions) do
		if is_inside(reg, pos) then
			return reg
		end
	end
	return REGION_WILDERNESS
end

-- Prefer the game-provided HUD title API if present; fall back to chat as a last resort.
local mcl_title = rawget(_G, "mcl_title")
if not mcl_title or not mcl_title.set then
	mcl_title = {
		set = function(player, _, def)
			if not player or not player.is_player or not player:is_player() then return end
			local text = def and def.text or ""
			if text == "" then return end
			local name = player:get_player_name()
			minetest.chat_send_player(name, minetest.colorize(def and def.color or "#ffffff", text))
		end
	}
	_G.mcl_title = _G.mcl_title or mcl_title
end
local function color_fn(c)
	local cf = rawget(_G, "color")
	if cf then return cf(c) end
	return c
end
local last_title = {}
-- Keep titles from spamming; shortened to 5s so it lines up with chat notices.
local TITLE_COOLDOWN = 5
local current_region = {}

local function normalize_color(value)
	if type(value) == "string" then
		local s = value
		if s:match("^#%x%x%x%x%x%x$") or s:match("^#%x%x%x$") then
			return s
		end
		if color_fn then
			return color_fn(s) or "#ffffff"
		end
	end
	return "#ffffff"
end

local function maybe_show_title(player, region)
	if not player or not region then return end
	-- Be resilient to mod load order: mcl_title might not exist at init time.
	local title_api = rawget(_G, "mcl_title") or mcl_title
	if not title_api or not title_api.set then return end
	local name = player:get_player_name()
	if not name or name == "" then return end
	local now = minetest.get_gametime()
	local next_allowed = last_title[name] or 0
	if now < next_allowed then return end
	last_title[name] = now + TITLE_COOLDOWN
	local cval = normalize_color(region.color)
	-- mcl_title has no fade support; set stay to 60 gameticks (~3s) for brevity.
	title_api.set(player, "subtitle", {text = region.name or "Protected Area", color = cval, stay = 60})
end

local function check_player_region(player)
	if not player then return end
	local pos = player:get_pos()
	if not pos then return end
	local name = player:get_player_name()
	if not name or name == "" then return end

	local reg = find_region(pos)
	local prev = current_region[name]
	local prev_name = prev and prev.name or nil
	local reg_name = reg and reg.name or nil

	if reg ~= prev then
		local same_name = prev_name and reg_name and prev_name == reg_name
		-- Leave message (only if different names and previous was not wilderness)
		if prev and prev.id ~= REGION_WILDERNESS.id and not same_name then
			local msg = "Leaving: " .. minetest.colorize(normalize_color(prev.color), (prev.name or "region"))
			minetest.chat_send_player(name, msg)
		end
		-- Enter message (only if different names)
		if reg and not same_name then
			local region_color = normalize_color(reg.color)
			local msg = "Now entering: " .. minetest.colorize(region_color, (reg.name or "region"))
			minetest.chat_send_player(name, msg)

			local owner = reg.faction or "Unowned"
			local owner_color = region_color
			if factions and factions.get_faction_color and reg.faction then
				owner_color = normalize_color(factions.get_faction_color(reg.faction)) or owner_color
			end
			local owner_msg = "Owned by: " .. minetest.colorize(owner_color or region_color, owner)
			minetest.chat_send_player(name, owner_msg)
			-- Only show titles on explicit enter events (not when names are identical)
			maybe_show_title(player, reg)
		end
		current_region[name] = reg
	end
end

-- Public API
local API = {}
function API.get_player_region_id(player_or_name)
	local name = player_or_name
	if type(player_or_name) ~= "string" then
		name = player_or_name and player_or_name:get_player_name()
	end
	local reg = name and current_region[name]
	return reg and reg.id or REGION_WILDERNESS.id, reg or REGION_WILDERNESS
end

function API.get_region_at_pos(pos)
	return find_region(pos)
end

function API.is_pos_protected(pos)
	local reg = pos and find_region(pos)
	return reg and reg.id ~= REGION_WILDERNESS.id and reg.protected == true or false
end

function API.is_mobs_allowed(pos)
	local reg = pos and find_region(pos)
	if not reg or reg.id == REGION_WILDERNESS.id then
		return true
	end
	-- Default when missing: allow mobs (keep behavior unless explicitly disabled).
	if reg.mobs == nil then
		return true
	end
	return reg.mobs == true
end

_G.mcl_lun_barriers = API

local old_is_protected = minetest.is_protected

function minetest.is_protected(pos, name)
	if pos then
		local reg = find_region(pos)
		if reg and reg.id ~= REGION_WILDERNESS.id and reg.protected == true then
			-- Allow bypass if player has protection_bypass
			if name and core.check_player_privs then
				if core.check_player_privs(name, {protection_bypass = true}) then
					return false
				end
			end
			if name then
				local player = minetest.get_player_by_name(name)
				if player then
					maybe_show_title(player, reg)
				end
			end
			if not factions or not factions.get_player_faction then
				return true
			end
			local player_fac = factions.get_player_faction(name)
			local fac_name = player_fac and player_fac.name
			if fac_name == reg.faction then
				return false
			else
				return true
			end
		end
	end
	if old_is_protected then
		return old_is_protected(pos, name)
	end
	return false
end

minetest.register_on_protection_violation(function(pos, name)
	if not pos or not name or name == "" then
		return
	end
	local reg = find_region(pos)
	if reg and reg.id ~= REGION_WILDERNESS.id and reg.protected == true then
		minetest.chat_send_player(name, "This area is protected.")
	end
end)

-- Periodically show titles when players are inside regions (independent of protection checks)
minetest.register_globalstep(function(dtime)
	for _, player in ipairs(minetest.get_connected_players()) do
		check_player_region(player)
	end
end)

-- On join, immediately report if inside a region
minetest.register_on_joinplayer(function(player)
	-- Reset cached region/title state so joiners get a fresh notification
	local name = player and player:get_player_name()
	if name and name ~= "" then
		current_region[name] = nil
		last_title[name] = nil
	end
	minetest.after(0.1, function(p)
		if p and p:is_player() then
			check_player_region(p)
		end
	end, player)
end)

local function get_region_center_xz(region)
	local minx = math.min(region.x1, region.x2)
	local maxx = math.max(region.x1, region.x2)
	local minz = math.min(region.z1, region.z2)
	local maxz = math.max(region.z1, region.z2)
	return (minx + maxx) / 2, (minz + maxz) / 2
end

local function find_closest_regions(pos, count)
	if not pos then return nil end
	count = tonumber(count) or 1
	if count < 1 then count = 1 end

	-- If the player is already inside a region, prefer that region.
	local inside = find_region(pos)
	local entries = {}
	local seen = {}
	if inside and inside.id ~= REGION_WILDERNESS.id and not inside.unlisted then
		local cx, cz = get_region_center_xz(inside)
		table.insert(entries, {region = inside, center = {x = cx, z = cz}, dist2 = 0})
		seen[inside] = true
	end

	-- Pick closest regions by distance to their centers (simple and stable).
	for _, reg in ipairs(regions) do
		if type(reg) == "table" and type(reg.x1) == "number" and type(reg.x2) == "number"
			and type(reg.z1) == "number" and type(reg.z2) == "number" then
			if not reg.unlisted and not seen[reg] then
				local cx, cz = get_region_center_xz(reg)
				local dx = cx - pos.x
				local dz = cz - pos.z
				local dist2 = dx * dx + dz * dz
				table.insert(entries, {region = reg, center = {x = cx, z = cz}, dist2 = dist2})
			end
		end
	end

	table.sort(entries, function(a, b)
		return (a.dist2 or math.huge) < (b.dist2 or math.huge)
	end)

	local out = {}
	for i = 1, math.min(count, #entries) do
		out[i] = entries[i]
	end
	return out
end

local function atan2(y, x)
	-- Lua 5.1 provides math.atan2; Lua 5.2+ provides math.atan(y, x).
	if type(math.atan2) == "function" then
		return math.atan2(y, x)
	end

	-- Fallback implementation.
	if x > 0 then
		return math.atan(y / x)
	end
	if x < 0 and y >= 0 then
		return math.atan(y / x) + math.pi
	end
	if x < 0 and y < 0 then
		return math.atan(y / x) - math.pi
	end
	if x == 0 and y > 0 then
		return math.pi / 2
	end
	if x == 0 and y < 0 then
		return -math.pi / 2
	end
	return 0
end

local function direction_from_to_xz(from_pos, to_pos)
	if not from_pos or not to_pos then return "Unknown" end
	local dx = (to_pos.x or 0) - (from_pos.x or 0)
	local dz = (to_pos.z or 0) - (from_pos.z or 0)
	if math.abs(dx) < 0.001 and math.abs(dz) < 0.001 then
		return "Here"
	end

	-- Minetest coordinates: +X = east, +Z = south.
	-- NOTE: This project treats +Z as "north" for player-facing directions (so N/S are swapped vs. the usual convention).
	local angle = math.deg(atan2(dx, dz))
	angle = (angle + 360) % 360

	local dirs = {
		"North",
		"North East",
		"East",
		"South East",
		"South",
		"South West",
		"West",
		"North West",
	}
	local idx = (math.floor((angle + 22.5) / 45) % 8) + 1
	return dirs[idx]
end

local function direction_from_to_xz_debug(from_pos, to_pos)
	if not from_pos or not to_pos then
		return "Unknown", nil, nil, nil
	end
	local dx = (to_pos.x or 0) - (from_pos.x or 0)
	local dz = (to_pos.z or 0) - (from_pos.z or 0)
	if math.abs(dx) < 0.001 and math.abs(dz) < 0.001 then
		return "Here", dx, dz, 0
	end
	local angle = math.deg(atan2(dx, dz))
	angle = (angle + 360) % 360
	local dirs = {
		"North",
		"North East",
		"East",
		"South East",
		"South",
		"South West",
		"West",
		"North West",
	}
	local idx = (math.floor((angle + 22.5) / 45) % 8) + 1
	return dirs[idx], dx, dz, angle
end

local RINNOSUKE_BOOK_FORMNAME = "mcl_lun_barriers:rinnosukes_directions_book"
local rinnosuke_book_state = {}

local function get_blue_color()
	return (rawget(_G, "color") and _G.color("blue"))
		or (rawget(_G, "colors_api") and colors_api and colors_api.color and colors_api.color("blue"))
		or "#0000FF"
end

local function get_sienna_color()
	return (rawget(_G, "color") and _G.color("sienna"))
		or (rawget(_G, "colors_api") and colors_api and colors_api.color and colors_api.color("sienna"))
		or "#A0522D"
end

local function build_rinnosuke_page_lines(pagenum, entries)
	local roman = {"I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"}
	local page_roman = ({"I", "II", "III"})[pagenum] or tostring(pagenum)

	local lines = {}
	lines[#lines + 1] = {text = "Kourindou Gensokyou Atlas", color = get_sienna_color()}
	lines[#lines + 1] = {text = "Page " .. page_roman .. "/III", color = get_sienna_color()}

	local nbsp = "\194\160"
	local start_idx = (pagenum - 1) * 4 + 1
	for i = start_idx, start_idx + 3 do
		local entry = entries[i]
		local idx = roman[i] or tostring(i)
		if not entry then
			lines[#lines + 1] = {text = string.format("%s. —", idx), color = get_sienna_color()}
			lines[#lines + 1] = {text = "", color = get_sienna_color()}
		else
			local reg = entry.region
			local center = entry.center or {x = 0, z = 0}
			local dir = entry.dir or "Unknown"
			local region_name = reg and (reg.name or "Unknown") or "Unknown"
			local region_color = (reg and reg.color and normalize_color(reg.color)) or get_sienna_color()

			local x = math.floor((center.x or 0) + 0.5)
			local z = math.floor((center.z or 0) + 0.5)
			lines[#lines + 1] = {text = string.format("%s. %s", idx, region_name), color = region_color}

			-- Keep "travel <direction>" together.
			local dir_display = tostring(dir):gsub(" ", nbsp)
			local travel_line = string.format("X:%s%d Z:%d, travel%s%s", nbsp, x, z, nbsp, dir_display)
			lines[#lines + 1] = {text = travel_line, color = region_color}

			-- Blank line between entries.
			lines[#lines + 1] = {text = "", color = get_sienna_color()}
		end
	end

	return lines
end

local function show_rinnosuke_book(player, page)
	if not player or not player.is_player or not player:is_player() then return end
	local name = player:get_player_name()
	if not name or name == "" then return end
	local state = rinnosuke_book_state[name]
	if not state then return end

	page = tonumber(page) or state.page or 1
	if page < 1 then page = 1 end
	if page > 3 then page = 3 end
	state.page = page

	local background = ""
	if minetest.get_modpath("mcl_books") then
		background = "background[-0.5,-0.5;9,10;mcl_books_book_bg.png]"
	end

	local lines = build_rinnosuke_page_lines(page, state.entries or {})
	local formspec = "formspec_version[4]size[8,9]" ..
		"no_prepend[]" ..
		background ..
		"style_type[label;textcolor=" .. get_sienna_color() .. "]"

	-- Render as labels instead of a textarea so colored lines don't wrap early.
	-- Two header lines + 4 entries x (2 lines + blank) = 14 lines max, fits easily.
	local x = 0.75
	local y = 0.6
	local line_h = 0.55
	for _, line in ipairs(lines) do
		local text = line.text or ""
		local color = line.color or get_sienna_color()
		local colored = minetest.colorize(color, text)
		formspec = formspec .. "label[" .. x .. "," .. y .. ";" .. minetest.formspec_escape(colored) .. "]"
		y = y + line_h
	end

	formspec = formspec ..
		"button[0.75,8.15;2.2,0.8;prev;<< Prev]" ..
		"button[2.95,8.15;2.2,0.8;next;Next >>]" ..
		"button_exit[5.15,8.15;2.1,0.8;close;Done]"
	minetest.show_formspec(name, RINNOSUKE_BOOK_FORMNAME, formspec)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= RINNOSUKE_BOOK_FORMNAME then return end
	if not player or not player.is_player or not player:is_player() then return true end

	local name = player:get_player_name()
	local state = name and rinnosuke_book_state[name]
	if not state then return true end

	if fields.quit then
		rinnosuke_book_state[name] = nil
		return true
	end
	if fields.prev then
		show_rinnosuke_book(player, (state.page or 1) - 1)
		return true
	end
	if fields.next then
		show_rinnosuke_book(player, (state.page or 1) + 1)
		return true
	end
	return true
end)

local function directions_use(itemstack, user)
	if not user or not user.is_player or not user:is_player() then
		return itemstack
	end
	local name = user:get_player_name()
	local pos = user:get_pos()
	if not name or name == "" or not pos then
		return itemstack
	end

	local closest = find_closest_regions(pos, 12)
	if not closest or #closest == 0 then
		minetest.chat_send_player(name, minetest.colorize("#ff5555", "Rinnosuke's Directions: no barrier locations configured."))
		return itemstack
	end

	minetest.log("action", string.format(
		"[mcl_lun_barriers] Rinnosuke's Directions used by=%s from=(x=%.2f,y=%.2f,z=%.2f)",
		tostring(name), pos.x or 0, pos.y or 0, pos.z or 0
	))

	local entries = {}
	for i, entry in ipairs(closest) do
		local reg = entry.region
		local center = entry.center
		local region_color = normalize_color(reg and reg.color)
		local dir, dx, dz, angle = direction_from_to_xz_debug(pos, center)
		minetest.log("action", string.format(
			"[mcl_lun_barriers]   #%d region=%s dest=(x=%.2f,z=%.2f) delta=(dx=%.2f,dz=%.2f) angle=%.2f dir=%s",
			i,
			tostring(reg and reg.name or "Unknown"),
			(center and center.x) or 0,
			(center and center.z) or 0,
			dx or 0,
			dz or 0,
			angle or 0,
			tostring(dir)
		))

		entries[i] = {
			region = reg,
			center = center,
			region_color = region_color,
			dir = dir,
			dx = dx,
			dz = dz,
			angle = angle,
		}
	end

	rinnosuke_book_state[name] = {page = 1, entries = entries}
	show_rinnosuke_book(user, 1)
	return itemstack
end

minetest.register_craftitem("mcl_lun_barriers:rinnosukes_directions", {
	description = minetest.colorize(
		(rawget(_G, "color") and _G.color("blue"))
			or (rawget(_G, "colors_api") and colors_api and colors_api.color and colors_api.color("blue"))
			or "#0000FF",
		"Rinnosuke's Directions"
	),
	inventory_image = "rinnosuke_directions.png",
	wield_image = "rinnosuke_directions.png",
	stack_max = 1,
	groups = {book = 1, tool = 1, disable_repair = 1},
	on_use = directions_use,
	on_secondary_use = directions_use,
	on_place = directions_use,
})

minetest.register_alias("mcl_lun_barriers:sages_directions", "mcl_lun_barriers:rinnosukes_directions")

minetest.register_craft({
	type = "shapeless",
	output = "mcl_lun_barriers:rinnosukes_directions",
	recipe = {"mcl_compass:compass", "mcl_core:paper"},
})
