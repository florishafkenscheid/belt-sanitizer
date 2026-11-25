local markers = require("stamp.markers")

-- A 3×3 drill centred on (0.5, 0.5) covers tiles -1..1; the ring around it is -2..2.
local DRILL = { left = -1, top = -1, right = 2, bottom = 2 }

local function tiles(map)
  return function(x, y) return map[x .. "," .. y] end
end

local NO_TILES = tiles({})

test("a_marker_tile_under_the_drill_picks_its_resource", function()
  assert_equal({ markers.resource(DRILL, tiles({ ["0,0"] = "concrete" }), {}) }, { "iron-ore", true })
end)

test("a_marker_tile_next_to_the_drill_picks_its_resource", function()
  assert_equal({ markers.resource(DRILL, tiles({ ["2,-2"] = "hazard-concrete-right" }), {}) }, { "coal", true })
end)

test("a_tile_two_tiles_away_is_not_a_marker", function()
  assert_equal({ markers.resource(DRILL, tiles({ ["3,0"] = "stone-path" }), {}) }, { nil, false })
end)

test("a_marker_module_picks_the_resource_for_its_quality", function()
  local modules = { { name = "efficiency-module", quality = "epic" } }
  assert_equal({ markers.resource(DRILL, NO_TILES, modules) }, { "coal", true })
end)

test("an_efficiency_module_2_marker_picks_a_space_age_resource", function()
  local modules = { { name = "efficiency-module-2", quality = "uncommon" } }
  assert_equal({ markers.resource(DRILL, NO_TILES, modules) }, { "tungsten-ore", true })
end)

test("a_tile_marker_beats_a_module_marker", function()
  local modules = { { name = "efficiency-module", quality = "legendary" } }
  assert_equal({ markers.resource(DRILL, tiles({ ["1,1"] = "refined-concrete" }), modules) }, { "copper-ore", true })
end)

test("other_modules_are_not_markers", function()
  local modules = { { name = "speed-module-3", quality = "legendary" } }
  assert_equal({ markers.resource(DRILL, NO_TILES, modules) }, { nil, false })
end)
