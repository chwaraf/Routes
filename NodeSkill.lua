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

local Routes = LibStub("AceAddon-3.0"):GetAddon("Routes", 1)
if not Routes then return end

local GetSpellName = C_Spell and C_Spell.GetSpellName or GetSpellInfo

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
-- behind the UI (invisible) while AddItem() is populating it.
local tt = CreateFrame("GameTooltip", "RoutesNodeSkillTooltip", nil, "GameTooltipTemplate")
tt:SetFrameLevel(0)
tt:ClearAllPoints()
tt:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -2000, -2000)

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
	tt:Hide()
	tt:AddItem(itemID)
	RefreshProfNames()
	local name = profName[prof]
	if name then
		for i = 1, tt:GetNumLines() do
			local text = tt:GetText(i, 1)
			if text and text:find(name, 1, true) then
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
			if name and (line:find(name, 1, true) or (base and line:find(base, 1, true))) then
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

-- vim: ts=4 noexpandtab
