local time_increment = mods.multiverse.time_increment
local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table

local node_child_iter = mods.multiverse.node_child_iter
local node_get_bool_default = mods.multiverse.node_get_bool_default
local node_get_number_default = mods.multiverse.node_get_number_default

local get_room_at_location = mods.oe.get_room_at_location
local xor = mods.oe.xor
local isPointInEllipse = mods.oe.isPointInEllipse
local worldToPlayerLocation = mods.oe.worldToPlayerLocation
local worldToEnemyLocation = mods.oe.worldToEnemyLocation
local get_distance = mods.oe.get_distance
local offset_point_in_direction = mods.oe.offset_point_in_direction
local get_point_local_offset = mods.oe.get_point_local_offset
local get_random_point_in_radius = mods.oe.get_random_point_in_radius
local normalise_angle = mods.oe.normalise_angle
local angle_diff = mods.oe.angle_diff
local get_angle_between_points = mods.oe.get_angle_between_points
local find_closest_slot = mods.oe.find_closest_slot

local function dijkstra(map, source, finish)
	local info = {}
	--print("source:"..tostring(source).." finish:"..tostring(finish))

	for loc in vter(map.locations) do
		local dis = math.huge
		if loc == source then
			dis = 0
		end
		table.insert(info, {beacon = loc, unVisited = true, distance = dis})
	end
	repeat
		local cur = nil
		for i, locTable in ipairs(info) do
			if locTable.unVisited and locTable.distance ~= math.huge and ((not cur) or locTable.distance < cur.distance) then
				cur = locTable
			end
		end
		if cur and tostring(cur.beacon) == tostring(finish) then
			local path = {cur.beacon}
			local last = cur.last
			while last and last.beacon ~= source do
				--print("path:"..tostring(last.beacon))
				table.insert(path, last.beacon)
				last = last.last
			end
			return path
		end
		if cur then
			for loc in vter(cur.beacon.connectedLocations) do
				local locTable = nil
				for i, findTable in ipairs(info) do
					if tostring(findTable.beacon) == tostring(loc) then
						locTable = findTable
					end
				end
				if locTable and locTable.unVisited then
					local dis = cur.distance + 1
					if dis < locTable.distance then
						locTable.distance = dis
						locTable.last = cur
					end
				end
			end
			cur.unVisited = false
		end
	until not cur
	--print("failed")
	return nil
end


local targets_enum = {player = 1, exit = 2, random = 3}
local start_side_enum = {left = 1, right  = 2, center = 3}

local roamer_def_list = {}
local roamer_file = "data/oe_roamers.xml"
do --Parse file
	local doc = RapidXML.xml_document(roamer_file)
	for node in node_child_iter(doc:first_node("FTL") or doc) do
		if node:name() == "roamer" then
			local new_roamer_def = {}
			new_roamer_def.name = node:first_attribute("name"):value()
			--print(new_roamer_def.name)
			if not new_roamer_def.name then
				new_roamer_def.name = "unnamed_roamer"
				log(string.format("roamer has no name, defaulting to unnamed_roamer."))
			end
			new_roamer_def.fleet = node_get_bool_default(node:first_attribute("fleet"), true)
			new_roamer_def.safe = node_get_bool_default(node:first_attribute("safe"), true)
			if not (new_roamer_def.fleet or new_roamer_def.safe) then
				log(string.format("roamer %s cannot be excluded from both the fleet and safe zone, defaulting to safe zone only.", new_roamer_def.name))
				new_roamer_def.safe = true
			end
			if node:first_node("event") then
				new_roamer_def.event = node:first_node("event"):value()
			else
				log(string.format("roamer %s does not have an event set, defaulting to PIRATE.", new_roamer_def.name))
				new_roamer_def.event = "PIRATE"
			end
			new_roamer_def.removeEvents = {}
			for removeEventNode in node_child_iter(node) do
				if removeEventNode:name() == "removeEvent" and removeEventNode:value() then
					new_roamer_def.removeEvents[removeEventNode:value()] = true
				end
			end
			new_roamer_def.sector = {}
			if node:first_node("sector") then
				local sectorNode = node:first_node("sector")
				new_roamer_def.sector.level = node_get_number_default(node:first_attribute("level"), nil)
				if sectorNode:first_node() then
					new_roamer_def.sector.names = {}
					for sectorNameNode in node_child_iter(sectorNode) do
						if sectorNameNode:name() == "name" and sectorNameNode:value() then
							new_roamer_def.sector.names[sectorNameNode:value()] = true
						end
					end
				end
			end
			local map_icon_name = (node:first_node("image") and node:first_node("image"):value()) or "map_icon_boss"
			new_roamer_def.image = Hyperspace.Resources:CreateImagePrimitiveString("map/"..map_icon_name..".png", -32, -32, 0, Graphics.GL_Color(1, 1, 1, 1), 1, false)
			if node:first_node("target") and node:first_node("target"):value() then
				new_roamer_def.target = targets_enum[node:first_node("target"):value()]
			else
				new_roamer_def.target = targets_enum.player
				log(string.format("roamer %s has no target set, defaulting to player.", new_roamer_def.name))
			end
			if node:first_node("jumpCooldown") and node:first_node("jumpCooldown"):value() then
				new_roamer_def.jumpCooldown = node:first_node("jumpCooldown"):value() and tonumber(node:first_node("jumpCooldown"):value()) or 0
			else
				new_roamer_def.jumpCooldown = 0
				log(string.format("roamer %s has no jumpCooldown set, defaulting to 0.", new_roamer_def.name))
			end
			if node:first_node("start") and node:first_node("start"):value() then
				new_roamer_def.start = start_side_enum[node:first_node("start"):value()]
			else
				new_roamer_def.start = start_side_enum.right
				log(string.format("roamer %s has no start set, defaulting to right side.", new_roamer_def.name))
			end
			table.insert(roamer_def_list, new_roamer_def)
		end
	end
