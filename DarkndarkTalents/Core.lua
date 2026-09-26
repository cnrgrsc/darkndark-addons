local addonName, ns = ...
local L = ns.L

DarkndarkTalents = ns

ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
if ns.version:find("@", 1, true) then ns.version = "dev" end

-- Display order of content types.
ns.CONTEXTS = { "mplus", "raid", "solo", "2v2", "3v3", "blitz", "rbg" }

ns.defaults = {
	autoPrompt = true,
	window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 40, scale = 1 },
	gearContext = nil,  -- which content the Gear tab compares against
	custom = {},        -- [specID] = { [ctx] = { code = "...", saved = "date" } }
	applied = {},       -- [configID] = import code last written into that loadout
}

local function MergeDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			MergeDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

function ns:Print(msg, ...)
	if select("#", ...) > 0 then msg = msg:format(...) end
	print("|cffa335eeDarkndark Talents|r: " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Events / callbacks
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}
function ns:RegisterEvent(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		frame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do fn(event, ...) end
end)

local callbacks = {}
function ns:On(name, fn)
	callbacks[name] = callbacks[name] or {}
	table.insert(callbacks[name], fn)
end
function ns:Fire(name, ...)
	for _, fn in ipairs(callbacks[name] or {}) do fn(...) end
end

ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= addonName then return end
	DarkndarkTalentsDB = DarkndarkTalentsDB or {}
	MergeDefaults(DarkndarkTalentsDB, ns.defaults)
	ns.db = DarkndarkTalentsDB
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
	ns:Fire("LOGIN")
	ns:Print(L.LOADED, ns.version)
end)

---------------------------------------------------------------------------
-- Spec helpers
---------------------------------------------------------------------------
function ns:GetSpecID()
	if PlayerUtil and PlayerUtil.GetCurrentSpecID then
		return PlayerUtil.GetCurrentSpecID()
	end
	local idx = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization)()
	return idx and (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo)(idx)
end

function ns:GetSpecName(specID)
	local _, name, _, icon, _, _, className = GetSpecializationInfoByID(specID)
	return name, icon, className
end

-- Data for ctx (raid falls back to M+ until raid data exists).
-- Returns the context table and whether it came from M+.
function ns:GetContextData(ctx, specID)
	specID = specID or self:GetSpecID()
	local spec = self.data and self.data.specs[specID]
	local c = spec and spec.contexts[ctx]
	if not (c and c.builds and #c.builds > 0) and ctx == "raid" and spec then
		return spec.contexts.mplus, true
	end
	return c, false
end

-- Recommended builds from the data only: main, alt (second hero tree).
function ns:GetDataBuilds(ctx, specID)
	local c, fromMplus = self:GetContextData(ctx, specID)
	return c and c.builds and c.builds[1], c and c.builds and c.builds[2], fromMplus
end

-- The player's saved build for ctx, if any.
function ns:GetCustomBuild(ctx, specID)
	specID = specID or self:GetSpecID()
	local custom = self.db.custom[specID] and self.db.custom[specID][ctx]
	return custom and { code = custom.code, hero = L.YOURS, custom = true } or nil
end

-- Ranked top players (with their talent strings) for ctx and the current spec.
function ns:GetPlayers(ctx, specID)
	local c, fromMplus = self:GetContextData(ctx, specID)
	return c and c.players or {}, fromMplus
end

-- Returns { code, hero, share, match, sample, custom = bool } for ctx, and
-- the alternative (second hero tree) build if any.
function ns:GetBuilds(ctx, specID)
	local main, alt, fromMplus = self:GetDataBuilds(ctx, specID)
	local c = self:GetContextData(ctx, specID)
	local custom = self:GetCustomBuild(ctx, specID)
	if custom then
		return custom, main, c, fromMplus
	end
	return main, alt, c, fromMplus
end

---------------------------------------------------------------------------
-- Slash
---------------------------------------------------------------------------
SLASH_DARKNDARKTALENTS1 = "/dndt"
SLASH_DARKNDARKTALENTS2 = "/darkndarktalents"
SlashCmdList.DARKNDARKTALENTS = function(input)
	local cmd = (input or ""):lower():match("^%s*(%S*)")
	if cmd == "gear" then
		ns:ShowWindow("gear")
	elseif cmd == "reset" then
		ns.db.window = CopyTable and CopyTable(ns.defaults.window) or { point = "CENTER", relPoint = "CENTER", x = 0, y = 40, scale = 1 }
		ns:Fire("WINDOW_RESET")
	elseif cmd == "minimap" then
		ns.db.minimap.hide = false
		if DarkndarkMinimap then DarkndarkMinimap:SetHidden(false) end
	elseif cmd == "check" then
		ns.Context:Check(true)
	else
		ns:ToggleWindow()
	end
end
