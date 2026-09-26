local _, ns = ...
local U = ns.U
local S = ns.Spells

-- Builds two lists for the current spec, out of combat only (base cooldowns
-- may be secret in combat):
--   list       offensive/major cooldowns, found by scanning the spellbook for
--              active spells whose base cooldown is at least the threshold
--   defensives known personal defensives from a curated table
local C = {}
ns.Cooldowns = C
C.list = {}
C.set = {}
C.defensives = {}
C.defensiveSet = {}

local MAX_BASE_CD = 600

-- Personal defensives per class. Unknown or unlearned IDs are simply skipped.
local DEFENSIVES = {
	WARRIOR     = { 871, 118038, 184364, 97462, 23920, 12975 },
	ROGUE       = { 5277, 31224, 185311, 1966 },
	MAGE        = { 45438, 55342, 342245, 414658, 11426, 235313, 235450 },
	HUNTER      = { 186265, 109304, 264735 },
	DEATHKNIGHT = { 48792, 48707, 49039, 55233, 51052 },
	DEMONHUNTER = { 198589, 196718, 187827, 204021, 203720 },
	DRUID       = { 22812, 61336, 108238, 102342 },
	MONK        = { 115203, 122470, 122278, 122783, 115176 },
	PALADIN     = { 642, 498, 184662, 31850, 86659, 403876, 1022 },
	PRIEST      = { 19236, 47585, 586, 33206, 47788 },
	SHAMAN      = { 108271, 108281, 198103 },
	WARLOCK     = { 104773, 108416 },
	EVOKER      = { 363916, 374348, 374227 },
}

local ALL_DEFENSIVES = {}
for _, ids in pairs(DEFENSIVES) do
	for _, id in ipairs(ids) do ALL_DEFENSIVES[id] = true end
end

local function IsExcluded(id)
	if ns.db.cooldowns.blacklist[id] then return true end
	if ns.Interrupt and id == ns.Interrupt.spellID then return true end
	return false
end

local function Add(list, set, id)
	if not id or set[id] or IsExcluded(id) then return end
	set[id] = true
	list[#list + 1] = id
end

local function ScanSpellbook()
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
	local threshold = ns.db.cooldowns.threshold

	for line = 2, C_SpellBook.GetNumSpellBookSkillLines() do -- line 1 is "General"
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.shouldHide and not info.isGuild and not info.offSpecID then
			local first = info.itemIndexOffset + 1
			local last = info.itemIndexOffset + info.numSpellBookItems
			for i = first, last do
				local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
				if item and item.spellID and not item.isPassive and not item.isOffSpec
					and (spellType == nil or item.itemType == spellType) then
					local id = item.spellID
					S.LearnBaseCooldown(id)
					local cd = S.baseCD[id]
					if cd and cd >= threshold and cd <= MAX_BASE_CD and U.IsPlayerSpell(id)
						and not ALL_DEFENSIVES[id] then
						Add(C.list, C.set, id)
					end
				end
			end
		end
	end
end

function C:Rebuild()
	if InCombatLockdown() then
		self.pending = true
		return
	end
	self.pending = false
	wipe(self.list); wipe(self.set)
	wipe(self.defensives); wipe(self.defensiveSet)

	local profile = ns.Profiles:GetActive()
	if profile and profile.cooldowns then
		for _, id in ipairs(profile.cooldowns) do
			if S.IsKnown(id) then Add(self.list, self.set, id) end
		end
	else
		ScanSpellbook()
	end

	local defs = (profile and profile.defensives) or DEFENSIVES[S.class] or {}
	for _, id in ipairs(defs) do
		if S.IsKnown(id) then Add(self.defensives, self.defensiveSet, id) end
	end

	ns:Fire("COOLDOWNS_CHANGED")
end

function C:Hide(id)
	ns.db.cooldowns.blacklist[id] = true
	ns:Print(ns.L.CD_HIDDEN, S.Name(id) or tostring(id))
	self:Rebuild()
end

ns:On("SPELLS_CHANGED", function() C:Rebuild() end)
ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if C.pending then C:Rebuild() end
end)
