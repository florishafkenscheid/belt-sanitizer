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

	local first_player = game.get_player(1)
	local s = first_player.surface
	local f = first_player.force.name
	local afterSpawns = {}

	local bp_entity = s.create_entity({ name = "item-on-ground", position = { 0, 0 }, stack = "blueprint" })
	bp_entity.stack.import_stack(blueprint.string)

	local first_ent = bp_entity.stack.get_blueprint_entities()[1]

	local bp_ghost = bp_entity.stack.build_blueprint({
		surface = s,
		force = f,
		position = first_player.position,
		force_build = true,
	})
	local first_ghost = bp_ghost[1]
	local offset = { first_ghost.position.x - first_ent.position.x, first_ghost.position.y - first_ent.position.y }
	for _, bpe in pairs(bp_entity.stack.get_blueprint_entities()) do
		if bpe.name ~= "big-mining-drill" or bpe.items == nil then
			goto continue
		end

		for _, req in pairs(bpe.items) do
			local module_name = req.id.name
			local quality = req.id.quality or "normal"

			local map = utils.resource_map[module_name]
			if not map then
				goto continue
			end

			local resource_name = map[quality] or map["normal"]
			if resource_name then
				s.create_entity({
					name = resource_name,
					amount = 10000000,
					position = {
						bpe.position.x + offset[1],
						bpe.position.y + offset[2],
					},
				})
			end
		end

		::continue::
	end
	for _, entity in pairs(bp_ghost) do
		if
			entity.ghost_name == "locomotive"
			or entity.ghost_name == "cargo-wagon"
			or entity.ghost_name == "fluid-wagon"
		then
			table.insert(afterSpawns, entity)
		else
			if
				entity ~= nil
				and entity.name == "entity-ghost"
				and entity.ghost_type ~= nil
				and entity.item_requests ~= nil
			then
				local items = util.table.deepcopy(entity.item_requests)

				local _, ri = entity.revive()
				if ri ~= nil then
					for _, v in pairs(items) do
						ri.get_module_inventory().insert({ name = v.name, count = v.count, quality = v.quality })
					end
				end
			else
				entity.revive()
			end
		end
	end

	for _, entity in pairs(afterSpawns) do
		entity.revive()
	end

	-- and now we need to rebuild stuff, so that we build the miners now that we have the proper ore under them
	afterSpawns = {}
	local bp_ghost2 = bp_entity.stack.build_blueprint({
		surface = s,
		force = f,
		position = first_player.position,
		force_build = true,
	})
	bp_entity.destroy()

	for _, entity in pairs(bp_ghost2) do
		if
			entity.ghost_name == "locomotive"
			or entity.ghost_name == "cargo-wagon"
			or entity.ghost_name == "fluid-wagon"
		then
			table.insert(afterSpawns, entity)
		else
			if
				entity ~= nil
				and entity.name == "entity-ghost"
				and entity.ghost_type ~= nil
				and entity.item_requests ~= nil
			then
				local items = util.table.deepcopy(entity.item_requests)

				local _, ri = entity.revive()
				if ri ~= nil then
					for _, v in pairs(items) do
						ri.get_module_inventory().insert({ name = v.name, count = v.count, quality = v.quality })
					end
				end
			else
				entity.revive()
			end
		end
	end
	for _, entity in pairs(afterSpawns) do
		entity.revive()
	end

	-- Add logistic bots to each roboport
	if blueprint.bot_count ~= nil and blueprint.bot_count > 0 then
		for _, roboport in pairs(s.find_entities_filtered({ type = "roboport" })) do
			roboport.insert({ name = "logistic-robot", count = blueprint.bot_count, quality = "legendary" })
		end
	end
end

return blueprint
