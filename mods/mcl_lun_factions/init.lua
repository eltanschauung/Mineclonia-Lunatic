local modpath = minetest.get_modpath(minetest.get_current_modname())
-- Store config alongside the mod (as requested).
local cfg_path = modpath .. "/factions.cfg"
local races_mod = rawget(_G, "mcl_lun_races")
local color_fn = rawget(_G, "color") or function(c) return c end

local function ensure_cfg()
	if minetest.safe_file_write and not io.open(cfg_path, "r") then
		local default_cfg = {
			factions = {
				{
					name = "default",
				color = "white",
				races = {},
			},
			{
				name = "Scarlet Devil Mansion",
				color = "crimson",
				races = {"vampire"},
			},
		},
	}
		minetest.safe_file_write(cfg_path, minetest.serialize(default_cfg))
	end
end

ensure_cfg()

local factions_cfg = {factions = {}}
local fh = io.open(cfg_path, "r")
if fh then
	local data = fh:read("*all")
	fh:close()
	-- Primary: data produced by minetest.serialize
	local des = minetest.deserialize(data)
	-- Fallback: accept simple Lua table syntax such as “factions = { … }”
	if not des then
		local normalized = data
		if normalized:match("^%s*factions%s*=") then
			normalized = "return {" .. normalized .. "}"
		else
			normalized = "return " .. normalized
		end
		local chunk, err = loadstring(normalized)
		if chunk then
			-- run in empty environment for safety
			setfenv(chunk, {})
			local ok, tbl = pcall(chunk)
			if ok and type(tbl) == "table" then
				des = tbl
			end
		end
	end
	-- Normalize into the expected shape
	if type(des) == "table" then
		if des.factions then
			factions_cfg = des
		elseif des[1] and des[1].name then
			-- Allow bare array of factions without top-level key
			factions_cfg = {factions = des}
		end
end
end

minetest.log("action", ("[mcl_lun_factions] loaded %d factions from %s"):format(#(factions_cfg.factions or {}), cfg_path))
if #(factions_cfg.factions or {}) == 0 then
	-- Final fallback to sane defaults
	factions_cfg = {
		factions = {
			{name = "default", color = "white", races = {}},
			{name = "Scarlet Devil Mansion", color = "crimson", races = {"vampire"}},
		},
	}
	minetest.log("warning", "[mcl_lun_factions] factions.cfg empty or unreadable; using built-in defaults")
end
for idx, fac in ipairs(factions_cfg.factions or {}) do
	minetest.log("action", ("[mcl_lun_factions] faction %d: name=%s color=%s"):format(idx, tostring(fac.name), tostring(fac.color)))
end

local F = {}

function F.get_factions()
	return factions_cfg.factions or {}
end

local function race_from_player(player)
	if not player then return nil end
	if races_mod and races_mod.get_race then
		return races_mod.get_race(player)
	end
	-- guard for older objects without get_meta
	local meta = player.get_meta and player:get_meta()
	return meta and meta:get_string("mcl_lun_races:race") or nil
end

local function faction_from_player(player)
	if not player then return nil end
	if races_mod and races_mod.get_faction then
		local f = races_mod.get_faction(player)
		if type(f) == "string" and f ~= "" then
			return f
		end
	end
	local meta = player.get_meta and player:get_meta()
	local f = meta and meta:get_string("mcl_lun_races:faction") or ""
	if f ~= "" then
		return f
	end
	return nil
end

function F.get_player_faction(player)
	-- Prefer an explicitly assigned faction (stored by mcl_lun_races) when available.
	local explicit = nil
	if type(player) == "userdata" and player.is_player and player:is_player() then
		explicit = faction_from_player(player)
	elseif type(player) == "string" then
		local p = minetest.get_player_by_name(player)
		if p then explicit = faction_from_player(p) end
	end
	if explicit then
		local fac = F.get_faction_by_name(explicit)
		if fac then
			return fac
		end
	end

	local race
	if type(player) == "userdata" and player.is_player and player:is_player() then
		race = race_from_player(player)
	elseif type(player) == "string" then
		local p = minetest.get_player_by_name(player)
		if p then race = race_from_player(p) end
	end
	for _, fac in ipairs(F.get_factions()) do
		if fac.races then
			for _, r in ipairs(fac.races) do
				if r == race then
					return fac
				end
			end
		end
	end
	-- default fallback
	for _, fac in ipairs(F.get_factions()) do
		if fac.name == "default" then
			return fac
		end
	end
	return {name = "default", color = "#ffffff", races = {}}
end

function F.get_faction_by_name(name)
	for _, fac in ipairs(F.get_factions()) do
		if fac.name == name then
			return fac
		end
	end
	return nil
end

function F.get_faction_color(name)
	local cf = rawget(_G, "color") or color_fn
	local fac = F.get_faction_by_name(name)
	return fac and cf(fac.color or "#ffffff") or cf("#ffffff")
end

_G.mcl_lun_factions = F