end

local map_updated = false
script.on_init(function()
	map_updated = false
end)
script.on_internal_event(Defines.InternalEvents.POST_CREATE_CHOICEBOX, function(choiceBox, event)
	local map = Hyperspace.App.world.starMap
	if event.eventName == map.currentLoc.event.eventName then
		map_updated = false
	end
end)
script.on_game_event("LOAD_ATLAS_MARKER", false, function()
	map_updated = false
end)

local function load_active_roamer(roamer_def)
	--print("load_active_roamer"..tostring(roamer_def.name))
	local new_roamer = {}
	local saved_x = Hyperspace.playerVariables[roamer_def.name.."_saved_x"]
	local saved_y = Hyperspace.playerVariables[roamer_def.name.."_saved_y"]
	local saved_point = Hyperspace.Pointf(saved_x, saved_y)
	local current_closest = nil
	local current_closest_dist = 1000
	for location in vter(Hyperspace.App.world.starMap.locations) do
		if (not current_closest) or get_distance(saved_point, location.loc) < current_closest_dist then
			current_closest = location
			current_closest_dist = get_distance(saved_point, location.loc)
		end
	end
	new_roamer.beacon = current_closest

	new_roamer.current_jump = Hyperspace.playerVariables[roamer_def.name.."_current_jump"]
	new_roamer.rotation = 0
	return new_roamer
end
local function new_active_roamer(roamer_def)
	--print("new_active_roamer"..tostring(roamer_def.name))
	local new_roamer = {}
	if roamer_def.start == start_side_enum.left then
		local current_closest = nil
		for location in vter(Hyperspace.App.world.starMap.locations) do
			local canMoveTo = false
			if roamer_def.fleet and (location.fleetChanging or location.dangerZone) then
				canMoveTo = true
			elseif roamer_def.safe and not (location.fleetChanging or location.dangerZone) then
				canMoveTo = true
			end
			if canMoveTo and ((not current_closest) or location.loc.x < current_closest.loc.x) then
				current_closest = location
			end
		end
		if current_closest then new_roamer.beacon = current_closest end
	elseif roamer_def.start == start_side_enum.right then
		local current_closest = nil
		for location in vter(Hyperspace.App.world.starMap.locations) do
			local canMoveTo = false
			if roamer_def.fleet and (location.fleetChanging or location.dangerZone) then
				canMoveTo = true
			elseif roamer_def.safe and not (location.fleetChanging or location.dangerZone) then
				canMoveTo = true
			end
			if canMoveTo and ((not current_closest) or location.loc.x > current_closest.loc.x) then
				current_closest = location
			end
		end
		if current_closest then new_roamer.beacon = current_closest end
	end
	if not new_roamer.beacon then
		print("could not create active roamer, no beacon")
		return nil
	end
	new_roamer.current_jump = roamer_def.jumpCooldown
	new_roamer.rotation = 0
	return new_roamer
end

