local _, ns = ...
local L = ns.L

-- Full action bar + keybind layout for the current build.
--
-- Every bar addon (Blizzard, ElvUI, Bartender4, Dominos) ultimately shows the
-- same numbered action slots; only their buttons and binding commands differ.
-- So we scan the visible buttons, learn each one's slot and binding command,
-- place spells into those slots and bind template keys to those commands.
-- Macros, items, mounts etc. are never touched. Everything is backed up first.
local AB = {}
ns.ActionBars = AB

local issecret = issecretvalue or function() return false end
local function Safe(v)
	if issecret(v) then return nil end
	return v
end

-- Default key template per spell group (editable via SavedVariables).
AB.DEFAULT_KEYS = {
	core       = { "1", "2", "3", "4", "5", "6", "R", "F", "T" },
	cooldowns  = { "SHIFT-1", "SHIFT-2", "SHIFT-3", "SHIFT-4", "SHIFT-5", "SHIFT-6" },
	defensives = { "CTRL-1", "CTRL-2", "CTRL-3", "CTRL-4", "CTRL-5" },
	interrupt  = { "G" },
	utility    = { "Z", "X", "C", "V", "SHIFT-R", "SHIFT-F", "SHIFT-T", "SHIFT-G" },
}
AB.GROUP_ORDER = { "core", "cooldowns", "defensives", "interrupt", "utility", "rest" }

-- Saved settings (merged into the DB on load).
ns.defaults.layout = {
	auto = true,        -- lay out bars after a build is applied
	confirmed = false,  -- player agreed once to automatic layouts
	keys = AB.DEFAULT_KEYS,
	backup = {},        -- [specID] = { oldest, ..., newest } (max 5)
	placed = {},        -- [specID] = { [slot] = spellID } spells this addon put on bars
}
local MAJOR_CD = 60

---------------------------------------------------------------------------
-- Button discovery
---------------------------------------------------------------------------
local BLIZZARD = {
	{ "ActionButton", "ACTIONBUTTON" },
	{ "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON" },
	{ "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON" },
	{ "MultiBarRightButton", "MULTIACTIONBAR3BUTTON" },
	{ "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON" },
	{ "MultiBar5Button", "MULTIACTIONBAR5BUTTON" },
	{ "MultiBar6Button", "MULTIACTIONBAR6BUTTON" },
	{ "MultiBar7Button", "MULTIACTIONBAR7BUTTON" },
}

local function ButtonSlot(btn)
	local slot = btn.action or btn._state_action
	if slot == nil and btn.GetAttribute then slot = btn:GetAttribute("action") end
	if issecret(slot) or type(slot) ~= "number" or slot < 1 or slot > 180 then return nil end
	return slot
end

local function ButtonCommand(btn, name, fallbackPrefix, index)
	if type(btn.config) == "table" and type(btn.config.keyBoundTarget) == "string" then return btn.config.keyBoundTarget end
	if type(btn.bindingAction) == "string" then return btn.bindingAction end
	if fallbackPrefix then return fallbackPrefix .. index end
	if name:find("^BT4Button") then return "CLICK " .. name .. ":Keybind" end
	if name:find("^DominosActionButton") then return "CLICK " .. name .. ":HOTKEY" end
	return "CLICK " .. name .. ":LeftButton"
end

-- Visible action buttons in layout order: { name, slot, command }.
function AB.ScanButtons()
	local list, seenSlot = {}, {}
	local function add(name, prefix, index)
		local btn = _G[name]
		if not (btn and btn.IsVisible and btn:IsVisible()) then return end
		local slot = ButtonSlot(btn)
		if not slot or seenSlot[slot] then return end
		seenSlot[slot] = true
		list[#list + 1] = { name = name, slot = slot, command = ButtonCommand(btn, name, prefix, index) }
	end
	-- Addon bars first: when present they are what the player actually sees.
	for i = 1, 180 do add("BT4Button" .. i) end
	for b = 1, 15 do for i = 1, 12 do add("ElvUI_Bar" .. b .. "Button" .. i) end end
	for i = 1, 180 do add("DominosActionButton" .. i) end
	for _, bar in ipairs(BLIZZARD) do
		for i = 1, 12 do add(bar[1] .. i, bar[2], i) end
	end
	return list
end

---------------------------------------------------------------------------
-- Spell grouping
---------------------------------------------------------------------------
local function IsKnown(id)
	if IsPlayerSpell and IsPlayerSpell(id) then return true end
	return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) or false
end

local function BaseCooldown(id)
	if not GetSpellBaseCooldown then return 0 end
	local ms = Safe((GetSpellBaseCooldown(id)))
	return (ms or 0) / 1000
end

