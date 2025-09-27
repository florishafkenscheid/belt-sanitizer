local OUTPUT_DIR = "belt"
local OUTPUT_FILE = OUTPUT_DIR .. "/sanitizer.json"

local ITEM_QUALITIES = {
    "normal",
    "uncommon",
    "rare",
    "epic",
    "legendary"
}

-- 1. Helper Functions
--------------------------------------------------------------------------------

local function g_bool(name, default)
  local setting = settings.startup[name]
  if setting == nil then return default end
  return setting.value
end

local function count_enemy(surface, type_name)
  return surface.count_entities_filtered({ force = "enemy", type = type_name })
end

local function total_pollution()
  local sum = 0
  for _, s in pairs(game.surfaces) do
    if s.valid and s.get_total_pollution then
      sum = sum + s:get_total_pollution()
    end
  end
  return sum
end

local function write_json(payload)
    if not g_bool("belt-sanitizer-write-diagnostics", true) then return end
    local ok, data = pcall(function() return helpers.table_to_json(payload) end)
    if not ok then
        helpers.write_file(OUTPUT_FILE, "sanitizer: json encode failed\n", false)
        return
    end
    helpers.write_file(OUTPUT_FILE, data .. "\n", false)
end

local function get_flow_precision_index(ticks)
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

local function get_check_tick()
    return settings.startup["belt-sanitizer-production-check-tick"].value
end

-- 2. Core Logic Functions
--------------------------------------------------------------------------------

local function snapshot()
    local per_surface = {}
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            table.insert(per_surface, {
                name = surface.name,
                peaceful = surface.peaceful_mode,
                total_pollution = surface.get_total_pollution and surface:get_total_pollution() or 0,
                enemy_units = count_enemy(surface, "unit"),
                enemy_spawners = count_enemy(surface, "unit-spawner"),
                enemy_worms = count_enemy(surface, "turret")
            })
        end
    end

    return {
        pollution_enabled = game.map_settings.pollution.enabled,
        enemy_expansion_enabled = game.map_settings.enemy_expansion.enabled,
        total_pollution = total_pollution(),
        surfaces = per_surface,
    }
end

local function check_benchmark_production()
    local item_list_str = settings.startup["belt-sanitizer-production-items"].value
    local fluid_list_str = settings.startup["belt-sanitizer-production-fluids"].value

    local precision = get_flow_precision_index(get_check_tick())
    local force = game.forces["player"]
    local production_results = { input = { items = {}, fluids = {} }, output = { items = {}, fluids = {} } }

    -- Get items and fluids into array from string
    local function parse_list(list_str)
        local list = {}
        for name in list_str:gmatch("([^,]+)") do
            list[#list+1] = name:gsub("^%s*(.-)%s*$", "%1")
        end
        return list
    end

    local items = parse_list(item_list_str)
    local fluids = parse_list(fluid_list_str)

    -- Initialize to 0
    for _, item in ipairs(items) do
        production_results.input.items[item] = {}
        production_results.output.items[item] = {}
        for _, quality in ipairs(ITEM_QUALITIES) do
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
                for _, quality in ipairs(ITEM_QUALITIES) do
                    local count = item_stats.get_flow_count({
                        name={name=item, quality=quality},
                        category="input",
                        precision_index=precision,
                        count=true
                    })
                    production_results.input.items[item][quality] = production_results.input.items[item][quality] + count
                end
                for _, quality in ipairs(ITEM_QUALITIES) do
                    local count = item_stats.get_flow_count({
                        name={name=item, quality=quality},
                        category="output",
                        precision_index=precision,
                        count=true
                    })
                    production_results.output.items[item][quality] = production_results.output.items[item][quality] + count
                end
            end
            local fluid_stats = force.get_fluid_production_statistics(surface)
            for _, fluid in ipairs(fluids) do
                local input_count = fluid_stats.get_flow_count({
                    name = fluid,
                    category="input",
                    precision_index=precision
                })
                production_results.input.fluids[fluid] = production_results.input.fluids[fluid] + input_count
                local output_count = fluid_stats.get_flow_count({
                    name = fluid,
                    category="output",
                    precision_index=precision
                })
                production_results.output.fluids[fluid] = production_results.output.fluids[fluid] + output_count
            end
        end
    end

    return production_results
end

local function run_once()
    local snap = snapshot()
    local production_data = check_benchmark_production()

    local payload = {
        settings = {
            report_pollution = g_bool("belt-sanitizer-report-pollution", true),
            report_biters = g_bool("belt-sanitizer-report-biters", true),
            peaceful_mode = g_bool("belt-sanitizer-peaceful-mode", true),
            report_expansion = g_bool("belt-sanitizer-report-expansion", true),
            freeze_daytime = g_bool("belt-sanitizer-freeze-daytime", false),
        },
        snapshot = snap,
        production_stats = production_data
    }

    write_json(payload)
end

-- 3. Event Handling (Entry Points)
--------------------------------------------------------------------------------

local function on_tick_handler()
    if game.tick == storage.benchmark_target_tick then
        run_once()
    end
end

local function on_first_tick()
    local duration_ticks = get_check_tick()

    log("Target tick: " .. game.tick + duration_ticks - 1 .. ". First tick: " .. game.tick)
    storage.benchmark_target_tick = game.tick + duration_ticks - 1

    script.on_event(defines.events.on_tick, nil)
    script.on_event(defines.events.on_tick, on_tick_handler)
end

-- 4. Initial Setup/Event Registration
--------------------------------------------------------------------------------

script.on_init(function()
    script.on_event(defines.events.on_tick, on_first_tick)
end)

script.on_load(function()
    script.on_event(defines.events.on_tick, on_first_tick)
end)

script.on_configuration_changed(function(_)
    storage.benchmark_target_tick = nil
end)