local last_sector_name = nil
local active_roamers = {}
local function save_active_roamer(roamer_def)
	--print("save_active_roamer"..tostring(roamer_def.name))
	local roamer = active_roamers[roamer_def.name]
	Hyperspace.playerVariables[roamer_def.name.."_saved_x"] = roamer.beacon.loc.x
	Hyperspace.playerVariables[roamer_def.name.."_saved_y"] = roamer.beacon.loc.y
	Hyperspace.playerVariables[roamer_def.name.."_current_jump"] = roamer.current_jump
end
local function remove_active_roamer(roamer_def)
	--print("remove_active_roamer"..tostring(roamer_def.name))
	active_roamers[roamer_def.name] = nil
	Hyperspace.playerVariables[roamer_def.name.."_active"] = 0
	Hyperspace.playerVariables[roamer_def.name.."_saved_x"] = 0
	Hyperspace.playerVariables[roamer_def.name.."_saved_y"] = 0
	Hyperspace.playerVariables[roamer_def.name.."_current_jump"] = 0
end
script.on_internal_event(Defines.InternalEvents.POST_CREATE_CHOICEBOX, function(choiceBox, event)
	for _, roamer_def in ipairs(roamer_def_list) do
		if roamer_def.removeEvents[event.eventName] and active_roamers[roamer_def.name] then
			Hyperspace.playerVariables[roamer_def.name.."_removed"] = 1
			remove_active_roamer(roamer_def)
		end
	end
end)

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
	local map = Hyperspace.App.world.starMap
	if (not map_updated) and Hyperspace.App.world.bStartedGame and map.currentSector and Hyperspace.playerVariables.oe_test_variable > 0 then
		--print("map_update")
		map_updated = true

		if map.currentSector.description.type ~= last_sector_name then
			active_roamers = {}
		end
		last_sector_name = map.currentSector.description.type

		for _, roamer_def in ipairs(roamer_def_list) do
			local should_be_active = true
			if roamer_def.sector then
				if roamer_def.sector.level and Hyperspace.playerVariables.loc_sector_count ~= roamer_def.sector.level then
					should_be_active = false
				end
				if roamer_def.sector.names and (not roamer_def.sector.names[map.currentSector.description.type]) then
					should_be_active = false
				end
			end
			if Hyperspace.playerVariables[roamer_def.name.."_removed"] == 1 then
				should_be_active = false
			end

			if (not active_roamers[roamer_def.name]) and should_be_active then
				local new_roamer = {}
				if Hyperspace.playerVariables[roamer_def.name.."_active"] == 1 then
					new_roamer = load_active_roamer(roamer_def)
				else
					new_roamer = new_active_roamer(roamer_def)
				end
				if new_roamer then
					active_roamers[roamer_def.name] = new_roamer
					Hyperspace.playerVariables[roamer_def.name.."_active"] = 1
				end
			elseif active_roamers[roamer_def.name] and (not should_be_active) then
				remove_active_roamer(roamer_def)
			end

			if active_roamers[roamer_def.name] then
				--update
				local roamer = active_roamers[roamer_def.name]

				save_active_roamer(roamer_def)
			end
		end
	end
end)

