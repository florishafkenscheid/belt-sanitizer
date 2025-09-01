-- local MOD_NAME = "belt-sanitizer"
-- local OUTPUT_DIR = "belt"
-- local MARKER_FILE = OUTPUT_DIR .. "/loaded.txt"
-- local UPDATE_FILE = OUTPUT_DIR .. "/updated.txt"

-- local function write_marker(kind, from, to)
--   local version = script.active_mods[MOD_NAME] or "unknown"
--   local base_version = script.active_mods["base"] or "unknown"
--   local lines = {
--     "kind=" .. (kind or "init"),
--     "mod=" .. MOD_NAME .. "@" .. version,
--     "base=" .. base_version,
--     "tick=" .. game.tick,
--   }
--   if from or to then
--     table.insert(lines, "from=" .. tostring(from))
--     table.insert(lines, "to=" .. tostring(to))
--   end
--   local payload = table.concat(lines, "\n") .. "\n"
--   local file = (kind == "update") and UPDATE_FILE or MARKER_FILE
--   -- Writes under <user-data-dir>/script-output/
--   helpers.write_file(file, payload, kind == "update") -- append if 'update'
--   log(MOD_NAME .. ": wrote " .. file .. " (" .. lines[1] .. ")")
-- end

-- script.on_init(function()
--   write_marker("init")
-- end)

-- script.on_configuration_changed(function(cfg)
--   local mc = cfg and cfg.mod_changes and cfg.mod_changes[MOD_NAME]
--   if not mc then return end
--   if not mc.old_version then
--     -- Mod was added to an existing save
--     write_marker("added")
--   elseif mc.old_version ~= mc.new_version then
--     -- Mod updated
--     write_marker("update", mc.old_version, mc.new_version)
--   end
-- end)

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

local function snapshot(kind)
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
        kind = kind,
        tick = game.tick,
        pollution_enabled = game.map_settings.pollution.enabled,
        enemy_expansion_enabled = game.map_settings.enemy_expansion.enabled,
        total_pollution = total_pollution(),
        surfaces = per_surface,
    }
end

local function apply_fixes(applied)
    -- pollution
    if g_bool("belt-sanitizer-fix-pollution", true) then
        game.map_settings.pollution.enabled = false
        for _, surface in pairs(game.surfaces) do
            if surface.valid and surface.clear_pollution then surface.clear_pollution() end
        end
        table.insert(applied, "pollution_disabled_and_cleared")
    end

    -- peaceful mode
    if g_bool("belt-sanitizer-peaceful-mode", true) then
        for _, s in pairs(game.surfaces) do
            if s.valid then s.peaceful_mode = true end
        end
        table.insert(applied, "peaceful_mode_enabled")
    end

    -- enemy expansion + evolution off
    if g_bool("belt-sanitizer-disable-expansion", true) then
        game.map_settings.enemy_expansion.enabled = false
        local evo = game.map_settings.enemy_evolution
        if evo then
            evo.time_factor = 0
            evo.pollution_factor = 0
        end

        table.insert(applied, "enemy_expansion_disabled_evolution_zeroed")
    end

    -- kill units and remove spawners/worms
    if g_bool("belt-sanitizer-fix-biters", true) then
        local enemy = game.forces["enemy"]
        if enemy and enemy.valid then enemy.kill_all_units() end
        for _, s in pairs(game.surfaces) do
            if s.valid then
                for _, e in pairs(s.find_entities_filtered({
                    force = "enemy",
                    type = "unit-spawner",
                })) do
                    e.destroy()
                end
                for _, e in pairs(s.find_entities_filtered({
                    force = "enemy",
                    type = "turret",
                })) do
                    e.destroy()
                end
            end
        end
        table.insert(applied, "biters_units_killed_spawners_worms_destroyed")
    end

    -- freeze daytime (optional)
    if g_bool("belt-sanitizer-freeze-daytime", false) then
        for _, s in pairs(game.surfaces) do
            if s.valid then
                s.freeze_daytime = true
                s.daytime = 0.5
            end
        end
        table.insert(applied, "daytime_frozen")
    end
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
    local cfg_apply = g_bool("belt-sanitizer-apply-fixes", true)

    local pre = snapshot("pre")
    local applied = {}

    if cfg_apply then apply_fixes(applied) end

    local post = snapshot(cfg_apply and "post" or "post_noop")

    local payload = {
        mod = MOD_NAME,
        tick = game.tick,
        mode = cfg_apply and "fix" or "detect",
        settings = {
            apply_fixes = cfg_apply,
            fix_pollution = g_bool("belt-sanitizer-fix-pollution", true),
            fix_biters = g_bool("belt-sanitizer-fix-biters", true),
            peaceful_mode = g_bool("belt-sanitizer-peaceful-mode", true),
            disable_expansion = g_bool("belt-sanitizer-disable-expansion", true),
            freeze_daytime = g_bool("belt-sanitizer-freeze-daytime", false),
        },
        applied_actions = applied,
        pre = pre,
        post = post,
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