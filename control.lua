local snapshot = require("sanitize.snapshot")
local blueprint = require("blueprint.blueprint")

local function snapshot_on_tick_handler()
	if game.tick == storage.benchmark_target_tick then
		snapshot.run_once()
	end
end

local save_complete = false

local function blueprint_on_tick_handler()
	-- BP Needs: bp string, save_name?, amount of copies, bp.loaded
	if not game.is_multiplayer() then
		return
	end
	if not blueprint.loaded then
		blueprint.create.draw_bp()
		blueprint.loaded = true
	end
	if blueprint.loaded and not save_complete then
		game.server_save(blueprint.save_name)
		save_complete = true
	end
end

local function on_first_tick()
	-- Decide mode from startup setting
	local blueprint_mode = settings.startup["belt-sanitizer-blueprint-mode"]
			and settings.startup["belt-sanitizer-blueprint-mode"].value
		or false

	-- Clear any existing on_tick handlers, then set the correct one
	script.on_event(defines.events.on_tick, nil)

	if blueprint_mode then
		-- Install blueprint-mode tick handler and return
		script.on_event(defines.events.on_tick, blueprint_on_tick_handler)
		return
	end

	-- Snapshot mode: compute target tick and install snapshot handler
	local duration_ticks = settings.startup["belt-sanitizer-production-check-tick"].value
	log("Target tick: " .. (game.tick + duration_ticks - 1) .. ". First tick: " .. game.tick)
	storage.benchmark_target_tick = game.tick + duration_ticks - 1
	script.on_event(defines.events.on_tick, snapshot_on_tick_handler)
end

-- General initialization
script.on_init(function()
	script.on_event(defines.events.on_tick, on_first_tick)
end)

script.on_load(function()
	script.on_event(defines.events.on_tick, on_first_tick)
end)

script.on_configuration_changed(function(_)
	storage.benchmark_target_tick = nil
end)
