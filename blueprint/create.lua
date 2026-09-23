---@module blueprint.create
-- Great thanks to TwostepSA, with some modifications of my own.
local util = require("util") -- factorio util lib
local utils = require("blueprint.utils")

local blueprint = { string = "", save_name = "", loaded = false, copies = 0, bot_count = 0 }

local create = {}
blueprint.create = create

function create.draw_bp()
	blueprint.string = utils.get_blueprint_string()
	blueprint.save_name = utils.get_save_name()
	blueprint.bot_count = utils.get_bot_count()
	blueprint.copies = utils.get_copy_count()
	blueprint.mining_module_replacement = utils.get_mining_module_replacement()
	blueprint.mining_module_replacement_quality = utils.get_mining_module_replacement_quality()

	local s = game.surfaces["nauvis"] or game.surfaces[1]
	if not s then
		error("No surface available to place blueprint on")
	end

	local force = game.forces["player"] or game.create_force("player")
	utils.ensure_force_ready(force)
	local f = force.name

	local spawn_pos = utils.safe_spawn(s, 256)

	-- Move player to not obstruct blueprint placement
	local player_char = game.players[1] and game.players[1].character
	if player_char and player_char.valid then
		local safe_player_x = spawn_pos.x - 200
		local safe_player_y = spawn_pos.y - 200
		player_char.teleport({ x = safe_player_x, y = safe_player_y }, s)
	end

	-- Get once to calculate dimensions
	local bp_entity = s.create_entity({ name = "item-on-ground", position = spawn_pos, stack = "blueprint" })
	if not (bp_entity and bp_entity.valid and bp_entity.stack and bp_entity.stack.valid_for_read) then
		error("Failed to create/import temporary blueprint item")
	end
	local ok, err = pcall(function()
		bp_entity.stack.import_stack(blueprint.string)
	end)
	if not ok then
		bp_entity.destroy()
		error("Invalid blueprint string: " .. tostring(err))
	end

	local ents = bp_entity.stack.get_blueprint_entities()
	local tiles = bp_entity.stack.get_blueprint_tiles()
	if not (ents and ents[1]) then
		bp_entity.destroy()
		error("Blueprint has no entities")
	end

	bp_entity.destroy()

	local copies = blueprint.copies or 1
	local layout = utils.calculate_grid_layout(ents, copies, 10)

	s.request_to_generate_chunks(spawn_pos, layout.area_radius)
	s.force_generate_chunk_requests()

	force.chart(s, {
		{ spawn_pos.x - 100, spawn_pos.y - 100 },
		{ spawn_pos.x + layout.total_width + 100, spawn_pos.y + layout.total_height + 100 },
	})

	local copy_idx = 0
	for row = 0, layout.rows - 1 do
		for col = 0, layout.copies_per_row - 1 do
			if copy_idx < copies then
				local copy_pos = {
					x = spawn_pos.x + (col * layout.x_offset),
					y = spawn_pos.y + (row * layout.y_offset),
				}

				place_single_blueprint(s, f, copy_pos, blueprint, ents, tiles)
				copy_idx = copy_idx + 1
			end
		end
	end

	if blueprint.bot_count and blueprint.bot_count > 0 then
		for _, roboport in pairs(s.find_entities_filtered({ type = "roboport", force = f })) do
			if roboport and roboport.valid and roboport.insert then
				roboport.insert({
					name = "logistic-robot",
					count = blueprint.bot_count,
					quality = "legendary",
				})
			end
		end
	end
end

local function point_x(position)
	return position.x or position[1]
end

local function point_y(position)
	return position.y or position[2]
end

local function position_key(position)
	return math.floor(point_x(position)) .. "," .. math.floor(point_y(position))
end

local function get_tile_resource_at_position(tile_resources, position)
	return tile_resources[position_key(position)]
end

local function get_tile_resource_for_drill(tile_resources, drill)
	if not tile_resources or not drill or not drill.position then
		return nil
	end

	local direct = get_tile_resource_at_position(tile_resources, drill.position)
	if direct then
		return direct
	end

	local drill_x = point_x(drill.position)
	local drill_y = point_y(drill.position)
	for x = math.floor(drill_x) - 2, math.floor(drill_x) + 2 do
		for y = math.floor(drill_y) - 2, math.floor(drill_y) + 2 do
			local resource = tile_resources[x .. "," .. y]
			if resource then
				return resource
			end
		end
	end

	return nil
end

local function build_tile_resource_lookup(tiles, offset)
	local tile_resources = {}
	if not tiles then
		return tile_resources
	end

	for _, tile in pairs(tiles) do
		local resource_name = utils.tile_resource_map[tile.name]
		if resource_name and tile.position then
			tile_resources[position_key({
				x = point_x(tile.position) + offset.x,
				y = point_y(tile.position) + offset.y,
			})] =
				resource_name
		end
	end

	return tile_resources
end

local function get_module_resource_for_drill(drill)
	if not drill.items then
		return nil
	end

	for _, req in pairs(drill.items) do
		local module_name = req.id and req.id.name
		local quality = (req.id and req.id.quality) or "normal"
		local map = module_name and utils.resource_map[module_name]
		if map then
			return map[quality] or map["normal"]
		end
	end

	return nil
end

local function is_module_item(name)
	return name and prototypes.item[name] and prototypes.item[name].type == "module"
end

