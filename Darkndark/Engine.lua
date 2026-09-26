local _, ns = ...
local U = ns.U
local S = ns.Spells
local P = ns.Profiles
local issecret = U.issecret

-- Recommendation engine. Layers, highest priority first:
--   1. Spec profile rules (if a profile exists and a rule fires)
--   2. Blizzard Assisted Combat suggestion
--   3. Fallback: first castable spell of Blizzard's rotation list
-- Then predicts the next few castable abilities for the queue.
local E = {}
ns.Engine = E

E.result = { primary = nil, source = nil, queue = {} }

function E:BlizzardSuggestion()
	if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell) then return nil end
	local ok, id = pcall(C_AssistedCombat.GetNextCastSpell, false)
	if not ok or issecret(id) or id == nil then return nil end
	return id
end

function E:IsBlizzardAvailable()
	if not (C_AssistedCombat and C_AssistedCombat.IsAvailable) then return false, "API missing" end
	local ok, available, reason = pcall(C_AssistedCombat.IsAvailable)
	if not ok then return false, "error" end
	return U.Bool(available) == true, U.Safe(reason)
end

-- With "hold cooldowns" on, major/defensive cooldowns are left to the player:
-- they light up on the cooldown bars instead of taking the main icon.
function E:IsHeld(id)
	if not ns.db.holdCooldowns then return false end
	local C = ns.Cooldowns
	return C.set[id] or C.defensiveSet[id] or false
end

-- First castable rotation spell, procs first. `exclude` skips already queued spells.
function E:FirstCastable(exclude)
	local rotation = S.rotation
	for i = 1, #rotation do
		local id = S.Override(rotation[i])
		if not (exclude and exclude[id]) and not self:IsHeld(id) and S.IsProc(id) and S.IsCastable(id) then
			return id
		end
	end
	for i = 1, #rotation do
		local id = S.Override(rotation[i])
		if not (exclude and exclude[id]) and not self:IsHeld(id) and S.IsCastable(id) and S.IsKnown(id) then
			return id
		end
	end
	return nil
end

function E:Compute(queueLength)
	S:BeginTick()
	local res = self.result
	wipe(res.queue)

	local blizz = self:BlizzardSuggestion()
	local profile = P:GetActive()
	local primary, source

	-- Blizzard wants a held cooldown: remember it (the bar glows it) and
	-- recommend the best filler instead.
	res.held = nil
	if blizz and self:IsHeld(blizz) then
		res.held = blizz
		blizz = nil
	end

	if profile then
		primary = P:Evaluate(profile, blizz)
		if primary then source = "profile" end
	end
	if not primary and blizz then
		primary, source = blizz, "blizzard"
	end
	if not primary then
		primary = self:FirstCastable(nil)
		source = primary and "fallback" or nil
	end

	res.primary, res.source, res.profile = primary, source, profile

	if primary and queueLength and queueLength > 0 then
		local used = { [primary] = true }
		local n = 0
		-- A profile override pushes Blizzard's pick to the front of the queue.
		if source == "profile" and blizz and blizz ~= primary then
			n = n + 1
			res.queue[n] = blizz
			used[blizz] = true
		end
		while n < queueLength do
			local nextID
			if profile then nextID = P:Evaluate(profile, blizz, used) end
			nextID = nextID or self:FirstCastable(used)
			if not nextID then break end
			n = n + 1
			res.queue[n] = nextID
			used[nextID] = true
		end
	end

	return res
end
