local time_increment = mods.multiverse.time_increment
local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table
local node_child_iter = mods.multiverse.node_child_iter

local get_room_at_location = mods.oe.get_room_at_location
local xor = mods.oe.xor
local isPointInEllipse = mods.oe.isPointInEllipse
local worldToPlayerLocation = mods.oe.worldToPlayerLocation
local worldToEnemyLocation = mods.oe.worldToEnemyLocation
local get_distance = mods.oe.get_distance
local offset_point_in_direction = mods.oe.offset_point_in_direction
local get_random_point_in_radius = mods.oe.get_random_point_in_radius
local normalise_angle = mods.oe.normalise_angle
local angle_diff = mods.oe.angle_diff
local get_angle_between_points = mods.oe.get_angle_between_points
local find_closest_slot = mods.oe.find_closest_slot

local function setArtySlot(blueprintName, slot)
	if Hyperspace.ships.player.artillerySystems[slot].projectileFactory.blueprint.name == blueprintName then return end
	local shipManager = Hyperspace.ships.player
	local weapons = {}
	for weapon in vter(shipManager.weaponSystem.weapons) do
		table.insert(weapons, weapon.blueprint.name)
	end
	for _, name in ipairs(weapons) do
		shipManager.weaponSystem:RemoveWeapon(0)
	end
	local commandGui = Hyperspace.App.gui
	local equipment = commandGui.equipScreen
	local artyBlueprint = Hyperspace.Blueprints:GetWeaponBlueprint(blueprintName)
	equipment:AddWeapon(artyBlueprint, true, false)
	local artilleryWeapon = shipManager.weaponSystem.weapons[0]
	artilleryWeapon.iAmmo = 99
	shipManager.artillerySystems[slot].projectileFactory = artilleryWeapon
	shipManager.weaponSystem:RemoveWeapon(0)
	for _, name in ipairs(weapons) do
		local blueprint = Hyperspace.Blueprints:GetWeaponBlueprint(name)
		equipment:AddWeapon(blueprint, true, false)
	end
end

local type_list = {[1] = "LASER", [2] = "BEAM", [3] = "MISSILE", [4] = "ION"}
local broadside_weapons = {
	LASER = {[1] = "ARTILLERY_OE_BROADSIDE_PIERCE", [2] = "ARTILLERY_OE_BROADSIDE2_LASER"},
	BEAM = {[1] = "ARTILLERY_OE_BROADSIDE_FOCUS", [2] = "ARTILLERY_OE_BROADSIDE2_BEAM"},
	MISSILE = {[1] = "ARTILLERY_OE_BROADSIDE_MISSILE", [2] = "ARTILLERY_OE_BROADSIDE2_MISSILE"},
	ION = {[1] = "ARTILLERY_OE_BROADSIDE_MINE", [2] = "ARTILLERY_OE_BROADSIDE2_ION"},
}

do
	local event_list = {[1] = "OE_BROADSIDE_CHOOSE_", [2] = "OE_BROADSIDE2_CHOOSE_"}
	for ship = 1, 2 do
		event_name_ship = event_list[ship]
		for type = 1, 4 do
			local type_name = type_list[type]
			for slot = 1, 3 do
				local eventName = event_name_ship..type_name.."_"..math.floor(slot)
				--print("event:"..eventName.." weapon:"..broadside_weapons[type_name][ship].." slot:"..slot - 1)
				script.on_game_event(eventName, false, function()
					--print("triggered event:"..eventName.." weapon:"..broadside_weapons[type_name][ship].." slot:"..slot - 1)
					setArtySlot(broadside_weapons[type_name][ship], slot - 1)
				end)
			end
		end
	end
end

local allWeapons = {}
for _, file in ipairs(mods.multiverse.blueprintFiles) do
	local doc = RapidXML.xml_document(file)
	for node in node_child_iter(doc:first_node("FTL") or doc) do
		if node:name() == "weaponBlueprint" then
			table.insert(allWeapons, node:first_attribute("name"):value())
		end
	end
	doc:clear()
