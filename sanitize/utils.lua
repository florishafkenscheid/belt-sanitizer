--- @module sanitize.utils
local utils = {}

-- Definitions
local OUTPUT_DIR = "belt"
local OUTPUT_FILE = OUTPUT_DIR .. "/sanitizer.json"

utils.ITEM_QUALITIES = {
	"normal",
	"uncommon",
	"rare",
	"epic",
	"legendary",
}

local NATIVE_INFINITY_ENTITY_TYPES = {
	["infinity-container"] = true,
	["infinity-pipe"] = true,
	["infinity-cargo-wagon"] = true,
}

local infinity_entity_names_by_type

-- Functions
function utils.g_bool(name, default)
	local setting = settings.startup[name]
	if setting == nil then
		return default
	end
	return setting.value
end

function utils.count_enemy(surface, type_name)
	return surface.count_entities_filtered({ force = "enemy", type = type_name })
end

function utils.total_pollution()
	local sum = 0
	for _, s in pairs(game.surfaces) do
		if s.valid and s.get_total_pollution then
			sum = sum + s:get_total_pollution()
		end
	end
	return sum
end

function utils.get_active_entities(surface)
	local n = {}
	local entity_types = { "rocket-silo", "car", "tank" }
	for _, type in pairs(entity_types) do
		n[type] = n[type] or 0
		for _, e in pairs(surface.find_entities_filtered({ type = type })) do
			if e.valid and e.active then
				n[type] = n[type] + 1
			end
		end
	end
	return n
end

function utils.get_infinity_entity_counts(surface)
	if not infinity_entity_names_by_type then
		infinity_entity_names_by_type = {}

		for name, prototype in pairs(prototypes.entity) do
			local is_editor_extensions = name:match("^ee%-infinity%-") ~= nil
			if
				(is_editor_extensions and not prototype.hidden)
				or (not is_editor_extensions and NATIVE_INFINITY_ENTITY_TYPES[prototype.type])
			then
				local names = infinity_entity_names_by_type[prototype.type]
				if not names then
					names = {}
					infinity_entity_names_by_type[prototype.type] = names
				end
				names[#names + 1] = name
			end
		end
	end

	local counts = {}
	for prototype_type, names in pairs(infinity_entity_names_by_type) do
		counts[prototype_type] = surface.count_entities_filtered({ name = names })
	end
	return counts
end

function utils.write_json(payload)
	if not utils.g_bool("belt-sanitizer-write-diagnostics", true) then
		return
	end
	local ok, data = pcall(function()
		return helpers.table_to_json(payload)
	end)
	if not ok then
		helpers.write_file(OUTPUT_FILE, "sanitizer: json encode failed\n", false)
		return
	end
	helpers.write_file(OUTPUT_FILE, data .. "\n", false)
end

function utils.get_flow_precision_index()
	local ticks = settings.startup["belt-sanitizer-target-tick"].value
	-- Map flow duration in ticks to the corresponding defines.flow_precision_index
	local ONE_MINUTE_TICKS = 3600 -- 60 seconds * 60 ticks
	local ONE_HOUR_TICKS = 216000 -- 60 minutes * 3600 ticks

	if ticks >= 250 * ONE_HOUR_TICKS then
		return defines.flow_precision_index.two_hundred_fifty_hours
	elseif ticks >= 50 * ONE_HOUR_TICKS then
		return defines.flow_precision_index.fifty_hours
	elseif ticks >= 10 * ONE_HOUR_TICKS then
		return defines.flow_precision_index.ten_hours
	elseif ticks >= ONE_HOUR_TICKS then
		return defines.flow_precision_index.one_hour
	elseif ticks >= 10 * ONE_MINUTE_TICKS then
		return defines.flow_precision_index.ten_minutes
	elseif ticks >= ONE_MINUTE_TICKS then
		return defines.flow_precision_index.one_minute
	else
		return defines.flow_precision_index.five_seconds
	end
end

function utils.get_check_tick()
	return settings.startup["belt-sanitizer-target-tick"].value
end

return utils
