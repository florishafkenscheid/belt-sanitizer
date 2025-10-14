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

return utils
