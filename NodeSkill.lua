-- NodeSkill.lua
-- Adds the minimum profession skill required for herb/mining nodes to the
-- Add-tab list entries, colored relative to the character's own skill:
--
--   Herbalism - Goldthorn (34) - 170
--                                  ^^^ colored:
--   purple - profession is not learned at all
--   red    - character has the profession but skill is below the requirement
--   orange - within 25 above the requirement
--   yellow - within 50
--   green  - within 100
--   grey   - 100 or more above (no skill gain)
--
-- The requirement is looked up from static per-expansion tables covering
-- every classic-flavored client, from Classic Era through Mists of Pandaria:
--
--   * NodeSkillByName   - keyed by the node's ENGLISH name. Serves the
--     name-based data sources (Gatherer, GatherLite) on any locale.
--   * NodeSkillByNodeID - keyed by GatherMate2's node id, so GatherMate2 gets
--     a locale-independent fast path (its node ids are not item ids).
--
-- Skill gates were removed from gathering in MoP patch 5.3 (nodes can be
-- picked at skill 1 for reduced "fragment" yield); the MoP values below are
-- the original orange/full-yield thresholds and are colored the same way.
-- Modern retail (Legion and later) has no numeric gathering skill at all, so
-- no suffix is produced there.
--
-- Nodes not in the tables fall back to reading the requirement off the item
-- tooltip (see GetNodeSkillSuffixFromItem), which covers item-id-based
-- sources and future nodes; if that also fails a one-shot diagnostic is
-- printed in chat.

local Routes = LibStub("AceAddon-3.0"):GetAddon("Routes", 1)
if not Routes then return end
local L = Routes.L or LibStub("AceLocale-3.0"):GetLocale("Routes", false)

local GetSpellName = C_Spell and C_Spell.GetSpellName or GetSpellInfo
local math_floor, math_max = math.floor, math.max

----------------------------------------------------------------
-- Static per-expansion requirement tables.
--
-- NodeSkillByName:  English node name -> minimum required skill.
--   Used by the name-based data sources (Gatherer, GatherLite).
--
-- NodeSkillByNodeID:  GatherMate2 node id -> minimum required skill.
--   Used by GatherMate2, which identifies nodes by its own id space
--   (herbs 401+, ores 201+) rather than by WoW item ids.
----------------------------------------------------------------
local NodeSkillByName = {
	-- ------------------------------------------------------------------
	-- Classic Era (1-300)
	-- ------------------------------------------------------------------
	-- herbs
	["Peacebloom"]          = 1,
	["Silverleaf"]          = 1,
	["Earthroot"]           = 15,
	["Mageroyal"]           = 50,
	["Briarthorn"]          = 70,
	["Stranglekelp"]        = 85,
	["Bruiseweed"]          = 100,
	["Wild Steelbloom"]     = 115,
	["Grave Moss"]          = 120,
	["Kingsblood"]          = 125,
	["Liferoot"]            = 150,
	["Fadeleaf"]            = 160,
	["Goldthorn"]           = 170,
	["Khadgar's Whisker"]   = 185,
	["Wintersbite"]         = 195,
	["Firebloom"]           = 205,
	["Purple Lotus"]        = 210,
	["Arthas' Tears"]       = 220,
	["Sungrass"]            = 230,
	["Blindweed"]           = 235,
	["Ghost Mushroom"]      = 245,
	["Gromsblood"]          = 250,
	["Golden Sansam"]       = 260,
	["Dreamfoil"]           = 270,
	["Mountain Silversage"] = 280,
	["Plaguebloom"]         = 285,
	["Icecap"]              = 290,
	["Black Lotus"]         = 300,
	-- ores
	["Copper Vein"]         = 1,
	["Tin Vein"]            = 65,
	["Silver Vein"]         = 75,
	["Iron Deposit"]        = 125,
	["Gold Vein"]           = 155,
	["Mithril Deposit"]     = 175,
	["Truesilver Deposit"]  = 230,
	["Small Thorium Vein"]  = 230,
	["Rich Thorium Vein"]   = 275,
	["Dark Iron Deposit"]   = 230,

	-- ------------------------------------------------------------------
	-- The Burning Crusade (300-375)
	-- ------------------------------------------------------------------
	-- herbs
	["Felweed"]             = 300,
	["Dreaming Glory"]      = 315,
	["Terocone"]            = 325,
	["Ragveil"]             = 325,
	["Flame Cap"]           = 335,
	["Ancient Lichen"]      = 340,
	["Netherbloom"]         = 350,
	["Netherdust Bush"]     = 350,
	["Nightmare Vine"]      = 365,
	["Mana Thistle"]        = 375,
	-- ores
	["Fel Iron Deposit"]    = 300,
	["Adamantite Deposit"]  = 325,
	["Rich Adamantite Deposit"] = 350,
	["Nethercite Deposit"]  = 350,
	["Khorium Vein"]        = 375,

	-- ------------------------------------------------------------------
	-- Wrath of the Lich King (350-450)
	-- ------------------------------------------------------------------
	-- herbs
	["Goldclover"]          = 350,
	["Firethorn"]           = 360,
	["Tiger Lily"]          = 375,
	["Talandra's Rose"]     = 385,
	["Adder's Tongue"]      = 400,
	["Frozen Herb"]         = 415,
	["Lichbloom"]           = 425,
	["Icethorn"]            = 435,
	["Frost Lotus"]         = 450,
	-- ores
	["Cobalt Deposit"]      = 350,
	["Rich Cobalt Deposit"] = 375,
	["Saronite Deposit"]    = 400,
	["Rich Saronite Deposit"] = 425,
	["Pure Saronite Deposit"] = 400,
	["Titanium Vein"]       = 450,

	-- ------------------------------------------------------------------
	-- Cataclysm (425-525)
	-- ------------------------------------------------------------------
	-- herbs
	["Cinderbloom"]         = 425,
	["Stormvine"]           = 425,
	["Azshara's Veil"]      = 425,
	["Heartblossom"]        = 475,
	["Whiptail"]            = 500,
	["Twilight Jasmine"]    = 525,
	["Dragon's Teeth"]      = 195, -- revamped low-level zones
	["Sorrowmoss"]          = 285, -- revamped mid-level zones
	-- ores
	["Obsidium Deposit"]    = 425,
	["Rich Obsidium Deposit"] = 450,
	["Elementium Vein"]     = 475,
	["Rich Elementium Vein"] = 500,
	["Pyrite Deposit"]      = 525,
	["Rich Pyrite Deposit"] = 525,

	-- ------------------------------------------------------------------
	-- Mists of Pandaria (500-600)
	--   Patch 5.3 removed the hard gate (everything is pickable at skill 1
	--   for reduced "fragment" yield); these are the original orange /
	--   full-yield thresholds.
	-- ------------------------------------------------------------------
	-- herbs
	["Green Tea Leaf"]      = 500,
	["Silkweed"]            = 500,
	["Rain Poppy"]          = 525,
	["Snow Lily"]           = 525,
	["Fool's Cap"]          = 550,
	["Sha-Touched Herb"]    = 550,
	["Golden Lotus"]        = 600,
	-- ores
	["Ghost Iron Deposit"]  = 500,
	["Rich Ghost Iron Deposit"] = 550,
	["Kyparite Deposit"]    = 550,
	["Rich Kyparite Deposit"] = 575,
	["Trillium Vein"]       = 600,
	["Rich Trillium Vein"]  = 600,
}

