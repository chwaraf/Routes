-- NodeSkill.lua
-- Shows the minimum profession skill required for herb and mining nodes in
-- the Add Route / Create Taboo lists, colored the same way the profession UI
-- colors gathering:
--   red    - player skill is below the requirement (cannot gather)
--   orange - can gather, guaranteed skill-up
--   yellow - can gather, likely skill-up
--   green  - can gather, unlikely skill-up
--   gray   - can gather, no skill-up left
--
-- The requirement is read from the node item's tooltip line
-- ("Requires <[Expansion] >Herbalism/Mining (N)"). That makes it locale
-- independent and keeps it correct for new nodes/patches without any data
-- table to maintain. Results are cached per item id for the session.
--
-- The tooltip population differs per client generation, so several methods
-- are tried in turn and each result is verified:
--   reworked clients (retail 10.0.2+, modernized classics such as the recent
--   Classic Era / TBC Anniversary) removed AddItem() from GameTooltipTemplate
--   frames; they populate via SetItemByID() or ProcessInfo() + C_TooltipInfo
--   older clients still expose AddItem() / SetHyperlink()
-- If none of them work on a client, the feature silently shows nothing.

local Routes = LibStub("AceAddon-3.0"):GetAddon("Routes", 1)
if not Routes then return end

local GetSpellName = C_Spell and C_Spell.GetSpellName or GetSpellInfo
local math_floor, math_max = math.floor, math.max

-- Base (localized) names of the gathering professions, identified by spell id
local HERB_SPELLS = { 170691, 9134 } -- Herbalism (modern, classic)
local MINE_SPELLS = { 2575 }         -- Mining

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
	profName.Herbalism = baseName(HERB_SPELLS)
	profName.Mining = baseName(MINE_SPELLS)
end

-- Hidden tooltip used to read the requirement line. Frame level 0 keeps it
-- behind the UI (invisible) while it is being populated.
local tt = CreateFrame("GameTooltip", "RoutesNodeSkillTooltip", nil, "GameTooltipTemplate")
tt:SetFrameLevel(0)
tt:ClearAllPoints()
tt:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -2000, -2000)

-- Number of populated lines (NumLines() exists on both tooltip systems;
-- GetNumLines() is the newer alias, kept as a fallback).
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
-- frame's TextLeftN font objects; GetText(line, subline) is the newer alias.
local function TooltipLineText(i)
	local left = tt["TextLeft"..i]
	if not left then
		left = _G[tt:GetName().."TextLeft"..i]
	end
	if left and left.GetText then
		return left:GetText()
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
-- Note: on 10.0+ C_Item.GetItemLink takes an item-location object, not an id.
local function ItemLinkForID(itemID)
	if C_Item and C_Item.GetItemLocation and C_Item.GetItemLink then
		local location = C_Item.GetItemLocation(itemID)
		if location then
			local link = C_Item.GetItemLink(location)
			if link then return link end
		end
	end
	if GetItemLink then
		local link = GetItemLink(itemID)
		if link then return link end
	end
	return ("item:%d:0:0:0:0:0:0:0:0:0:0"):format(itemID)
end

-- Try to populate the hidden tooltip with the item, using whichever method
-- this client generation provides. Each attempt is verified to actually
-- produce lines before it is accepted. Returns true on success.
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