-- All active class/spec spells from the spellbook (no General tab, no passives).
local function SpellbookSpells()
	local out, seen = {}, {}
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
	for line = 2, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.shouldHide and not info.offSpecID then
			for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
				local id = item and item.spellID
				if id and not item.isPassive and not item.isOffSpec and not seen[id] then
					seen[id] = true
					out[#out + 1] = id
				end
			end
		end
	end
	return out, seen
end

-- Returns { core = {...}, cooldowns = {...}, ... } of spell IDs.
function AB.GroupSpells()
	local class = select(2, UnitClass("player"))
	local groups = { core = {}, cooldowns = {}, defensives = {}, interrupt = {}, utility = {}, rest = {} }
	local used = {}
	local function put(group, id)
		if id and not used[id] and IsKnown(id) then
			used[id] = true
			table.insert(groups[group], id)
		end
	end

	for _, id in ipairs(ns.ClassSpells.interrupts[class] or {}) do
		if IsKnown(id) then put("interrupt", id) break end
	end
	for _, id in ipairs(ns.ClassSpells.defensives[class] or {}) do put("defensives", id) end

	-- Blizzard's rotation list is the core; long cooldowns inside it go to cooldowns.
	local rotation = C_AssistedCombat and C_AssistedCombat.GetRotationSpells and C_AssistedCombat.GetRotationSpells() or {}
	for _, id in ipairs(rotation) do
		if not issecret(id) then
			put(BaseCooldown(id) >= MAJOR_CD and "cooldowns" or "core", id)
		end
	end

	local book = SpellbookSpells()
	for _, id in ipairs(book) do
		if not used[id] then
			local cd = BaseCooldown(id)
			if cd >= MAJOR_CD and C_Spell.IsSpellHarmful and not C_Spell.IsSpellHarmful(id) and #groups.cooldowns < 6 then
				put("cooldowns", id)
			elseif cd > 0 then
				put("utility", id)
			else
				put("rest", id)
			end
		end
	end
	return groups
end

---------------------------------------------------------------------------
-- Backup / restore
---------------------------------------------------------------------------
local GetActionInfoCompat = (C_ActionBar and C_ActionBar.GetActionInfo) or GetActionInfo

local function ActionInfo(slot)
	local kind, id, subType = GetActionInfoCompat(slot)
	return Safe(kind), Safe(id), Safe(subType)
end

local function TemplateKeys()
	local keys = {}
	for _, list in pairs(ns.db.layout.keys) do
		for _, k in ipairs(list) do keys[#keys + 1] = k end
	end
	return keys
end

function AB.Backup(buttons)
	local b = { actions = {}, bindings = {}, date = date("%Y-%m-%d %H:%M") }
	for _, btn in ipairs(buttons) do
		local kind, id = ActionInfo(btn.slot)
		b.actions[btn.slot] = kind and { kind = kind, id = id } or false
	end
	for _, key in ipairs(TemplateKeys()) do
		b.bindings[key] = GetBindingAction(key) or ""
	end
	local specID = ns:GetSpecID()
	local stack = ns.db.layout.backup[specID]
	if type(stack) ~= "table" or stack.actions then stack = {} end
	stack[#stack + 1] = b
	while #stack > 5 do table.remove(stack, 1) end
	ns.db.layout.backup[specID] = stack
	return b
end

local function PlaceOnCursor(kind, id)
	if kind == "spell" then
		C_Spell.PickupSpell(id)
	elseif kind == "macro" then
		PickupMacro(id)
	elseif kind == "item" then
		(C_Item and C_Item.PickupItem or PickupItem)(id)
	end
end

local function ClearSlot(slot)
	PickupAction(slot)
	ClearCursor()
end

local function PutSpell(slot, spellID)
	ClearCursor()
	C_Spell.PickupSpell(spellID)
	if GetCursorInfo() then
		PlaceAction(slot)
	end
	ClearCursor()
end

function AB.Restore()
	if InCombatLockdown() then
		ns:Print(L.ERR_COMBAT)
		return
	end
	local stack = ns.db.layout.backup[ns:GetSpecID()]
	local b = type(stack) == "table" and table.remove(stack)
	if not b then
		ns:Print(L.LAYOUT_NO_BACKUP)
		return
	end
	for slot, a in pairs(b.actions) do
		local kind, id = ActionInfo(slot)
		local same = a and kind == a.kind and id == a.id
		if not same then
			ClearSlot(slot)
			if a then
				ClearCursor()
				PlaceOnCursor(a.kind, a.id)
				if GetCursorInfo() then PlaceAction(slot) end
				ClearCursor()
			end
		end
	end
	for key, command in pairs(b.bindings) do
		SetBinding(key, command ~= "" and command or nil)
	end
	SaveBindings(GetCurrentBindingSet())
	ns:Print(L.LAYOUT_RESTORED, b.date)
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
-- Slots we must never touch: the skyriding bar (121-132) and the vehicle /
-- override pages (133-144) that replace the main bar while mounted etc.
local function IsProtectedSlot(slot)
	return slot >= 121 and slot <= 144
end

local function PlacedBySpec()
	local specID = ns:GetSpecID()
	ns.db.layout.placed[specID] = ns.db.layout.placed[specID] or {}
	return ns.db.layout.placed[specID]
end

-- A spell we manage: part of this build, a talent spell the player no longer
-- has (left over from the previous build), or one we placed ourselves.
-- Anything else (skyriding, racials, professions, general spells) is kept.
local function IsManagedSpell(slot, id, pool, placed)
	if not id then return false end
	if pool[id] then return true end
	if placed[slot] == id then return true end
	if not IsKnown(id) and C_Spell.IsClassTalentSpell and Safe(C_Spell.IsClassTalentSpell(id)) then
		return true
	end
	return false
end

-- Returns a plan: list of { slot, command, spell, key, group }.
function AB.Plan(buttons, groups)
	local pool = {}
	for _, list in pairs(groups) do
		for _, id in ipairs(list) do pool[id] = true end
	end
	local placed = PlacedBySpec()

	-- Only empty slots and slots holding spells we manage can be used.
	-- Macros, items, mounts, toys and every other spell stay where they are.
	local free = {}
	for _, btn in ipairs(buttons) do
		if not IsProtectedSlot(btn.slot) then
			local kind, id = ActionInfo(btn.slot)
			if kind == nil or (kind == "spell" and IsManagedSpell(btn.slot, id, pool, placed)) then
				free[#free + 1] = btn
			end
		end
	end
	local plan, i = {}, 1
	local keys = ns.db.layout.keys
	for _, group in ipairs(AB.GROUP_ORDER) do
		local groupKeys = keys[group] or {}
		for n, spell in ipairs(groups[group] or {}) do
			local btn = free[i]
			if not btn then return plan end
			i = i + 1
			plan[#plan + 1] = { slot = btn.slot, command = btn.command, spell = spell, key = groupKeys[n], group = group }
		end
	end
	-- Remaining free buttons are cleared of spells (old talents etc.).
	for j = i, #free do
		plan[#plan + 1] = { slot = free[j].slot, clear = true }
	end
	return plan
end

-- While mounted, in a vehicle or with an override bar, the main bar shows a
-- different page (skyriding abilities etc.), so we wait until that's over.
function AB.IsBarSwapped()
	if IsMounted and IsMounted() then return true end
	if UnitInVehicle and Safe(UnitInVehicle("player")) then return true end
	if HasOverrideActionBar and HasOverrideActionBar() then return true end
	if HasVehicleActionBar and HasVehicleActionBar() then return true end
	if HasBonusActionBar and HasBonusActionBar() and GetBonusBarOffset and GetBonusBarOffset() == 5 then return true end
	return false
end

function AB.Apply()
	if InCombatLockdown() then
		ns:Print(L.ERR_COMBAT)
		return false
	end
	if AB.IsBarSwapped() then
		AB.pending = true
		ns:Print(L.LAYOUT_WAIT_MOUNT)
		return false
	end
	AB.pending = false
	local buttons = AB.ScanButtons()
	if #buttons == 0 then
		ns:Print(L.LAYOUT_NO_BUTTONS)
		return false
	end
	AB.Backup(buttons)
	local plan = AB.Plan(buttons, AB.GroupSpells())
	local placedBy = PlacedBySpec()

	local placed, bound = 0, 0
	for _, p in ipairs(plan) do
		if p.clear then
			local kind = ActionInfo(p.slot)
			if kind == "spell" then ClearSlot(p.slot) end
			placedBy[p.slot] = nil
		else
			local kind, id = ActionInfo(p.slot)
			if not (kind == "spell" and id == p.spell) then
				ClearSlot(p.slot)
				PutSpell(p.slot, p.spell)
			end
			placedBy[p.slot] = p.spell
			placed = placed + 1
			if p.key then
				if SetBinding(p.key, p.command) then bound = bound + 1 end
			end
		end
	end
	SaveBindings(GetCurrentBindingSet())
	ns:Print(L.LAYOUT_DONE, placed, bound)
	ns:Fire("LAYOUT_APPLIED")
	return true
end

---------------------------------------------------------------------------
-- Auto layout after a build is applied
---------------------------------------------------------------------------
StaticPopupDialogs["DARKNDARK_TALENTS_LAYOUT"] = {
	text = "%s",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		ns.db.layout.confirmed = true
		AB.Apply()
	end,
	OnCancel = function()
		ns.db.layout.auto = false
		ns:Print(L.LAYOUT_AUTO_OFF)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function AB.AfterBuildApplied()
	if not ns.db.layout.auto then return end
	-- Let the new talents' spells finish loading into the spellbook.
	C_Timer.After(1.5, function()
		if InCombatLockdown() then return end
		if ns.db.layout.confirmed then
			AB.Apply()
		else
			StaticPopup_Show("DARKNDARK_TALENTS_LAYOUT", L.LAYOUT_CONFIRM)
		end
	end)
end

ns:On("LOADOUT_CHANGED", AB.AfterBuildApplied)

-- Finish a layout that was postponed while mounted / in a vehicle.
local function ResumePending()
	if not AB.pending then return end
	C_Timer.After(1, function()
		if AB.pending and not InCombatLockdown() and not AB.IsBarSwapped() then AB.Apply() end
	end)
end
ns:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", ResumePending)
ns:RegisterEvent("UPDATE_BONUS_ACTIONBAR", ResumePending)
ns:RegisterEvent("UNIT_EXITED_VEHICLE", ResumePending)
ns:RegisterEvent("PLAYER_REGEN_ENABLED", ResumePending)
