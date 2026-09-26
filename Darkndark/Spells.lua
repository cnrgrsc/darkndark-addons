local _, ns = ...
local U = ns.U
local issecret = U.issecret

-- Secret-safe spell state. Every query returns true / false / nil (unknown).
-- Results are memoised per engine tick so the queue can ask many times cheaply.
local S = {}
ns.Spells = S

local GCD_SPELL = 61304

S.procs = {}          -- [spellID] = true while the spell glows
S.cdSerial = 0        -- bumps on every cooldown change; lets icons refresh swipes lazily
S.baseCD = {}         -- [spellID] = base cooldown in seconds (learned out of combat)
S.rotation = {}       -- Blizzard rotation spell list for the current spec
S.rotationSet = {}
S.specID = nil
S.class = select(2, UnitClass("player"))

local memoReady, memoUsable, memoNoMana, memoRange = {}, {}, {}, {}
local UNKNOWN = {} -- sentinel so nil results are memoised too

function S:BeginTick()
	wipe(memoReady); wipe(memoUsable); wipe(memoNoMana); wipe(memoRange)
end

local function memo(t, id, v)
	t[id] = (v == nil) and UNKNOWN or v
	return v
end

local function recall(t, id)
	local v = t[id]
	if v == UNKNOWN then return true, nil end
	if v ~= nil then return true, v end
	return false
end

---------------------------------------------------------------------------
-- Basic info
---------------------------------------------------------------------------
function S.Texture(id)
	if not id then return nil end
	local tex = C_Spell.GetSpellTexture(id)
	return U.Safe(tex)
end

function S.Name(id)
	return id and U.Safe(C_Spell.GetSpellName(id)) or nil
end

function S.IsKnown(id)
	if U.IsPlayerSpell(id) then return true end
	-- Override spells (e.g. talent replacements) are not always "known" by ID.
	local base = C_Spell.GetBaseSpell and U.Try(C_Spell.GetBaseSpell, id)
	if base and base ~= id and U.IsPlayerSpell(base) then return true end
	return false
end

function S.Override(id)
	if not (id and C_Spell.GetOverrideSpell) then return id end
	local o = U.Try(C_Spell.GetOverrideSpell, id)
	return o or id
end

function S.LearnBaseCooldown(id)
	if S.baseCD[id] ~= nil or not GetSpellBaseCooldown then return end
	local ok, ms = pcall(GetSpellBaseCooldown, id)
	ms = ok and U.Safe(ms) or nil
	if ms then S.baseCD[id] = ms / 1000 end
end

---------------------------------------------------------------------------
-- Readiness: uses the NeverSecret isActive / isOnGCD flags from 12.0.
---------------------------------------------------------------------------
function S.GCDActive()
	local ok, info = pcall(C_Spell.GetSpellCooldown, GCD_SPELL)
	if not ok or not info then return false end
	return U.Bool(info.isActive) == true
end

function S.IsReady(id)
	local hit, v = recall(memoReady, id)
	if hit then return v end

	local ok, info = pcall(C_Spell.GetSpellCooldown, id)
	if not ok or not info then return memo(memoReady, id, true) end

	local active = info.isActive
	if active == nil or issecret(active) then
		-- Older client without the flags: fall back to numbers if readable.
		local dur = U.Safe(info.duration)
		if dur == nil then return memo(memoReady, id, nil) end
		if dur == 0 then return memo(memoReady, id, true) end
		local g = U.Safe((C_Spell.GetSpellCooldown(GCD_SPELL) or {}).duration)
		return memo(memoReady, id, g ~= nil and dur <= g + 0.01)
	end

	if not active then return memo(memoReady, id, true) end
	if U.Bool(info.isOnGCD) then return memo(memoReady, id, true) end

	-- isOnGCD is only trustworthy right after SPELL_UPDATE_COOLDOWN; if the
	-- GCD is rolling and this spell has no real cooldown, it's ready.
	local base = S.baseCD[id]
	if base == 0 and S.GCDActive() then return memo(memoReady, id, true) end
	return memo(memoReady, id, false)
end

