local _, ns = ...
local L = ns.L

-- Blizzard Settings panel (Esc > Options > AddOns > Darkndark).
local category, layout

local function Root() return ns.db end
local function CD() return ns.db.cooldowns end
local function INT() return ns.db.interrupt end
local function DEF() return ns.db.defensives end
local function SND() return ns.db.sounds end

local function Changed()
	ns:Fire("LAYOUT_CHANGED")
end

local function Header(text)
	if layout and CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
	end
end

local counter = 0
local function Register(name, default, get, set)
	counter = counter + 1
	return Settings.RegisterProxySetting(category, "DARKNDARK_OPT_" .. counter, type(default), name, default, get, set)
end

local function Checkbox(tbl, key, default, name, tooltip, onSet)
	local setting = Register(name, default,
		function() return tbl()[key] end,
		function(v)
			tbl()[key] = v
			if onSet then onSet(v) else Changed() end
		end)
	Settings.CreateCheckbox(category, setting, tooltip)
end

local function Slider(tbl, key, default, name, minV, maxV, step, tooltip, decimals, get, set)
	local setting = Register(name, default,
		get or function() return tbl()[key] end,
		set or function(v)
			tbl()[key] = v
			Changed()
		end)
	local options = Settings.CreateSliderOptions(minV, maxV, step)
	local fmt = decimals and ("%." .. decimals .. "f") or "%d"
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
		return fmt:format(v)
	end)
	Settings.CreateSlider(category, setting, options, tooltip)
end

local function Dropdown(tbl, key, default, name, choices, tooltip)
	local setting = Register(name, default,
		function() return tbl()[key] end,
		function(v)
			tbl()[key] = v
			Changed()
		end)
	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		for _, c in ipairs(choices) do container:Add(c[1], c[2]) end
		return container:GetData()
	end
	local create = Settings.CreateDropdown or Settings.CreateDropDown
	create(category, setting, GetOptions, tooltip)
end

