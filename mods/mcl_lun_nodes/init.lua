local modname = core.get_current_modname()
local F = core.formspec_escape
local S = core.get_translator and core.get_translator("mcl_lun_nodes") or function(str) return str end
local slot_bg = mcl_formspec and mcl_formspec.get_itemslot_bg_v4 or function() return "" end
local drop_items = (mcl_util and mcl_util.drop_items_from_meta_container and
	mcl_util.drop_items_from_meta_container("main")) or function() end

local function donation_box_formspec(pos)
	local spos = ("%d,%d,%d"):format(pos.x, pos.y, pos.z)
	local meta = core.get_meta(pos)
	local title = meta:get_string("name")
	if title == "" then
		title = S("Donation Box")
	end
	title = F(title)
	return table.concat({
		"formspec_version[4]",
		"size[11.75,14]",
		"label[0.375,0.375;", title, "]",
		-- Single 9x5 storage
		slot_bg(0.375, 0.75, 9, 5),
		"list[nodemeta:", spos, ";main;0.375,0.75;9,5;]",
		-- Player inventory
		"label[0.375,7.35;", F(S("Inventory")), "]",
		slot_bg(0.375, 7.75, 9, 3),
		"list[current_player;main;0.375,7.75;9,3;9]",
		slot_bg(0.375, 11.7, 9, 1),
		"list[current_player;main;0.375,11.7;9,1;]",
		"listring[nodemeta:", spos, ";main]",
		"listring[current_player;main]",
	})
end

local function donation_box_protected(pos, player)
	if player and core.is_protected(pos, player:get_player_name()) then
		core.record_protection_violation(pos, player:get_player_name())
		return true
	end
	return false
end

local donation_desc = S("Donation Box")
local donation_flavor = minetest.colorize(color("gray") or "#888888", S("The emptiest thing in the world, the perfect storage..."))

minetest.register_node("mcl_lun_nodes:donation_box", {
	paramtype2 = "facedir",
	drawtype = "nodebox",
	is_ground_content = false,
	sounds = mcl_sounds and mcl_sounds.node_sound_wood_defaults() or nil,
	node_box = {
		type = "fixed",
		fixed = {
			{-0.4063, 0.3750, -0.4375, -0.3438, 0.4375, 0.4375},
			{-0.2188, 0.3750, -0.4375, -0.1563, 0.4375, 0.4375},
			{-0.03125, 0.3750, -0.4375, 0.03125, 0.4375, 0.4375},
			{0.1563, 0.3750, -0.4375, 0.2188, 0.4375, 0.4375},
			{0.3438, 0.3750, -0.4375, 0.4063, 0.4375, 0.4375},
			{-0.5000, -0.4375, -0.5000, 0.5000, 0.5000, -0.4375},
			{-0.5000, -0.4375, -0.4375, -0.4375, 0.5000, 0.4375},
			{-0.5000, -0.5000, -0.5000, 0.5000, -0.4375, 0.5000},
			{0.4375, -0.5000, -0.4375, 0.5000, 0.5000, 0.5000},
			{-0.5000, -0.4375, 0.4375, 0.4375, 0.5000, 0.5000}
		}
	},
	description = core.colorize(color("axis") or "#dc143c", donation_desc),
	tiles = {
		"default_wood.png",
		"default_wood.png",
		"mcl_lun_nodes_donation_box_side.png",
		"mcl_lun_nodes_donation_box_side.png",
		"mcl_lun_nodes_donation_box_side.png",
		"mcl_lun_nodes_donation_box_front.png",
	},
	groups = {
		handy = 1,
		axey = 1,
		deco_block = 1,
		material_wood = 1,
		flammable = -1,
		container = 1,
		pathfinder_partial = 1,
	},
	selection_box = {
		type = "fixed",
		fixed = { -0.5, -0.5, -0.5, 0.5, 0.5, 0.5 },
	},
	_mcl_blast_resistance = 2.5,
	_mcl_hardness = 2.5,
	_tt_help = donation_flavor,
	_doc_items_longdesc = donation_flavor,
	on_construct = function(pos)
		local meta = core.get_meta(pos)
		meta:set_string("description", donation_flavor)
		meta:set_string("name", "")
		local inv = meta:get_inventory()
		inv:set_size("main", 9 * 5)
	end,
	after_place_node = function(pos, placer, itemstack)
		local meta = core.get_meta(pos)
		local custom_name = itemstack and itemstack:get_meta():get_string("name") or ""
		meta:set_string("name", custom_name)
		return placer
	end,
	after_dig_node = function(pos, oldnode, oldmeta, digger)
		drop_items(pos, oldnode)
	end,
	allow_metadata_inventory_put = function(pos, listname, _, stack, player)
		if listname ~= "main" then
			return 0
		end
		if donation_box_protected(pos, player) then
			return 0
		end
		return stack:get_count()
	end,
	allow_metadata_inventory_take = function(pos, listname, _, stack, player)
		if listname ~= "main" then
			return 0
		end
		if donation_box_protected(pos, player) then
			return 0
		end
		return stack:get_count()
	end,
	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
		if from_list ~= "main" or to_list ~= "main" then
			return 0
		end
		if donation_box_protected(pos, player) then
			return 0
		end
		return count
	end,
	on_rightclick = function(pos, node, clicker)
		if not clicker or not clicker:is_player() then
			return
		end
		local above = core.get_node_or_nil({ x = pos.x, y = pos.y + 1, z = pos.z })
		if above then
			local def = core.registered_nodes[above.name]
			if def and def.groups and def.groups.opaque == 1 then
				return
			end
		end
		core.show_formspec(clicker:get_player_name(),
			string.format("mcl_lun_nodes:donation_box_%d_%d_%d", pos.x, pos.y, pos.z),
			donation_box_formspec(pos))
	end,
})

