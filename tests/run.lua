-- Unit tests for the mod's pure modules. Run from the repository root: lua5.4 tests/run.lua
package.path = "./?.lua;" .. package.path

local tests, failures = {}, 0

function test(name, body)
  tests[#tests + 1] = { name = name, body = body }
end

function assert_equal(actual, expected)
  local function show(value)
    if type(value) ~= "table" then return tostring(value) end
    local parts = {}
    for key, item in pairs(value) do parts[#parts + 1] = tostring(key) .. "=" .. show(item) end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  if show(actual) ~= show(expected) then
    error("expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

dofile("tests/markers_test.lua")
dofile("tests/layout_test.lua")

for _, case in ipairs(tests) do
  local ok, problem = pcall(case.body)
  print((ok and "ok     " or "FAILED ") .. case.name .. (ok and "" or ("\n       " .. tostring(problem))))
  if not ok then failures = failures + 1 end
end
print(string.format("%d tests, %d failed", #tests, failures))
os.exit(failures == 0 and 0 or 1)