local last_potential_loc = nil
local last_original_event = nil
script.on_internal_event(Defines.InternalEvents.JUMP_LEAVE, function(shipManager)
	local map = Hyperspace.App.world.starMap
	if shipManager.iShipId == 0 then
		for _, roamer_def in ipairs(roamer_def_list) do
			if active_roamers[roamer_def.name] then 
				--print("attempt_move_active_roamer"..tostring(roamer_def.name))
				local roamer = active_roamers[roamer_def.name]
				if tostring(roamer.beacon) == tostring(map.currentLoc) then
					if last_original_event then
						roamer.beacon.event = Hyperspace.Event:CreateEvent(last_original_event, Hyperspace.playerVariables.loc_sector_count, true)
						last_original_event = nil
					end
					roamer.beacon = roamer.beacon.connectedLocations[0]
					roamer.current_jump = roamer_def.jumpCooldown
				elseif roamer.current_jump <= 0 then
					local target = map.currentLoc
					if roamer_def.target == targets_enum.player and last_potential_loc then
						target = last_potential_loc
					elseif roamer_def.target == targets_enum.exit then
						--Need exposure
					elseif roamer_def.target == targets_enum.random then
						target = map.locations[math.random(0, map.locations:size() - 1)]
					end

					local nextTable = dijkstra(map, roamer.beacon, target)
					if nextTable then
						local next = table.remove(nextTable)
						local canMoveTo = false
						if roamer_def.fleet and (next.fleetChanging or next.dangerZone) then
							canMoveTo = true
						elseif roamer_def.safe and not (next.fleetChanging or next.dangerZone) then
							canMoveTo = true
						end
						if canMoveTo and tostring(next) == tostring(last_potential_loc) then
							last_original_event = next.event.eventName
							next.event = Hyperspace.Event:CreateEvent(roamer_def.event, Hyperspace.playerVariables.loc_sector_count, true)
							next.visited = 0
							roamer.beacon = next
							roamer.current_jump = roamer_def.jumpCooldown
						elseif canMoveTo then
							roamer.beacon = next
							roamer.current_jump = roamer_def.jumpCooldown
						end
					end
				else
					roamer.current_jump = roamer.current_jump - 1
				end

				save_active_roamer(roamer_def)
			end
		end
	end
end)
--local update_timer = {current = 0, goal = 0.1}
script.on_render_event(Defines.RenderEvents.GUI_CONTAINER, function() end, function()
	local map = Hyperspace.App.world.starMap
	if map.bOpen and (not map.bChoosingNewSector) and map.potentialLoc then
		last_potential_loc = map.potentialLoc
	end
	if map.bOpen and (not map.bChoosingNewSector) then
		for _, roamer_def in ipairs(roamer_def_list) do
			if active_roamers[roamer_def.name] then 
				local roamer = active_roamers[roamer_def.name]
				local projected_next = nil
				if tostring(roamer.beacon) == tostring(map.currentLoc) then
					if last_original_event then
						roamer.beacon.event = Hyperspace.Event:CreateEvent(last_original_event, Hyperspace.playerVariables.loc_sector_count, true)
						last_original_event = nil
					end
					projected_next = roamer.beacon.connectedLocations[0]
				elseif roamer.current_jump <= 0 then
					local target = map.currentLoc
					if roamer_def.target == targets_enum.player and map.potentialLoc then
						target = map.potentialLoc
					elseif roamer_def.target == targets_enum.exit then
						--Need exposure
					elseif roamer_def.target == targets_enum.random then
						target = map.locations[math.random(0, map.locations:size() - 1)]
					end

					local nextTable = dijkstra(map, roamer.beacon, target)
					if nextTable then
						local next = table.remove(nextTable)
						local canMoveTo = false
						if roamer_def.fleet and (next.fleetChanging or next.dangerZone) then
							canMoveTo = true
						elseif roamer_def.safe and not (next.fleetChanging or next.dangerZone) then
							canMoveTo = true
						end
						if canMoveTo then
							projected_next = next
						end
					end
				end

				if projected_next then
					local this_loc = roamer.beacon.loc
					local next_loc = projected_next.loc
					roamer.rotation = roamer.rotation + time_increment(false) * 15
					local distance = get_distance(this_loc, next_loc)
					if roamer.rotation > 30 then roamer.rotation = roamer.rotation - 30 end

					local point = get_point_local_offset(this_loc, next_loc, roamer.rotation + 10, 0)

					local alpha = math.atan((this_loc.y-next_loc.y), (this_loc.x-next_loc.x))

					local pointAngle = math.deg(alpha) - 90

					local fade = math.min(1, (30 - roamer.rotation)/10, roamer.rotation)

					Graphics.CSurface.GL_DrawLine(this_loc.x + 385, this_loc.y + 123, next_loc.x + 385, next_loc.y + 123, 9, Graphics.GL_Color(0.88, 0.4, 0.4, 0.5))

					Graphics.CSurface.GL_PushMatrix()
					Graphics.CSurface.GL_Translate(point.x + 385,point.y + 123,0)
					Graphics.CSurface.GL_Rotate(pointAngle, 0, 0, 1)
					Graphics.CSurface.GL_RenderPrimitiveWithAlpha(roamer_def.image, fade)
					Graphics.CSurface.GL_PopMatrix()
				else
					roamer.rotation = roamer.rotation + time_increment(false) * 18
					if roamer.rotation > 360 then roamer.rotation = roamer.rotation - 360 end
					Graphics.CSurface.GL_PushMatrix()
					Graphics.CSurface.GL_Translate(roamer.beacon.loc.x + 385, roamer.beacon.loc.y + 123, 0)
					Graphics.CSurface.GL_Rotate(360-roamer.rotation, 0, 0, 1)
					Graphics.CSurface.GL_Translate(22, 0, 0)
					Graphics.CSurface.GL_RenderPrimitive(roamer_def.image)
					Graphics.CSurface.GL_PopMatrix()
				end
			end
		end
		--[[update_timer.current = update_timer.current + time_increment(false)
		if update_timer.current >= update_timer.goal then
			update_timer.current = 0
		end]]
	end
end)