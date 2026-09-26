local _, ns = ...
local L = ns.L

-- Detects which content the player is in and offers to switch builds.
local Context = {}
ns.Context = Context

local MYTHIC_KEYSTONE_DIFFICULTY = 8

local function Call(t, fn, ...)
	if t and t[fn] then
		local ok, v = pcall(t[fn], ...)
		if ok then return v end
	end
	return nil
end

-- Returns a context key ("mplus", "raid", "solo", "2v2", "3v3", "blitz", "rbg") or nil.
function Context:Detect()
	local _, instanceType = IsInInstance()
	if instanceType == "arena" then
		if Call(C_PvP, "IsSoloShuffle") then return "solo" end
		local size = math.max(GetNumGroupMembers() or 0, GetNumArenaOpponentSpecs and GetNumArenaOpponentSpecs() or 0)
		if size >= 3 then return "3v3" end
		return "2v2"
	elseif instanceType == "pvp" then
		if Call(C_PvP, "IsSoloRBG") then return "blitz" end
		return "rbg"
	elseif instanceType == "raid" then
		return "raid"
	elseif instanceType == "party" then
		return "mplus"
	end
	return nil
end

function Context:IsKeystoneActive()
	local _, _, difficulty = GetInstanceInfo()
	return difficulty == MYTHIC_KEYSTONE_DIFFICULTY
end

-- Should we offer a switch for ctx? Not when the build is already active.
local function NeedsSwitch(ctx)
	local build = ns:GetBuilds(ctx)
	if not build or not build.code then return false end
	if ns.Loadout.ActiveName() == L["LOADOUT_" .. ctx] then return false end
	local similarity = ns.Loadout.Similarity(build.code)
	return not similarity or similarity < 95
end

local lastOffered

function Context:Check(force)
	if not ns.db then return end
	local ctx = self:Detect()
	if not ctx then
		lastOffered = nil
		return
	end
	if InCombatLockdown() then return end
	-- A running keystone locks talents; don't nag.
	if ctx == "mplus" and self:IsKeystoneActive() and not force then return end
	local key = ctx .. ":" .. tostring(select(8, GetInstanceInfo()))
	if not force and (not ns.db.autoPrompt or lastOffered == key) then return end
	lastOffered = key
	if NeedsSwitch(ctx) then
		ns:ShowPrompt(ctx)
	end
end

local function Schedule()
	C_Timer.After(2, function() Context:Check(false) end)
end

ns:RegisterEvent("PLAYER_ENTERING_WORLD", Schedule)
ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", Schedule)
ns:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS", Schedule)
