local layout = require("stamp.layout")

test("copies_are_laid_out_in_a_compact_rectangle", function()
  local positions = layout.positions(5, 10, 6, 4, { x = 0, y = 0 })
  assert_equal(positions, {
    { x = -14, y = -4 }, { x = 0, y = -4 }, { x = 14, y = -4 },
    { x = -14, y = 6 }, { x = 0, y = 6 },
  })
end)

test("positions_and_pitch_stay_on_the_rail_grid", function()
  local positions = layout.positions(2, 9, 9, 2, { x = 0.5, y = 0.5 })
  assert_equal(positions, { { x = -6, y = 0 }, { x = 6, y = 0 } })
end)
