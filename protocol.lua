-- The interface with the belt CLI (see README.md). Bump INTERFACE, and the major version in
-- info.json, on any change the CLI can't ignore.
local protocol = {}

protocol.INTERFACE = 2
protocol.PREFIX = "BELT-SANITIZER "

--- Sends one message to the CLI as a single stdout line.
function protocol.send(message)
  print(protocol.PREFIX .. helpers.table_to_json(message))
end

--- Reads job.lua and checks its interface version. Any problem is an error in the main chunk,
--- which makes Factorio exit non-zero with the message: a loud refusal.
function protocol.read_job()
  local found, json = pcall(require, "job")
  if not found then
    error("belt-sanitizer runs only under the belt CLI, which writes its job.lua: " .. tostring(json))
  end
  local job = helpers.json_to_table(json)
  if type(job) ~= "table" then
    error("belt-sanitizer: job.lua does not hold a JSON job")
  end
  if job.interface ~= protocol.INTERFACE then
    error(string.format("belt-sanitizer speaks interface %d, but the job is for interface %s; install matching versions of belt and belt-sanitizer",
      protocol.INTERFACE, tostring(job.interface)))
  end
  return job
end

--- A list for a message: nil when empty, because table_to_json writes an empty table as {}.
function protocol.list(items)
  if #items == 0 then return nil end
  return items
end

--- Runs `step` and turns an error into an error message for the CLI. Returns whether it worked.
function protocol.guarded(step, ...)
  local ok, problem = xpcall(step, debug.traceback, ...)
  if not ok then
    protocol.send({ type = "error", message = tostring(problem) })
  end
  return ok
end

return protocol
