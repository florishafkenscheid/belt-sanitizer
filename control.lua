local MOD_NAME = "belt-sanitizer"
local OUTPUT_DIR = "belt"
local OUTPUT_FILE = OUTPUT_DIR .. "/sanitizer.json"

local function g_bool(name, default)
  local setting = settings.global[name]
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

local function write_json(payload)
    if not g_bool("belt-sanitizer-write-diagnostics", true) then return end
    local ok, data = pcall(function() return helpers.table_to_json(payload) end)
    if not ok then
        helpers.write_file(OUTPUT_FILE, "sanitizer: json encode failed\n", false)
        return
    end
    helpers.write_file(OUTPUT_FILE, data .. "\n", false)
end

local function run_once()
    local snap = snapshot()

    local payload = {
        mod = MOD_NAME,
        settings = {
            report_pollution = g_bool("belt-sanitizer-report-pollution", true),
            report_biters = g_bool("belt-sanitizer-report-biters", true),
            peaceful_mode = g_bool("belt-sanitizer-peaceful-mode", true),
            report_expansion = g_bool("belt-sanitizer-report-expansion", true),
            freeze_daytime = g_bool("belt-sanitizer-freeze-daytime", false),
        },
        snapshot = snap,
    }

    write_json(payload)
end

local function on_first_tick()
    script.on_event(defines.events.on_tick, nil)
    run_once()
end

script.on_init(function()
    script.on_event(defines.events.on_tick, on_first_tick)
end)

script.on_load(function()
    script.on_event(defines.events.on_tick, on_first_tick)
end)

script.on_configuration_changed(function(_)
    script.on_event(defines.events.on_tick, on_first_tick)
end)