-- Crafting recipe: sticks on top row; planks/ink sac/planks middle; planks bottom row.
minetest.register_craft({
	output = "mcl_lun_nodes:donation_box",
	recipe = {
		{"mcl_core:stick", "mcl_core:stick", "mcl_core:stick"},
		{"group:wood", "mcl_mobitems:ink_sac", "group:wood"},
		{"group:wood", "group:wood", "group:wood"},
	},
})

-- Allow black dye as an alternative to ink sac in the center slot.
minetest.register_craft({
	output = "mcl_lun_nodes:donation_box",
	recipe = {
		{"mcl_core:stick", "mcl_core:stick", "mcl_core:stick"},
		{"group:wood", "mcl_dye:black", "group:wood"},
		{"group:wood", "group:wood", "group:wood"},
	},
})

local grill_desc = S("Grill")

local function get_grill_formspec(fuel_percent)
	local label_color = (rawget(_G, "mcl_formspec") and mcl_formspec.label_color) or "#FFFFFF"
	local slot_bg = rawget(_G, "mcl_formspec") and mcl_formspec.get_itemslot_bg_v4 or nil

	local formspec = {
		"formspec_version[4]",
		"size[11.75,10.425]",
		"label[0.375,0.375;" .. F(core.colorize(label_color, grill_desc)) .. "]",

		-- Fire icon centered at top
		"image[5.25,0.75;1,1;default_furnace_fire_bg.png^[lowpart:" ..
		(fuel_percent) .. ":default_furnace_fire_fg.png]",

		-- 3x2 Fuel grid centered below fire
		slot_bg and slot_bg(4.00, 2.0, 3, 2) or "",
		"list[context;fuel;4.00,2.0;3,2;]",

		"label[0.375,4.7;" .. F(core.colorize(label_color, S("Inventory"))) .. "]",
		slot_bg and slot_bg(0.375, 5.1, 9, 3) or "",
		"list[current_player;main;0.375,5.1;9,3;9]",
		slot_bg and slot_bg(0.375, 9.05, 9, 1) or "",
		"list[current_player;main;0.375,9.05;9,1;]",

		"listring[context;fuel]",
		"listring[current_player;main]",
	}
	return table.concat(formspec)
end

local function grill_node_timer(pos, elapsed)
	local meta = core.get_meta(pos)
	local fuel_time = meta:get_float("fuel_time") or 0
	local fuel_totaltime = meta:get_float("fuel_totaltime") or 0
	local inv = meta:get_inventory()
	
	-- Resize inventory if needed (migration)
	if inv:get_size("fuel") ~= 6 then
		inv:set_size("fuel", 6)
	end

	local update = true
	while elapsed > 0 and update do
		if fuel_time > 0 then
			local burn = math.min(fuel_time, elapsed)
			fuel_time = fuel_time - burn
			elapsed = elapsed - burn
		end

		if fuel_time <= 0 then
			-- Find first valid fuel in the 3x2 grid
			local fuel_list = inv:get_list("fuel")
			local found = false
			for i, stack in ipairs(fuel_list) do
				if not stack:is_empty() then
					local fuel, afterfuel = core.get_craft_result({ method = "fuel", width = 1, items = {stack} })
					if fuel.time > 0 then
						inv:set_stack("fuel", i, afterfuel.items[1])
						local ftime = fuel.time
						if stack:get_name() == "mcl_core:charcoal_lump" then
							ftime = ftime * 3
						end
						fuel_time = fuel_time + ftime
						fuel_totaltime = ftime
						mcl_furnaces.give_xp(pos)
						found = true
						break
					end
				end
			end
			
			if not found then
				update = false
			end
		end
	end

	meta:set_float("fuel_time", fuel_time)
	meta:set_float("fuel_totaltime", fuel_totaltime)
	
	local fuel_percent = 0
	if fuel_totaltime > 0 then
		fuel_percent = math.floor(fuel_time / fuel_totaltime * 100)
	end
	meta:set_string("formspec", get_grill_formspec(fuel_percent))

	local node = core.get_node(pos)
	if fuel_time > 0 then
		if node.name == "mcl_lun_nodes:grill" then
			node.name = "mcl_lun_nodes:grill_active"
			core.swap_node(pos, node)
		end
		return true
	else
		if node.name == "mcl_lun_nodes:grill_active" then
			node.name = "mcl_lun_nodes:grill"
			core.swap_node(pos, node)
			if mcl_campfires and mcl_campfires.clear_smoke then
				mcl_campfires.clear_smoke(pos)
			end
		end
		return false
	end
