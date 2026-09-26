local _, ns = ...
local L = ns.L

local W = {}
ns.Window = W

local WIDTH, HEIGHT = 640, 510
local ROW_H = 52
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ACCENT = { 0.64, 0.21, 0.93 }
local GOLD = { 1, 0.82, 0 }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Text(parent, size, color, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(STANDARD_TEXT_FONT, size or 12, "")
	if color then fs:SetTextColor(unpack(color)) end
	fs:SetJustifyH(justify or "LEFT")
	return fs
end

local function Button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function Tooltip(widget, fn)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		fn(GameTooltip)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function SavePosition(f)
	local point, _, relPoint, x, y = f:GetPoint(1)
	local w = ns.db.window
	w.point, w.relPoint, w.x, w.y = point, relPoint, x, y
end

local function ApplyPosition(f)
	local w = ns.db.window
	f:ClearAllPoints()
	f:SetScale(w.scale or 1)
	f:SetPoint(w.point or "CENTER", UIParent, w.relPoint or "CENTER", w.x or 0, w.y or 0)
end

local function SetScale(f, value)
	value = math.max(0.5, math.min(2, value))
	local w = ns.db.window
	local old = f:GetScale()
	w.x, w.y = (w.x or 0) * old / value, (w.y or 0) * old / value
	w.scale = value
	ApplyPosition(f)
end

---------------------------------------------------------------------------
-- Copy popup
---------------------------------------------------------------------------
local copyFrame
local function ShowCopy(text)
	if not copyFrame then
		local f = CreateFrame("Frame", "DarkndarkTalentsCopy", UIParent, "BackdropTemplate")
		f:SetSize(460, 70)
		f:SetPoint("CENTER", 0, 150)
		f:SetFrameStrata("DIALOG")
		f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		f:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
		f:SetBackdropBorderColor(unpack(ACCENT))
		local hint = Text(f, 11, { 0.7, 0.7, 0.7 })
		hint:SetPoint("TOP", 0, -8)
		hint:SetText(L.COPY_HINT)
		local e = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
		e:SetSize(420, 24)
		e:SetPoint("BOTTOM", 0, 12)
		e:SetAutoFocus(true)
		e:SetScript("OnEscapePressed", function() f:Hide() end)
		e:SetScript("OnEnterPressed", function() f:Hide() end)
		f.edit = e
		copyFrame = f
	end
	copyFrame.edit:SetText(text or "")
	copyFrame:Show()
	copyFrame.edit:SetFocus()
	copyFrame.edit:HighlightText()
end

---------------------------------------------------------------------------
-- Talents tab
---------------------------------------------------------------------------
local function CreateRow(parent, ctx, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(WIDTH - 24, ROW_H - 4)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
	row.ctx = ctx

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0.06)

	row.title = Text(row, 13, GOLD)
	row.title:SetPoint("TOPLEFT", 8, -7)
	row.title:SetText(L["CTX_" .. ctx])

	row.info = Text(row, 10, { 0.8, 0.8, 0.8 })
	row.info:SetPoint("TOPLEFT", 8, -24)
	row.info:SetWidth(245)
	row.info:SetWordWrap(true)

	row.save = Button(row, L.SAVE_MINE, 108, function()
		local code = ns.Loadout.Export()
		if not code then return end
		local specID = ns:GetSpecID()
		ns.db.custom[specID] = ns.db.custom[specID] or {}
		if ns.db.custom[specID][ctx] then
			ns.db.custom[specID][ctx] = nil
			ns:Print(L.RESET, L["CTX_" .. ctx])
		else
			ns.db.custom[specID][ctx] = { code = code, saved = date("%Y-%m-%d") }
			ns:Print(L.SAVED, L["CTX_" .. ctx])
		end
		W:Refresh()
	end)
	row.save:SetPoint("RIGHT", -6, 0)

	row.copy = Button(row, L.COPY, 58, function() ShowCopy(row.code) end)
	row.copy:SetPoint("RIGHT", row.save, "LEFT", -4, 0)

	row.share = Button(row, L.SHARE_BUTTON, 62, function() ns:ShareBuild(row.code) end)
	row.share:SetPoint("RIGHT", row.copy, "LEFT", -4, 0)
	Tooltip(row.share, function(tt)
		tt:SetText(L.SHARE_BUTTON)
		tt:AddLine(L.SHARE_TT, 1, 1, 1, true)
	end)

	row.alt = Button(row, L.ALT, 40, function()
		if row.altBuild then ns.Loadout.Apply(row.altBuild.code, L["LOADOUT_" .. ctx]) end
	end)
	row.alt:SetPoint("RIGHT", row.share, "LEFT", -4, 0)
	Tooltip(row.alt, function(tt)
		local b = row.altBuild
		if not b then return end
		tt:SetText(b.hero)
		if b.share then tt:AddLine(L.SHARE:format(b.share), 1, 1, 1) end
	end)

	row.apply = Button(row, L.APPLY, 70, function()
		if row.code then ns.Loadout.Apply(row.code, L["LOADOUT_" .. ctx]) end
	end)
	row.apply:SetPoint("RIGHT", row.alt, "LEFT", -4, 0)

	return row
end

function W:RefreshTalents()
	local f = self.frame
	local specID = ns:GetSpecID()
	local name, icon, className = ns:GetSpecName(specID or 0)
	f.specIcon:SetTexture(icon)
	f.specName:SetText(("%s %s"):format(name or "?", className or ""))
	local active = ns.Loadout.ActiveName()
	f.active:SetText(active or "")
	local d = ns.data
	local here = ns.Context:Detect()
	f.dataInfo:SetText(d and L.DATA_INFO:format(d.patch or "?", d.updated or "?", "murlok.io + raider.io") or "")

	for _, row in ipairs(f.rows) do
		local build, alt, _, fromMplus = ns:GetBuilds(row.ctx, specID)
		row.code = build and build.code
		row.altBuild = (not (build and build.custom)) and alt or nil
		local parts = {}
		if build then
			parts[#parts + 1] = "|cffffffff" .. (build.hero or "?") .. "|r"
			if build.share then parts[#parts + 1] = L.SHARE:format(build.share) end
			if fromMplus then parts[#parts + 1] = L.FROM_MPLUS end
			if build.match and build.match < 60 then parts[#parts + 1] = "|cffff9933" .. L.LOW_CONF .. "|r" end
			local sim = ns.Loadout.Similarity(build.code)
			if sim then
				local color = sim >= 95 and "|cff33ff66" or (sim >= 75 and "|cffffd100" or "|cffff5555")
				parts[#parts + 1] = color .. L.MATCH:format(sim) .. "|r"
			end
		else
			parts[#parts + 1] = "|cff888888" .. L.NO_DATA .. "|r"
		end
		row.info:SetText(table.concat(parts, "  ·  "))
		row.apply:SetEnabled(row.code ~= nil)
		row.copy:SetEnabled(row.code ~= nil)
		row.share:SetEnabled(row.code ~= nil)
		row.alt:SetShown(row.altBuild ~= nil)
		local custom = ns.db.custom[specID] and ns.db.custom[specID][row.ctx]
		row.save:SetText(custom and L.DELETE_MINE or L.SAVE_MINE)
		if row.ctx == here then
			row.bg:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.25)
			row.title:SetText(L["CTX_" .. row.ctx] .. "  |cff33ff66(" .. L.CURRENT_HERE .. ")|r")
		else
			row.bg:SetColorTexture(1, 1, 1, 0.04)
			row.title:SetText(L["CTX_" .. row.ctx])
		end
	end
end

---------------------------------------------------------------------------
-- Gear tab
---------------------------------------------------------------------------
local function CreateStatRow(parent, key, index)
	local r = CreateFrame("Frame", nil, parent)
	r:SetSize(WIDTH - 40, 26)
	r:SetPoint("TOPLEFT", 0, -(index - 1) * 29)
	r.label = Text(r, 12, { 1, 1, 1 })
	r.label:SetPoint("TOPLEFT", 0, -2)
	r.label:SetWidth(120)
	r.label:SetText(L["STAT_" .. key])

	local function Bar(y, color)
		local bg = r:CreateTexture(nil, "BACKGROUND")
		bg:SetColorTexture(1, 1, 1, 0.08)
		bg:SetPoint("TOPLEFT", 130, y)
		bg:SetSize(300, 10)
		local fill = r:CreateTexture(nil, "ARTWORK")
		fill:SetColorTexture(unpack(color))
		fill:SetPoint("TOPLEFT", bg, "TOPLEFT")
		fill:SetSize(1, 10)
		local txt = Text(r, 10, { 0.9, 0.9, 0.9 })
		txt:SetPoint("LEFT", bg, "RIGHT", 6, 0)
		return fill, txt
	end
	r.mine, r.mineText = Bar(0, { ACCENT[1], ACCENT[2], ACCENT[3], 0.9 })
	r.top, r.topText = Bar(-12, { GOLD[1], GOLD[2], GOLD[3], 0.8 })
	r.key = key
	return r
end

local function CycleGearContext(delta)
	local list = ns.CONTEXTS
	local current = ns.db.gearContext or ns.Context:Detect() or "mplus"
	local idx = 1
	for i, c in ipairs(list) do if c == current then idx = i end end
	idx = ((idx - 1 + delta) % #list) + 1
	ns.db.gearContext = list[idx]
	W:RefreshGear()
end

function W:RefreshGear()
	local g = self.frame.gear
	local ctx = ns.db.gearContext or ns.Context:Detect() or "mplus"
	g.ctxLabel:SetText(L["CTX_" .. ctx])
	local report = ns.Gear.Analyze(ctx)

	g.ilvl:SetText(L.GEAR_ILVL:format(report.ilvl or 0, report.topIlvl and tostring(report.topIlvl) or "?"))
	for _, r in ipairs(g.stats) do
		local mine = report.mine[r.key] or 0
		local top = report.top and report.top[r.key]
		r.mine:SetWidth(math.max(1, 3 * mine))
		r.mineText:SetText(("%s %d%%"):format(L.YOU, mine))
		r.top:SetShown(top ~= nil)
		r.topText:SetShown(top ~= nil)
		if top then
			r.top:SetWidth(math.max(1, 3 * top))
			r.topText:SetText(("%s %d%%"):format(L.TOP, top))
		end
	end
	if report.priority then
		local names = {}
		for i, k in ipairs(report.priority) do names[i] = L["STAT_" .. k] end
		g.priority:SetText(L.GEAR_PRIORITY:format(table.concat(names, " > ")))
	else
		g.priority:SetText("")
	end

	local lines = {}
	for _, issue in ipairs(report.issues) do lines[#lines + 1] = "|cffff6666•|r " .. issue end
	if #lines == 0 then lines[1] = "|cff33ff66" .. L.GEAR_ALL_GOOD .. "|r" end
	g.issues:SetText(table.concat(lines, "\n"))
	g.issuesChild:SetHeight((g.issues:GetStringHeight() or 0) + 8)
end

---------------------------------------------------------------------------
-- Top players tab
---------------------------------------------------------------------------
local PLAYER_ROW_H = 42
local MAX_PLAYERS = 20

local function CyclePlayersContext(delta)
	local list = ns.CONTEXTS
	local current = ns.db.playersContext or ns.Context:Detect() or "mplus"
	local idx = 1
	for i, c in ipairs(list) do if c == current then idx = i end end
	idx = ((idx - 1 + delta) % #list) + 1
	ns.db.playersContext = list[idx]
	W:RefreshPlayers()
end

local function CreatePlayerRow(parent, index)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(WIDTH - 60, PLAYER_ROW_H - 4)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * PLAYER_ROW_H)

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.025 or 0.05)

	row.rank = Text(row, 14, GOLD, "RIGHT")
	row.rank:SetPoint("LEFT", 4, 0)
	row.rank:SetWidth(34)

	row.name = Text(row, 13, { 1, 1, 1 })
	row.name:SetPoint("TOPLEFT", 46, -5)
	row.name:SetWidth(300)
	row.name:SetWordWrap(false)

	row.info = Text(row, 10, { 0.75, 0.75, 0.8 })
	row.info:SetPoint("TOPLEFT", 46, -22)
	row.info:SetWidth(370)
	row.info:SetWordWrap(false)

	row.copy = Button(row, L.COPY, 58, function() ShowCopy(row.player and row.player.code) end)
	row.copy:SetPoint("RIGHT", -4, 0)
	row.share = Button(row, L.SHARE_BUTTON, 62, function() ns:ShareBuild(row.player and row.player.code) end)
	row.share:SetPoint("RIGHT", row.copy, "LEFT", -4, 0)
	row.use = Button(row, L.USE, 70, function()
		local p = row.player
		if not p then return end
		ns:Print(L.USING_PLAYER, p.rank, p.name)
		ns.Loadout.Apply(p.code, L["LOADOUT_" .. row.ctx])
	end)
	row.use:SetPoint("RIGHT", row.share, "LEFT", -4, 0)
	return row
end

function W:RefreshPlayers()
	local p = self.frame.players
	local ctx = ns.db.playersContext or ns.Context:Detect() or "mplus"
	local specID = ns:GetSpecID()
	local name, _, className = ns:GetSpecName(specID or 0)
	local players, fromMplus = ns:GetPlayers(ctx, specID)
	p.ctxLabel:SetText(L["CTX_" .. ctx])
	p.subtitle:SetText(L.PLAYERS_SUBTITLE:format(#players, name or "?", className or "")
		.. (fromMplus and ("  " .. L.FROM_MPLUS) or ""))
	p.empty:SetShown(#players == 0)

	local unit = (ctx == "mplus" or ctx == "raid") and L.SCORE or L.RATING
	for i, row in ipairs(p.rows) do
		local pl = players[i]
		row.player, row.ctx = pl, ctx
		if pl then
			row.rank:SetText("#" .. pl.rank)
			row.name:SetText(("%s |cff888888- %s (%s)|r"):format(pl.name, pl.realm or "?", pl.region or "?"))
			local parts = { "|cffffffff" .. (pl.hero or "?") .. "|r" }
			if pl.rating then parts[#parts + 1] = ("%d %s"):format(pl.rating, unit) end
			if pl.ilvl then parts[#parts + 1] = ("%d ilvl"):format(pl.ilvl) end
			local sim = ns.Loadout.Similarity(pl.code)
			if sim then
				local color = sim >= 95 and "|cff33ff66" or (sim >= 75 and "|cffffd100" or "|cffff5555")
				parts[#parts + 1] = color .. L.MATCH_SHORT:format(sim) .. "|r"
			end
			row.info:SetText(table.concat(parts, "  ·  "))
			row:Show()
		else
			row:Hide()
		end
	end
	p.child:SetHeight(math.max(1, math.min(#players, MAX_PLAYERS)) * PLAYER_ROW_H)
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
function W:SelectTab(tab)
	local f = self.frame
	f.tab = tab
	f.talents:SetShown(tab == "talents")
	f.players:SetShown(tab == "players")
	f.gear:SetShown(tab == "gear")
	f.tabTalents:SetAlpha(tab == "talents" and 1 or 0.6)
	f.tabPlayers:SetAlpha(tab == "players" and 1 or 0.6)
	f.tabGear:SetAlpha(tab == "gear" and 1 or 0.6)
	self:Refresh()
end

function W:Refresh()
	local f = self.frame
	if not (f and f:IsShown()) or InCombatLockdown() then return end
	if f.tab == "gear" then
		self:RefreshGear()
	elseif f.tab == "players" then
		self:RefreshPlayers()
	else
		self:RefreshTalents()
	end
end

function W:Create()
	local f = CreateFrame("Frame", "DarkndarkTalentsWindow", UIParent, "BackdropTemplate")
	self.frame = f
	f:SetSize(WIDTH, HEIGHT)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:EnableMouseWheel(true)
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	f:SetBackdropColor(0.04, 0.04, 0.07, 0.96)
	f:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(self)
	end)
	-- Ctrl + mouse wheel: scale
	f:SetScript("OnMouseWheel", function(self, delta)
		if IsControlKeyDown() then SetScale(self, self:GetScale() + delta * 0.05) end
	end)
	f:Hide()
	tinsert(UISpecialFrames, "DarkndarkTalentsWindow")

	local title = Text(f, 15, { ACCENT[1] + 0.2, ACCENT[2] + 0.3, 1 })
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(L.TITLE)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	f.specIcon = f:CreateTexture(nil, "ARTWORK")
	f.specIcon:SetSize(28, 28)
	f.specIcon:SetPoint("TOPLEFT", 12, -36)
	f.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.specName = Text(f, 14, { 1, 1, 1 })
	f.specName:SetPoint("TOPLEFT", f.specIcon, "TOPRIGHT", 8, -1)
	f.active = Text(f, 11, { 0.6, 0.9, 0.6 })
	f.active:SetPoint("TOPLEFT", f.specName, "BOTTOMLEFT", 0, -2)

	f.tabGear = Button(f, L.TAB_GEAR, 116, function() W:SelectTab("gear") end)
	f.tabGear:SetPoint("TOPRIGHT", -30, -38)
	f.tabPlayers = Button(f, L.TAB_PLAYERS, 116, function() W:SelectTab("players") end)
	f.tabPlayers:SetPoint("RIGHT", f.tabGear, "LEFT", -4, 0)
	f.tabTalents = Button(f, L.TAB_TALENTS, 100, function() W:SelectTab("talents") end)
	f.tabTalents:SetPoint("RIGHT", f.tabPlayers, "LEFT", -4, 0)

	-- Top players tab
	local pt = CreateFrame("Frame", nil, f)
	pt:SetPoint("TOPLEFT", 12, -76)
	pt:SetPoint("BOTTOMRIGHT", -12, 56)
	f.players = pt
	local ctxText = Text(pt, 12, { 0.8, 0.8, 0.8 })
	ctxText:SetPoint("TOPLEFT", 4, -2)
	ctxText:SetText(L.PLAYERS_CONTENT)
	local pPrev = Button(pt, "<", 24, function() CyclePlayersContext(-1) end)
	pPrev:SetPoint("LEFT", ctxText, "RIGHT", 8, 0)
	pt.ctxLabel = Text(pt, 13, GOLD, "CENTER")
	pt.ctxLabel:SetWidth(170)
	pt.ctxLabel:SetPoint("LEFT", pPrev, "RIGHT", 4, 0)
	local pNext = Button(pt, ">", 24, function() CyclePlayersContext(1) end)
	pNext:SetPoint("LEFT", pt.ctxLabel, "RIGHT", 4, 0)
	pt.subtitle = Text(pt, 10, { 0.6, 0.6, 0.66 })
	pt.subtitle:SetPoint("TOPLEFT", 4, -24)
	local scroll = CreateFrame("ScrollFrame", nil, pt, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -42)
	scroll:SetPoint("BOTTOMRIGHT", -24, 0)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(WIDTH - 60, MAX_PLAYERS * PLAYER_ROW_H)
	scroll:SetScrollChild(child)
	pt.child = child
	pt.rows = {}
	for i = 1, MAX_PLAYERS do pt.rows[i] = CreatePlayerRow(child, i) end
	pt.empty = Text(pt, 12, { 0.6, 0.6, 0.6 }, "CENTER")
	pt.empty:SetPoint("CENTER")
	pt.empty:SetText(L.NO_DATA)

	-- Talents tab
	local t = CreateFrame("Frame", nil, f)
	t:SetPoint("TOPLEFT", 12, -76)
	t:SetPoint("BOTTOMRIGHT", -12, 56)
	f.talents = t
	f.rows = {}
	for i, ctx in ipairs(ns.CONTEXTS) do f.rows[i] = CreateRow(t, ctx, i) end

	-- Gear tab
	local g = CreateFrame("Frame", nil, f)
	g:SetPoint("TOPLEFT", 16, -80)
	g:SetPoint("BOTTOMRIGHT", -16, 56)
	f.gear = g
	local compare = Text(g, 12, { 0.8, 0.8, 0.8 })
	compare:SetPoint("TOPLEFT", 0, 0)
	compare:SetText(L.GEAR_COMPARE)
	local prev = Button(g, "<", 24, function() CycleGearContext(-1) end)
	prev:SetPoint("LEFT", compare, "RIGHT", 8, 0)
	g.ctxLabel = Text(g, 13, GOLD, "CENTER")
	g.ctxLabel:SetWidth(170)
	g.ctxLabel:SetPoint("LEFT", prev, "RIGHT", 4, 0)
	local nextB = Button(g, ">", 24, function() CycleGearContext(1) end)
	nextB:SetPoint("LEFT", g.ctxLabel, "RIGHT", 4, 0)
	g.ilvl = Text(g, 12, { 0.85, 0.85, 0.85 })
	g.ilvl:SetPoint("TOPLEFT", 0, -30)
	local statsHeader = Text(g, 12, GOLD)
	statsHeader:SetPoint("TOPLEFT", 0, -56)
	statsHeader:SetText(L.GEAR_STATS)
	local statBox = CreateFrame("Frame", nil, g)
	statBox:SetPoint("TOPLEFT", 0, -76)
	statBox:SetSize(WIDTH - 40, 120)
	g.stats = {}
	for i, k in ipairs(ns.Gear.STATS) do g.stats[i] = CreateStatRow(statBox, k, i) end
	g.priority = Text(g, 11, { 0.8, 0.8, 0.8 })
	g.priority:SetPoint("TOPLEFT", 0, -196)
	local issuesHeader = Text(g, 12, GOLD)
	issuesHeader:SetPoint("TOPLEFT", 0, -218)
	issuesHeader:SetText(L.GEAR_ISSUES)
	-- Problems can be long (enchants, sockets): keep them in a scroll area.
	local issuesScroll = CreateFrame("ScrollFrame", nil, g, "UIPanelScrollFrameTemplate")
	issuesScroll:SetPoint("TOPLEFT", 0, -236)
	issuesScroll:SetPoint("BOTTOMRIGHT", -24, 4)
	local issuesChild = CreateFrame("Frame", nil, issuesScroll)
	issuesChild:SetSize(WIDTH - 76, 10)
	issuesScroll:SetScrollChild(issuesChild)
	g.issuesChild = issuesChild
	g.issues = Text(issuesChild, 11, { 1, 1, 1 })
	g.issues:SetPoint("TOPLEFT", 0, 0)
	g.issues:SetWidth(WIDTH - 80)
	g.issues:SetJustifyV("TOP")
	g.issues:SetSpacing(3)

	-- Footer
	local auto = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	auto:SetSize(24, 24)
	auto:SetPoint("BOTTOMLEFT", 10, 26)
	auto:SetScript("OnClick", function(self) ns.db.autoPrompt = self:GetChecked() and true or false end)
	auto:SetScript("OnShow", function(self) self:SetChecked(ns.db.autoPrompt) end)
	local autoText = Text(f, 12, { 0.9, 0.9, 0.9 })
	autoText:SetPoint("LEFT", auto, "RIGHT", 2, 0)
	autoText:SetText(L.PROMPT_AUTO)

	local autoLayout = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	autoLayout:SetSize(24, 24)
	autoLayout:SetPoint("LEFT", autoText, "RIGHT", 16, 0)
	autoLayout:SetScript("OnClick", function(self) ns.db.layout.auto = self:GetChecked() and true or false end)
	autoLayout:SetScript("OnShow", function(self) self:SetChecked(ns.db.layout.auto) end)
	local autoLayoutText = Text(f, 12, { 0.9, 0.9, 0.9 })
	autoLayoutText:SetPoint("LEFT", autoLayout, "RIGHT", 2, 0)
	autoLayoutText:SetText(L.LAYOUT_AUTO)

	local undo = Button(f, L.LAYOUT_UNDO, 124, function() ns.ActionBars.Restore() end)
	undo:SetPoint("BOTTOMRIGHT", -20, 28)
	local layout = Button(f, L.LAYOUT_BUTTON, 110, function()
		ns.db.layout.confirmed = true
		ns.ActionBars.Apply()
	end)
	layout:SetPoint("RIGHT", undo, "LEFT", -4, 0)
	Tooltip(layout, function(tt)
		tt:SetText(L.LAYOUT_BUTTON)
		tt:AddLine(L.LAYOUT_TT, 1, 1, 1, true)
	end)

	f.dataInfo = Text(f, 10, { 0.55, 0.55, 0.6 })
	f.dataInfo:SetPoint("BOTTOMLEFT", 14, 10)

	-- Resize grip
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnMouseDown", function(self)
		self.startX = GetCursorPosition()
		self.startScale = f:GetScale()
		self:SetScript("OnUpdate", function()
			local x = GetCursorPosition()
			local delta = (x - self.startX) / UIParent:GetEffectiveScale()
			SetScale(f, self.startScale * (1 + delta / (WIDTH * self.startScale)))
		end)
	end)
	grip:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)

	f:SetScript("OnShow", function() W:Refresh() end)
	ApplyPosition(f)
	self:SelectTab("talents")
end

-- ctx (optional) preselects the content on the Top players tab.
function ns:ShowWindow(tab, ctx)
	if not W.frame then W:Create() end
	if ctx then ns.db.playersContext = ctx end
	W.frame:Show()
	W:SelectTab(tab or W.frame.tab or "talents")
end

function ns:ToggleWindow()
	if W.frame and W.frame:IsShown() then
		W.frame:Hide()
	else
		self:ShowWindow()
	end
end

-- Keep the window current.
local refresh = function() W:Refresh() end
for _, e in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED",
	"PLAYER_EQUIPMENT_CHANGED", "COMBAT_RATING_UPDATE", "ZONE_CHANGED_NEW_AREA" }) do
	ns:RegisterEvent(e, function() C_Timer.After(0.3, refresh) end)
end
ns:On("LOADOUT_CHANGED", function() C_Timer.After(0.5, refresh) end)
ns:On("WINDOW_RESET", function() if W.frame then ApplyPosition(W.frame) end end)

-- Launcher button on Blizzard's talent window.
local function AddTalentFrameButton()
	local parent = PlayerSpellsFrame
	if not parent or parent.DarkndarkButton then return end
	local b = Button(parent, "Darkndark", 96, function() ns:ToggleWindow() end)
	b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -60, -1)
	b:SetFrameLevel(parent:GetFrameLevel() + 20)
	parent.DarkndarkButton = b
end

ns:RegisterEvent("ADDON_LOADED", function(_, name)
	if name == "Blizzard_PlayerSpells" then AddTalentFrameButton() end
end)
ns:On("LOGIN", AddTalentFrameButton)
