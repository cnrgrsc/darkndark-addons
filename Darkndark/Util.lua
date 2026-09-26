local _, ns = ...

-- Secret-value helpers. Any value that may be secret during combat must pass
-- through here before we compare, do arithmetic, or branch on it; touching a
-- secret directly raises a Lua error on tainted (addon) code paths.
local U = {}
ns.U = U

local issecretvalue = issecretvalue or function() return false end
U.issecret = issecretvalue

-- Returns v, or nil when v is secret.
function U.Safe(v)
	if issecretvalue(v) then return nil end
	return v
end

-- Returns a plain boolean, or nil when unknown/secret.
function U.Bool(v)
	if v == nil or issecretvalue(v) then return nil end
	return v and true or false
end

-- Calls fn(...) protected and returns its first result made secret-safe.
function U.Try(fn, ...)
	if not fn then return nil end
	local ok, v = pcall(fn, ...)
	if not ok then return nil end
	return U.Safe(v)
end

-- Number of values a function returns (safe way to detect "returned anything"
-- without testing possibly-secret values).
function U.Count(...)
	return select("#", ...)
end

function U.Clamp(v, lo, hi)
	if v < lo then return lo elseif v > hi then return hi end
	return v
end

-- Compatibility shims for APIs that moved between namespaces.
function U.GetSpecializationIndex()
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		return C_SpecializationInfo.GetSpecialization()
	end
	return GetSpecialization and GetSpecialization()
end

function U.GetSpecID()
	local idx = U.GetSpecializationIndex()
	if not idx then return nil end
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
		return (C_SpecializationInfo.GetSpecializationInfo(idx))
	end
	return GetSpecializationInfo and (GetSpecializationInfo(idx))
end

function U.IsPlayerSpell(spellID)
	if not spellID then return false end
	if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		if C_SpellBook.IsSpellKnown(spellID) then return true end
		if Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
			and C_SpellBook.IsSpellKnown(spellID, Enum.SpellBookSpellBank.Pet) then
			return true
		end
	end
	return false
end

function U.GetActionBarPage()
	if C_ActionBar and C_ActionBar.GetActionBarPage then return C_ActionBar.GetActionBarPage() end
	return GetActionBarPage and GetActionBarPage() or 1
end

function U.GetBonusBarOffset()
	if C_ActionBar and C_ActionBar.GetBonusBarOffset then return C_ActionBar.GetBonusBarOffset() end
	return GetBonusBarOffset and GetBonusBarOffset() or 0
end

function U.GetActionInfo(slot)
	if C_ActionBar and C_ActionBar.GetActionInfo then return C_ActionBar.GetActionInfo(slot) end
	return GetActionInfo(slot)
end

function U.InCombat()
	return InCombatLockdown() or U.Bool(UnitAffectingCombat("player")) == true
end

-- Restriction state (for diagnostics / display only).
function U.IsRestricted(typeName)
	if not (C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive) then return false end
	local enum = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType[typeName]
	if enum == nil then return false end
	local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive, enum)
	return ok and active or false
end

-- Throttle helper: runs fn at most once per `delay` seconds, trailing edge.
function U.Debounce(delay, fn)
	local pending = false
	return function()
		if pending then return end
		pending = true
		C_Timer.After(delay, function()
			pending = false
			fn()
		end)
	end
end