-- GatherMate2's node-id space. See GatherMate2/Constants.lua ("node_ids"):
--   Mining          -> 201+ (Copper Vein 201 ... Rich Trillium Vein 248)
--   Herb Gathering  -> 401+ (Peacebloom 401 ... Golden Lotus 462)
local NodeSkillByNodeID = {
	-- Classic Era - herbs
	[401] = 1,    -- Peacebloom
	[402] = 1,    -- Silverleaf
	[403] = 15,   -- Earthroot
	[404] = 50,   -- Mageroyal
	[405] = 70,   -- Briarthorn
	[407] = 85,   -- Stranglekelp
	[408] = 100,  -- Bruiseweed
	[409] = 115,  -- Wild Steelbloom
	[410] = 120,  -- Grave Moss
	[411] = 125,  -- Kingsblood
	[412] = 150,  -- Liferoot
	[413] = 160,  -- Fadeleaf
	[414] = 170,  -- Goldthorn
	[415] = 185,  -- Khadgar's Whisker
	[416] = 195,  -- Wintersbite
	[417] = 205,  -- Firebloom
	[418] = 210,  -- Purple Lotus
	[420] = 220,  -- Arthas' Tears
	[421] = 230,  -- Sungrass
	[422] = 235,  -- Blindweed
	[423] = 245,  -- Ghost Mushroom
	[424] = 250,  -- Gromsblood
	[425] = 260,  -- Golden Sansam
	[426] = 270,  -- Dreamfoil
	[427] = 280,  -- Mountain Silversage
	[428] = 285,  -- Plaguebloom
	[429] = 290,  -- Icecap
	[431] = 300,  -- Black Lotus
	-- Classic Era - ores
	[201] = 1,    -- Copper Vein
	[202] = 65,   -- Tin Vein
	[203] = 125,  -- Iron Deposit
	[204] = 75,   -- Silver Vein
	[205] = 155,  -- Gold Vein
	[206] = 175,  -- Mithril Deposit
	[207] = 175,  -- Ooze Covered Mithril Deposit
	[208] = 230,  -- Truesilver Deposit
	[209] = 75,   -- Ooze Covered Silver Vein
	[210] = 155,  -- Ooze Covered Gold Vein
	[211] = 230,  -- Ooze Covered Truesilver Deposit
	[212] = 275,  -- Ooze Covered Rich Thorium Vein
	[213] = 230,  -- Ooze Covered Thorium Vein
	[214] = 230,  -- Small Thorium Vein
	[215] = 275,  -- Rich Thorium Vein
	[217] = 230,  -- Dark Iron Deposit
	-- The Burning Crusade - herbs
	[432] = 300,  -- Felweed
	[433] = 315,  -- Dreaming Glory
	[434] = 325,  -- Terocone
	[435] = 340,  -- Ancient Lichen
	[437] = 375,  -- Mana Thistle
	[438] = 350,  -- Netherbloom
	[439] = 365,  -- Nightmare Vine
	[440] = 325,  -- Ragveil
	[441] = 335,  -- Flame Cap
	[442] = 350,  -- Netherdust Bush
	-- The Burning Crusade - ores
	[221] = 300,  -- Fel Iron Deposit
	[222] = 325,  -- Adamantite Deposit
	[223] = 350,  -- Rich Adamantite Deposit
	[224] = 375,  -- Khorium Vein
	[227] = 350,  -- Nethercite Deposit
	-- Wrath of the Lich King - herbs
	[443] = 400,  -- Adder's Tongue
	[446] = 350,  -- Goldclover
	[447] = 435,  -- Icethorn
	[448] = 425,  -- Lichbloom
	[449] = 385,  -- Talandra's Rose
	[450] = 375,  -- Tiger Lily
	[451] = 360,  -- Firethorn
	[452] = 415,  -- Frozen Herb
	[453] = 450,  -- Frost Lotus
	-- Wrath of the Lich King - ores
	[228] = 350,  -- Cobalt Deposit
	[229] = 375,  -- Rich Cobalt Deposit
	[230] = 450,  -- Titanium Vein
	[231] = 400,  -- Saronite Deposit
	[232] = 425,  -- Rich Saronite Deposit
	[235] = 400,  -- Pure Saronite Deposit
	-- Cataclysm - herbs
	[454] = 195,  -- Dragon's Teeth (revamped low-level zones)
	[455] = 285,  -- Sorrowmoss (revamped mid-level zones)
	[456] = 425,  -- Azshara's Veil
	[457] = 425,  -- Cinderbloom
	[458] = 425,  -- Stormvine
	[459] = 475,  -- Heartblossom
	[460] = 525,  -- Twilight Jasmine
	[461] = 500,  -- Whiptail
	-- Cataclysm - ores
	[233] = 425,  -- Obsidium Deposit
	[236] = 475,  -- Elementium Vein
	[237] = 500,  -- Rich Elementium Vein
	[238] = 525,  -- Pyrite Deposit
	[239] = 450,  -- Rich Obsidium Deposit
	[240] = 525,  -- Rich Pyrite Deposit
	-- Mists of Pandaria - herbs
	[462] = 600,  -- Golden Lotus
	[463] = 550,  -- Fool's Cap
	[464] = 525,  -- Snow Lily
	[465] = 500,  -- Silkweed
	[466] = 500,  -- Green Tea Leaf
	[467] = 525,  -- Rain Poppy
	[468] = 550,  -- Sha-Touched Herb
	-- Mists of Pandaria - ores
	[241] = 500,  -- Ghost Iron Deposit
	[242] = 550,  -- Rich Ghost Iron Deposit
	[245] = 550,  -- Kyparite Deposit
	[246] = 575,  -- Rich Kyparite Deposit
	[247] = 600,  -- Trillium Vein
	[248] = 600,  -- Rich Trillium Vein
}

