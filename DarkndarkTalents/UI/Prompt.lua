local _, ns = ...
local L = ns.L

-- Build chooser shown when entering content. The player always decides:
-- recommended build, the other hero tree, their own saved build, a specific
-- top player's build, or keeping their current talents.
local prompt
local WIDTH = 380
local OPTION_H = 34

local function Create()
	local f = CreateFrame("Frame", "DarkndarkTalentsPrompt", UIParent, "BackdropTemplate")
	f:SetWidth(WIDTH)
	f:SetPoint("TOP", 0, -120)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	f:SetBackdropColor(0.04, 0.04, 0.07, 0.97)
	f:SetBackdropBorderColor(0.64, 0.21, 0.93, 0.9)

	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(36, 36)
	f.icon:SetPoint("TOPLEFT", 12, -12)
	f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	f.text:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -2)
	f.text:SetPoint("RIGHT", -30, 0)
	f.text:SetJustifyH("LEFT")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	f.options = {}

	f.auto = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.auto:SetSize(22, 22)
	f.auto:SetScript("OnClick", function(self) ns.db.autoPrompt = self:GetChecked() and true or false end)
	f.autoText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.autoText:SetPoint("LEFT", f.auto, "RIGHT", 2, 0)
	f.autoText:SetText(L.PROMPT_AUTO)
	return f
end

local function GetOption(f, i)
	local b = f.options[i]
	if not b then
		b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(WIDTH - 24, OPTION_H - 6)
		b:SetText(" ")
		local fs = b:GetFontString()
		if fs then
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", 12, 0)
			fs:SetPoint("RIGHT", -12, 0)
			fs:SetJustifyH("LEFT")
			fs:SetWordWrap(false)
		end
		b:SetScript("OnClick", function(self)
			f:Hide()
			if self.action then self.action() end
		end)
		f.options[i] = b
	end
	return b
end

local function Describe(build)
	local parts = { build.hero or "?" }
	if build.share then parts[#parts + 1] = L.SHARE:format(build.share) end
	local sim = ns.Loadout.Similarity(build.code)
	if sim then parts[#parts + 1] = L.MATCH:format(sim) end
	return table.concat(parts, "  ·  ")
end

function ns:ShowPrompt(ctx)
	prompt = prompt or Create()
	local f = prompt
	f.ctx = ctx
	local loadoutName = L["LOADOUT_" .. ctx]
	local _, icon = ns:GetSpecName(ns:GetSpecID())
	f.icon:SetTexture(icon)
	f.text:SetText(L.CHOOSER_TEXT:format(L["CTX_" .. ctx]))

	local main, alt = ns:GetDataBuilds(ctx)
	local custom = ns:GetCustomBuild(ctx)
	local players = ns:GetPlayers(ctx)
	local choices = {}
	if main then
		choices[#choices + 1] = { label = L.CHOOSE_RECOMMENDED .. ": |cffffffff" .. Describe(main) .. "|r",
			action = function() ns.Loadout.Apply(main.code, loadoutName) end }
	end
	if alt then
		choices[#choices + 1] = { label = L.CHOOSE_ALT .. ": |cffffffff" .. Describe(alt) .. "|r",
			action = function() ns.Loadout.Apply(alt.code, loadoutName) end }
	end
	if custom then
		choices[#choices + 1] = { label = L.CHOOSE_MINE,
			action = function() ns.Loadout.Apply(custom.code, loadoutName) end }
	end
	if #players > 0 then
		choices[#choices + 1] = { label = L.CHOOSE_PLAYER:format(#players),
			action = function() ns:ShowWindow("players", ctx) end }
	end
	choices[#choices + 1] = { label = "|cffaaaaaa" .. L.CHOOSE_KEEP .. "|r" }
	if #choices == 1 then return end

	local top = 60
	for i, c in ipairs(choices) do
		local b = GetOption(f, i)
		b:ClearAllPoints()
		b:SetPoint("TOP", 0, -(top + (i - 1) * OPTION_H))
		b:SetText(c.label)
		b.action = c.action
		b:Show()
	end
	for i = #choices + 1, #f.options do f.options[i]:Hide() end

	local bottom = top + #choices * OPTION_H
	f.auto:ClearAllPoints()
	f.auto:SetPoint("TOPLEFT", 12, -(bottom + 2))
	f.auto:SetChecked(ns.db.autoPrompt)
	f:SetHeight(bottom + 34)
	f:Show()
end

ns:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if prompt then prompt:Hide() end
end)
