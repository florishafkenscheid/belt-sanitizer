-- Where the copies go: a compact rectangle around a centre. Pure: no game state.
local layout = {}

-- Rails sit on a 2-tile grid, so every position and pitch is a multiple of this.
local GRID = 2

local function to_grid(value)
  return math.floor(value / GRID + 0.5) * GRID
end

local function up_to_grid(value)
  return math.ceil(value / GRID) * GRID
end

--- Build positions for `count` copies of a `width` × `height` blueprint, `margin` tiles apart,
--- in `ceil(sqrt(count))` columns centred on `centre`. Row by row, top left first.
function layout.positions(count, width, height, margin, centre)
  local columns = math.ceil(math.sqrt(count))
  local rows = math.ceil(count / columns)
  local pitch_x = up_to_grid(width + margin)
  local pitch_y = up_to_grid(height + margin)
  local left = to_grid(centre.x - (columns - 1) * pitch_x / 2)
  local top = to_grid(centre.y - (rows - 1) * pitch_y / 2)
  local positions = {}
  for index = 0, count - 1 do
    local column, row = index % columns, math.floor(index / columns)
    positions[#positions + 1] = { x = left + column * pitch_x, y = top + row * pitch_y }
  end
  return positions
end

return layout
