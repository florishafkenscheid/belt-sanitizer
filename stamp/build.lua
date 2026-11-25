-- The stamp job: build job.count copies of one blueprint near spawn, fully (not as ghosts), let
-- the game run job.buffer_ticks, then report. The CLI saves the map once the report arrives.
--
-- Blueprint coordinates are absolute, so each copy is first built as a probe on a private lab
-- surface (no events, nothing on the player's map) to learn where it lands. Mining drills need
-- ore to be placed, so in the probe each drill is swapped for 1×1 anchors on its corner tiles,
-- which keeps the blueprint's bounding box and so its placement. The copy's area on the real
-- surface is then cleared, the real build follows, and the drills get their ore.
local util = require("util")
local protocol = require("protocol")
local markers = require("stamp.markers")
local layout = require("stamp.layout")

local build = {}

local ORE_AMOUNT = 1000000000
local PROBE_SURFACE = "belt-sanitizer-probe"
local ANCHOR = "wooden-chest"
local FAST_SPEED = 1000
local REVIVE_PASSES = 10

local function surface_of_spawn()
  return game.surfaces["nauvis"] or game.surfaces[1]
end

local function footprint(entity)
  local box = prototypes.entity[entity.name].collision_box
  -- Drills and most stamped entities are square; for others the larger extent covers both
  -- orientations, which only widens the area that gets cleared.
  local reach = math.max(-box.left_top.x, -box.left_top.y, box.right_bottom.x, box.right_bottom.y)
  return {
    left = entity.position.x - reach,
    top = entity.position.y - reach,
    right = entity.position.x + reach,
    bottom = entity.position.y + reach,
  }
end

local function bounds(entities, tiles)
  local area = { left = math.huge, top = math.huge, right = -math.huge, bottom = -math.huge }
  local function grow(box)
    area.left = math.min(area.left, box.left)
    area.top = math.min(area.top, box.top)
    area.right = math.max(area.right, box.right)
    area.bottom = math.max(area.bottom, box.bottom)
  end
  for _, entity in pairs(entities) do grow(footprint(entity)) end
  for _, tile in pairs(tiles) do
    grow({ left = tile.position.x, top = tile.position.y, right = tile.position.x + 1, bottom = tile.position.y + 1 })
  end
  return area
end

-- Copies must not share roboport networks or power poles, so they sit this far apart.
local function margin(entities)
  local widest = 0
  local seen = {}
  for _, entity in pairs(entities) do
    if not seen[entity.name] then
      seen[entity.name] = true
      local prototype = prototypes.entity[entity.name]
      if prototype.type == "roboport" then
        widest = math.max(widest, 2 * prototype.logistic_radius)
      elseif prototype.type == "electric-pole" then
        widest = math.max(widest, prototype.get_max_wire_distance() or 0)
      end
    end
  end
  return math.ceil(widest) + 1
end

local function is_module(name)
  local item = prototypes.item[name]
  return item ~= nil and item.type == "module"
end

-- Applies the marker rules to the blueprint's drills: picks each drill's resource (nil: built
-- without ore) and replaces the module requests of every marked drill.
local function apply_markers(entities, tiles, job)
  local tile_names = {}
  for _, tile in pairs(tiles) do
    tile_names[tile.position.x .. "," .. tile.position.y] = tile.name
  end
  local function tile_at(x, y) return tile_names[x .. "," .. y] end
  local drills, missing, unmarked = {}, {}, 0
  for _, entity in pairs(entities) do
    if prototypes.entity[entity.name].type == "mining-drill" then
      local modules = {}
      for _, request in pairs(entity.items or {}) do
        if is_module(request.id.name) then
          modules[#modules + 1] = { name = request.id.name, quality = request.id.quality }
        end
      end
      local resource, marked = markers.resource(footprint(entity), tile_at, modules)
      if marked then
        for _, request in pairs(entity.items or {}) do
          if is_module(request.id.name) then
            request.id = { name = job.module_replacement.name, quality = job.module_replacement.quality }
          end
        end
      end
      if not resource then
        unmarked = unmarked + 1
      elseif not prototypes.entity[resource] then
        missing[resource] = true
        resource = nil
      end
      drills[#drills + 1] = { name = entity.name, position = entity.position, resource = resource }
    end
  end
  local missing_list = {}
  for resource in pairs(missing) do missing_list[#missing_list + 1] = resource end
  table.sort(missing_list)
  return drills, missing_list, unmarked
end

-- The blueprint the probe builds: drills replaced by anchors on their corner tiles, no wires.
local function probe_entities(entities)
  local probe = {}
  for _, entity in pairs(entities) do
    if prototypes.entity[entity.name].type == "mining-drill" then
      local box = footprint(entity)
      local left, top = math.floor(box.left), math.floor(box.top)
      local right, bottom = math.ceil(box.right) - 1, math.ceil(box.bottom) - 1
      for _, corner in pairs({ { left, top }, { right, top }, { left, bottom }, { right, bottom } }) do
        probe[#probe + 1] = { entity_number = #probe + 1, name = ANCHOR, position = { x = corner[1] + 0.5, y = corner[2] + 0.5 } }
      end
    else
      local copy = util.table.deepcopy(entity)
      copy.entity_number = #probe + 1
      copy.wires = nil
      copy.items = nil
      probe[#probe + 1] = copy
    end
  end
  return probe
end

local function probe_surface()
  local surface = game.surfaces[PROBE_SURFACE] or game.create_surface(PROBE_SURFACE)
  surface.generate_with_lab_tiles = true
  return surface
end

-- Where one copy lands: the most common shift between same-named probe ghosts and blueprint
-- entities, taken over the rarest name so the comparison stays small.
local function offset_of(probe, entities)
  local by_name = {}
  for _, entity in pairs(entities) do
    by_name[entity.name] = by_name[entity.name] or {}
    table.insert(by_name[entity.name], entity.position)
  end
  local ghosts_by_name = {}
  for _, ghost in pairs(probe) do
    if ghost.valid and ghost.type == "entity-ghost" then
      ghosts_by_name[ghost.ghost_name] = ghosts_by_name[ghost.ghost_name] or {}
      table.insert(ghosts_by_name[ghost.ghost_name], ghost.position)
    end
  end
  local rarest
  for name, ghosts in pairs(ghosts_by_name) do
    if by_name[name] and (not rarest or #by_name[name] * #ghosts < #by_name[rarest] * #ghosts_by_name[rarest]) then
      rarest = name
    end
  end
  if not rarest then return nil end
  local votes, best, best_votes = {}, nil, 0
  for _, ghost in pairs(ghosts_by_name[rarest]) do
    for _, position in pairs(by_name[rarest]) do
      local dx, dy = ghost.x - position.x, ghost.y - position.y
      local key = dx .. "," .. dy
      votes[key] = (votes[key] or 0) + 1
      if votes[key] > best_votes then
        best, best_votes = { x = dx, y = dy }, votes[key]
      end
    end
  end
  return best
end

local function shifted(area, offset, grow)
  return {
    { area.left + offset.x - grow, area.top + offset.y - grow },
    { area.right + offset.x + grow, area.bottom + offset.y + grow },
  }
end

local function clear(surface, area)
  for _, entity in pairs(surface.find_entities_filtered({ area = area })) do
    if entity.valid and entity.type ~= "character" then
      entity.destroy()
    end
  end
  local landfill = {}
  for x = math.floor(area[1][1]), math.ceil(area[2][1]) - 1 do
    for y = math.floor(area[1][2]), math.ceil(area[2][2]) - 1 do
      if surface.get_tile(x, y).collides_with("water_tile") then
        landfill[#landfill + 1] = { name = "landfill", position = { x, y } }
      end
    end
  end
  surface.set_tiles(landfill)
end

-- A blueprint only places a drill over ore it can mine without fluid, so every drill first
-- stands on this placeholder; the real ore (or none) replaces it after building.
local placeholders = {}
local function placeholder_for(drill_name)
  if placeholders[drill_name] then return placeholders[drill_name] end
  local categories = prototypes.entity[drill_name].resource_categories or {}
  local names = {}
  for name, prototype in pairs(prototypes.entity) do
    if prototype.type == "resource" and categories[prototype.resource_category] and not prototype.infinite_resource
      and not (prototype.mineable_properties and prototype.mineable_properties.required_fluid) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  if not names[1] then
    error("no resource lets " .. drill_name .. " be placed")
  end
  placeholders[drill_name] = names[1]
  return names[1]
end

local function tiles_under(centre, half)
  local tiles = {}
  for x = math.floor(centre.x - half), math.ceil(centre.x + half) - 1 do
    for y = math.floor(centre.y - half), math.ceil(centre.y + half) - 1 do
      tiles[#tiles + 1] = { x + 0.5, y + 0.5 }
    end
  end
  return tiles
end

local function world(position, offset)
  return { x = position.x + offset.x, y = position.y + offset.y }
end

local function place_placeholders(surface, drills, offset)
  local placed = {}
  for _, drill in pairs(drills) do
    local box = prototypes.entity[drill.name].collision_box
    local half = math.max(box.right_bottom.x, box.right_bottom.y)
    for _, tile in pairs(tiles_under(world(drill.position, offset), half)) do
      placed[#placed + 1] = surface.create_entity({ name = placeholder_for(drill.name), position = tile, amount = 1 })
    end
  end
  return placed
end

-- Gives every marked drill its ore on its whole mining area. Natural ore there (outside the
-- cleared rectangle) is replaced, so a drill mines only its marker's resource; where two drills'
-- areas overlap, the first drill's ore stays.
local function place_ore(surface, drills, offset)
  local ours = {}
  for _, drill in pairs(drills) do
    if drill.resource then
      local radius = prototypes.entity[drill.name].mining_drill_radius
      for _, tile in pairs(tiles_under(world(drill.position, offset), radius)) do
        local key = tile[1] .. "," .. tile[2]
        if not ours[key] then
          for _, natural in pairs(surface.find_entities_filtered({ position = tile, type = "resource" })) do
            natural.destroy()
          end
          surface.create_entity({ name = drill.resource, position = tile, amount = ORE_AMOUNT })
          ours[key] = true
        end
      end
    end
  end
  -- A drill only looks for ore when built; this makes every drill see its ore (or its lack).
  for _, drill in pairs(drills) do
    for _, built in pairs(surface.find_entities_filtered({ position = world(drill.position, offset), name = drill.name })) do
      built.update_connections()
    end
  end
end

-- Puts the requested items (modules, fuel, …) straight into the entity, as robots would.
local function fulfil(entity, proxy)
  for _, plan in pairs(proxy.insert_plan) do
    for _, position in pairs(plan.items.in_inventory or {}) do
      local inventory = entity.get_inventory(position.inventory)
      if inventory then
        inventory[position.stack + 1].set_stack({ name = plan.id.name, quality = plan.id.quality, count = position.count or 1 })
      end
    end
  end
  proxy.destroy()
end

local function revive_all(ghosts)
  local pending = ghosts
  for _ = 1, REVIVE_PASSES do
    local still = {}
    for _, ghost in pairs(pending) do
      if ghost.valid then
        local _, entity, proxy = ghost.revive({ raise_revive = true })
        if entity and proxy and proxy.valid then
          fulfil(entity, proxy)
        elseif not entity and ghost.valid then
          still[#still + 1] = ghost
        end
      end
    end
    if #still == 0 or #still == #pending then return end
    pending = still
  end
end

local function unplaced(surface, entities, offset)
  local missing = {}
  for _, entity in pairs(entities) do
    local position = { entity.position.x + offset.x, entity.position.y + offset.y }
    if surface.count_entities_filtered({ position = position, name = entity.name }) == 0 then
      local reason
      if surface.count_entities_filtered({ position = position, ghost_name = entity.name }) > 0 then
        reason = "its ghost could not be revived"
      else
        local box = footprint({ name = entity.name, position = { x = position[1], y = position[2] } })
        local blockers = {}
        for _, blocker in pairs(surface.find_entities_filtered({ area = { { box.left, box.top }, { box.right, box.bottom } } })) do
          blockers[#blockers + 1] = blocker.name
        end
        local tile = surface.get_tile(position[1], position[2]).name
        reason = #blockers > 0 and ("blocked by " .. table.concat(blockers, ", ")) or ("not placed on tile " .. tile)
      end
      missing[#missing + 1] = { name = entity.name, x = position[1], y = position[2], reason = reason }
    end
  end
  return missing
end

local function add_robots(surface, area, count)
  local roboports = surface.find_entities_filtered({ area = area, type = "roboport" })
  if #roboports == 0 then
    return "has no roboport for its " .. count .. " robots"
  end
  local networks = {}
  for _, roboport in pairs(roboports) do
    local network = roboport.logistic_network
    local id = network and network.network_id or ("roboport " .. roboport.unit_number)
    networks[id] = networks[id] or {}
    table.insert(networks[id], roboport)
  end
  for id, members in pairs(networks) do
    local remaining = count
    for _, roboport in pairs(members) do
      if remaining > 0 then
        remaining = remaining - roboport.get_inventory(defines.inventory.roboport_robot).insert({ name = "logistic-robot", count = remaining })
      end
    end
    if remaining > 0 then
      return string.format("network %s has room for only %d of %d robots", tostring(id), count - remaining, count)
    end
  end
  return nil
end

local function check_replacement(job)
  local module = job.module_replacement
  if not prototypes.item[module.name] then
    error(string.format("%s: the replacement module %s doesn't exist in this save", job.name, module.name))
  end
  if not prototypes.quality[module.quality] then
    error(string.format("%s: the replacement quality %s doesn't exist in this save (is the quality mod enabled?)", job.name, module.quality))
  end
end

local function stamp(job)
  check_replacement(job)
  local inventory = game.create_inventory(2)
  local stack = inventory[1]
  local imported = stack.import_stack(job.blueprint)
  if imported ~= 0 or not stack.is_blueprint then
    inventory.destroy()
    error(job.name .. ": the blueprint string could not be imported cleanly (does it use prototypes this save lacks?)")
  end
  local entities = stack.get_blueprint_entities() or {}
  local tiles = stack.get_blueprint_tiles() or {}
  if #entities == 0 then
    inventory.destroy()
    error(job.name .. ": the blueprint has no entities")
  end
  local drills, missing_resources, unmarked = apply_markers(entities, tiles, job)
  stack.set_blueprint_entities(entities)
  local area = bounds(entities, tiles)
  local surface = surface_of_spawn()
  local spawn = game.forces.player.get_spawn_position(surface)
  local positions = layout.positions(job.count, area.right - area.left, area.bottom - area.top, margin(entities), spawn)

  local copies = {}
  for _, position in pairs(positions) do
    surface.request_to_generate_chunks(position, math.ceil(math.max(area.right - area.left, area.bottom - area.top) / 64) + 1)
  end
  surface.force_generate_chunk_requests()
  local probe_stack = inventory[2]
  local probe_list = probe_entities(entities)
  probe_stack.set_stack({ name = "blueprint" })
  probe_stack.set_blueprint_entities(probe_list)
  probe_stack.set_blueprint_tiles(tiles)
  local lab = probe_surface()
  for index, position in pairs(positions) do
    lab.request_to_generate_chunks(position, math.ceil(math.max(area.right - area.left, area.bottom - area.top) / 64) + 1)
    lab.force_generate_chunk_requests()
    local probe = probe_stack.build_blueprint({ surface = lab, force = "player", position = position, build_mode = defines.build_mode.forced })
    local offset = offset_of(probe, probe_list)
    for _, ghost in pairs(probe) do
      if ghost.valid then ghost.destroy() end
    end
    if not offset then
      inventory.destroy()
      error(string.format("%s: copy %d could not be placed even on an empty lab surface", job.name, index))
    end
    copies[index] = { offset = offset, area = shifted(area, offset, 1) }
  end
  game.delete_surface(lab)
  -- Characters (players' bodies) are moved clear of the whole stamped rectangle first.
  local whole = { { math.huge, math.huge }, { -math.huge, -math.huge } }
  for _, copy in pairs(copies) do
    whole[1][1] = math.min(whole[1][1], copy.area[1][1])
    whole[1][2] = math.min(whole[1][2], copy.area[1][2])
    whole[2][1] = math.max(whole[2][1], copy.area[2][1])
    whole[2][2] = math.max(whole[2][2], copy.area[2][2])
  end
  for _, character in pairs(surface.find_entities_filtered({ area = whole, type = "character" })) do
    local outside = { whole[2][1] + 10, (whole[1][2] + whole[2][2]) / 2 }
    local clear_spot = surface.find_non_colliding_position("character", outside, 100, 1)
    if not clear_spot then
      error(job.name .. ": no free spot to move a character out of the way")
    end
    character.teleport(clear_spot)
  end
  local all_unplaced = {}
  local placed = 0
  for index, copy in ipairs(copies) do
    clear(surface, copy.area)
    local placeholder_ore = place_placeholders(surface, drills, copy.offset)
    local ghosts = stack.build_blueprint({
      surface = surface,
      force = "player",
      position = positions[index],
      build_mode = defines.build_mode.forced,
      raise_built = true,
    })
    revive_all(ghosts)
    for _, ore in pairs(placeholder_ore) do
      if ore.valid then ore.destroy() end
    end
    place_ore(surface, drills, copy.offset)
    local missing = unplaced(surface, entities, copy.offset)
    placed = placed + #entities - #missing
    for _, entity in pairs(missing) do all_unplaced[#all_unplaced + 1] = entity end
  end
  inventory.destroy()
  return {
    copies = copies,
    report = {
      expected = #entities * job.count,
      placed = placed,
      stamped_tick = game.tick,
      unmarked_drills = unmarked,
      missing_resources = protocol.list(missing_resources),
      unplaced = protocol.list(all_unplaced),
    },
  }
end

function build.start(job)
  local stamped, finish_tick, original_speed
  local function robots()
    for index, copy in pairs(stamped.copies) do
      local problem = add_robots(surface_of_spawn(), copy.area, job.bot_count)
      if problem then
        protocol.send({ type = "warning", text = string.format("%s: copy %d %s", job.name, index, problem) })
      end
    end
  end
  local function report()
    protocol.send({ type = "stamp_result", report = stamped.report })
  end
  script.on_event(defines.events.on_tick, function(event)
    if finish_tick == nil and stamped == nil then
      local ok = protocol.guarded(function() stamped = stamp(job) end)
      if not ok then
        finish_tick = -1
        return
      end
      if job.bot_count > 0 then
        -- Logistic networks form on the tick after building.
        return
      end
    end
    if finish_tick == nil then
      if job.bot_count > 0 and not protocol.guarded(robots) then
        finish_tick = -1
        return
      end
      original_speed = game.speed
      game.speed = FAST_SPEED
      finish_tick = event.tick + job.buffer_ticks
    end
    if finish_tick >= 0 and event.tick >= finish_tick then
      game.speed = original_speed
      finish_tick = -1
      protocol.guarded(report)
    end
  end)
end

return build
