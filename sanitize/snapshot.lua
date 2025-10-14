--- @module sanitize.snapshot
local utils = require("sanitize.utils")

local snapshot = {}

local function create_snapshot()
	local per_surface = {}
	for _, surface in pairs(game.surfaces) do
		if surface.valid then
			table.insert(per_surface, {
				name = surface.name,
				peaceful = surface.peaceful_mode,
				total_pollution = surface.get_total_pollution and surface:get_total_pollution() or 0,
				enemy_units = utils.count_enemy(surface, "unit"),
				enemy_spawners = utils.count_enemy(surface, "unit-spawner"),
				enemy_worms = utils.count_enemy(surface, "turret"),
			})
		end
	end

	return {
		pollution_enabled = game.map_settings.pollution.enabled,
		enemy_expansion_enabled = game.map_settings.enemy_expansion.enabled,
		total_pollution = utils.total_pollution(),
		surfaces = per_surface,
	}
end

local function check_benchmark_production()
	local item_list_str = settings.startup["belt-sanitizer-production-items"].value
	local fluid_list_str = settings.startup["belt-sanitizer-production-fluids"].value

	local precision = utils.get_flow_precision_index()
	local force = game.forces["player"]
	local production_results = { input = { items = {}, fluids = {} }, output = { items = {}, fluids = {} } }

	-- Get items and fluids into array from string
	local function parse_list(list_str)
		local list = {}
		for name in list_str:gmatch("([^,]+)") do
			list[#list + 1] = name:gsub("^%s*(.-)%s*$", "%1")
		end
		return list
	end

	local items = parse_list(item_list_str)
	local fluids = parse_list(fluid_list_str)

	-- Initialize to 0
	for _, item in ipairs(items) do
		production_results.input.items[item] = {}
		production_results.output.items[item] = {}
		for _, quality in ipairs(utils.ITEM_QUALITIES) do
			production_results.input.items[item][quality] = 0
			production_results.output.items[item][quality] = 0
		end
	end
	for _, fluid in ipairs(fluids) do
		production_results.input.fluids[fluid] = 0
		production_results.output.fluids[fluid] = 0
	end

	-- Get production stats
	for _, surface in pairs(game.surfaces) do
		if surface.valid then
			local item_stats = force.get_item_production_statistics(surface)
			for _, item in ipairs(items) do
				for _, quality in ipairs(utils.ITEM_QUALITIES) do
					local input_count = item_stats.get_flow_count({
						name = { name = item, quality = quality },
						category = "input",
						precision_index = precision,
						count = true,
					})
					production_results.input.items[item][quality] = production_results.input.items[item][quality]
						+ input_count
					local output_count = item_stats.get_flow_count({
						name = { name = item, quality = quality },
						category = "output",
						precision_index = precision,
						count = true,
					})
					production_results.output.items[item][quality] = production_results.output.items[item][quality]
						+ output_count
				end
			end
			local fluid_stats = force.get_fluid_production_statistics(surface)
			for _, fluid in ipairs(fluids) do
				local input_count = fluid_stats.get_flow_count({
					name = fluid,
					category = "input",
					precision_index = precision,
					count = true,
				})
				production_results.input.fluids[fluid] = production_results.input.fluids[fluid] + input_count
				local output_count = fluid_stats.get_flow_count({
					name = fluid,
					category = "output",
					precision_index = precision,
					count = true,
				})
				production_results.output.fluids[fluid] = production_results.output.fluids[fluid] + output_count
			end
		end
	end

	return production_results
end

function snapshot.run_once()
	local snap = create_snapshot()
	local production_data = check_benchmark_production()

	local payload = {
		settings = {
			report_pollution = utils.g_bool("belt-sanitizer-report-pollution", true),
			report_biters = utils.g_bool("belt-sanitizer-report-biters", true),
			peaceful_mode = utils.g_bool("belt-sanitizer-peaceful-mode", true),
			report_expansion = utils.g_bool("belt-sanitizer-report-expansion", true),
			freeze_daytime = utils.g_bool("belt-sanitizer-freeze-daytime", false),
		},
		snapshot = snap,
		production_stats = production_data,
	}

	utils.write_json(payload)
end

return snapshot