local function Build()
	local d = ns.defaults
	category, layout = Settings.RegisterVerticalLayoutCategory("Darkndark")

	Header(L.OPT_GENERAL)
	Checkbox(Root, "enabled", d.enabled, L.OPT_ENABLED, nil, function(v) ns:SetEnabled(v) end)
	Checkbox(Root, "locked", d.locked, L.OPT_LOCKED, L.OPT_LOCKED_TT, function(v) ns:SetLocked(v) end)
	Dropdown(Root, "visibility", d.visibility, L.OPT_VISIBILITY, {
		{ "always", L.OPT_VIS_ALWAYS },
		{ "combat", L.OPT_VIS_COMBAT },
		{ "hostile", L.OPT_VIS_HOSTILE },
	})
	Slider(Root, "oocAlpha", d.oocAlpha, L.OPT_OOC_ALPHA, 0, 1, 0.05, nil, 2)
	Checkbox(Root, "useProfiles", d.useProfiles, L.OPT_PROFILES, L.OPT_PROFILES_TT, function()
		ns:Fire("SPELLS_CHANGED")
	end)
	Slider(Root, "updateInterval", d.updateInterval, L.OPT_UPDATE, 0.02, 0.25, 0.01, nil, 2)

	Header(L.FRAME_MAIN)
	Slider(nil, nil, 1, L.OPT_SCALE, 0.4, 3, 0.05, nil, 2,
		function() return ns.db.frames.main.scale end,
		function(v) ns:SetFrameScale("main", v) end)
	Slider(Root, "iconSize", d.iconSize, L.OPT_ICON_SIZE, 24, 128, 1)
	Slider(Root, "queueLength", d.queueLength, L.OPT_QUEUE_LENGTH, 0, 4, 1, L.OPT_QUEUE_LENGTH_TT)
	Slider(Root, "queueScale", d.queueScale, L.OPT_QUEUE_SCALE, 0.4, 1, 0.05, nil, 2)
	Slider(Root, "spacing", d.spacing, L.OPT_SPACING, 0, 20, 1)
	Dropdown(Root, "direction", d.direction, L.OPT_DIRECTION, {
		{ "RIGHT", L.OPT_DIR_RIGHT },
		{ "LEFT", L.OPT_DIR_LEFT },
		{ "UP", L.OPT_DIR_UP },
		{ "DOWN", L.OPT_DIR_DOWN },
	})
	Checkbox(Root, "showKeybinds", d.showKeybinds, L.OPT_KEYBINDS)
	Slider(Root, "keybindSize", d.keybindSize, L.OPT_KEYBIND_SIZE, 8, 28, 1)
	Checkbox(Root, "showSwipe", d.showSwipe, L.OPT_SWIPE)
	Checkbox(Root, "rangeTint", d.rangeTint, L.OPT_RANGE)
	Checkbox(Root, "usableTint", d.usableTint, L.OPT_USABLE)
	Checkbox(Root, "glowProcs", d.glowProcs, L.OPT_GLOW)

	Header(L.OPT_COOLDOWNS)
	Checkbox(CD, "enabled", d.cooldowns.enabled, L.OPT_CD_ENABLED)
	Checkbox(CD, "readyOnly", d.cooldowns.readyOnly, L.OPT_CD_READY_ONLY)
	Slider(CD, "threshold", d.cooldowns.threshold, L.OPT_CD_THRESHOLD, 20, 300, 5, nil, nil, nil, function(v)
		ns.db.cooldowns.threshold = v
		ns.Cooldowns:Rebuild()
	end)
	Slider(CD, "max", d.cooldowns.max, L.OPT_CD_MAX, 1, 12, 1)
	Slider(CD, "iconSize", d.cooldowns.iconSize, L.OPT_CD_SIZE, 20, 80, 1)
	Slider(nil, nil, 1, L.OPT_CD_SCALE, 0.4, 3, 0.05, nil, 2,
		function() return ns.db.frames.cooldowns.scale end,
		function(v) ns:SetFrameScale("cooldowns", v) end)

	Checkbox(Root, "holdCooldowns", d.holdCooldowns, L.OPT_HOLD, L.OPT_HOLD_TT)

	Header(L.OPT_DEFENSIVES)
	Checkbox(DEF, "enabled", d.defensives.enabled, L.OPT_DEF_ENABLED)
	Checkbox(DEF, "readyOnly", d.defensives.readyOnly, L.OPT_DEF_READY_ONLY)
	Slider(DEF, "max", d.defensives.max, L.OPT_CD_MAX, 1, 10, 1)
	Slider(DEF, "iconSize", d.defensives.iconSize, L.OPT_CD_SIZE, 20, 80, 1)
	Slider(nil, nil, 1, L.OPT_DEF_SCALE, 0.4, 3, 0.05, nil, 2,
		function() return ns.db.frames.defensives.scale end,
		function(v) ns:SetFrameScale("defensives", v) end)

	Header(L.OPT_SOUNDS)
	Checkbox(SND, "kick", d.sounds.kick, L.OPT_SOUND_KICK)
	Checkbox(SND, "proc", d.sounds.proc, L.OPT_SOUND_PROC)

	Header(L.OPT_INTERRUPT)
	Checkbox(INT, "enabled", d.interrupt.enabled, L.OPT_INT_ENABLED)
	Checkbox(INT, "onlyWhenCasting", d.interrupt.onlyWhenCasting, L.OPT_INT_ONLY_CASTING)
	Slider(INT, "iconSize", d.interrupt.iconSize, L.OPT_INT_SIZE, 20, 96, 1)
	Slider(nil, nil, 1, L.OPT_INT_SCALE, 0.4, 3, 0.05, nil, 2,
		function() return ns.db.frames.interrupt.scale end,
		function(v) ns:SetFrameScale("interrupt", v) end)

	Settings.RegisterAddOnCategory(category)
end

function ns:OpenOptions()
	if not category then return end
	Settings.OpenToCategory(category:GetID())
end

ns:On("DB_READY", function()
	local ok, err = pcall(Build)
	if not ok then
		ns:Print("options panel failed: %s", tostring(err))
	end
end)
