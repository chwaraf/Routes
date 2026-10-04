local Routes = LibStub("AceAddon-3.0"):GetAddon("Routes", 1)
if not Routes then
    return
end

local SourceName = "GatherLite"
-- setup
Routes.plugins[SourceName] = {}
local source = Routes.plugins[SourceName]

do
    local loaded = true
    local function IsActive()
        -- Can we gather data?
        return GatherLite and loaded
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

local amount_of = {}
local type_of = {}
local translate_db_type = {
    ["herbalism"] = "Herbalism",
    ["mining"] = "Mining",
}
local function Summarize(data, zone)
    local zoneID = Routes.LZName[zone]
    wipe(amount_of)
    wipe(type_of)

    -- GatherLite can store thousands of nodes in Classic Era. Aggregate once
    -- per object instead of building a per-zone node copy and formatting the
    -- same display row repeatedly for every individual node.
    for index, node in ipairs(GatherLite:GetNodes()) do
        if zoneID == node.mapID then
            amount_of[node.object] = (amount_of[node.object] or 0) + 1
            type_of[node.object] = node.type
        end
    end

    for objectID, count in pairs(amount_of) do
        local object = GatherLite:GetNodeObject(objectID)
        if object then
            local db_type = type_of[objectID]
            local translatednode = GatherLite:translate("node." .. object.name)
            -- append the minimum required skill, colored by the character's own
            -- skill: "Herbalism - Goldthorn (34) - 170"
            local suffix = ""
            local prof = translate_db_type[db_type]
            if (prof == "Herbalism" or prof == "Mining") and Routes.GetNodeSkillSuffix then
                suffix = Routes:GetNodeSkillSuffix(prof, nil, object.name)
                if not suffix then
                    suffix = Routes:GetNodeSkillSuffix(prof, nil, translatednode)
                end
                suffix = suffix or ""
            end
            data[("%s;%s;%s;%s"):format(SourceName, db_type, object.name, count)] = ("%s - %s (%d)%s"):format(translate_db_type[db_type], translatednode, count, suffix)
        end
    end
    return data
end

local function AppendNodes(node_list, zone, db_type, node_type)
    local zoneID = Routes.LZName[zone]

    for index, node in ipairs(GatherLite:GetNodes()) do
        if zoneID == node.mapID and node.type == db_type then
            local object = GatherLite:GetNodeObject(node.object)
            if object and object.name == node_type then
                local newLoc = Routes:getID(node.posX, node.posY)
                tinsert(node_list, newLoc)
            end
        end
    end

    local translatednode = GatherLite:translate("node." .. node_type)
    return node_type, translatednode, translate_db_type[db_type]
end

local function InsertNode(event, node)
    local newCoord = Routes:getID(node.posX, node.posY)
    local zoneLocalized = Routes.GetZoneName(node.mapID)
    if not zoneLocalized then return end

    local object = GatherLite:GetNodeObject(node.object);
    local translatednode = GatherLite:translate("node." .. object.name)

    Routes:InsertNode(zoneLocalized, newCoord, translatednode)
end

local function AddCallbacks()
    Routes:RegisterMessage("GatherLiteNodeAdded", InsertNode)
end

local function RemoveCallbacks()
    Routes:UnregisterMessage("GatherLiteNodeAdded")
end

source.Summarize = Summarize
source.AppendNodes = AppendNodes
source.AddCallbacks = AddCallbacks
source.RemoveCallbacks = RemoveCallbacks
