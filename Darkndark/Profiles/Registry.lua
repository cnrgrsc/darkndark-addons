local _, ns = ...
local S = ns.Spells

--[[
Spec profiles refine Blizzard's suggestion. A profile is a priority list; the
first rule whose condition passes AND whose spell is castable right now wins.
If no rule fires, Blizzard's suggestion is used.

Usage (from any file, or from a separate addon that depends on Darkndark):

  Darkndark:RegisterProfile(260, {          -- specID (260 = Outlaw Rogue)
      key = "default",
      name = "Outlaw - core",
      author = "you",
      cooldowns = { 13750 },                 -- optional: explicit cooldown bar list
      interrupt = 1766,                       -- optional: override interrupt spell
      priority = {
          -- Spell glowing (proc) -> press it.
          { spell = 185763, when = function(s) return s.proc(185763) end },
          -- 5+ combo points -> finisher. s.power returns nil when secret,
          -- so use the *AtLeast helpers which return nil instead of erroring.
          { spell = 2098, when = function(s) return s.powerAtLeast(Enum.PowerType.ComboPoints, 5) end },
          -- AoE: 3+ enemies nearby.
          { spell = 13877, when = function(s) return s.enemiesAtLeast(3) end },
      },
  })

Condition helpers available on `s`:
  s.specID, s.blizzard (Blizzard's current suggestion), s.inCombat
  s.known(id) s.ready(id) s.usable(id) s.inRange(id) s.proc(id) s.castable(id)
  s.charges(id) -> current, max (nil when secret)
  s.chargesAtLeast(id, n)
  s.power(type), s.powerMax(type), s.powerAtLeast(type, n), s.powerDeficitAtLeast(type, n)
  s.buff(id) -> true/false/nil, s.buffStacksAtLeast(id, n)
  s.enemies(), s.enemiesAtLeast(n)
  s.targetCasting()
A condition returning nil (unknown) is treated as "no".
]]

local P = {}
ns.Profiles = P
P.bySpec = {} -- [specID] = { profile, ... }

function ns:RegisterProfile(specID, def)
	assert(type(specID) == "number", "RegisterProfile: specID must be a number")
	assert(type(def) == "table" and type(def.priority) == "table", "RegisterProfile: def.priority required")
	def.specID = specID
	def.key = def.key or "default"
	def.name = def.name or def.key
	local list = P.bySpec[specID]
	if not list then
		list = {}
		P.bySpec[specID] = list
	end
	for i, existing in ipairs(list) do
		if existing.key == def.key then
			list[i] = def
			return def
		end
	end
	list[#list + 1] = def
	return def
end

function P:GetActive()
	if not ns.db.useProfiles then return nil end
	local specID = S.specID
	local list = specID and self.bySpec[specID]
	if not list or #list == 0 then return nil end
	local choice = ns.db.profileChoice[specID]
	if choice then
		for _, p in ipairs(list) do
			if p.key == choice then return p end
		end
	end
	return list[1]
end

---------------------------------------------------------------------------
-- Condition state passed to rules
---------------------------------------------------------------------------
local function atLeast(v, n)
	if v == nil then return nil end
	return v >= n
end

local state = {}
P.state = state

state.known = S.IsKnown
state.ready = S.IsReady
state.usable = function(id) return (S.IsUsable(id)) end
state.inRange = S.InRange
state.proc = S.IsProc
state.castable = S.IsCastable
state.charges = S.Charges
state.chargesAtLeast = function(id, n) return atLeast((S.Charges(id)), n) end
state.power = S.Power
state.powerMax = S.PowerMax
state.powerAtLeast = function(t, n) return atLeast(S.Power(t), n) end
state.powerDeficitAtLeast = function(t, n)
	local cur, max = S.Power(t), S.PowerMax(t)
	if cur == nil or max == nil then return nil end
	return (max - cur) >= n
end
state.buff = function(id) return (S.Aura(id)) end
state.buffStacksAtLeast = function(id, n)
	local has, stacks = S.Aura(id)
	if has == nil then return nil end
	if not has then return false end
	return atLeast(stacks or 1, n)
end
state.enemies = S.EnemyCount
state.enemiesAtLeast = function(n) return atLeast(S.EnemyCount(), n) end
state.targetCasting = function() return ns.Interrupt and ns.Interrupt.targetCasting or false end

-- Returns spellID, rule for the first rule that fires.
function P:Evaluate(profile, blizzard, exclude)
	state.specID = S.specID
	state.blizzard = blizzard
	state.inCombat = ns.U.InCombat()
	for _, rule in ipairs(profile.priority) do
		local id = rule.spell
		if id and not (exclude and exclude[id]) and S.IsKnown(id) then
			local pass = true
			if rule.when then
				local ok, res = pcall(rule.when, state)
				if not ok then
					ns:Debug("rule error (%s): %s", tostring(id), tostring(res))
					pass = false
				else
					pass = res == true
				end
			end
			if pass and S.IsCastable(id) then
				return id, rule
			end
		end
	end
	return nil
end
