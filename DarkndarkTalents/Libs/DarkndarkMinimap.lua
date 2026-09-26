-- Shared minimap button for the Darkndark addon family.
-- Any Darkndark addon can ship this same file. Whichever loads first creates
-- the one button; each addon registers its own menu section.
-- Left-click runs the first entry's default action, right-click opens the menu.
local VERSION = 2
local lib = DarkndarkMinimap
if lib and lib.version >= VERSION then return end
lib = lib or { entries = {} }
lib.version = VERSION
DarkndarkMinimap = lib

local ICON = "Interface\\Icons\\Ability_DualWield"
local DEFAULT_ANGLE = 200

local function Sorted()
	local list = {}
	for _, e in pairs(lib.entries) do list[#list + 1] = e end
	table.sort(list, function(a, b) return (a.order or 99) < (b.order or 99) end)
	return list
end

local function Angle()
	for _, e in ipairs(Sorted()) do
		local a = e.getAngle and e.getAngle()
		if a then return a end
	end
	return DEFAULT_ANGLE
end

local function Radius()
	return (Minimap:GetWidth() / 2) + 10
end

function lib:UpdatePosition()
	local b = self.button
	if not b then return end
	local a = math.rad(Angle())
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * Radius(), math.sin(a) * Radius())
end

function lib:UpdateVisibility()
	local b = self.button
	if not b then return end
	local hidden = true
	for _, e in pairs(self.entries) do
		if not (e.isHidden and e.isHidden()) then hidden = false end
	end
	b:SetShown(not hidden)
end

function lib:SetHidden(hidden)
	for _, e in pairs(self.entries) do
		if e.setHidden then e.setHidden(hidden) end
	end
	self:UpdateVisibility()
end

function lib:OpenMenu(owner)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		-- Very old client fallback: run the first entry's default action.
		local first = Sorted()[1]
		if first and first.default then first.default() end
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		for i, e in ipairs(Sorted()) do
			if i > 1 then root:CreateDivider() end
			root:CreateTitle(e.title)
			e.build(root)
		end
		root:CreateDivider()
		root:CreateButton(lib.hideLabel or "Hide minimap button", function() lib:SetHidden(true) end)
	end)
end

local function CreateButton()
	local b = CreateFrame("Button", "DarkndarkMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:SetMovable(true)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(18, 18)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetVertexColor(0.9, 0.75, 1)
	b.icon = icon

	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(self, button)
		local first = Sorted()[1]
		if button == "RightButton" or not (first and first.default) then
			lib:OpenMenu(self)
		else
			first.default()
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("|cffa335eeDarkndark|r")
		GameTooltip:AddLine(lib.tooltipHint or "Click: open  ·  Right-click: menu  ·  Drag: move", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)

	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			local px, py = GetCursorPosition()
			px, py = px / scale, py / scale
			local angle = math.deg((math.atan2 or math.atan)(py - my, px - mx)) % 360
			for _, e in pairs(lib.entries) do
				if e.setAngle then e.setAngle(angle) end
			end
			lib:UpdatePosition()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	return b
end

-- entry = { id, title, order, build(rootDescription), default(),
--           getAngle(), setAngle(a), isHidden(), setHidden(bool) }
function lib:Register(entry)
	self.entries[entry.id] = entry
	self.button = self.button or _G.DarkndarkMinimapButton or CreateButton()
	self:UpdatePosition()
	self:UpdateVisibility()
end