end

local function grill_on_construct(pos)
	local meta = core.get_meta(pos)
	meta:set_string("formspec", get_grill_formspec(0))
	local inv = meta:get_inventory()
	inv:set_size("fuel", 6)
end

local function grill_allow_metadata_inventory_put(pos, listname, index, stack, player)
	local name = player:get_player_name()
	if core.is_protected(pos, name) then
		core.record_protection_violation(pos, name)
		return 0
	end
	if listname == "fuel" then
		local fuel, _ = core.get_craft_result({ method = "fuel", width = 1, items = { stack } })
		if fuel.time > 0 then
			return stack:get_count()
		else
			return 0
		end
	end
	return 0
end

local function grill_allow_metadata_inventory_move(pos, from_list, from_index, to_list, to_index, count, player)
	local meta = core.get_meta(pos)
	local inv = meta:get_inventory()
	local stack = inv:get_stack(from_list, from_index)
	return grill_allow_metadata_inventory_put(pos, to_list, to_index, stack, player)
end

local function grill_allow_metadata_inventory_take(pos, listname, index, stack, player)
	local name = player:get_player_name()
	if core.is_protected(pos, name) then
		core.record_protection_violation(pos, name)
		return 0
	end
	return stack:get_count()
end

local function grill_on_metadata_inventory_put(pos, listname, index, stack, player)
	if listname == "fuel" then
		core.get_node_timer(pos):start(1.0)
	end
end

-- Entity for displaying items on the grill
local grill_item_entity = {
	initial_properties = {
		visual = "wielditem",
		visual_size = {x = 0.3, y = 0.3},
		physical = false,
		pointable = true,
		textures = {"blank.png"},
		glow = 0,
		collisionbox = {-0.15, -0.05, -0.15, 0.15, 0.05, 0.15},
		selectionbox = {-0.15, -0.05, -0.15, 0.15, 0.05, 0.15},
		hp_max = 1,
	},
	_item = "",
	_pos = nil,
}

function grill_item_entity:on_activate(staticdata)
	if staticdata and staticdata ~= "" then
		local data = core.deserialize(staticdata) or {}
		self._item = data.item or ""
		self._pos = data.pos
	end
	if self._item ~= "" then
		self.object:set_properties({textures = {self._item}})
		self.object:set_rotation(vector.new(math.pi / 2, 0, 0))
	end
end

function grill_item_entity:get_staticdata()
	return core.serialize({item = self._item, pos = self._pos})
end

function grill_item_entity:on_punch(puncher)
	if self._item ~= "" then
		core.add_item(self.object:get_pos(), self._item)
	end
	if self._pos then
		local meta = core.get_meta(self._pos)
		if meta then
			meta:set_string("grill_item", "")
		end
	end
	self.object:remove()
end

core.register_entity("mcl_lun_nodes:grill_item", grill_item_entity)

local function update_grill_entity(pos)
	-- Remove existing entities
	for _, obj in pairs(core.get_objects_inside_radius(pos, 0.5)) do
		local luaentity = obj:get_luaentity()
		if luaentity and luaentity.name == "mcl_lun_nodes:grill_item" then
			obj:remove()
		end
	end

	local meta = core.get_meta(pos)
	local item = meta:get_string("grill_item")
	if item ~= "" then
		local obj = core.add_entity(vector.add(pos, vector.new(0, 0.52, 0)), "mcl_lun_nodes:grill_item")
		if obj then
			local ent = obj:get_luaentity()
			ent._item = item
			ent._pos = pos
			obj:set_properties({textures = {item}})
			obj:set_rotation(vector.new(math.pi / 2, 0, 0))
		end
	end
