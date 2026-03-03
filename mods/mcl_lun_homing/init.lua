
local modname = minetest.get_current_modname()
local homing = {}
_G.mcl_lun_homing = homing

-- --- Configuration ---
-- Default values if not specified in function calls
local DEFAULT_RANGE = 35
local DEFAULT_FOV_COSINE = 0.92 -- Increased sensitivity
local DEFAULT_TURN_RATE = 6.0   -- Faster steering for improved responsiveness

-- --- Internal Helpers ---

local function is_valid_target(obj, self_obj)
	if not obj or not obj:get_pos() then return false end
	if obj == self_obj then return false end
	
	-- Check HP
	local hp = obj:get_hp()
	if not hp or hp <= 0 then return false end
	
	-- Check if entity is generic item or ignored type
	local lua = obj:get_luaentity()
	if lua then
		if lua.name == "__builtin:item" then return false end
		-- Add other ignore checks here if needed (e.g. text displays)
	end
	
	return true
end

local function has_line_of_sight(pos1, pos2, self_obj, target_obj)
	local ray = minetest.raycast(pos1, pos2, true, true)
	for hit in ray do
		if hit.type == "node" then
			local node = minetest.get_node(hit.under)
			local def = minetest.registered_nodes[node.name]
			if def and def.walkable then
				return false
			end
		elseif hit.type == "object" then
			-- Ignore self and target in LOS check to prevent self-collision errors
			if hit.ref ~= self_obj and hit.ref ~= target_obj then
				-- Optional: deciding if other objects block LOS. 
				-- For now, let's say they don't block aiming.
			end
		end
	end
	return true
end

-- --- Public API ---

--[[
	find_best_target(player, range, fov_cosine)
	
	Scans for the best target currently in the player's view cone.
	- player: The player object (User)
	- range: Maximum distance (default 30)
	- fov_cosine: Minimum dot product value (default 0.8). 1.0 is dead center.
	
	Returns: invalid object or nil
]]
function homing.find_best_target(player, range, fov_cosine)
	if not player or not player:is_player() then return nil end
	
	local range = range or DEFAULT_RANGE
	local min_dot = fov_cosine or DEFAULT_FOV_COSINE
	local pos = player:get_pos()
	local camera_pos = vector.add(pos, {x=0, y=player:get_properties().eye_height, z=0})
	local look_dir = player:get_look_dir()
	
	local objects = minetest.get_objects_inside_radius(pos, range)
	local best_target = nil
	local best_score = -1 -- Logic score: combined distance and angle? For now just angle.
	
	for _, obj in ipairs(objects) do
		if is_valid_target(obj, player) then
			local obj_pos = obj:get_pos()
			-- Center of mass approximation (up 1 node? or half height?)
			local center_pos = vector.add(obj_pos, {x=0, y=0.5, z=0}) 
			
			local dir_to = vector.direction(camera_pos, center_pos)
			local dist = vector.distance(camera_pos, center_pos)
			
			if dist > 0 then
				local dot = vector.dot(look_dir, dir_to)
				
				if dot >= min_dot then
					-- Check Line of Sight
					if has_line_of_sight(camera_pos, center_pos, player, obj) then
						-- Scoring: Prefer closer to crosshair (higher dot)
						-- We could also factor in distance (closer = better?)
						-- Current logic: strict "closest to crosshair"
						if dot > best_score then
							best_score = dot
							best_target = obj
						end
					end
				end
			end
		end
	end
	
	return best_target
end

--[[
	steer(current_vel, current_pos, target_pos, turn_rate, dtime)
	
	Calculates a new velocity vector that steers towards the target.
	- current_vel: Current velocity vector
	- current_pos: Current position vector
	- target_pos: Target position vector
	- turn_rate: Max radians to turn per second (default 4.0)
	- dtime: Time step
	
	Returns: new velocity vector (same speed magnitude, new direction)
]]
function homing.steer(current_vel, current_pos, target_pos, turn_rate, dtime)
	if not current_vel or not current_pos or not target_pos then return current_vel end
	
	local speed = vector.length(current_vel)
	if speed < 0.001 then return current_vel end -- Cannot steer zero velocity
	
	local desired_dir = vector.direction(current_pos, target_pos)
	local current_dir = vector.normalize(current_vel)
	
	-- Calculate angle between current and desired
	local dot = vector.dot(current_dir, desired_dir)
	-- Clamp dot to -1..1 to avoid acos errors
	dot = math.max(-1, math.min(1, dot))
	local angle = math.acos(dot)
	
	if angle < 0.001 then return current_vel end -- Already facing target
	
	-- Max turn for this frame
	local max_turn = (turn_rate or DEFAULT_TURN_RATE) * dtime
	
	if angle <= max_turn then
		-- Can turn fully to target
		return vector.multiply(desired_dir, speed)
	else
		-- Slerp (Spherical Linear Interpolation) implementation for vectors
		-- Formula: v = (sin((1-t)*a)/sin(a)) * p1 + (sin(t*a)/sin(a)) * p2
		local t = max_turn / angle
		local p1 = current_dir
		local p2 = desired_dir
		local sin_a = math.sin(angle)
		
		local w1 = math.sin((1-t)*angle) / sin_a
		local w2 = math.sin(t*angle) / sin_a
		
		local new_dir = vector.add(vector.multiply(p1, w1), vector.multiply(p2, w2))
		return vector.multiply(vector.normalize(new_dir), speed)
	end
end

-- --- Debug Utilities ---

minetest.register_chatcommand("scan_target", {
	description = "Find the best homing target in view",
	func = function(name)
		local player = minetest.get_player_by_name(name)
		if not player then return end
		local target = homing.find_best_target(player)
		if target then
			local tname = target:is_player() and target:get_player_name() or (target:get_luaentity() and target:get_luaentity().name or "Unknown Entity")
			minetest.chat_send_player(name, "Locked Target: " .. tname)
		else
			minetest.chat_send_player(name, "No target found.")
		end
	end
})
