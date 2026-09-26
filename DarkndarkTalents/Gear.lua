local _, ns = ...
local L = ns.L

-- Compares the player's gear with top players of the same spec/content:
-- secondary stat distribution, item level, missing enchants, empty sockets.
local Gear = {}
ns.Gear = Gear

local issecret = issecretvalue or function() return false end
local function Safe(v)
	if issecret(v) then return nil end
	return v
end

Gear.STATS = { "crit", "haste", "mastery", "vers" }
local RATING = {
	crit = CR_CRIT_MELEE or 9,
	haste = CR_HASTE_MELEE or 18,
	mastery = CR_MASTERY or 26,
	vers = CR_VERSATILITY_DAMAGE_DONE or 29,
}

-- murlok slot names -> inventory slots
local SLOTS = {
	Head = { 1 }, Shoulders = { 3 }, Back = { 15 }, Chest = { 5 }, Wrist = { 9 },
	Legs = { 7 }, Feet = { 8 }, Rings = { 11, 12 }, ["Main Hand"] = { 16 }, ["Off Hand"] = { 17 },
}
local SLOT_LABEL = { ["Main Hand"] = "SLOT_MainHand", ["Off Hand"] = "SLOT_OffHand" }
local ALL_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

function Gear.SlotLabel(name)
	return L[SLOT_LABEL[name] or ("SLOT_" .. name)]
end

function Gear.Ratings()
	local r, total = {}, 0
	for _, k in ipairs(Gear.STATS) do
		local v = Safe(GetCombatRating(RATING[k])) or 0
		r[k] = v
		total = total + v
	end
	return r, total
end

-- Share of total secondary rating per stat (0-100).
local function Shares(ratings)
	local total = 0
	for _, k in ipairs(Gear.STATS) do total = total + (ratings[k] or 0) end
	local s = {}
	for _, k in ipairs(Gear.STATS) do
		s[k] = total > 0 and math.floor(100 * (ratings[k] or 0) / total + 0.5) or 0
	end
	return s
end
Gear.Shares = Shares

function Gear.ItemLevel()
	local _, equipped = GetAverageItemLevel()
	return Safe(equipped) and math.floor(equipped) or nil
end

-- item:ID:enchant:gem1:gem2:gem3:gem4:...
local function ParseLink(link)
	local body = link and link:match("item:([%-%d:]*)")
	if not body then return nil end
	local f = {}
	for part in (body .. ":"):gmatch("([^:]*):") do f[#f + 1] = part end
	return f
end

local function HasEnchant(slot)
	local f = ParseLink(GetInventoryItemLink("player", slot))
	if not f then return nil end -- empty slot
	local enchant = tonumber(f[2])
	return enchant ~= nil and enchant > 0
end

local function EmptySockets(slot)
	local link = GetInventoryItemLink("player", slot)
	if not link then return 0 end
	local stats = (C_Item and C_Item.GetItemStats or GetItemStats)(link)
	if not stats then return 0 end
	local sockets = 0
	for key, n in pairs(stats) do
		if type(key) == "string" and key:find("^EMPTY_SOCKET_") then sockets = sockets + n end
	end
	local f = ParseLink(link)
	local filled = 0
	for i = 3, 6 do
		if f and tonumber(f[i]) and tonumber(f[i]) > 0 then filled = filled + 1 end
	end
	return math.max(0, sockets - filled)
end

-- Returns a report table for the given content context.
function Gear.Analyze(ctx)
	local _, _, c = ns:GetBuilds(ctx)
	local report = { issues = {}, ctx = ctx }

	local ratings = Gear.Ratings()
	report.mine = Shares(ratings)
	report.ilvl = Gear.ItemLevel()

	if c and c.stats then
		report.priority = c.stats.priority
		local topRatings = c.stats.rating
		if topRatings and next(topRatings) then
			report.top = Shares(topRatings)
		elseif c.stats.pct then
			report.top = Shares(c.stats.pct)
		end
		report.topIlvl = c.ilvl
	end

	if report.top then
		for _, k in ipairs(Gear.STATS) do
			local diff = report.mine[k] - report.top[k]
			if diff <= -12 then
				report.issues[#report.issues + 1] = L.WARN_STAT_LOW:format(L["STAT_" .. k], report.mine[k], report.top[k])
			elseif diff >= 12 then
				report.issues[#report.issues + 1] = L.WARN_STAT_HIGH:format(L["STAT_" .. k], report.mine[k], report.top[k])
			end
		end
	end

	if report.ilvl and report.topIlvl and report.topIlvl - report.ilvl >= 10 then
		report.issues[#report.issues + 1] = L.WARN_ILVL:format(report.topIlvl - report.ilvl)
	end

	if c and c.enchants then
		for slotName, enchant in pairs(c.enchants) do
			for _, slot in ipairs(SLOTS[slotName] or {}) do
				if HasEnchant(slot) == false then
					report.issues[#report.issues + 1] = L.WARN_ENCHANT:format(Gear.SlotLabel(slotName), enchant)
					break
				end
			end
		end
	end

	for _, slot in ipairs(ALL_SLOTS) do
		local empty = EmptySockets(slot)
		if empty > 0 then
			local link = GetInventoryItemLink("player", slot)
			report.issues[#report.issues + 1] = L.WARN_GEM:format(link or ("#" .. slot), empty)
		end
	end

	return report
end
