local _, ns = ...
local U = ns.U
local issecret = U.issecret

-- Resolves spellID -> short key text ("S3", "CF", "M4") by scanning action
-- slots (spells and macros) and matching them to bindings of Blizzard bars and
-- popular bar addons. Rebuilt lazily when bars or bindings change.
local K = {}
ns.Keybinds = K

local slotSpells = {}   -- [slot] = spellID
local spellSlots = {}   -- [spellID] = { slot, ... }
local slotKeys = {}     -- [slot] = key text
local cache = {}        -- [spellID] = key text or false
local dirty = true

-- Blizzard action slot ranges -> binding command prefix.
local BLIZZARD_RANGES = {
	{ 1,   12,  "ACTIONBUTTON",          true },  -- main bar page 1 (paging-aware)
	{ 13,  24,  "ACTIONBUTTON",          true },  -- main bar page 2
	{ 25,  36,  "MULTIACTIONBAR3BUTTON" },        -- right bar
	{ 37,  48,  "MULTIACTIONBAR4BUTTON" },        -- right bar 2
	{ 49,  60,  "MULTIACTIONBAR2BUTTON" },        -- bottom right
	{ 61,  72,  "MULTIACTIONBAR1BUTTON" },        -- bottom left
	{ 73,  132, "ACTIONBUTTON",          true },  -- stance / bonus / skyriding bars
	{ 145, 156, "MULTIACTIONBAR5BUTTON" },
	{ 157, 168, "MULTIACTIONBAR6BUTTON" },
	{ 169, 180, "MULTIACTIONBAR7BUTTON" },
}

local MAX_SLOT = 180

local function Shorten(key)
	if not key or key == "" then return nil end
	key = key:upper()
	key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A"):gsub("META%-", "M")
	key = key:gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD")
	key = key:gsub("MIDDLEMOUSE", "M3"):gsub("BUTTON(%d+)", "M%1")
	key = key:gsub("NUMPADPLUS", "N+"):gsub("NUMPADMINUS", "N-")
	key = key:gsub("NUMPADMULTIPLY", "N*"):gsub("NUMPADDIVIDE", "N/")
	key = key:gsub("NUMPADDECIMAL", "N."):gsub("NUMPAD", "N")
	key = key:gsub("SPACE", "Sp"):gsub("BACKSPACE", "Bs"):gsub("CAPSLOCK", "Cap")
	key = key:gsub("PAGEUP", "PU"):gsub("PAGEDOWN", "PD"):gsub("INSERT", "Ins")
	key = key:gsub("DELETE", "Del"):gsub("HOME", "Hm"):gsub("END", "End")
	return key
end
K.Shorten = Shorten

-- Which slots the main bar currently shows (stance/form/page aware).
local function MainBarRange()
	local page = U.GetActionBarPage() or 1
	local bonus = U.GetBonusBarOffset() or 0
	local first
	if bonus > 0 and page == 1 then
		first = 72 + (bonus - 1) * 12 + 1
	else
		first = (page - 1) * 12 + 1
	end
	return first, first + 11
end

