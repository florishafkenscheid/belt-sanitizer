---@module blueprint.utils

local utils = {}

function utils.get_blueprint_string()
	return settings.startup["belt-sanitizer-blueprint-string"].value
end

function utils.get_save_name()
	return settings.startup["belt-sanitizer-blueprint-save-name"].value
end

function utils.get_bot_count()
	return settings.startup["belt-sanitizer-blueprint-bot-count"].value
end

function utils.get_copy_count()
	return settings.startup["belt-sanitizer-blueprint-count"].value
end

function utils.get_mining_module_replacement()
	return settings.startup["belt-sanitizer-mining-module-replacement"].value
end

function utils.get_mining_module_replacement_quality()
	return settings.startup["belt-sanitizer-mining-module-replacement-quality"].value
end

function utils.safe_spawn(surface, radius)
	local p = surface.find_non_colliding_position("character", { 0, 0 }, radius or 128, 0.5)
	if not p then
		return { x = 0, y = 0 }
	end

	return { x = p.x or p[1], y = p.y or p[2] }
end

function utils.ensure_force_ready(force)
	force.research_all_technologies()
end

function utils.calculate_grid_layout(ents, copies, spacing)
	spacing = spacing or 10
	copies = copies or 1

	-- Calculate grid dimensions
	local copies_per_row = math.ceil(math.sqrt(copies))
	local rows = math.ceil(copies / copies_per_row)

	-- Calculate blueprint dimensions
	local min_x, max_x = math.huge, -math.huge
	local min_y, max_y = math.huge, -math.huge

	for _, ent in pairs(ents) do
		min_x = math.min(min_x, ent.position.x)
		max_x = math.max(max_x, ent.position.x)
		min_y = math.min(min_y, ent.position.y)
		max_y = math.max(max_y, ent.position.y)
	end

	local bp_width = max_x - min_x
	local bp_height = max_y - min_y
	local x_offset = bp_width + spacing
	local y_offset = bp_height + spacing

	local total_width = copies_per_row * x_offset
	local total_height = rows * y_offset

	return {
		copies_per_row = copies_per_row,
		rows = rows,
		bp_width = bp_width,
		bp_height = bp_height,
		x_offset = x_offset,
		y_offset = y_offset,
		total_width = total_width,
		total_height = total_height,
		area_radius = math.ceil(math.max(total_width, total_height, 100) / 32) + 2
	}
end

utils.resource_map = {
	["efficiency-module"] = {
		normal = "stone",
		uncommon = "iron-ore",
		rare = "copper-ore",
		epic = "coal",
		legendary = "uranium-ore",
	},
	["efficiency-module-2"] = {
		normal = "calcite",
		uncommon = "tungsten-ore",
		rare = "scrap",
	},
}

utils.tile_resource_map = {
	["stone-path"] = "stone",
	["concrete"] = "iron-ore",
	["hazard-concrete"] = "coal",
	["refined-concrete"] = "copper-ore",
	["refined-hazard-concrete"] = "scrap",
}

utils.mining_drills = {
	["electric-mining-drill"] = true,
	["big-mining-drill"] = true,
}

return utils