function S.IsUsable(id)
	local hit, v = recall(memoUsable, id)
	if hit then return v, (select(2, recall(memoNoMana, id))) end
	local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, id)
	if not ok then
		memo(memoNoMana, id, nil)
		return memo(memoUsable, id, nil), nil
	end
	memo(memoNoMana, id, U.Bool(noMana))
	return memo(memoUsable, id, U.Bool(usable)), U.Bool(noMana)
end

function S.InRange(id, unit)
	unit = unit or "target"
	if unit == "target" then
		local hit, v = recall(memoRange, id)
		if hit then return v end
	end
	if not UnitExists(unit) then return nil end
	local ok, r = pcall(C_Spell.IsSpellInRange, id, unit)
	r = ok and U.Bool(r) or nil
	if unit == "target" then memo(memoRange, id, r) end
	return r
end

function S.IsProc(id)
	if S.procs[id] then return true end
	local f = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
	if f then
		local ok, v = pcall(f, id)
		if ok and U.Bool(v) then return true end
	end
	return false
end

-- Can the player press this right now? nil (unknown) counts as "yes" so we
-- never hide a valid suggestion just because data is restricted.
function S.IsCastable(id)
	if S.IsReady(id) == false then return false end
	if S.IsUsable(id) == false then return false end
	if S.InRange(id) == false then return false end
	return true
end

function S.Charges(id)
	local ok, c = pcall(C_Spell.GetSpellCharges, id)
	if not ok or issecret(c) or not c then return nil end
	return U.Safe(c.currentCharges), U.Safe(c.maxCharges)
end

function S.Power(powerType)
	return U.Try(UnitPower, "player", powerType)
end

function S.PowerMax(powerType)
	return U.Try(UnitPowerMax, "player", powerType)
end

-- Player aura: true/false when readable, nil when the aura is secret.
function S.Aura(id)
	if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
	local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
	if not ok or issecret(a) then return nil end
	if a == nil then return false end
	return true, U.Safe(a.applications)
end

-- Hostile units in combat with visible nameplates (AoE heuristics).
function S.EnemyCount()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or not plates then return nil end
	local n = 0
	for _, plate in ipairs(plates) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit and not issecret(unit) then
			if U.Bool(UnitCanAttack("player", unit)) and U.Bool(UnitAffectingCombat(unit)) then
				n = n + 1
			end
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Rotation list / spec tracking
---------------------------------------------------------------------------
function S:RefreshRotation()
	wipe(self.rotation)
	wipe(self.rotationSet)
	self.specID = U.GetSpecID()
	if C_AssistedCombat and C_AssistedCombat.GetRotationSpells then
		local ok, list = pcall(C_AssistedCombat.GetRotationSpells)
		if ok and type(list) == "table" then
			for _, id in ipairs(list) do
				if not issecret(id) and not self.rotationSet[id] then
					self.rotation[#self.rotation + 1] = id
					self.rotationSet[id] = true
				end
			end
		end
	end
	if not InCombatLockdown() then
		for _, id in ipairs(self.rotation) do S.LearnBaseCooldown(id) end
	end
	ns:Fire("SPELLS_CHANGED")
end

local refresh = U.Debounce(0.3, function() S:RefreshRotation() end)

for _, e in ipairs({ "SPELLS_CHANGED", "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_TALENT_UPDATE",
	"TRAIT_CONFIG_UPDATED", "PLAYER_ENTERING_WORLD" }) do
	ns:RegisterEvent(e, refresh)
end

ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	-- Learn base cooldowns that were secret during combat.
	for _, id in ipairs(S.rotation) do S.LearnBaseCooldown(id) end
end)

ns:RegisterEvent("SPELL_UPDATE_COOLDOWN", function()
	S.cdSerial = S.cdSerial + 1
end)
ns:RegisterEvent("SPELL_UPDATE_CHARGES", function()
	S.cdSerial = S.cdSerial + 1
end)

ns:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, id)
	if id and not issecret(id) then S.procs[id] = true end
end)
ns:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, id)
	if id and not issecret(id) then S.procs[id] = nil end
end)
