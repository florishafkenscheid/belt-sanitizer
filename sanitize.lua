-- The sanitize job: run the save for job.ticks ticks, then report what would skew a benchmark
-- and the production and consumption of the tracked items and fluids over those ticks.
local protocol = require("protocol")

local sanitize = {}

local ENEMY_UNITS = { "unit", "segmented-unit", "spider-unit" }
local ENEMY_SPAWNERS = { "unit-spawner" }
local ENEMY_WORMS = { "turret" }
local VEHICLES = { "rocket-silo", "car" }
-- Test entities that create or destroy items, fluids or energy from nothing.
local INFINITY_TYPES = { "infinity-container", "infinity-pipe", "infinity-cargo-wagon", "electric-energy-interface", "heat-interface" }
-- Editor Extensions' test entities; its hidden ones are internal helpers and don't count.
local EDITOR_EXTENSIONS_PREFIX = "ee-infinity-"

local function check_names(names, prototype_table, kind)
  for _, name in pairs(names) do
    if not prototype_table[name] then
      error(string.format("unknown %s %q", kind, name))
    end
  end
end

-- Totals over every surface and force: produced (input) and consumed (output).
local function flow_totals(job)
  local items, fluids = {}, {}
  for _, name in pairs(job.items) do
    for quality in pairs(prototypes.quality) do
      items[name .. "/" .. quality] = { name = name, quality = quality, produced = 0, consumed = 0 }
    end
  end
  for _, name in pairs(job.fluids) do
    fluids[name] = { name = name, produced = 0, consumed = 0 }
  end
  for _, force in pairs(game.forces) do
    for _, surface in pairs(game.surfaces) do
      local item_statistics = force.get_item_production_statistics(surface)
      for _, flow in pairs(items) do
        local id = { name = flow.name, quality = flow.quality }
        flow.produced = flow.produced + item_statistics.get_input_count(id)
        flow.consumed = flow.consumed + item_statistics.get_output_count(id)
      end
      local fluid_statistics = force.get_fluid_production_statistics(surface)
      for _, flow in pairs(fluids) do
        flow.produced = flow.produced + fluid_statistics.get_input_count(flow.name)
        flow.consumed = flow.consumed + fluid_statistics.get_output_count(flow.name)
      end
    end
  end
  return items, fluids
end

local function counts_by(entities, key)
  local counts = {}
  for _, entity in pairs(entities) do
    local name = key(entity)
    counts[name] = (counts[name] or 0) + 1
  end
  local list = {}
  for name, count in pairs(counts) do
    list[#list + 1] = { name = name, count = count }
  end
  table.sort(list, function(left, right) return left.name < right.name end)
  return protocol.list(list)
end

local function infinity_entities(surface)
  local counted_editor_extensions = {}
  for name, prototype in pairs(prototypes.entity) do
    if name:sub(1, #EDITOR_EXTENSIONS_PREFIX) == EDITOR_EXTENSIONS_PREFIX and not prototype.hidden then
      counted_editor_extensions[#counted_editor_extensions + 1] = name
    end
  end
  local found = {}
  for _, entity in pairs(surface.find_entities_filtered({ type = INFINITY_TYPES })) do
    if entity.name:sub(1, #EDITOR_EXTENSIONS_PREFIX) ~= EDITOR_EXTENSIONS_PREFIX then
      found[#found + 1] = entity
    end
  end
  if #counted_editor_extensions > 0 then
    for _, entity in pairs(surface.find_entities_filtered({ name = counted_editor_extensions })) do
      found[#found + 1] = entity
    end
  end
  return counts_by(found, function(entity) return entity.type end)
end

local function surface_report(surface)
  local active_vehicles = {}
  for _, entity in pairs(surface.find_entities_filtered({ type = VEHICLES })) do
    if entity.active then
      active_vehicles[#active_vehicles + 1] = entity
    end
  end
  return {
    name = surface.name,
    pollution = surface.get_total_pollution(),
    enemy_units = surface.count_entities_filtered({ force = "enemy", type = ENEMY_UNITS }),
    enemy_spawners = surface.count_entities_filtered({ force = "enemy", type = ENEMY_SPAWNERS }),
    enemy_worms = surface.count_entities_filtered({ force = "enemy", type = ENEMY_WORMS }),
    vehicles = counts_by(active_vehicles, function(entity) return entity.name end),
    infinity = infinity_entities(surface),
  }
end

local function report(job, baseline_items, baseline_fluids)
  local items, fluids = flow_totals(job)
  local item_list, fluid_list = {}, {}
  for key, flow in pairs(items) do
    local before = baseline_items[key]
    item_list[#item_list + 1] = {
      name = flow.name,
      quality = flow.quality,
      produced = flow.produced - before.produced,
      consumed = flow.consumed - before.consumed,
    }
  end
  table.sort(item_list, function(left, right)
    if left.name ~= right.name then return left.name < right.name end
    return prototypes.quality[left.quality].level < prototypes.quality[right.quality].level
  end)
  for name, flow in pairs(fluids) do
    local before = baseline_fluids[name]
    fluid_list[#fluid_list + 1] = { name = name, produced = flow.produced - before.produced, consumed = flow.consumed - before.consumed }
  end
  table.sort(fluid_list, function(left, right) return left.name < right.name end)
  local surfaces = {}
  for _, surface in pairs(game.surfaces) do
    surfaces[#surfaces + 1] = surface_report(surface)
  end
  return {
    pollution_enabled = game.map_settings.pollution.enabled,
    expansion_enabled = game.map_settings.enemy_expansion.enabled,
    surfaces = protocol.list(surfaces),
    items = protocol.list(item_list),
    fluids = protocol.list(fluid_list),
  }
end

function sanitize.start(job)
  local baseline_items, baseline_fluids, end_tick
  local function begin(tick)
    check_names(job.items, prototypes.item, "item")
    check_names(job.fluids, prototypes.fluid, "fluid")
    baseline_items, baseline_fluids = flow_totals(job)
    end_tick = tick + job.ticks
  end
  local function finish()
    protocol.send({ type = "sanitize_result", report = report(job, baseline_items, baseline_fluids) })
  end
  script.on_event(defines.events.on_tick, function(event)
    if not end_tick then
      if not protocol.guarded(begin, event.tick) then
        script.finish_test(false)
      end
      return
    end
    if event.tick >= end_tick then
      script.finish_test(protocol.guarded(finish))
    end
  end)
end

return sanitize