end
local function setArtySlotFromWeapon(slot)
	local shipManager = Hyperspace.ships.player
	local commandGui = Hyperspace.App.gui
	local equipment = commandGui.equipScreen
	local weaponName = shipManager.weaponSystem.weapons[0].blueprint.name
	for i, name in ipairs(allWeapons) do
		if name == weaponName then
			Hyperspace.playerVariables["oe_broadside_c_slot"..math.floor(slot+1)] = i
			break
		else
			Hyperspace.playerVariables["oe_broadside_c_slot"..math.floor(slot+1)] = 0
		end
	end
	if Hyperspace.playerVariables["oe_broadside_c_slot"..math.floor(slot+1)] == 0 then
		print("COULD NOT SAVE WEAPON: "..weaponName..", WILL NOT BE RETURNED AFTER A SAVE AND QUIT")
	end
	local artilleryWeapon = shipManager.weaponSystem.weapons[0]
	artilleryWeapon.iAmmo = 99
	shipManager.artillerySystems[slot].projectileFactory = artilleryWeapon
	shipManager.weaponSystem:RemoveWeapon(0)
end

do
	script.on_game_event("AEA_BROADSIDE_C_SLOT1", false, function()
		setArtySlotFromWeapon(0)
	end)
	script.on_game_event("AEA_BROADSIDE_C_SLOT2", false, function()
		setArtySlotFromWeapon(1)
	end)
	script.on_game_event("AEA_BROADSIDE_C_SLOT3", false, function()
		setArtySlotFromWeapon(2)
	end)
end

local needSetArty = false
--Run on game load
script.on_init(function()
	needSetArty = true
end)

local var_name = "oe_broadside_slot%d"
script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
	if Hyperspace.ships.player and needSetArty and shipManager:HasAugmentation("SHIP_OE_BROADSIDE") > 0 and Hyperspace.playerVariables.oe_test_variable > 0 then
		needSetArty = false
		for slot = 1, 3 do
			local type_name = type_list[Hyperspace.playerVariables[string.format(var_name, slot)]]
			if type_name then
				--print("load weapon:"..broadside_weapons[type_name][1].." slot:"..slot - 1)
				setArtySlot(broadside_weapons[type_name][1], slot - 1)
			end
		end
	elseif Hyperspace.ships.player and needSetArty and shipManager:HasAugmentation("SHIP_OE_BROADSIDE2") > 0 and Hyperspace.playerVariables.oe_test_variable > 0 then
		needSetArty = false
		for slot = 1, 3 do
			local type_name = type_list[Hyperspace.playerVariables[string.format(var_name, slot)]]
			if type_name then
				--print("load weapon:"..broadside_weapons[type_name][2].." slot:"..slot - 1)
				setArtySlot(broadside_weapons[type_name][2], slot - 1)
			end
		end
	elseif Hyperspace.ships.player and needSetArty and shipManager:HasAugmentation("SHIP_OE_BROADSIDE3") > 0 and Hyperspace.playerVariables.oe_test_variable > 0 then
		needSetArty = false
		if Hyperspace.playerVariables.oe_broadside_c_slot1 > 0 then
			setArtySlot(allWeapons[Hyperspace.playerVariables.oe_broadside_c_slot1], 0)
		end
		if Hyperspace.playerVariables.oe_broadside_c_slot2 > 0 then
			setArtySlot(allWeapons[Hyperspace.playerVariables.oe_broadside_c_slot2], 1)
		end
		if Hyperspace.playerVariables.oe_broadside_c_slot3 > 0 then
			setArtySlot(allWeapons[Hyperspace.playerVariables.oe_broadside_c_slot3], 2)
		end
	elseif Hyperspace.ships.player and needSetArty and shipManager.iShipId == 0 and Hyperspace.playerVariables.oe_test_variable > 0 then
		needSetArty = false
	end
end)

script.on_internal_event(Defines.InternalEvents.PROJECTILE_FIRE, function(projectile, weapon)
	if weapon.isArtillery and Hyperspace.ships(weapon.iShipId):HasAugmentation("SHIP_AEA_BROADSIDE3") > 0 then
		if weapon.blueprint.typeName == "BEAM" then
			projectile.sub_end = Hyperspace.Pointf(projectile.position.x, projectile.position.y - 300)
		elseif weapon.blueprint.typeName ~= "BOMB" then
			projectile.heading = -90
		end
	end
end)

script.on_internal_event(Defines.InternalEvents.SHIP_LOOP, function(shipManager)
	if shipManager.iShipId == 0 and shipManager:HasAugmentation("SHIP_AEA_BROADSIDE3") and shipManager.weaponSystem then
		if shipManager.weaponSystem.weapons:size() > 0 then
			Hyperspace.playerVariables.oe_broadside_c_has_weapon = 1
		else
			Hyperspace.playerVariables.oe_broadside_c_has_weapon = 0
		end
	end
end)
