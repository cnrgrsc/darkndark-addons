-- Minimal WoW API mock for load/runtime smoke tests.
unpack = unpack or table.unpack
local SecretMT = {}
local function err() error("attempt to use a secret value", 2) end
SecretMT.__add, SecretMT.__sub, SecretMT.__mul, SecretMT.__div = err, err, err, err
SecretMT.__lt, SecretMT.__le, SecretMT.__concat, SecretMT.__len = err, err, err, err
SecretMT.__index = function() err() end
SecretMT.__tostring = function() return "<secret>" end
function MakeSecret() return setmetatable({}, SecretMT) end
function issecretvalue(v) return getmetatable(v) == SecretMT end
SECRET_MODE = false
CD_ACTIVE = { [13750] = true }
SOUNDS_PLAYED = {}
function PlaySound(id) SOUNDS_PLAYED[#SOUNDS_PLAYED + 1] = id end
local function maybe(v) if SECRET_MODE then return MakeSecret() end return v end

EVENTS = {}      -- event -> list of frames
FRAMES = {}
local FrameMT = {}
FrameMT.__index = function(t, k)
	local f = rawget(FrameMT, k)
	if f then return f end
	return function() return nil end
end
local function NewObj(kind, name)
	local o = setmetatable({ _kind = kind, _scripts = {}, _shown = true, _scale = 1, _w = 40, _h = 40, _points = {} }, FrameMT)
	if name then _G[name] = o end
	FRAMES[#FRAMES + 1] = o
	return o
end
function FrameMT.CreateTexture() return NewObj("Texture") end
function FrameMT.CreateFontString() return NewObj("FontString") end
function FrameMT.CreateAnimationGroup() return NewObj("AnimGroup") end
function FrameMT.CreateAnimation() return NewObj("Anim") end
function FrameMT.SetScript(self, k, fn) self._scripts[k] = fn end
function FrameMT.GetScript(self, k) return self._scripts[k] end
function FrameMT.RegisterEvent(self, e) EVENTS[e] = EVENTS[e] or {}; table.insert(EVENTS[e], self) end
function FrameMT.RegisterUnitEvent(self, e) FrameMT.RegisterEvent(self, e) end
function FrameMT.Show(self) self._shown = true end
function FrameMT.Hide(self) self._shown = false end
function FrameMT.SetShown(self, v) self._shown = v and true or false end
function FrameMT.IsShown(self) return self._shown end
function FrameMT.IsVisible(self) return self._shown end
function FrameMT.SetScale(self, s) self._scale = s end
function FrameMT.GetScale(self) return self._scale end
function FrameMT.GetEffectiveScale(self) return self._scale end
function FrameMT.SetSize(self, w, h) self._w, self._h = w, h end
function FrameMT.GetWidth(self) return self._w end
function FrameMT.GetHeight(self) return self._h end
function FrameMT.SetPoint(self, ...) self._points = { ... } end
function FrameMT.GetPoint(self) local p = self._points; return p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0 end
function FrameMT.GetFrameLevel() return 1 end
function FrameMT.SetText(self, t) self._text = t end
function FrameMT.GetText(self) return self._text end
function FrameMT.GetStringHeight() return 100 end
function FrameMT.IsMouseOver() return false end
function FrameMT.SetTexture(self, t) self._tex = t end

function CreateFrame(kind, name) return NewObj(kind, name) end
UIParent = NewObj("Frame", "UIParent")
GameTooltip = NewObj("GameTooltip", "GameTooltip")
ChatFontNormal = {}
UISpecialFrames = {}
function GameTooltip_Hide() end
function Mixin(o, ...) for _, m in ipairs({ ... }) do for k, v in pairs(m) do o[k] = v end end return o end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
function GetLocale() return LOCALE or "enUS" end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
RANGE_INDICATOR = "●"
SlashCmdList = {}
function print(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end io_write("  [print] " .. table.concat(t, " ")) end
function date() return "2026-09-26" end
function GetBuildInfo() return "12.0.7", "60000", "Sep 2026", 120007 end
function InCombatLockdown() return IN_COMBAT or false end
function UnitAffectingCombat() return maybe(IN_COMBAT or false) end
function UnitClass() return "Rogue", "ROGUE", 4 end
function UnitExists(u) return u == "player" or (u == "target" and HAS_TARGET) or false end
function UnitCanAttack() return maybe(true) end
function UnitIsDeadOrGhost() return maybe(false) end
function UnitHasVehicleUI() return false end
function UnitPower() return maybe(3) end
function UnitPowerMax(_, t) if t == 4 or t == 3 then return 5 end return 0 end
function UnitHealth() return MakeSecret() end
function UnitHealthPercent() return MakeSecret() end
function UnitCastingInfo() if TARGET_CASTING then return MakeSecret(), MakeSecret(), 1, MakeSecret(), MakeSecret(), false, MakeSecret(), MakeSecret(), MakeSecret() end return nil end
function UnitChannelInfo() return nil end
function IsInInstance() return false, "none" end
function IsShiftKeyDown() return false end
function GetCursorPosition() return 0, 0 end
function GetBindingKey(cmd) if cmd == "ACTIONBUTTON1" then return "SHIFT-1" end if cmd == "ACTIONBUTTON2" then return "BUTTON4" end end
function GetActionInfo(slot) if slot == 1 then return "spell", 1752 end if slot == 2 then return "macro", 5, "spell" end end
function GetMacroSpell() return 196819 end
function GetActionBarPage() return 1 end
function GetBonusBarOffset() return 0 end
function IsPlayerSpell(id) return id ~= 99999 end
function GetSpellBaseCooldown(id) if id == 13750 then return 180000, 0 end if id == 1766 then return 15000, 0 end return 0, 1500 end
function GetSpecialization() return 2 end
function GetSpecializationInfo() return 260 end
C_Timer = { After = function(_, fn) TIMERS[#TIMERS + 1] = fn end }
TIMERS = {}
C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
C_PetBattles = { IsInBattle = function() return false end }
C_Spell = {
	GetSpellCooldown = function(id)
		return { startTime = maybe(0), duration = maybe(0), isEnabled = true, isActive = CD_ACTIVE[id] or false, isOnGCD = false, modRate = maybe(1) }
	end,
	GetSpellCooldownDuration = function() return MakeSecret() end,
	GetSpellCharges = function() return nil end,
	IsSpellUsable = function() return true, false end,
	IsSpellInRange = function() return true end,
	GetSpellTexture = function() return 136000 end,
	GetSpellName = function(id) return "Spell" .. id end,
	GetOverrideSpell = function(id) return id end,
	GetBaseSpell = function(id) return id end,
}
C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return id == 196819 end }
C_AssistedCombat = {
	GetNextCastSpell = function() return NEXT_SPELL or 1752 end,
	GetRotationSpells = function() return { 1752, 196819, 13750, 315496 } end,
	IsAvailable = function() return true, "" end,
	GetActionSpell = function() return 1229376 end,
}
C_ActionBar = { FindSpellActionButtons = function() return nil end }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 3 end,
	GetSpellBookSkillLineInfo = function(i) return { itemIndexOffset = (i - 1) * 3, numSpellBookItems = 3, isGuild = false, shouldHide = false } end,
	GetSpellBookItemInfo = function(i) local ids = { 1, 2, 3, 13750, 1766, 1752, 51690, 2, 3 }; return { spellID = ids[i], itemType = 1, isPassive = false, isOffSpec = false } end,
	IsSpellKnown = function(id) return id ~= 99999 end,
}
C_UnitAuras = {
	GetPlayerAuraBySpellID = function() return nil end,
	GetAuraDataByIndex = function(_, i) if i == 1 then return MakeSecret() end return nil end,
}
C_NamePlate = { GetNamePlates = function() return { { namePlateUnitToken = "nameplate1" }, { namePlateUnitToken = "nameplate2" } } end }
C_RestrictedActions = { IsAddOnRestrictionActive = function(t) return SECRET_MODE and t == 0 end }
Enum = {
	AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
	PowerType = { Energy = 3, ComboPoints = 4, Mana = 0 },
	SpellBookSpellBank = { Player = 0, Pet = 1 },
	SpellBookItemType = { Spell = 1 },
}
-- Settings API
local function SettingObj() return setmetatable({}, { __index = function() return function() end end }) end
Settings = {
	RegisterVerticalLayoutCategory = function() local c = SettingObj(); c.GetID = function() return 42 end; return c, SettingObj() end,
	RegisterProxySetting = function(_, var, typ, name, def, get, set)
		SETTINGS = SETTINGS or {}
		local s = { get = get, set = set, name = name }
		SETTINGS[#SETTINGS + 1] = s
		return s
	end,
	CreateCheckbox = function() end, CreateSlider = function() end, CreateDropdown = function(_, _, getOpts) getOpts() end,
	CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
	CreateControlTextContainer = function() local t = { d = {} }; function t:Add(v, l) self.d[#self.d + 1] = { v, l } end; function t:GetData() return self.d end; return t end,
	RegisterAddOnCategory = function() end,
	OpenToCategory = function(id) OPENED = id end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
function CreateSettingsListSectionHeaderInitializer() return {} end

function FireEvent(e, ...)
	for _, f in ipairs(EVENTS[e] or {}) do
		local fn = f._scripts.OnEvent
		if fn then fn(f, e, ...) end
	end
end
function RunTimers()
	local t = TIMERS; TIMERS = {}
	for _, fn in ipairs(t) do fn() end
end
function RunOnUpdate(dt)
	for _, f in ipairs(FRAMES) do
		local fn = f._scripts.OnUpdate
		if fn then fn(f, dt) end
	end
end

-- Minimap + menus
Minimap = CreateFrame("Frame", "Minimap"); Minimap._w = 140
function Minimap:GetCenter() return 1000, 700 end
MENU_LOG = {}
local function Root()
  local r = {}
  function r:CreateTitle(t) MENU_LOG[#MENU_LOG + 1] = "title:" .. t end
  function r:CreateDivider() MENU_LOG[#MENU_LOG + 1] = "---" end
  function r:CreateButton(t, fn) MENU_LOG[#MENU_LOG + 1] = "button:" .. t; MENU_FN = MENU_FN or {}; MENU_FN[t] = fn end
  function r:CreateCheckbox(t, get, set) MENU_LOG[#MENU_LOG + 1] = "check:" .. t .. "=" .. tostring(get()); MENU_FN = MENU_FN or {}; MENU_FN[t] = set end
  return r
end
MenuUtil = { CreateContextMenu = function(owner, gen) MENU_LOG = {}; gen(owner, Root()) end }
