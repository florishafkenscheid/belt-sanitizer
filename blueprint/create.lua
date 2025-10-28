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

	local s = game.surfaces["nauvis"] or game.surfaces[1]
	if not s then
		error("No surface available to place blueprint on")
	end

	local force = game.forces["player"] or game.create_force("player")
	utils.ensure_force_ready(force)
	local f = force.name

	local spawn_pos = utils.safe_spawn(s, 256)

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
        { spawn_pos.x + layout.total_width + 100, spawn_pos.y + layout.total_height + 100 }
	})

    local copy_idx = 0
    for row = 0, layout.rows - 1 do
        for col = 0, layout.copies_per_row - 1 do
            if copy_idx < copies then
                local copy_pos = {
                    x = spawn_pos.x + (col * layout.x_offset),
                    y = spawn_pos.y + (row * layout.y_offset)
                }

                place_single_blueprint(s, f, copy_pos, blueprint, ents)
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

function place_single_blueprint(s, f, spawn_pos, blueprint, ents)
	local bp_entity = s.create_entity({ name = "item-on-ground", position = spawn_pos, stack = "blueprint" })
	if not (bp_entity and bp_entity.valid and bp_entity.stack and bp_entity.stack.valid_for_read) then
		return
	end
	bp_entity.stack.import_stack(blueprint.string)

	local first_ent = ents[1]
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

	local first_ghost = bp_ghost[1]
	local offset = {
		x = (first_ghost.position.x - first_ent.position.x),
		y = (first_ghost.position.y - first_ent.position.y),
	}

	-- Place resources under drills
	for _, bpe in pairs(ents) do
		if bpe.name == "big-mining-drill" and bpe.items ~= nil then
			for _, req in pairs(bpe.items) do
				local module_name = req.id.name
				local quality = req.id.quality or "normal"
				local map = utils.resource_map[module_name]
				if map then
					local resource_name = map[quality] or map["normal"]
					if resource_name then
						s.create_entity({
							name = resource_name,
							amount = 10000000,
							position = { bpe.position.x + offset.x, bpe.position.y + offset.y },
						})
					end
				end
			end
		end
	end

	-- Revive non-rolling-stock first
	local afterSpawns = {}
	for _, entity in pairs(bp_ghost) do
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
				local _, ri = entity.revive()
				if ri and ri.valid and ri.get_module_inventory then
					for _, v in pairs(items) do
						local inv = ri.get_module_inventory()
						if inv and inv.valid then
							inv.insert({ name = v.name, count = v.count, quality = v.quality })
						end
					end
				end
			elseif entity and entity.valid then
				entity.revive()
			end
		end
	end

	for _, entity in pairs(afterSpawns) do
		if entity and entity.valid then
			entity.revive()
		end
	end

	-- Rebuild for drills
	afterSpawns = {}
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
		for _, entity in pairs(bp_ghost2) do
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
					local _, ri = entity.revive()
					if ri and ri.valid and ri.get_module_inventory then
						for _, v in pairs(items) do
							local inv = ri.get_module_inventory()
							if inv and inv.valid then
								inv.insert({ name = v.name, count = v.count, quality = v.quality })
							end
						end
					end
				elseif entity and entity.valid then
					entity.revive()
				end
			end
		end

		for _, entity in pairs(afterSpawns) do
			if entity and entity.valid then
				entity.revive()
			end
		end
	end
end

return blueprint
