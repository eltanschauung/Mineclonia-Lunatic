local S = core.get_translator(core.get_current_modname())

local C = core.colorize
local F = core.formspec_escape

local function place_only_on_top(itemstack, placer, pointed_thing)
	if not pointed_thing or pointed_thing.type ~= "node" then
		return itemstack
	end
	local under = pointed_thing.under
	local above = pointed_thing.above
	if not under or not above or above.y ~= under.y + 1 then
		if placer and placer:is_player() then
			core.chat_send_player(placer:get_player_name(), S("Place this on the top of a node."))
		end
		return itemstack
	end
	local param2 = 0
	if placer and placer.is_player and placer:is_player() then
		local placer_pos = placer:get_pos()
		if placer_pos then
			-- Like Mineclonia stairs placement, but rotated so the model's X face
			-- (local +X) points towards the player.
			local dir = vector.subtract(placer_pos, above)
			dir.y = 0
			param2 = (core.dir_to_facedir(dir) + 2) % 4
		end
	end
	return core.item_place_node(itemstack, placer, pointed_thing, param2)
end

local function is_knife_stack(stack)
	return stack and not stack:is_empty() and core.get_item_group(stack:get_name(), "knife") == 1
end

local function get_board_title(node_name)
	local def = node_name and core.registered_nodes[node_name] or nil
	if not def then
		return S("Cutting Board")
	end
	return def._tt_original_description or def.description or S("Cutting Board")
end

local function board_formspec(pos)
	local node = core.get_node(pos)
	local title = get_board_title(node.name)
	local label_color = (rawget(_G, "mcl_formspec") and mcl_formspec.label_color) or "#FFFFFF"
	local slot_bg = rawget(_G, "mcl_formspec") and mcl_formspec.get_itemslot_bg_v4 or nil

	local fs = {
		"formspec_version[4]",
		"size[11.75,10.425]",
		"label[0.375,0.375;" .. F(C(label_color, title)) .. "]",

		"label[1.375,2.0;" .. F(S("Knife")) .. "]",
		slot_bg and slot_bg(1.375, 1.15, 1, 1) or "",
		"list[context;tool;1.375,1.15;1,1;]",

		"label[3.5,2.0;" .. F(S("Inputs")) .. "]",
		slot_bg and slot_bg(3.5, 1.15, 1, 2) or "",
		"list[context;src;3.5,1.15;1,2;]",

		"button[4.65,1.7;1.6,0.9;process;" .. F(S("Cut")) .. "]",

		"label[6.5,0.75;" .. F(S("Output")) .. "]",
		slot_bg and slot_bg(6.5, 1.15, 3, 3) or "",
		"list[context;dst;6.5,1.15;3,3;]",

		"label[0.375,4.7;" .. F(C(label_color, S("Inventory"))) .. "]",
		slot_bg and slot_bg(0.375, 5.1, 9, 3) or "",
		"list[current_player;main;0.375,5.1;9,3;9]",
		slot_bg and slot_bg(0.375, 9.05, 9, 1) or "",
		"list[current_player;main;0.375,9.05;9,1;]",

		"listring[context;dst]",
		"listring[current_player;main]",
		"listring[context;src]",
		"listring[current_player;main]",
		"listring[context;tool]",
		"listring[current_player;main]",
	}

	return table.concat(fs)
end

local function board_set_formspec(pos)
	local meta = core.get_meta(pos)
	meta:set_string("formspec", board_formspec(pos))
	meta:set_string("infotext", get_board_title(core.get_node(pos).name))
end

local function board_is_output_empty(inv)
	for i = 1, inv:get_size("dst") do
		if not inv:get_stack("dst", i):is_empty() then
			return false
		end
	end
	return true
end

local chicken_cut_pool = {
	"mcl_lun_cooking:chicken_breast",
	"mcl_lun_cooking:chicken_thigh",
	"mcl_lun_cooking:chicken_thigh",
	"mcl_lun_cooking:chicken_drumstick",
	"mcl_lun_cooking:chicken_drumstick",
	"mcl_lun_cooking:chicken_wing",
	"mcl_lun_cooking:chicken_wing",
	"mcl_lun_cooking:chicken_wing",
	"mcl_lun_cooking:chicken_wing",
	"mcl_lun_cooking:chicken_tender",
	"mcl_lun_cooking:chicken_tender",
	"mcl_lun_cooking:chicken_heart",
	"mcl_lun_cooking:chicken_liver",
}

local cutting_board_recipes = {}

local function register_cutting_board_recipe(def)
	table.insert(cutting_board_recipes, def)
end

local function clear_output(inv)
	for i = 1, inv:get_size("dst") do
		inv:set_stack("dst", i, ItemStack())
	end
end

