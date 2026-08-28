local Routes = LibStub("AceAddon-3.0"):GetAddon("Routes", 1)
if not Routes then return end

local SourceName = "GatherMate2"
local L = LibStub("AceLocale-3.0"):GetLocale("Routes")
local LN = LibStub("AceLocale-3.0"):GetLocale("GatherMate2Nodes", true)

------------------------------------------
-- setup
Routes.plugins[SourceName] = {}
local source = Routes.plugins[SourceName]

do
	local loaded = true
	local function IsActive() -- Can we gather data?
		return GatherMate2 and loaded
	end
	source.IsActive = IsActive

	-- stop loading if the addon is not enabled, or
	-- stop loading if there is a reason why it can't be loaded ("MISSING" or "DISABLED")
	local enabled = C_AddOns.GetAddOnEnableState(SourceName, UnitName("player")) > 0
	local name, title, notes, loadable, reason, security = C_AddOns.GetAddOnInfo(SourceName)
	if not enabled or (reason ~= nil and reason ~= "" and reason ~= "DEMAND_LOADED") then
		loaded = false
		return
	end
end

------------------------------------------
-- functions

-- returns the english name, translated name for the node so we can store it was being requested
-- also returns the type of db for use with auto show/hide route
local translate_db_type = {
	["Herb Gathering"] = "Herbalism",
	["Mining"] = "Mining",
	["Fishing"] = "Fishing",
	["Extract Gas"] = "ExtractGas",
	["Treasure"] = "Treasure",
	["Archaeology"] = "Archaeology",
	["Logging"] = "Logging",
}
-- GatherMate2 identifies nodes by its own node-id space, and GetNameForNode
-- returns the client-locale name. Resolve the ENGLISH name from
-- GatherMate2.nodeIDs (keyed by English name -> node id) so the name-based
-- skill table works on any locale as a second path alongside the node-id
-- table (which stays correct even if a future GatherMate2 renumbers nodes).
local english_node_cache = {}
local function english_node_name(db_type, node)
	local ids = GatherMate2.nodeIDs and GatherMate2.nodeIDs[db_type]
	if not ids then return nil end
	local cache = english_node_cache[db_type]
	if not cache then
		cache = {}
		english_node_cache[db_type] = cache
	end
	if cache[node] ~= nil then
		return cache[node] or nil
	end
	for name, id in pairs(ids) do
		if id == node then
			cache[node] = name
			return name
		end
	end
	cache[node] = false
	return nil
end

-- herb and mining nodes get their minimum required skill appended to the
-- name, colored against the player's own profession skill
local function node_skill_suffix(db_type, node, nodeName)
	local prof = translate_db_type[db_type]
	if (prof == "Herbalism" or prof == "Mining") and Routes.GetNodeSkillSuffix then
		return Routes:GetNodeSkillSuffix(prof, node, english_node_name(db_type, node) or nodeName)
	end
	return nil
end

local amount_of = {}
local function Summarize(data, zone)
	LN = LibStub("AceLocale-3.0"):GetLocale("GatherMate2Nodes", true) -- Workaround LoD of GatherMate2 if AddonLoader is used.
	for db_type, db_data in pairs(GatherMate2.gmdbs) do
		-- reuse table
		wipe(amount_of)
		-- only look for data for this currentzone
		local zoneID = Routes.LZName[zone]
		if db_data[zoneID] then
			-- count the unique values (structure is: location => itemID)
			for _,node in pairs(db_data[zoneID]) do
				amount_of[node] = (amount_of[node] or 0) + 1
			end
			-- store combinations with all information we have
			for node,count in pairs(amount_of) do
				local translatednode = GatherMate2:GetNameForNode(db_type, node)
				if translatednode then
					-- append the minimum required skill, colored by the
					-- character's own skill: "Herbalism - Goldthorn (34) - 170"
					local suffix = node_skill_suffix(db_type, node, translatednode) or ""
					data[ ("%s;%s;%s;%s"):format(SourceName, db_type, node, count) ] = ("%s - %s (%d)%s"):format(L[SourceName..db_type], translatednode, count, suffix)
				end
			end
		end
	end
	return data
end
source.Summarize = Summarize
local function AppendNodes(node_list, zone, db_type, node_type)
	if type(GatherMate2.gmdbs[db_type]) == "table" then
		node_type = tonumber(node_type)

		-- Find all of the notes
		local zoneID = Routes.LZName[zone]
		for loc, t in GatherMate2:GetNodesForZone(zoneID, db_type, true) do
			-- And are of a selected type - store
			if t == node_type then
				-- Convert GM2 location to our format
				local x, y, l = GatherMate2:DecodeLoc(loc) -- ignore level for now
				local newLoc = Routes:getID(x, y)
				tinsert( node_list, newLoc )
			end
		end

		-- return the node_type for auto-adding
		local translatednode = GatherMate2:GetNameForNode(db_type, node_type)
		for k, v in pairs(LN) do
			if v == translatednode then -- get the english name
				return k, v, translate_db_type[db_type]
			end
		end
	end
end
source.AppendNodes = AppendNodes

local function InsertNode(event, zone, nodeType, coord, node_name)
	-- Convert coords
	local x, y, l = GatherMate2:DecodeLoc(coord) -- ignore level for now
	local newCoord = Routes:getID(x, y)
	-- Convert zone
	local zoneLocalized = Routes.GetZoneName(zone)
	if not zoneLocalized then return end
	Routes:InsertNode(zoneLocalized, newCoord, node_name)
end

local function DeleteNode(event, zone, nodeType, coord, node_name)
	-- Convert coords
	local x, y, l = GatherMate2:DecodeLoc(coord) -- ignore level for now
	local newCoord = Routes:getID(x, y)
	-- Convert zone
	local zoneLocalized = Routes.GetZoneName(zone)
	if not zoneLocalized then return end
	Routes:DeleteNode(zoneLocalized, newCoord, node_name)
end

local function AddCallbacks()
	Routes:RegisterMessage("GatherMate2NodeAdded", InsertNode)
	Routes:RegisterMessage("GatherMate2NodeDeleted", DeleteNode)
end
source.AddCallbacks = AddCallbacks

local function RemoveCallbacks()
	Routes:UnregisterMessage("GatherMate2NodeAdded")
	Routes:UnregisterMessage("GatherMate2NodeDeleted")
end
source.RemoveCallbacks = RemoveCallbacks

-- vim: ts=4 noexpandtab
