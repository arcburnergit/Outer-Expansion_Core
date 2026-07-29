local version = {major = 1, minor = 20}
if not (Hyperspace.version and Hyperspace.version.major == version.major and Hyperspace.version.minor >= version.minor) then
	error("Incorrect Hyperspace version detected! The Outer Expansion: Core requires Hyperspace "..version.major.."."..version.minor.."+")
end
mods.oe = {}

local time_increment = mods.multiverse.time_increment
local vter = mods.multiverse.vter
local userdata_table = mods.multiverse.userdata_table
local node_child_iter = mods.multiverse.node_child_iter

function mods.oe.get_room_at_location(shipManager, location, includeWalls)
	return Hyperspace.ShipGraph.GetShipInfo(shipManager.iShipId):GetSelectedRoom(location.x, location.y, includeWalls)
end
local get_room_at_location = mods.oe.get_room_at_location

function mods.oe.xor(a, b)
	return (a and not b) or (not a and b)
end
local xor = mods.oe.xor

function mods.oe.isPointInEllipse(point, ellipse)
	if ellipse.a <= 0 or ellipse.b <= 0 then
		return false
	end
	local dx = point.x - ellipse.center.x
	local dy = point.y - ellipse.center.y
	local result = (dx^2 / ellipse.a^2) + (dy^2 / ellipse.b^2)

	return result <= 1
end
local isPointInEllipse = mods.oe.isPointInEllipse

function mods.oe.worldToPlayerLocation(location)
	local cApp = Hyperspace.App
	local combatControl = cApp.gui.combatControl
	local playerPosition = combatControl.playerShipPosition
	if cApp.menu.shipBuilder.bOpen then
		local commandGui = cApp.gui
		return Hyperspace.Point(location.x - commandGui.shipPosition.x - 30, location.y - commandGui.shipPosition.y + 139)
	end
	return Hyperspace.Point(location.x - playerPosition.x, location.y - playerPosition.y)
end
function mods.oe.worldToEnemyLocation(location)
	local cApp = Hyperspace.App
	local combatControl = cApp.gui.combatControl
	local position = combatControl.position
	local targetPosition = combatControl.targetPosition
	local enemyShipOriginX = position.x + targetPosition.x
	local enemyShipOriginY = position.y + targetPosition.y
	return Hyperspace.Point(location.x - enemyShipOriginX, location.y - enemyShipOriginY)
end
local worldToPlayerLocation = mods.oe.worldToPlayerLocation
local worldToEnemyLocation = mods.oe.worldToEnemyLocation

function mods.oe.get_distance(point1, point2)
	return math.sqrt(((point2.x - point1.x)^ 2)+((point2.y - point1.y) ^ 2))
end
local get_distance = mods.oe.get_distance

function mods.oe.offset_point_in_direction(position, angle, offset_x, offset_y)
	local alpha = math.rad(angle)
	local newX = position.x - (offset_y * math.cos(alpha)) - (offset_x * math.cos(alpha+math.rad(90)))
	local newY = position.y - (offset_y * math.sin(alpha)) - (offset_x * math.sin(alpha+math.rad(90)))
	return Hyperspace.Pointf(newX, newY)
end
local offset_point_in_direction = mods.oe.offset_point_in_direction

function mods.oe.get_point_local_offset(original, target, offsetForwards, offsetRight)
	local alpha = math.atan((original.y-target.y), (original.x-target.x))
	local newX = original.x - (offsetForwards * math.cos(alpha)) - (offsetRight * math.cos(alpha+math.rad(90)))
	local newY = original.y - (offsetForwards * math.sin(alpha)) - (offsetRight * math.sin(alpha+math.rad(90)))
	return Hyperspace.Pointf(newX, newY)
end
local get_point_local_offset = mods.oe.get_point_local_offset

function mods.oe.get_random_point_in_radius(center, radius)
	r = radius * math.sqrt(math.random())
	theta = math.random() * 2 * math.pi
	return Hyperspace.Pointf(center.x + r * math.cos(theta), center.y + r * math.sin(theta))
end
local get_random_point_in_radius = mods.oe.get_random_point_in_radius

function mods.oe.normalise_angle(angle)
	angle = angle % 360
	if angle < 0 then
		angle = angle + 360
	end
	return angle
end
local normalise_angle = mods.oe.normalise_angle

function mods.oe.angle_diff(angle1, angle2)
	local diff = angle2 - angle1
	while diff > 180 do
		diff = diff - 360
	end
	while diff < -180 do
		diff = diff + 360
	end
	return diff
end
local angle_diff = mods.oe.angle_diff

function mods.oe.get_angle_between_points(pos, target_pos)
	local alpha = math.atan((target_pos.y-pos.y), (target_pos.x-pos.x))
	return normalise_angle(math.deg(alpha))
end
local get_angle_between_points = mods.oe.get_angle_between_points

function mods.oe.find_closest_slot(roomShape, pos)
	local slotSize = 35
	local relX = pos.x - roomShape.x
	local relY = pos.y - roomShape.y
	if relX < 0 or relX >= roomShape.w or relY < 0 or relY >= roomShape.h then
		return 0
	end
	local slotsPerRow = math.floor(roomShape.w / slotSize)
	local col = math.floor(relX / slotSize)
	local row = math.floor(relY / slotSize)
	local slotID = (row * slotsPerRow) + col

	return slotID
end
local find_closest_slot = mods.oe.find_closest_slot



--[[local usedFTLman = false
for _, file in ipairs(mods.multiverse.blueprintFiles) do
	local doc = RapidXML.xml_document(file)
	for node in node_child_iter(doc:first_node("FTL") or doc) do
		if node:name() == "usedFTLman" then
			usedFTLman = true
		end
	end
	doc:clear()
end
script.on_render_event(Defines.RenderEvents.MAIN_MENU, function() end, function()
    local menu = Hyperspace.Global.GetInstance():GetCApp().menu
    if menu.shipBuilder.bOpen or usedFTLman then
        return
    end
    Graphics.CSurface.GL_DrawRect(15, 540, 340, 165, Graphics.GL_Color(0, 0, 0, 0.8))
    Graphics.freetype.easy_print(10, 20, 545, "WARNING: It is recommended you use FTLman \ninstead of slipstream to patch your addons.")
    Graphics.freetype.easy_print(10, 20, 590, "This will enable The Outer Expansion to \ngive it's custom systems to non OE ships.")
    Graphics.freetype.easy_print(10, 20, 635, "FTLman can be found here: \nhttps://github.com/afishhh/ftlman/releases/latest\nThis is completely optional, if you're not \ncomfortable switching, ignore this message.")
end)]]