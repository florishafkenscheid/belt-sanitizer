-- Entry point. The belt CLI writes job.lua next to this file before every run; the job decides
-- what the mod does. Without a job the mod refuses to load, so it never runs by accident.
local protocol = require("protocol")

local job = protocol.read_job()
protocol.send({ type = "hello", interface = protocol.INTERFACE })

if job.kind == "sanitize" then
  require("sanitize").start(job)
elseif job.kind == "stamp" then
  require("stamp.build").start(job)
else
  error("belt-sanitizer: unknown job kind " .. tostring(job.kind))
end
