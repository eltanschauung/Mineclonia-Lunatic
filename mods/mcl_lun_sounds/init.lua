local M = {}

local function shallow_copy(tbl)
	if not tbl then return {} end
	local out = {}
	for k, v in pairs(tbl) do
		out[k] = v
	end
	return out
end

M.sounds = {
	player_death = "pldead00",
	firefly_ambient_1 = "fireflies_1",
	firefly_ambient_2 = "fireflies_2",
	leaves_rustling_wind = "leaves_rustling_wind",
	leaves_rustling_wind_mountain = "leaves2",
	ambience_creek = "ambience_creek",
	knife = "knife",
}

-- Basic play helper
function M.play(name, params, ephemeral)
	if not name then return end
	return minetest.sound_play(name, params or {}, ephemeral == nil and true or ephemeral)
end

-- Play with optional random pitch/gain variation (percent)
function M.play_var(name, params, variance_pct, variance_gain_pct)
	local spec = shallow_copy(params)
	local pvar = variance_pct or 0
	local gvar = variance_gain_pct or pvar
	if pvar ~= 0 then
		local factor = 1 + (math.random(-pvar, pvar) / 100)
		spec.pitch = (spec.pitch or 1.0) * factor
	end
	if gvar ~= 0 and spec.gain then
		local factor = 1 + (math.random(-gvar, gvar) / 100)
		spec.gain = spec.gain * factor
	end
	return M.play(name, spec, params and params.ephemeral)
end

minetest.register_on_dieplayer(function(player)
	if not (player and player.is_player and player:is_player()) then
		return
	end
	local pos = player:get_pos()
	if not pos then
		return
	end
	M.play(M.sounds.player_death, {pos = pos, max_hear_distance = 32, gain = 0.1}, true)
end)

mcl_lun_sounds = M
return M