-- One-shot compact diagnostic, printed when no populate strategy works for
-- a known item. Paste this line back to the addon maintainer and the client
-- API surface is identified without any further guessing.
local diagnosed = false
local function DiagnoseFailure(itemID)
	if diagnosed then return end
	diagnosed = true
	local function yn(v) return v and "yes" or "no" end
	local CTI = C_TooltipInfo or {}
	local CI = C_Item or {}
	local hasTextLeft = (tt.TextLeft1 ~= nil or _G[tt:GetName().."TextLeft1"] ~= nil)
	Routes:Print(("skill-suffix unavailable: frame{{SetItemByID=%s ProcessInfo=%s AddItem=%s SetHyperlink=%s NumLines=%s GetNumLines=%s TextLeft1=%s}} api{{C_TooltipInfo=%s ByLocation=%s ByID=%s C_Item=%s GetItemLocation=%s GetItemLink=%s GetItemLink-global=%s SetItemTooltip-global=%s}} item %d known=%s"):format(
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
		local ok, err = pcall(tt.SetItemByID, tt, itemID)
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

-- itemID .. ":" .. prof -> { req = number, line = string } or false (no
-- requirement line). The item's tooltip only carries the requirement for the
-- profession that actually gathers it, so lookups are per profession.
local skillCache = {}
-- Returns the required skill and the tooltip line it was read from.
local function NodeRequiredSkill(itemID, prof)
	if type(itemID) ~= "number" or itemID <= 0 then return nil end
	local key = itemID .. ":" .. prof
	local cached = skillCache[key]
	if cached ~= nil then
		if type(cached) == "table" then return cached.req, cached.line end
		return nil
	end
	local req, line = nil, nil
	if PopulateItemTooltip(itemID) then
		RefreshProfNames()
		local name = profName[prof]
		if name then
			for i = 1, TooltipLineCount() do
				local text = TooltipLineText(i)
				if text and LineMentionsProfession(text, name) then
					-- "Requires <[Expansion] >Herbalism/Mining (N)"
					local num = text:match("(%d+)%)%s*$")
					if num then
						req = tonumber(num)
						line = text
						break
					end
				end
			end
		end
	end
	tt:Hide()
	if req then
		skillCache[key] = { req = req, line = line }
		return req, line
	else
		skillCache[key] = false
		return nil
	end
end

-- The player's skill on the exact profession line named in the tooltip line
-- (per-expansion lines on modern clients, the base line on classic).
-- Returns nil when the player does not have that profession.
local function PlayerSkillForLine(line, prof)
	if not line or not prof then return nil end
	-- Modern clients: match the exact expansion line (e.g. "The War Within Herbalism")
	if C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines
		and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
		for _, lineID in pairs(C_TradeSkillUI.GetAllProfessionTradeSkillLines()) do
			local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(lineID)
			if info and info.professionName and line:find(info.professionName, 1, true) then
				return info.skillLevel
			end
		end
	end
	-- Fallback (and classic path): the base profession entry. Match on the
	-- full name or the base profession name, since some requirement lines
	-- carry no expansion prefix ("Requires Herbalism (75)").
	local base = profName[prof]
	for i = 1, 6 do
		local idx = select(i, GetProfessions())
		if idx then
			local name, icon, rank = GetProfessionInfo(idx)
			if name and (line:find(name, 1, true) or LineMentionsProfession(line, base or "")) then
				return rank
			end
		end
	end
	return nil
end

local function ColorFor(playerSkill, req)
	if playerSkill < req then return "ff3333" end   -- red: cannot gather
	local diff = playerSkill - req
	if diff < 25 then return "ff8040" end           -- orange: guaranteed skill-up
	if diff < 50 then return "ffff00" end           -- yellow: likely skill-up
	if diff < 100 then return "40cc40" end          -- green: unlikely skill-up
	return "808080"                                 -- gray: no skill-up left
end

-- Routes:GetNodeSkillSuffix(prof, itemID)
-- prof:    "Herbalism" or "Mining"
-- itemID:  the gatherable node's item id
-- Returns a display suffix like " |cffff8040(75)|r" to append after the node
-- name, or nil when the requirement is unknown. Uncolored when the player
-- does not have the profession (no skill level to compare against).
function Routes:GetNodeSkillSuffix(prof, itemID)
	if prof ~= "Herbalism" and prof ~= "Mining" then return nil end
	RefreshProfNames()
	if not profName[prof] then return nil end
	local req, line = NodeRequiredSkill(itemID, prof)
	if not req then return nil end
	local playerSkill = PlayerSkillForLine(line, prof)
	if playerSkill then
		return (" |c%s(%d)|r"):format(ColorFor(playerSkill, req), req)
	end
	return (" (%d)"):format(req)
end

--------------------------------------------------------------------
-- Routes:NodeSkillDebug(itemID) - diagnostic for "/routes skilldebug"
-- Reports which tooltip APIs this client exposes and what the lookup finds
-- for the given item (or a default sample), so problems can be diagnosed
-- without a live client here.
function Routes:NodeSkillDebug(itemID)
	local function yn(v) return v and "yes" or "no" end
	local build, major = GetBuildInfo()
	Routes:Print(("NodeSkill debug - client %s (interface %s, project %d)"):format(build, major, WOW_PROJECT_ID or 0))

	-- what the hidden tooltip frame exposes
	Routes:Print(("  frame: SetItemByID=%s ProcessInfo=%s AddItem=%s SetHyperlink=%s NumLines=%s GetNumLines=%s GetText=%s TextLeft1=%s"):format(
		yn(tt.SetItemByID), yn(tt.ProcessInfo), yn(tt.AddItem), yn(tt.SetHyperlink),
		yn(tt.NumLines ~= nil), yn(tt.GetNumLines ~= nil), yn(tt.GetText ~= nil),
		yn(tt.TextLeft1 ~= nil or _G[tt:GetName().."TextLeft1"] ~= nil)))

	-- item data APIs
	local CTI = C_TooltipInfo or {}
	local CI = C_Item or {}
	Routes:Print(("  C_TooltipInfo: ByLocation=%s ByID=%s TooltipData=%s Tooltip=%s"):format(
		yn(CTI.GetItemByLocation ~= nil), yn(CTI.GetItemByID ~= nil),
		yn(CTI.GetItemTooltipData ~= nil), yn(CTI.GetItemTooltip ~= nil)))
	Routes:Print(("  C_Item: GetItemLocation=%s GetItemLink=%s GetItemInfo=%s  GetItemLink(global)=%s"):format(
		yn(CI.GetItemLocation ~= nil), yn(CI.GetItemLink ~= nil), yn(CI.GetItemInfo ~= nil),
		yn(GetItemLink ~= nil)))
	RefreshProfNames()
	Routes:Print(("  profession names: Herbalism=%s Mining=%s  C_TradeSkillUI=%s"):format(
		tostring(profName.Herbalism), tostring(profName.Mining), yn(C_TradeSkillUI ~= nil)))

	-- Sample item: prefer the one given (e.g. /routes skilldebug 2259),
	-- else well-known classic nodes (Kingsblood herb / Tin Vein ore).
	local samples = { itemID, 22595, 22603 }
	for s = 1, #samples do
		local id = samples[s]
		if type(id) == "number" and id > 0 then
			local known
			if CI.GetItemInfo then
				known = CI.GetItemInfo(id) ~= nil
			elseif GetItemInfo then
				known = GetItemInfo(id) ~= nil
			end
			local name
			if known then
				if CI.GetItemInfo then name = CI.GetItemInfo(id) else name = GetItemInfo(id) end
			end
			Routes:Print(("  item %d: known=%s name=%s"):format(id, yn(known), tostring(name)))

			-- frame sanity: can this frame render lines at all?
			tt:Hide()
			if tt.AddLine then
				tt:AddLine("skilldebug sanity line")
				Routes:Print(("    sanity AddLine -> lines=%d text1=[%s]"):format(
					TooltipLineCount(), tostring(TooltipLineText(1))))
			else
				Routes:Print("    sanity AddLine: absent on this frame")
			end
			tt:Hide()

			-- probe each populate strategy separately
			tt:Hide()
			if tt.SetItemByID then
				tt:SetItemByID(id)
				Routes:Print(("    probe SetItemByID -> lines=%d"):format(TooltipLineCount()))
			else
				Routes:Print("    probe SetItemByID: absent")
			end
			tt:Hide()
			if tt.ProcessInfo then
				local info = ItemTooltipInfo(id)
				if info then
					tt:ProcessInfo(info)
					Routes:Print(("    probe ProcessInfo(%s) -> lines=%d"):format(info.getterName, TooltipLineCount()))
				else
					Routes:Print("    probe ProcessInfo: no usable item getter")
				end
			else
				Routes:Print("    probe ProcessInfo: absent")
			end
			tt:Hide()
			if tt.AddItem then
				tt:AddItem(id)
				Routes:Print(("    probe AddItem -> lines=%d"):format(TooltipLineCount()))
			else
				Routes:Print("    probe AddItem: absent")
			end
			tt:Hide()
			if tt.SetHyperlink then
				local link = ItemLinkForID(id)
				tt:SetHyperlink(link)
				Routes:Print(("    probe SetHyperlink -> lines=%d link=[%s]"):format(TooltipLineCount(), link:sub(1, 60)))
			else
				Routes:Print("    probe SetHyperlink: absent")
			end

			local req, line = NodeRequiredSkill(id, "Herbalism")
			Routes:Print(("    result: herbalism req=%s line=[%s]"):format(tostring(req), tostring(line)))
			local req2, line2 = NodeRequiredSkill(id, "Mining")
			Routes:Print(("    result: mining    req=%s line=[%s]"):format(tostring(req2), tostring(line2)))
			break
		end
	end
end

-- vim: ts=4 noexpandtab
