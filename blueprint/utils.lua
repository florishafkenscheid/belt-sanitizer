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

utils.resource_map = {
	["efficiency-module-1"] = {
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