----------------------------------------------------------------
-- Character skill for a gathering profession (nil when not learned)
----------------------------------------------------------------
local profName = {}
local profNameReady = false
local function RefreshProfNames()
	if profNameReady then return end
	profNameReady = true
	local function baseName(spellIDs)
		for i = 1, #spellIDs do
			local n = GetSpellName(spellIDs[i])
			if n and n ~= "" then return n end
		end
		return nil
	end
	profName.Herbalism = baseName({ 170691, 9134 })
	profName.Mining = baseName({ 2575 })
end

-- Successes are cached for the session (the rank only changes on skill-up);
-- FAILURES are only remembered for a short TTL, because profession data is
-- not always available on the very first lookups right after login -- a
-- failed early lookup must not poison every later node list.
local playerSkillCache = {}
local playerSkillFailAt = {}
local PLAYER_SKILL_FAIL_TTL = 10 -- seconds

-- Different client generations expose the rank through different APIs, so
-- several are probed (all wrapped in pcall, since a hybrid classic client
-- may expose an API that exists but does not work):
--   1. GetNumPrimaryProfessions() + GetPrimaryProfessionInfo(i)
--        -- the classic primary API
--   2. GetProfessions() + GetProfessionInfo(idx)
--        -- TBC+ / hybrid clients; note the return order is
--        -- name, icon, skillLevel, maxSkillLevel (rank is the THIRD value)
--   3. GetNumSkillLines() + GetSkillLineInfo(i)
--        -- the oldest spellbook API: name, isHeader, icon, rank, ...
local function RankValue(rank)
	-- some hybrid clients return the rank as a numeric string
	if type(rank) == "number" then return rank end
	if type(rank) == "string" then
		local n = tonumber(rank)
		if n then return n end
	end
	return nil
end

local function RankFromPrimaryProfessions(target)
	if not GetNumPrimaryProfessions or not GetPrimaryProfessionInfo then return nil, nil end
	local ok, count = pcall(GetNumPrimaryProfessions)
	if not ok or type(count) ~= "number" then return nil, nil end
	for i = 1, count do
		local ok2, name, _icon, rank = pcall(GetPrimaryProfessionInfo, i)
		if ok2 and name == target then
			return RankValue(rank), true
		end
	end
	return nil, false
end

local function RankFromProfessions(target)
	if not GetProfessions or not GetProfessionInfo then return nil, nil end
	local ok, n = pcall(function() return select("#", GetProfessions()) end)
	if not ok or type(n) ~= "number" then return nil, nil end
	for i = 1, n do
		local idx = select(i, GetProfessions())
		if idx then
			local ok2, name, _icon, rank = pcall(GetProfessionInfo, idx)
			if ok2 and name == target then
				return RankValue(rank), true
			end
		end
	end
	-- tolerant match for clients that suffix the profession name
	for i = 1, n do
		local idx = select(i, GetProfessions())
		if idx then
			local ok2, name, _icon, rank = pcall(GetProfessionInfo, idx)
			if ok2 and type(name) == "string" and name:find(target, 1, true) then
				return RankValue(rank), true
			end
		end
	end
	return nil, false
end

local function RankFromSkillLines(target)
	if not GetNumSkillLines or not GetSkillLineInfo then return nil, nil end
	local ok, count = pcall(GetNumSkillLines)
	if not ok or type(count) ~= "number" then return nil, nil end
	for i = 1, count do
		local ok2, name, isHeader, _icon, rank = pcall(GetSkillLineInfo, i)
		if ok2 and not isHeader and name == target then
			return RankValue(rank), true
		end
	end
	-- tolerant match
	for i = 1, count do
		local ok2, name, isHeader, _icon, rank = pcall(GetSkillLineInfo, i)
		if ok2 and not isHeader and type(name) == "string" and name:find(target, 1, true) then
			return RankValue(rank), true
		end
	end
	return nil, false