register_cutting_board_recipe({
	id = "make_skewers",
	match = function(_, src1, src2)
		local n1 = src1 and src1:get_name() or ""
		local n2 = src2 and src2:get_name() or ""
		if n1 == "mcl_core:stick" then
			return true, 1
		end
		if n2 == "mcl_core:stick" then
			return true, 2
		end
		return false
	end,
	apply = function(inv, src_index)
		if not board_is_output_empty(inv) then
			return false, S("Clear the output first.")
		end

		local src = inv:get_stack("src", src_index)
		if src:is_empty() then
			return false
		end
		src:take_item(1)
		inv:set_stack("src", src_index, src)

		clear_output(inv)
		local seed = (core.get_us_time and core.get_us_time()) or os.time()
		local pr = PcgRandom(seed)
		inv:set_stack("dst", 1, ItemStack("mcl_lun_cooking:skewer " .. pr:next(1, 3)))
		return true
	end,
})

register_cutting_board_recipe({
	id = "cut_raw_chicken",
	match = function(tool, src1, src2)
		if not is_knife_stack(tool) then
			return false
		end
		local n1 = src1 and src1:get_name() or ""
		local n2 = src2 and src2:get_name() or ""
		if n1 == "mcl_mobitems:chicken" then
			return true, 1
		end
		if n2 == "mcl_mobitems:chicken" then
			return true, 2
		end
		return false
	end,
	apply = function(inv, src_index)
		if not board_is_output_empty(inv) then
			return false, S("Clear the output first.")
		end

		local src = inv:get_stack("src", src_index)
		if src:is_empty() then
			return false
		end
		src:take_item(1)
		inv:set_stack("src", src_index, src)

		inv:set_stack("dst", 1, ItemStack("mcl_lun_cooking:chicken_drumstick 2"))
		inv:set_stack("dst", 2, ItemStack("mcl_lun_cooking:chicken_breast 2"))
		inv:set_stack("dst", 3, ItemStack("mcl_lun_cooking:chicken_tender 2"))
		inv:set_stack("dst", 4, ItemStack("mcl_lun_cooking:chicken_wing 2"))
		inv:set_stack("dst", 5, ItemStack("mcl_lun_cooking:chicken_thigh 2"))
		inv:set_stack("dst", 6, ItemStack("mcl_lun_cooking:chicken_heart"))
		inv:set_stack("dst", 7, ItemStack("mcl_lun_cooking:chicken_liver"))
		return true
	end,
})

local function board_try_process(pos, player)
	local meta = core.get_meta(pos)
	local inv = meta:get_inventory()

	local tool = inv:get_stack("tool", 1)
	local src1 = inv:get_stack("src", 1)
	local src2 = inv:get_stack("src", 2)

	for _, recipe in ipairs(cutting_board_recipes) do
		local ok, src_index = recipe.match(tool, src1, src2)
		if ok then
			local success, err = recipe.apply(inv, src_index, player)
			if success then
				if mcl_lun_sounds and mcl_lun_sounds.play and mcl_lun_sounds.sounds.knife then
					mcl_lun_sounds.play(mcl_lun_sounds.sounds.knife, {pos = pos, max_hear_distance = 16}, true)
				end
			end
			return success, err
		end
	end
	return false, S("No matching recipe.")
end

local function board_allow_put(pos, listname, index, stack, player)
	local name = player:get_player_name()
	if core.is_protected(pos, name) then
		core.record_protection_violation(pos, name)
		return 0
	end
	if listname == "tool" then
		return is_knife_stack(stack) and 1 or 0
	elseif listname == "src" then
		return stack:get_count()
	elseif listname == "dst" then
		return 0
	end
	return 0
end

local function board_allow_move(pos, from_list, from_index, to_list, to_index, count, player)
	local meta = core.get_meta(pos)
	local inv = meta:get_inventory()
	local stack = inv:get_stack(from_list, from_index)
	stack:set_count(count)
	return board_allow_put(pos, to_list, to_index, stack, player)
end

local function board_allow_take(pos, _, _, stack, player)
	local name = player:get_player_name()
	if core.is_protected(pos, name) then
		core.record_protection_violation(pos, name)
		return 0
	end
	return stack:get_count()
end

local function board_can_dig(pos, player)
	local name = player and player:get_player_name() or ""
	if name ~= "" and core.is_protected(pos, name) then
		return false
	end
	local inv = core.get_meta(pos):get_inventory()
	return inv:is_empty("tool") and inv:is_empty("src") and inv:is_empty("dst")
end

local function board_on_receive_fields(pos, _, fields, sender)
	if not (sender and sender.is_player and sender:is_player()) then
		return
	end
	if fields.process then
		local ok, err = board_try_process(pos, sender)
		if not ok and err then
			core.chat_send_player(sender:get_player_name(), err)
		end
	end