local function AddSlotSpell(slot, spellID)
	if not spellID or issecret(spellID) then return end
	slotSpells[slot] = spellID
	local list = spellSlots[spellID]
	if not list then
		list = {}
		spellSlots[spellID] = list
	end
	list[#list + 1] = slot
end

local function ScanSlots()
	wipe(slotSpells)
	wipe(spellSlots)
	for slot = 1, MAX_SLOT do
		local ok, kind, id, subType = pcall(U.GetActionInfo, slot)
		if ok and not issecret(kind) and kind then
			if kind == "spell" then
				AddSlotSpell(slot, U.Safe(id))
			elseif kind == "macro" then
				-- Depending on client version `id` is either the macro index or,
				-- with subType "spell", the macro's spell. Try both.
				local direct = (subType == "spell") and U.Safe(id) or nil
				local viaMacro = GetMacroSpell and U.Try(GetMacroSpell, id) or nil
				AddSlotSpell(slot, direct)
				if viaMacro ~= direct then AddSlotSpell(slot, viaMacro) end
			end
		end
	end
end

local function BindingFor(command)
	local key = GetBindingKey(command)
	return Shorten(key)
end

local function ScanBlizzardKeys()
	local mainFirst, mainLast = MainBarRange()
	for _, r in ipairs(BLIZZARD_RANGES) do
		local first, last, prefix, paged = r[1], r[2], r[3], r[4]
		for slot = first, last do
			if slotSpells[slot] then
				local visible = not paged or (slot >= mainFirst and slot <= mainLast)
				if visible then
					local idx = ((slot - first) % 12) + 1
					local key = BindingFor(prefix .. idx)
					if key then slotKeys[slot] = key end
				end
			end
		end
	end
end

-- Addon bars: we read each button's action slot and its click binding, and
-- fall back to the button's own HotKey text.
local function ButtonAction(btn)
	local action = btn.action or btn._state_action
	if (not action) and btn.GetAttribute then
		action = btn:GetAttribute("action")
	end
	if issecret(action) or type(action) ~= "number" then return nil end
	return action
end

local function ButtonKey(btn, name)
	for _, suffix in ipairs({ ":Keybind", ":LeftButton", ":HOTKEY" }) do
		local key = GetBindingKey("CLICK " .. name .. suffix)
		if key then return Shorten(key) end
	end
	if type(btn.config) == "table" and type(btn.config.keyBoundTarget) == "string" then
		local key = GetBindingKey(btn.config.keyBoundTarget)
		if key then return Shorten(key) end
	end
	local hk = btn.HotKey
	if hk and hk.GetText then
		local t = hk:GetText()
		if t and not issecret(t) and t ~= "" and t ~= RANGE_INDICATOR then
			return t
		end
	end
	return nil
end

local ADDON_BUTTONS = {
	function(add) for i = 1, 180 do add("BT4Button" .. i) end end,                       -- Bartender4
	function(add) for b = 1, 15 do for i = 1, 12 do add("ElvUI_Bar" .. b .. "Button" .. i) end end end, -- ElvUI
	function(add) for i = 1, 180 do add("DominosActionButton" .. i) end end,              -- Dominos
}

local function ScanAddonKeys()
	local function add(name)
		local btn = _G[name]
		if not btn or not btn.IsVisible or not btn:IsVisible() then return end
		local slot = ButtonAction(btn)
		if slot and slotSpells[slot] and not slotKeys[slot] then
			local key = ButtonKey(btn, name)
			if key then slotKeys[slot] = key end
		end
	end
	for _, scan in ipairs(ADDON_BUTTONS) do scan(add) end
end

function K:Rebuild()
	wipe(slotKeys)
	wipe(cache)
	ScanSlots()
	ScanAddonKeys()     -- addon bars first: they reflect what is actually on screen
	ScanBlizzardKeys()
	dirty = false
end

function K:Get(spellID)
	if not spellID then return nil end
	if dirty then self:Rebuild() end
	local c = cache[spellID]
	if c ~= nil then return c or nil end

	local found
	local candidates = { spellID }
	local base = C_Spell.GetBaseSpell and U.Try(C_Spell.GetBaseSpell, spellID)
	if base and base ~= spellID then candidates[#candidates + 1] = base end
	local over = ns.Spells.Override(spellID)
	if over and over ~= spellID then candidates[#candidates + 1] = over end

	for _, id in ipairs(candidates) do
		local slots = spellSlots[id]
		if not slots and C_ActionBar.FindSpellActionButtons then
			local ok, found_ = pcall(C_ActionBar.FindSpellActionButtons, id)
			if ok and type(found_) == "table" then slots = found_ end
		end
		if slots then
			for _, slot in ipairs(slots) do
				if not issecret(slot) and slotKeys[slot] then
					found = slotKeys[slot]
					break
				end
			end
		end
		if found then break end
	end

	cache[spellID] = found or false
	return found
end

local markDirty = U.Debounce(0.2, function()
	dirty = true
	ns:Fire("KEYBINDS_CHANGED")
end)

for _, e in ipairs({ "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
	"UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD",
	"ACTIONBAR_HIDEGRID", "UPDATE_MACROS", "SPELLS_CHANGED" }) do
	ns:RegisterEvent(e, markDirty)
end
