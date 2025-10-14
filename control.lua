local snapshot = require("sanitize.snapshot")
local blueprint = require("blueprint.create")

local function snapshot_on_tick_handler()
	if game.tick == storage.target_tick then
		snapshot.run_once()
	end
end

local save_complete = false

local function blueprint_on_tick_handler()
	if not blueprint.loaded then
		blueprint.create.draw_bp()
		log("Blueprint loaded")
		blueprint.loaded = true
		game.speed = 100
	end
	if blueprint.loaded and not save_complete and game.tick == storage.target_tick then
		game.auto_save(blueprint.save_name)
		log("Game saved at tick: " .. game.tick)
		save_complete = true
	end
end

local function on_first_tick()
	local duration_ticks = settings.startup["belt-sanitizer-target-tick"].value
	log("Target tick: " .. (game.tick + duration_ticks - 1) .. ". First tick: " .. game.tick)
	storage.target_tick = game.tick + duration_ticks - 1

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
	storage.target_tick = nil
end)
