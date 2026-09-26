local _, ns = ...
local L = ns.L

-- Darkndark Talents' section of the shared Darkndark minimap button menu.
ns.defaults.minimap = { hide = false }

local function Build(root)
	root:CreateButton(L.TAB_TALENTS, function() ns:ShowWindow("talents") end)
	root:CreateButton(L.TAB_PLAYERS, function() ns:ShowWindow("players") end)
	root:CreateButton(L.TAB_GEAR, function() ns:ShowWindow("gear") end)
	root:CreateButton(L.LAYOUT_BUTTON, function()
		ns.db.layout.confirmed = true
		ns.ActionBars.Apply()
	end)
	root:CreateButton(L.LAYOUT_UNDO, function() ns.ActionBars.Restore() end)
	root:CreateCheckbox(L.PROMPT_AUTO, function() return ns.db.autoPrompt end, function()
		ns.db.autoPrompt = not ns.db.autoPrompt
	end)
end

ns:On("LOGIN", function()
	if not DarkndarkMinimap then return end
	DarkndarkMinimap.hideLabel = L.MM_HIDE
	DarkndarkMinimap.tooltipHint = L.MM_HINT
	DarkndarkMinimap:Register({
		id = "DarkndarkTalents",
		title = "Darkndark Talents",
		order = 2,
		build = Build,
		default = function() ns:ToggleWindow() end,
		getAngle = function() return ns.db.minimap.angle end,
		setAngle = function(a) ns.db.minimap.angle = a end,
		isHidden = function() return ns.db.minimap.hide end,
		setHidden = function(h) ns.db.minimap.hide = h end,
	})
end)

function DarkndarkTalents_OnAddonCompartmentClick()
	ns:ToggleWindow()
end
