-- Which ore a mining drill gets, from markers in the blueprint. Pure: no game state.
local markers = {}

-- Marker tiles under or next to a drill. Hazard tiles come in -left and -right variants.
markers.TILES = {
  ["stone-path"] = "stone",
  ["concrete"] = "iron-ore",
  ["hazard-concrete-left"] = "coal",
  ["hazard-concrete-right"] = "coal",
  ["refined-concrete"] = "copper-ore",
  ["refined-hazard-concrete-left"] = "scrap",
  ["refined-hazard-concrete-right"] = "scrap",
}

-- Marker modules requested in a drill, by quality.
markers.MODULES = {
  ["efficiency-module"] = { normal = "stone", uncommon = "iron-ore", rare = "copper-ore", epic = "coal", legendary = "uranium-ore" },
  ["efficiency-module-2"] = { normal = "calcite", uncommon = "tungsten-ore", rare = "scrap" },
}

--- The drill's resource and whether it carries a marker at all.
--- `box` is the drill's footprint {left, top, right, bottom} in blueprint coordinates,
--- `tile_at(x, y)` names the blueprint tile at that tile position (or nil), and `modules` lists
--- the drill's module requests as {name, quality}. A marker tile on the footprint or the 1-tile
--- ring around it wins over a module marker.
function markers.resource(box, tile_at, modules)
  local epsilon = 1e-6
  for x = math.floor(box.left) - 1, math.floor(box.right - epsilon) + 1 do
    for y = math.floor(box.top) - 1, math.floor(box.bottom - epsilon) + 1 do
      local resource = markers.TILES[tile_at(x, y) or ""]
      if resource then
        return resource, true
      end
    end
  end
  for _, module in ipairs(modules) do
    local by_quality = markers.MODULES[module.name]
    if by_quality then
      return by_quality[module.quality or "normal"], true
    end
  end
  return nil, false
end

return markers