end

-- Returns rank, found:
--   rank number, true  - profession is learned and rank is known
--   nil, true          - profession is learned but rank was not available
--   nil, false         - profession APIs worked and did not list it
--   nil, nil           - profession APIs/names are unavailable; state unknown
local function QuerySkillRank(prof)
	local target = profName[prof]
	if not target then return nil, nil end
	local sawMissing = false
	local rank, found = RankFromPrimaryProfessions(target)
	if rank ~= nil then return rank, true end
	if found then return nil, true elseif found == false then sawMissing = true end
	rank, found = RankFromProfessions(target)
	if rank ~= nil then return rank, true end
	if found then return nil, true elseif found == false then sawMissing = true end
	rank, found = RankFromSkillLines(target)
	if rank ~= nil then return rank, true end
	if found then return nil, true elseif found == false then sawMissing = true end
	if sawMissing then return nil, false end
	return nil, nil
end

-- previous rank per profession, to fire Routes.OnNodeSkillChanged() when the
-- rank appears, disappears or changes (the node list cache must be dropped
-- so the next dropdown open rebuilds the colored strings)
local lastKnownRank = {}

local function UpdateSkillState(prof)
	local cached = playerSkillCache[prof]
	local value
	if cached ~= nil then
		value = cached
	else
		local rank, found = QuerySkillRank(prof)
		if rank ~= nil then
			value = rank
			playerSkillCache[prof] = rank
		elseif found == false then
			value = false -- known: profession is not learned
			playerSkillCache[prof] = false
		else
			playerSkillFailAt[prof] = GetTime()
			value = nil -- unknown/unavailable; retry after the short TTL
		end
	end
	local prev = lastKnownRank[prof]
	if value ~= prev then
		lastKnownRank[prof] = value
		if Routes.OnNodeSkillChanged then
			local ok = pcall(Routes.OnNodeSkillChanged, Routes)
			if not ok then lastKnownRank[prof] = prev end
		end
	end
	return value or nil
end

local function PlayerSkillFor(prof)
	local cached = playerSkillCache[prof]
	if cached ~= nil then
		return cached or nil
	end
	local failAt = playerSkillFailAt[prof]
	if failAt and (GetTime() - failAt) < PLAYER_SKILL_FAIL_TTL then
		return nil -- per-node path: don't hammer the API while data may load
	end
	return UpdateSkillState(prof)
end

local function PlayerProfessionMissing(prof)
	if playerSkillCache[prof] == nil then
		UpdateSkillState(prof)
	end
	return playerSkillCache[prof] == false
end

-- Called once per node list (re)build from the options frame. If no rank is
-- cached yet this forces a fresh query even within the per-node TTL, so
-- profession data that loads after the first (uncolored) list build shows
-- up colored on the very next open instead of after the TTL.
function Routes:RefreshNodeSkills()
	RefreshProfNames()
	-- A known-missing profession is cached so a single node-list build does not
	-- rescan the profession APIs for every node. Clear that cache on the next
	-- list rebuild so learning Herbalism/Mining in the same session is noticed.
	if playerSkillCache.Herbalism == false then playerSkillCache.Herbalism = nil end
	if playerSkillCache.Mining == false then playerSkillCache.Mining = nil end
	if playerSkillCache.Herbalism == nil then UpdateSkillState("Herbalism") end
	if playerSkillCache.Mining == nil then UpdateSkillState("Mining") end
end

----------------------------------------------------------------
-- Color of the requirement number relative to the character's skill
----------------------------------------------------------------
local function RequirementColor(skill, req, missingProfession)
	if missingProfession then return "ffb060ff" end -- purple: profession not learned
	if type(skill) ~= "number" then
		return "ffff3333" -- rank unknown = cannot confirm pickup
	end
	if skill < req then return "ffff3333" end   -- red: learned, but too low
	local diff = skill - req
	if diff < 25 then return "ffff8040" end     -- orange
	if diff < 50 then return "ffffff00" end     -- yellow
	if diff < 100 then return "ff40cc40" end    -- green
	return "ff808080"                           -- grey: no skill gain
end

local function RequirementSuffix(prof, req)
	local skill = PlayerSkillFor(prof)
	local missingProfession = PlayerProfessionMissing(prof)
	local color = RequirementColor(skill, req, missingProfession)
	if missingProfession then
		return (" - |c%s%s|r"):format(color, L["No %s (%d)"]:format(profName[prof] or prof, req))
	end
	if color then
		return (" - |c%s%d|r"):format(color, req)
	end
	return (" - %d"):format(req)
end

----------------------------------------------------------------
-- Tooltip fallback for nodes that are not in the static tables
----------------------------------------------------------------
local tt = CreateFrame("GameTooltip", "RoutesNodeSkillTooltip", nil, "GameTooltipTemplate")
tt:SetFrameLevel(0)
tt:ClearAllPoints()
tt:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -2000, -2000)

-- Number of lines the hidden tooltip currently shows. Modern frames expose
-- NumLines()/GetNumLines(); classic-era frames often expose neither, so as a
-- last resort scan the TextLeftN font strings directly. Item tooltips can
-- contain empty separator lines, so the count is the highest non-empty line.
local function TooltipLineCount()
	if tt.NumLines then
		local n = tt:NumLines()
		if n and n > 0 then return n end
	end
	if tt.GetNumLines then
		local n = tt:GetNumLines()
		if n and n > 0 then return n end
	end
	local count = 0
	for i = 1, 30 do
		local fs = tt["TextLeft"..i] or _G[tt:GetName().."TextLeft"..i]
		if fs and fs.GetText then
			local text = fs:GetText()
			if text and text ~= "" then
				count = i
			end
		end
	end
	return count