end

local function register_cutting_board(name, desc, texture, icon_texture, groups_overrides)
	local groups = {
		handy = 1,
		axey = 1,
		building_block = 1,
		deco_block = 1,
		material_wood = 1,
		flammable = 1,
		crafting_table = 9,
	}
	if groups_overrides then
		for k, v in pairs(groups_overrides) do
			groups[k] = v
		end
	end

	core.register_node(name, {
		description = desc,
		_tt_help = S("Cutting and crafting"),
		_doc_items_longdesc = S("A cutting board with slots for a knife and ingredients."),
		_doc_items_hidden = false,
		drawtype = "mesh",
		mesh = "mcl_lun_cooking_cutting_board.obj",
		tiles = {texture},
		use_texture_alpha = "clip",
		paramtype = "light",
		paramtype2 = "facedir",
		is_ground_content = false,
		stack_max = 1,
		selection_box = {
			type = "fixed",
			fixed = { -0.45, -0.5, -0.40, 0.45, -0.40, 0.35 },
		},
		collision_box = {
			type = "fixed",
			fixed = { -0.45, -0.5, -0.40, 0.45, -0.40, 0.35 },
		},
		groups = groups,
		sounds = mcl_sounds and mcl_sounds.node_sound_wood_defaults() or nil,
		_mcl_hardness = 1.0,
		_mcl_blast_resistance = 1.0,
		on_place = place_only_on_top,
		on_construct = function(pos)
			local meta = core.get_meta(pos)
			local inv = meta:get_inventory()
			inv:set_size("tool", 1)
			inv:set_size("src", 2)
			inv:set_size("dst", 9)
			board_set_formspec(pos)
		end,
		allow_metadata_inventory_put = board_allow_put,
		allow_metadata_inventory_move = board_allow_move,
		allow_metadata_inventory_take = board_allow_take,
		can_dig = board_can_dig,
		on_receive_fields = board_on_receive_fields,
	})
end

register_cutting_board(
	"mcl_lun_cooking:cutting_board_oak",
	S("Oak Cutting Board"),
	"mcl_core_stripped_oak_side.png",
	"default_wood.png"
)

register_cutting_board(
	"mcl_lun_cooking:cutting_board_cherry",
	S("Cherry Cutting Board"),
	"mcl_cherry_blossom_log_stripped.png",
	"mcl_cherry_blossom_planks.png"
)

register_cutting_board(
	"mcl_lun_cooking:cutting_board_spruce",
	S("Spruce Cutting Board"),
	"mcl_core_stripped_spruce_side.png",
	"mcl_core_planks_spruce.png"
)

register_cutting_board(
	"mcl_lun_cooking:cutting_board_quartz",
	S("Quartz Cutting Board"),
	"mcl_nether_quartz_block_side.png",
	"default_stone.png",
	{material_wood = nil, flammable = nil, pickaxey = 1, cracky = 1}
)

register_cutting_board(
	"mcl_lun_cooking:cutting_board_stone",
	S("Stone Cutting Board"),
	"default_stone.png",
	"default_stone.png",
	{material_wood = nil, flammable = nil, pickaxey = 1, cracky = 1}
)

core.register_lbm({
	label = "Initialize cutting board inventories",
	name = "mcl_lun_cooking:init_cutting_board",
	nodenames = {
		"mcl_lun_cooking:cutting_board_oak",
		"mcl_lun_cooking:cutting_board_cherry",
		"mcl_lun_cooking:cutting_board_spruce",
		"mcl_lun_cooking:cutting_board_quartz",
		"mcl_lun_cooking:cutting_board_stone",
	},
	run_at_every_load = false,
	action = function(pos)
		local meta = core.get_meta(pos)
		local inv = meta:get_inventory()
		if inv:get_size("tool") == 0 then inv:set_size("tool", 1) end
		if inv:get_size("src") == 0 then inv:set_size("src", 2) end
		if inv:get_size("dst") == 0 then inv:set_size("dst", 9) end
		board_set_formspec(pos)
	end,
})

-- Backward compat: old node name becomes the cherry cutting board.
core.register_alias("mcl_lun_cooking:cutting_board", "mcl_lun_cooking:cutting_board_cherry")

local function register_knife(setname, base_sword, texture, desc)
	local base_def = core.registered_tools[base_sword]
	if not base_def then
		core.log("warning", "[mcl_lun_cooking] Missing base sword "..base_sword..", cannot register knife "..setname)
		return
	end

	local def = table.copy(base_def)
	def.description = desc
	def.inventory_image = texture
	def.wield_image = texture
	def.groups = table.copy(def.groups or {})
	def.groups.knife = 1

	core.register_tool("mcl_lun_cooking:knife_"..setname, def)