end



local function grill_on_rightclick(pos, node, clicker, itemstack, pointed_thing)
	if not clicker or not clicker:is_player() then return end
	
	local item_name = itemstack:get_name()
	local meta = core.get_meta(pos)
	local current_item = meta:get_string("grill_item")
	
	-- Place item
	if current_item == "" and (item_name == "mcl_lun_cooking:chicken_drumstick" or item_name == "mcl_lun_items:yakitori_uncooked") then
		meta:set_string("grill_item", item_name)
		update_grill_entity(pos)
		if not core.is_creative_enabled(clicker:get_player_name()) then
			itemstack:take_item()
		end
		return itemstack
	end

	-- Remove item (Shift + Right Click or Empty Hand? Just use Shift+Click to retrieve like item frames often do, or just click if empty hand?)
	-- User request: "right click ... holding ... place it".
	-- Doesn't specify removal, but implied.
	-- Let's allow removal if sneaking or if not holding a placeable item and there is something there?
	-- Standard mcl_itemframe behavior is punch to remove. Right click rotates.
	-- Let's stick to strict user request: Place if holding item.
	-- If we just want to open formspec otherwise:
	
	-- Use a unique formname based on position
	local formname = "mcl_lun_nodes:grill_" .. pos.x .. "_" .. pos.y .. "_" .. pos.z
	core.show_formspec(clicker:get_player_name(), formname, meta:get_string("formspec"))
end

local grill_def = {
	description = core.colorize(color("axis") or "#dc143c", grill_desc),
	tiles = {
		"loom_top.png", "loom_bottom.png",
		"loom_side.png", "loom_side.png",
		"loom_side.png", "loom_front.png",
	},
	paramtype2 = "facedir",
	paramtype = "light",
	is_ground_content = false,
	sounds = mcl_sounds and mcl_sounds.node_sound_wood_defaults() or nil,
	groups = {
		handy = 1,
		axey = 1,
		deco_block = 1,
		material_wood = 1,
		flammable = 1,
		grill_smoke = 1,
	},
	_mcl_blast_resistance = 2.5,
	_mcl_hardness = 2.5,
	on_construct = grill_on_construct,
	on_timer = grill_node_timer,
	on_rightclick = grill_on_rightclick,
	allow_metadata_inventory_put = grill_allow_metadata_inventory_put,
	allow_metadata_inventory_move = grill_allow_metadata_inventory_move,
	allow_metadata_inventory_take = grill_allow_metadata_inventory_take,
	on_metadata_inventory_put = grill_on_metadata_inventory_put,
	on_metadata_inventory_move = grill_on_metadata_inventory_put, -- Restart timer on move too
	on_destruct = function(pos)
		if mcl_campfires and mcl_campfires.clear_smoke then
			mcl_campfires.clear_smoke(pos)
		end
		-- Remove entity
		update_grill_entity(pos) -- Will remove if meta is cleared, but meta is on node...
		-- Actually we need to explicitly remove entities
		for _, obj in pairs(core.get_objects_inside_radius(pos, 0.5)) do
			local luaentity = obj:get_luaentity()
			if luaentity and luaentity.name == "mcl_lun_nodes:grill_item" then
				obj:remove()
			end
		end
		drop_items(pos, core.get_node(pos))
	end,
}

local grill_def_active = table.copy(grill_def)
grill_def_active.groups.not_in_creative_inventory = 1
grill_def_active.light_source = 13
grill_def_active.mod_origin = modname

core.register_node("mcl_lun_nodes:grill", grill_def)
core.register_node("mcl_lun_nodes:grill_active", grill_def_active)

core.register_abm({
	label = "Grill Smoke",
	nodenames = {"mcl_lun_nodes:grill_active"},
	interval = 4,
	chance = 1,
	action = function(pos)
		if mcl_campfires and mcl_campfires.generate_smoke then
			mcl_campfires.generate_smoke(pos)
		end
	end,
})

core.register_lbm({
	label = "Restore grill items",
	name = "mcl_lun_nodes:restore_grill_items",
	nodenames = {"mcl_lun_nodes:grill", "mcl_lun_nodes:grill_active"},
	run_at_every_load = true,
	action = function(pos)
		update_grill_entity(pos)
	end,
})

core.register_craft({
	output = "mcl_lun_nodes:grill",
	recipe = {
		{"mcl_core:iron_ingot", "mcl_core:iron_ingot", "mcl_core:iron_ingot"},
		{"", "mcl_loom:loom", ""},
		{"", "mcl_core:stick", ""},
	},
})