end

-- Text of the left column of a line. Both systems store lines in the
-- TextLeftN font strings; GetText(line, subline) is the modern alias.
local function TooltipLineText(i)
	local fs = tt["TextLeft"..i] or _G[tt:GetName().."TextLeft"..i]
	if fs and fs.GetText then
		return fs:GetText()
	end
	if tt.GetText then
		return tt:GetText(i, 1)
	end
	return nil
end

-- Build a ProcessInfo payload for this item, or nil when this client has no
-- way to fetch item tooltip data. The API was refactored across versions:
-- retail 10.0+ is item-location based (C_Item.GetItemLocation +
-- C_TooltipInfo.GetItemByLocation), older clients are item-id based.
local function ItemTooltipInfo(itemID)
	if not C_TooltipInfo then return nil end
	if C_TooltipInfo.GetItemByLocation then
		local location
		if C_Item and C_Item.GetItemLocation then
			location = C_Item.GetItemLocation(itemID)
		end
		if location then
			return { getterName = "GetItemByLocation", getterArgs = { location } }
		end
		return nil
	end
	if C_TooltipInfo.GetItemByID then
		return { getterName = "GetItemByID", getterArgs = { itemID } }
	end
	if C_TooltipInfo.GetItemTooltipData then
		return { getterName = "GetItemTooltipData", getterArgs = { itemID } }
	end
	if C_TooltipInfo.GetItemTooltip then
		return { getterName = "GetItemTooltip", getterArgs = { itemID } }
	end
	return nil
end

-- An item link for this item id, using whichever API this client provides.
-- Note: on 10.0+ C_Item.GetItemLink takes an item-location object, not an id,
-- while hybrid classic builds expose C_Item.GetItemLink(itemID) directly.
local function ItemLinkForID(itemID)
	if C_Item and C_Item.GetItemLink then
		if C_Item.GetItemLocation then
			local location = C_Item.GetItemLocation(itemID)
			if location then
				local ok, link = pcall(C_Item.GetItemLink, C_Item, location)
				if ok and link then return link end
			end
		else
			local ok, link = pcall(C_Item.GetItemLink, C_Item, itemID)
			if ok and link then return link end
		end
	end
	if GetItemLink then
		local ok, link = pcall(GetItemLink, itemID)
		if ok and link then return link end
	end
	return ("item:%d:0:0:0:0:0:0:0:0:0:0"):format(itemID)
end

-- Is this item known to this client's item database?
local function ItemKnown(itemID)
	if C_Item and C_Item.GetItemInfo then
		return C_Item.GetItemInfo(itemID) ~= nil
	end
	if GetItemInfo then
		return GetItemInfo(itemID) ~= nil
	end
	return false
end