end

register_knife("wood", "mcl_tools:sword_wood", "mcl_lun_cooking_wooden_knife.png", S("Wooden Knife"))
register_knife("stone", "mcl_tools:sword_stone", "mcl_lun_cooking_stone_knife.png", S("Stone Knife"))
register_knife("iron", "mcl_tools:sword_iron", "mcl_lun_cooking_iron_knife.png", S("Iron Knife"))
register_knife("gold", "mcl_tools:sword_gold", "mcl_lun_cooking_golden_knife.png", S("Golden Knife"))
register_knife("diamond", "mcl_tools:sword_diamond", "mcl_lun_cooking_diamond_knife.png", S("Diamond Knife"))
register_knife("netherite", "mcl_tools:sword_netherite", "mcl_lun_cooking_netherite_knife.png", S("Netherite Knife"))

local function register_knife_crafts(setname, material)
	local output = "mcl_lun_cooking:knife_"..setname
	core.register_craft({
		output = output,
		recipe = {
			{ "", material, "" },
			{ "mcl_core:stick", "", "" },
		},
	})
	core.register_craft({
		output = output,
		recipe = {
			{ "", "", material },
			{ "", "mcl_core:stick", "" },
		},
	})
end

register_knife_crafts("wood", "group:wood")
register_knife_crafts("stone", "group:cobble")
register_knife_crafts("iron", "mcl_core:iron_ingot")
register_knife_crafts("gold", "mcl_core:gold_ingot")
register_knife_crafts("diamond", "mcl_core:diamond")
register_knife_crafts("netherite", "mcl_nether:netherite_ingot")

local function register_raw_chicken_variant(itemname, desc)
	local base = core.registered_items["mcl_mobitems:chicken"]
	if not base then
		core.log("warning", "[mcl_lun_cooking] Missing base item mcl_mobitems:chicken, cannot register "..itemname)
		return
	end
	local def = table.copy(base)
	def.description = desc
	def.groups = table.copy(def.groups or {})
	def.groups.chicken_component = 1
	core.register_craftitem(itemname, def)
end

register_raw_chicken_variant("mcl_lun_cooking:chicken_breast", S("Chicken Breast"))
register_raw_chicken_variant("mcl_lun_cooking:chicken_thigh", S("Chicken Thigh"))
register_raw_chicken_variant("mcl_lun_cooking:chicken_drumstick", S("Chicken Drumstick"))
register_raw_chicken_variant("mcl_lun_cooking:chicken_wing", S("Chicken Wing"))
register_raw_chicken_variant("mcl_lun_cooking:chicken_tender", S("Chicken Tender"))
register_raw_chicken_variant("mcl_lun_cooking:chicken_heart", S("Chicken Heart"))
register_raw_chicken_variant("mcl_lun_cooking:chicken_liver", S("Chicken Liver"))

core.override_item("mcl_lun_cooking:chicken_drumstick", {
	inventory_image = "mcl_lun_cooking_chicken_drumstick.png",
	wield_image = "mcl_lun_cooking_chicken_drumstick.png",
})

do
	local base = core.registered_items["mcl_mobitems:cooked_chicken"]
	if base then
		local def = table.copy(base)
		def.description = S("Cooked Chicken Drumstick")
		def.inventory_image = "mcl_lun_cooking_cooked_chicken_drumstick.png"
		def.wield_image = "mcl_lun_cooking_cooked_chicken_drumstick.png"
		def._mcl_saturation = 6.48 -- 10% less than cooked chicken (7.2)
		core.register_craftitem("mcl_lun_cooking:cooked_chicken_drumstick", def)
	end
end

core.override_item("mcl_lun_cooking:chicken_drumstick", {
	_mcl_cooking_output = "mcl_lun_cooking:cooked_chicken_drumstick",
})

do
	local base = core.registered_items["mcl_core:stick"]
	if base then
		local def = table.copy(base)
		def.description = S("Skewer")
		def.inventory_image = "mcl_lun_cooking_skewer.png"
		def.wield_image = "mcl_lun_cooking_skewer.png"
		core.register_craftitem("mcl_lun_cooking:skewer", def)
	end
end

do
	-- Any chicken cut + skewer -> uncooked yakitori.
	core.register_craft({
		type = "shapeless",
		output = "mcl_lun_items:yakitori_uncooked",
		recipe = { "group:chicken_component", "group:chicken_component", "mcl_lun_cooking:skewer" },
	})

	-- Chicken breast counts as two components.
	core.register_craft({
		type = "shapeless",
		output = "mcl_lun_items:yakitori_uncooked",
		recipe = { "mcl_lun_cooking:chicken_breast", "mcl_lun_cooking:skewer" },
	})
end
