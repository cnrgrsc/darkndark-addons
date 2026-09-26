local addonName, ns = ...
local L = ns.L

-- Public handle so external profile packs can call Darkndark:RegisterProfile(...)
Darkndark = ns

ns.name = addonName
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
if ns.version:find("@", 1, true) then ns.version = "dev" end

ns.defaults = {
	enabled = true,
	locked = true,
	debug = false,
	visibility = "always", -- always | combat | hostile
	oocAlpha = 1.0,
	updateInterval = 0.05,

	iconSize = 56,
	queueLength = 2,
	queueScale = 0.75,
	spacing = 4,
	direction = "RIGHT",
	showKeybinds = true,
	keybindSize = 14,
	showSwipe = true,
	rangeTint = true,
	usableTint = true,
	glowProcs = true,
	useProfiles = true,
	profileChoice = {}, -- [specID] = profile key
	holdCooldowns = false,

	sounds = {
		kick = true,  -- target starts a cast while your interrupt is ready
		proc = false, -- the main recommendation starts glowing
	},

	cooldowns = {
		enabled = true,
		threshold = 60,
		max = 6,
		iconSize = 38,
		readyOnly = false,
		blacklist = {}, -- [spellID] = true
	},

	defensives = {
		enabled = true,
		max = 5,
		iconSize = 32,
		readyOnly = false,
	},

	interrupt = {
		enabled = true,
		onlyWhenCasting = true,
		iconSize = 44,
	},

	frames = {
		main       = { point = "CENTER", relPoint = "CENTER", x = 0,    y = -170, scale = 1 },
		cooldowns  = { point = "CENTER", relPoint = "CENTER", x = 0,    y = -230, scale = 1 },
		defensives = { point = "CENTER", relPoint = "CENTER", x = 0,    y = -275, scale = 1 },
		interrupt  = { point = "CENTER", relPoint = "CENTER", x = -110, y = -170, scale = 1 },
	},
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

function ns:CopyTable(src)
	local t = {}
	for k, v in pairs(src) do
		t[k] = type(v) == "table" and self:CopyTable(v) or v
	end
	return t
end

function ns:Print(msg, ...)
	if select("#", ...) > 0 then msg = msg:format(...) end
	print("|cffa335eeDarkndark|r: " .. tostring(msg))
end

function ns:Debug(msg, ...)
	if not (self.db and self.db.debug) then return end
	self:Print("|cff999999" .. msg .. "|r", ...)
end

---------------------------------------------------------------------------
-- Event bus: several modules can listen to the same event.
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
local unitEvents = {}

function ns:RegisterEvent(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

-- Unit events get their own frame per (event, unit) pair so RegisterUnitEvent filters work.
function ns:RegisterUnitEvent(event, unit, fn)
	local key = event .. ":" .. unit
	local f = unitEvents[key]
	if not f then
		f = CreateFrame("Frame")
		f.fns = {}
		f:RegisterUnitEvent(event, unit)
		f:SetScript("OnEvent", function(self, ...)
			for i = 1, #self.fns do self.fns[i](...) end
		end)
		unitEvents[key] = f
	end
	table.insert(f.fns, fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do list[i](event, ...) end
end)

-- Simple callback bus between modules (e.g. "LAYOUT_CHANGED", "SPELLS_CHANGED").
local callbacks = {}
function ns:On(name, fn)
	callbacks[name] = callbacks[name] or {}
	table.insert(callbacks[name], fn)
end

function ns:Fire(name, ...)
	local list = callbacks[name]
	if not list then return end
	for i = 1, #list do list[i](...) end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= addonName then return end
	DarkndarkDB = DarkndarkDB or {}
	MergeDefaults(DarkndarkDB, ns.defaults)
	ns.db = DarkndarkDB
	ns:Fire("DB_READY")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
	ns:Fire("LOGIN")
	ns:Print(L.LOADED, ns.version)
end)

function ns:SetLocked(locked)
	self.db.locked = locked and true or false
	self:Fire("LOCK_CHANGED", self.db.locked)
	self:Print(self.db.locked and L.LOCKED or L.UNLOCKED)
end

function ns:SetEnabled(enabled)
	self.db.enabled = enabled and true or false
	self:Fire("LAYOUT_CHANGED")
	self:Print(self.db.enabled and L.ENABLED or L.DISABLED)
end

function ns:ResetPositions()
	self.db.frames = self:CopyTable(self.defaults.frames)
	self:Fire("LAYOUT_CHANGED")
	self:Print(L.POSITIONS_RESET)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_DARKNDARK1 = "/dnd"
SLASH_DARKNDARK2 = "/darkndark"
SlashCmdList.DARKNDARK = function(input)
	local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "lock" then
		ns:SetLocked(true)
	elseif cmd == "unlock" or cmd == "move" then
		ns:SetLocked(false)
	elseif cmd == "toggle" then
		ns:SetEnabled(not ns.db.enabled)
	elseif cmd == "config" or cmd == "options" or cmd == "opt" then
		ns:OpenOptions()
	elseif cmd == "reset" then
		ns:ResetPositions()
	elseif cmd == "scale" then
		local v = tonumber(arg)
		if v then
			ns:SetFrameScale("main", v)
		end
	elseif cmd == "probe" then
		ns:RunProbe()
	elseif cmd == "debug" then
		ns.db.debug = not ns.db.debug
		ns:Fire("LAYOUT_CHANGED")
		ns:Print("debug: %s", tostring(ns.db.debug))
	elseif cmd == "cdreset" then
		wipe(ns.db.cooldowns.blacklist)
		ns:Fire("SPELLS_CHANGED")
		ns:Print(L.CD_RESET)
	else
		ns:Print(L.HELP_HEADER)
		for _, k in ipairs({ "HELP_LOCK", "HELP_TOGGLE", "HELP_CONFIG", "HELP_RESET", "HELP_SCALE", "HELP_PROBE", "HELP_DEBUG" }) do
			print("  " .. L[k])
		end
	end
end

-- Blizzard's addon compartment (the addon list button on the minimap).
function Darkndark_OnAddonCompartmentClick()
	ns:OpenOptions()
end