-- One-shot compact diagnostic, printed when the tooltip fallback fails for
-- a known item that is not in the static tables.
local diagnosed = false
-- Once the tooltip path is proven dead on this client, stop trying it: some
-- classic builds expose the API but it produces nothing, and retrying it per
-- node makes large node lists slow for zero benefit. A single failure is not
-- proof (the item may simply be unknown to this client's item database), so
-- the path is declared dead after a run of consecutive failures; any
-- success resets the counter.
local fallbackDead = false
local fallbackFails = 0
local FALLBACK_FAIL_LIMIT = 10
local function DiagnoseFailure(itemID)
	if diagnosed then return end
	diagnosed = true
	if ItemKnown(itemID) then fallbackDead = true end -- known item, no lines: definitively dead
	local function yn(v) return v and "yes" or "no" end
	local CTI = C_TooltipInfo or {}
	local CI = C_Item or {}
	local hasTextLeft = (tt.TextLeft1 ~= nil or _G[tt:GetName().."TextLeft1"] ~= nil)
	Routes:Print(("skill-suffix (tooltip fallback) unavailable: frame{{SetItemByID=%s ProcessInfo=%s AddItem=%s SetHyperlink=%s NumLines=%s GetNumLines=%s TextLeft1=%s}} api{{C_TooltipInfo=%s ByLocation=%s ByID=%s C_Item=%s GetItemLocation=%s GetItemLink=%s GetItemLink-global=%s SetItemTooltip-global=%s}} item %d known=%s"):format(
		yn(tt.SetItemByID ~= nil), yn(tt.ProcessInfo ~= nil), yn(tt.AddItem ~= nil),
		yn(tt.SetHyperlink ~= nil), yn(tt.NumLines ~= nil), yn(tt.GetNumLines ~= nil), yn(hasTextLeft),
		yn(C_TooltipInfo ~= nil), yn(CTI.GetItemByLocation ~= nil), yn(CTI.GetItemByID ~= nil),
		yn(C_Item ~= nil), yn(CI.GetItemLocation ~= nil), yn(CI.GetItemLink ~= nil),
		yn(GetItemLink ~= nil), yn(type(GameTooltip_SetItemTooltip) == "function"),
		itemID, yn(ItemKnown(itemID))))
end

-- Try to populate the hidden tooltip with the item, using whichever method
-- this client generation provides. Each attempt is verified to actually
-- produce lines before it is accepted. Returns true on success. Classic
-- helpers are wrapped in pcall: on some clients they exist but misbehave.
local function PopulateItemTooltip(itemID)
	tt:Hide()
	local success = false

	if tt.SetItemByID then
		local ok = pcall(tt.SetItemByID, tt, itemID)
		if ok then
			success = TooltipLineCount() > 0
		end
	end

	if not success and tt.ProcessInfo then
		local info = ItemTooltipInfo(itemID)
		if info then
			local ok = pcall(tt.ProcessInfo, tt, info)
			if ok then
				success = TooltipLineCount() > 0
			end
		end
	end

	if not success and tt.AddItem then
		local ok = pcall(tt.AddItem, tt, itemID)
		if ok then
			success = TooltipLineCount() > 0
		end
	end

	if not success then
		local link = ItemLinkForID(itemID)
		if tt.SetHyperlink then
			local ok = pcall(tt.SetHyperlink, tt, link)
			if ok then
				success = TooltipLineCount() > 0
			end
		end
		-- Classic-era fallback: the 1.15 global helper that populates a
		-- custom GameTooltip frame (frame method not available)
		if not success and type(GameTooltip_SetHyperlink) == "function" then
			local ok = pcall(GameTooltip_SetHyperlink, tt, link)
			if ok then
				success = TooltipLineCount() > 0
			end
		end
		-- Classic-era item helper (1.15 GameTooltip_SetItemTooltip)
		if not success and type(GameTooltip_SetItemTooltip) == "function" then
			local ok = pcall(GameTooltip_SetItemTooltip, tt, itemID)
			if ok then
				success = TooltipLineCount() > 0
			end
		end
	end

	tt:Hide()

	if not success and ItemKnown(itemID) then
		DiagnoseFailure(itemID)
	end

	return success
end

-- Does this tooltip line mention the profession? The line carries the
-- localized profession name, but some languages inflect it (e.g. the Polish
-- genitive "Ziołoznawstwa" vs the base "Ziołoznawstwo"), so fall back to a
-- distinctive prefix of the name.
local function LineMentionsProfession(text, name)
	if text:find(name, 1, true) then return true end
	local prefixLen = math_max(4, math_floor(#name * 0.6))
	local prefix = name:sub(1, prefixLen)
	return text:find(prefix, 1, true) ~= nil
end

-- itemID .. ":" .. prof -> { req = number } or false (no requirement line)
local tooltipSkillCache = {}
-- Read the requirement from the item tooltip (fallback for nodes missing
-- from the static tables). Returns the required skill or nil.
local function NodeRequiredSkill(itemID, prof)
	if fallbackDead then return nil end -- proven dead on this client, see DiagnoseFailure
	local key = itemID .. ":" .. prof
	local cached = tooltipSkillCache[key]
	if cached ~= nil then
		if type(cached) == "table" then return cached.req end
		return nil
	end
	local req
	local populated = PopulateItemTooltip(itemID)
	if populated then
		fallbackFails = 0
		local target = profName[prof]
		if target then
			for i = 1, TooltipLineCount() do
				local text = TooltipLineText(i)
				if text and text:find(target, 1, true) then
					local num = text:match("(%d+)%)%s*$")
					if num then
						req = tonumber(num)
						break
					end
				elseif text and LineMentionsProfession(text, target) then
					local num = text:match("(%d+)%)%s*$")
					if num then
						req = tonumber(num)
						break
					end
				end
			end
		end
	else
		fallbackFails = fallbackFails + 1
		if fallbackFails >= FALLBACK_FAIL_LIMIT then
			fallbackDead = true -- this client's tooltip path yields nothing; stop retrying
		end
	end
	tt:Hide()
	if req then
		tooltipSkillCache[key] = { req = req }
		return req
	else
		tooltipSkillCache[key] = false
		return nil
	end
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
-- Routes:GetNodeSkillSuffix(prof, nodeID, nodeName)
-- prof:     "Herbalism" or "Mining"
-- nodeID:   the node id when the data source provides one (GatherMate2's
--           node-id space - NOT a WoW item id)
-- nodeName: the node's ENGLISH name when the data source is name-based
--           (Gatherer / GatherLite)
-- Returns a display suffix like " - |cffff3333170|r" to append after the
-- node count, or nil when the requirement is unknown. The number is colored
-- against the character's own rank. If the profession is not learned at all,
-- the suffix uses the localized "No <profession> (<skill>)" text in purple
-- instead of the red low-skill number.
function Routes:GetNodeSkillSuffix(prof, nodeID, nodeName)
	if prof ~= "Herbalism" and prof ~= "Mining" then return nil end
	RefreshProfNames()

	local req
	if type(nodeID) == "number" then
		req = NodeSkillByNodeID[nodeID]
	end
	if not req and type(nodeName) == "string" and nodeName ~= "" then
		req = NodeSkillByName[nodeName]
	end
	if not req then return nil end

	return RequirementSuffix(prof, req)
end

-- Item-id based variant, for data sources that hand us a real WoW item id
-- instead of a node name or a GatherMate2 node id. Reads the requirement off
-- the item tooltip ("Requires Herbalism (170)") rather than the static
-- tables above.
function Routes:GetNodeSkillSuffixFromItem(prof, itemID)
	if prof ~= "Herbalism" and prof ~= "Mining" then return nil end
	RefreshProfNames()

	local req
	if type(itemID) == "number" and itemID > 0 then
		req = NodeRequiredSkill(itemID, prof)
	end
	if not req then return nil end

	return RequirementSuffix(prof, req)
end

----------------------------------------------------------------
-- /routes skilldebug [itemID] - full diagnostic
----------------------------------------------------------------
function Routes:NodeSkillDebug(itemID)
	local function yn(v) return v and "yes" or "no" end
	local build, major = GetBuildInfo()
	Routes:Print(("NodeSkill debug - client %s (interface %s, project %d)"):format(build, major, WOW_PROJECT_ID or 0))

	-- refresh the shared state too, so running this command also drops the
	-- node list cache when professions became available
	Routes:RefreshNodeSkills()
	local skill = PlayerSkillFor("Herbalism")
	local mskill = PlayerSkillFor("Mining")
	Routes:Print(("  player skills: Herbalism=%s Mining=%s  (names: %s / %s)"):format(
		tostring(skill), tostring(mskill),
		tostring(profName.Herbalism), tostring(profName.Mining)))

	-- raw profession API dump: shows exactly what this client returns, so a
	-- nil above is never a mystery
	if GetNumPrimaryProfessions and GetPrimaryProfessionInfo then
		local ok, count = pcall(GetNumPrimaryProfessions)
		if ok and type(count) == "number" then
			local parts = {}
			for i = 1, count do
				local ok2, name, _icon, rank, maxRank = pcall(GetPrimaryProfessionInfo, i)
				if ok2 then parts[#parts + 1] = ("[%d %s %s/%s]"):format(i, tostring(name), tostring(rank), tostring(maxRank)) end
			end
			Routes:Print(("  GetNumPrimaryProfessions=%d %s"):format(count, table.concat(parts, " ")))
		else
			Routes:Print("  GetNumPrimaryProfessions: pcall failed")
		end
	else
		Routes:Print("  GetNumPrimaryProfessions: absent")
	end
	if GetProfessions and GetProfessionInfo then
		local ok, n = pcall(function() return select("#", GetProfessions()) end)
		if ok and type(n) == "number" then
			local parts = {}
			for i = 1, n do
				local idx = select(i, GetProfessions())
				local ok2, name, _icon, rank, maxRank = pcall(GetProfessionInfo, idx)
				if ok2 then parts[#parts + 1] = ("[idx %s %s %s/%s]"):format(tostring(idx), tostring(name), tostring(rank), tostring(maxRank)) end
			end
			Routes:Print(("  GetProfessions n=%d %s"):format(n, table.concat(parts, " ")))
		else
			Routes:Print("  GetProfessions: pcall failed")
		end
	else
		Routes:Print("  GetProfessions: absent")
	end
	if GetNumSkillLines and GetSkillLineInfo then
		local ok, count = pcall(GetNumSkillLines)
		if ok and type(count) == "number" then
			local parts = {}
			for i = 1, count do
				local ok2, name, isHeader, _icon, rank, _a, maxRank = pcall(GetSkillLineInfo, i)
				if ok2 then parts[#parts + 1] = ("[%d %s%s %s/%s]"):format(i, tostring(name), isHeader and " header" or "", tostring(rank), tostring(maxRank)) end
			end
			Routes:Print(("  GetNumSkillLines=%d %s"):format(count, table.concat(parts, " ")))
		else
			Routes:Print("  GetNumSkillLines: pcall failed")
		end
	else
		Routes:Print("  GetNumSkillLines: absent")
	end

	local id = itemID
	if type(id) ~= "number" or id <= 0 then id = 2447 end -- Peacebloom (item id)
	Routes:Print(("  item %d: static-by-name=%s  tooltip-suffix=%s"):format(
		id, tostring(NodeSkillByName["Peacebloom"]), tostring(Routes:GetNodeSkillSuffixFromItem("Herbalism", id))))

	-- probe one REAL node from the player's zone, straight from the data
	-- source, so the pasted line covers the actual list entries too
	local probe_map = ({ ["Herb Gathering"] = "Herbalism", ["Mining"] = "Mining" })
	if GatherMate2 and type(GatherMate2.gmdbs) == "table"
		and Routes.Dragons and Routes.Dragons.GetPlayerZone and Routes.GetZoneName then
		local mapID = Routes.Dragons:GetPlayerZone()
		if mapID then
			local mdata = Routes.Dragons.mapData and Routes.Dragons.mapData[mapID]
			if mdata and Enum and Enum.UIMapType
				and (mdata.mapType == Enum.UIMapType.Dungeon or mdata.mapType == Enum.UIMapType.Micro) then
				mapID = mdata.parent
			end
			local zoneName = Routes.GetZoneName(mapID)
			if zoneName and Routes.LZName[zoneName] then
				local zoneID = Routes.LZName[zoneName]
				for db_type, db_data in pairs(GatherMate2.gmdbs) do
					local prof = probe_map[db_type]
					if prof and type(db_data) == "table" and type(db_data[zoneID]) == "table" then
						for _, node in pairs(db_data[zoneID]) do
							local nm = GatherMate2.GetNameForNode and GatherMate2:GetNameForNode(db_type, node)
							if nm then
								Routes:Print(("  real node [%s]: %s (id %s) suffix=%s"):format(
									db_type, nm, tostring(node),
									tostring(Routes:GetNodeSkillSuffix(prof, node, nm))))
							end
							break
						end
						break
					end
				end
			end
		end
	end

	Routes:Print(("  frame: SetItemByID=%s ProcessInfo=%s AddItem=%s SetHyperlink=%s NumLines=%s GetNumLines=%s GetText=%s TextLeft1=%s"):format(
		yn(tt.SetItemByID), yn(tt.ProcessInfo), yn(tt.AddItem), yn(tt.SetHyperlink),
		yn(tt.NumLines ~= nil), yn(tt.GetNumLines ~= nil), yn(tt.GetText ~= nil),
		yn(tt.TextLeft1 ~= nil or _G[tt:GetName().."TextLeft1"] ~= nil)))

	local CTI = C_TooltipInfo or {}
	local CI = C_Item or {}
	Routes:Print(("  C_TooltipInfo: ByLocation=%s ByID=%s TooltipData=%s Tooltip=%s"):format(
		yn(CTI.GetItemByLocation ~= nil), yn(CTI.GetItemByID ~= nil),
		yn(CTI.GetItemTooltipData ~= nil), yn(CTI.GetItemTooltip ~= nil)))
	Routes:Print(("  C_Item: GetItemLocation=%s GetItemLink=%s GetItemInfo=%s  GetItemLink(global)=%s"):format(
		yn(CI.GetItemLocation ~= nil), yn(CI.GetItemLink ~= nil), yn(CI.GetItemInfo ~= nil),
		yn(GetItemLink ~= nil)))

	do
		local sid = id
		Routes:Print(("  tooltip probe item %d: known=%s"):format(sid, yn(ItemKnown(sid))))
		tt:Hide()
		if tt.SetItemByID then
			pcall(tt.SetItemByID, tt, sid)
			Routes:Print(("    probe SetItemByID -> lines=%d"):format(TooltipLineCount()))
		else
			Routes:Print("    probe SetItemByID: absent")
		end
		tt:Hide()
		if tt.ProcessInfo then
			local info = ItemTooltipInfo(sid)
			if info then
				pcall(tt.ProcessInfo, tt, info)
				Routes:Print(("    probe ProcessInfo(%s) -> lines=%d"):format(info.getterName, TooltipLineCount()))
			else
				Routes:Print("    probe ProcessInfo: no usable item getter")
			end
		else
			Routes:Print("    probe ProcessInfo: absent")
		end
		tt:Hide()
		if tt.AddItem then
			pcall(tt.AddItem, tt, sid)
			Routes:Print(("    probe AddItem -> lines=%d"):format(TooltipLineCount()))
		else
			Routes:Print("    probe AddItem: absent")
		end
		tt:Hide()
		local link = ItemLinkForID(sid)
		if tt.SetHyperlink then
			pcall(tt.SetHyperlink, tt, link)
			Routes:Print(("    probe SetHyperlink(%s) -> lines=%d"):format(link:sub(1, 40), TooltipLineCount()))
		elseif type(GameTooltip_SetHyperlink) == "function" then
			pcall(GameTooltip_SetHyperlink, tt, link)
			Routes:Print(("    probe SetHyperlink-global(%s) -> lines=%d"):format(link:sub(1, 40), TooltipLineCount()))
		end
		if type(GameTooltip_SetItemTooltip) == "function" then
			tt:Hide()
			pcall(GameTooltip_SetItemTooltip, tt, sid)
			Routes:Print(("    probe SetItemTooltip-global -> lines=%d"):format(TooltipLineCount()))
		end
		if C_Item and C_Item.GetItemLink and not C_Item.GetItemLocation then
			tt:Hide()
			local ok, directLink = pcall(C_Item.GetItemLink, C_Item, sid)
			if ok and directLink then
				if tt.SetHyperlink then
					pcall(tt.SetHyperlink, tt, directLink)
					Routes:Print(("    probe SetHyperlink(C_Item direct) -> lines=%d"):format(TooltipLineCount()))
				end
			else
				Routes:Print("    probe C_Item.GetItemLink: no link")
			end
		end
		for i = 1, math_max(TooltipLineCount(), 1) do
			Routes:Print(("    line %d: [%s]"):format(i, tostring(TooltipLineText(i))))
		end
	end

	-- Final line: which API found the rank (or NOT FOUND). Placed at the very
	-- end of the output on purpose -- this is the line that matters, and chat
	-- pastes tend to include the tail.
	local function RankSource(prof)
		local target = profName[prof]
		if not target then return nil, "no name" end
		local r = RankFromPrimaryProfessions(target)
		if r then return r, "GetPrimaryProfessionInfo" end
		r = RankFromProfessions(target)
		if r then return r, "GetProfessionInfo" end
		r = RankFromSkillLines(target)
		if r then return r, "GetSkillLineInfo" end
		return nil, "NOT FOUND"
	end
	local hRank, hSrc = RankSource("Herbalism")
	local mRank, mSrc = RankSource("Mining")
	-- If anything is missing, list the raw skill lines this client reports,
	-- so a name mismatch (vs. a genuinely unlearned profession) is visible
	-- in the single pasted line.
	local extra = ""
	if not hRank or not mRank then
		local seen = {}
		if GetNumSkillLines and GetSkillLineInfo then
			local ok, count = pcall(GetNumSkillLines)
			if ok and type(count) == "number" then
				for i = 1, count do
					local ok2, name, isHeader, _icon, rank = pcall(GetSkillLineInfo, i)
					if ok2 and not isHeader and name then
						seen[#seen + 1] = ("%s %s"):format(name, tostring(rank))
					end
				end
			end
		end
		if #seen == 0 and GetNumPrimaryProfessions and GetPrimaryProfessionInfo then
			local ok, count = pcall(GetNumPrimaryProfessions)
			if ok and type(count) == "number" then
				for i = 1, count do
					local ok2, name, _icon, rank = pcall(GetPrimaryProfessionInfo, i)
					if ok2 and name then
						seen[#seen + 1] = ("%s %s"):format(name, tostring(rank))
					end
				end
			end
		end
		if #seen == 0 and GetProfessions and GetProfessionInfo then
			local ok, n = pcall(function() return select("#", GetProfessions()) end)
			if ok and type(n) == "number" then
				for i = 1, n do
					local idx = select(i, GetProfessions())
					local ok2, name, _icon, rank = pcall(GetProfessionInfo, idx)
					if ok2 and name then
						seen[#seen + 1] = ("%s %s"):format(name, tostring(rank))
					end
				end
			end
		end
		extra = "  lines seen: [" .. table.concat(seen, ", ") .. "]"
	end
	Routes:Print(("=== SKILL RESULT: Herbalism=%s [%s]  Mining=%s [%s]%s  (paste THIS line)"):format(
		tostring(hRank), tostring(hSrc), tostring(mRank), tostring(mSrc), extra))
end

-- vim: ts=4 noexpandtab
