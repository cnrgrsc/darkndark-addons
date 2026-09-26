local _, ns = ...
local U = ns.U
local S = ns.Spells

-- Detects the class interrupt and tracks whether the target is casting.
-- Cast payloads may be secret, so we rely on the events firing (and on the
-- number of values UnitCastingInfo returns), never on their contents.
local I = {}
ns.Interrupt = I
I.spellID = nil
I.targetCasting = false
I.notInterruptible = false

local CLASS_INTERRUPTS = {
	WARRIOR     = { 6552 },            -- Pummel
	ROGUE       = { 1766 },            -- Kick
	MAGE        = { 2139 },            -- Counterspell
	HUNTER      = { 147362, 187707 },  -- Counter Shot, Muzzle
	DEATHKNIGHT = { 47528 },           -- Mind Freeze
	DEMONHUNTER = { 183752 },          -- Disrupt
	DRUID       = { 106839, 78675 },   -- Skull Bash, Solar Beam
	MONK        = { 116705 },          -- Spear Hand Strike
	PALADIN     = { 96231 },           -- Rebuke
	PRIEST      = { 15487 },           -- Silence
	SHAMAN      = { 57994 },           -- Wind Shear
	WARLOCK     = { 119910, 19647, 132409, 89766 }, -- Command Demon / Spell Lock / Axe Toss
	EVOKER      = { 351338 },          -- Quell
}

function I:Detect()
	self.spellID = nil
	local profile = ns.Profiles:GetActive()
	if profile and profile.interrupt and S.IsKnown(profile.interrupt) then
		self.spellID = profile.interrupt
	else
		for _, id in ipairs(CLASS_INTERRUPTS[S.class] or {}) do
			if S.IsKnown(id) then
				self.spellID = id
				break
			end
		end
	end
	ns:Fire("INTERRUPT_CHANGED")
end

-- Returns (isCasting, nth value) for a cast query on the target. A secret
-- first value still means "a cast exists"; only a plain nil means "no cast".
local function CastQuery(fn, n)
	local function collect(ok, ...)
		if not ok or select("#", ...) == 0 then return false end
		local first = ...
		local casting = U.issecret(first) or first ~= nil
		return casting, (select(n, ...))
	end
	return collect(pcall(fn, "target"))
end

function I:Recheck()
	local casting, castLock = CastQuery(UnitCastingInfo, 8)
	local channel, chanLock = CastQuery(UnitChannelInfo, 7)
	self.targetCasting = casting or channel
	if casting then
		self.notInterruptible = U.Bool(castLock) == true
	elseif channel then
		self.notInterruptible = U.Bool(chanLock) == true
	else
		self.notInterruptible = false
	end
	ns:Fire("TARGET_CAST_CHANGED")
end

local function OnStart()
	I.targetCasting = true
	I:Recheck()
end

local function OnStop()
	-- The cast info can linger for a frame after STOP; re-check next frame.
	C_Timer.After(0, function() I:Recheck() end)
end

ns:On("DB_READY", function()
	for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START" }) do
		ns:RegisterUnitEvent(e, "target", OnStart)
	end
	for _, e in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP",
		"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
		ns:RegisterUnitEvent(e, "target", OnStop)
	end
	ns:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "target", function()
		I.notInterruptible = true
		ns:Fire("TARGET_CAST_CHANGED")
	end)
	ns:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "target", function()
		I.notInterruptible = false
		ns:Fire("TARGET_CAST_CHANGED")
	end)
end)

ns:RegisterEvent("PLAYER_TARGET_CHANGED", function() I:Recheck() end)
ns:On("SPELLS_CHANGED", function() I:Detect() end)