local function get_mining_module_replacement(blueprint)
	local module_name = blueprint.mining_module_replacement
	if not is_module_item(module_name) then
		module_name = "speed-module-3"
	end

	local quality = blueprint.mining_module_replacement_quality or "normal"
	if not (prototypes.quality and prototypes.quality[quality]) then
		quality = "normal"
	end

	return module_name, quality
end

local function has_resource_marker_module(items)
	if not items then
		return false
	end

	for _, item in pairs(items) do
		if item.name and utils.resource_map[item.name] then
			return true
		end
	end

	return false
end

local function insert_modules(entity, items, blueprint)
	if not (entity and entity.valid and entity.get_module_inventory) then
		return
	end

	local inv = entity.get_module_inventory()
	if not (inv and inv.valid) then
		return
	end

	if utils.mining_drills[entity.name] and has_resource_marker_module(items) then
		local module_name, quality = get_mining_module_replacement(blueprint)
		local stack = { name = module_name, quality = quality }
		stack.count = inv.get_insertable_count(stack)
		if stack.count > 0 then
			inv.insert(stack)
		end
		return
	end

	for _, v in pairs(items) do
		inv.insert({ name = v.name, count = v.count, quality = v.quality })
	end
end

local function revive_entities(entities, blueprint)
	local afterSpawns = {}
	for _, entity in pairs(entities) do
		if
			entity
			and entity.valid
			and entity.name == "entity-ghost"
			and (
				entity.ghost_name == "locomotive"
				or entity.ghost_name == "cargo-wagon"
				or entity.ghost_name == "fluid-wagon"
			)
		then
			table.insert(afterSpawns, entity)
		else
			if
				entity
				and entity.valid
				and entity.name == "entity-ghost"
				and entity.ghost_type ~= nil
				and entity.item_requests ~= nil
			then
				local items = util.table.deepcopy(entity.item_requests)
				local _, ri = entity.revive({ raise_revive = true })
				insert_modules(ri, items, blueprint)
			elseif entity and entity.valid then
				entity.revive({ raise_revive = true })
			end
		end
	end

	for _, entity in pairs(afterSpawns) do
		if entity and entity.valid then
			entity.revive({ raise_revive = true })
		end
	end
end

local function create_resource_patch(surface, resource_name, position)
	if not (resource_name and prototypes.entity[resource_name]) then
		return
	end

	surface.create_entity({
		name = resource_name,
		amount = 10000000,
		position = position,
	})
end

local function calculate_blueprint_offset(spawn_pos, ents, tiles, built_entities)
	if tiles and tiles[1] then
		for _, entity in pairs(built_entities) do
			if entity and entity.valid and entity.name == "tile-ghost" then
				return {
					x = point_x(entity.position) - point_x(tiles[1].position),
					y = point_y(entity.position) - point_y(tiles[1].position),
				}
			end
		end
	end

	for _, entity in pairs(built_entities) do
		if entity and entity.valid and entity.name ~= "tile-ghost" then
			return {
				x = point_x(entity.position) - point_x(ents[1].position),
				y = point_y(entity.position) - point_y(ents[1].position),
			}
		end
	end

	return {
		x = point_x(spawn_pos),
		y = point_y(spawn_pos),
	}
end

function place_single_blueprint(s, f, spawn_pos, blueprint, ents, tiles)
	local bp_entity = s.create_entity({ name = "item-on-ground", position = spawn_pos, stack = "blueprint" })
	if not (bp_entity and bp_entity.valid and bp_entity.stack and bp_entity.stack.valid_for_read) then
		return
	end
	bp_entity.stack.import_stack(blueprint.string)

	local bp_ghost = bp_entity.stack.build_blueprint({
		surface = s,
		force = f,
		position = spawn_pos,
		skip_fog_of_war = false,
		build_mode = defines.build_mode.superforced,
	})

	if not (bp_ghost and #bp_ghost > 0) then
		bp_entity.destroy()
		return
	end

	local offset = calculate_blueprint_offset(spawn_pos, ents, tiles, bp_ghost)
	local tile_resources = build_tile_resource_lookup(tiles, offset)

	-- Place resources under drills
	for _, bpe in pairs(ents) do
		if utils.mining_drills[bpe.name] then
			local drill_position = {
				x = point_x(bpe.position) + offset.x,
				y = point_y(bpe.position) + offset.y,
			}
			local resource_name = get_tile_resource_for_drill(tile_resources, {
				position = drill_position,
			}) or get_module_resource_for_drill(bpe)
			if resource_name then
				create_resource_patch(s, resource_name, drill_position)
			end
		end
	end

	-- Revive non-rolling-stock first
	revive_entities(bp_ghost, blueprint)

	-- Rebuild for drills
	local bp_ghost2 = nil

	if not (bp_entity and bp_entity.valid) then
		bp_entity = s.create_entity({ name = "item-on-ground", position = spawn_pos, stack = "blueprint" })
		if bp_entity and bp_entity.valid and bp_entity.stack and bp_entity.stack.valid_for_read then
			bp_entity.stack.import_stack(blueprint.string)
		end
	end

	if bp_entity and bp_entity.valid then
		bp_ghost2 = bp_entity.stack.build_blueprint({
			surface = s,
			force = f,
			position = spawn_pos,
			skip_fog_of_war = false,
			build_mode = defines.build_mode.superforced,
		})
		bp_entity.destroy()
	end

	if bp_ghost2 then
		revive_entities(bp_ghost2, blueprint)
	end
end

return blueprint
