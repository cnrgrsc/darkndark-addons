local _, ns = ...
local L = ns.L
local U = ns.U
local S = ns.Spells
local K = ns.Keybinds
local E = ns.Engine
local I = ns.Interrupt
local Icon = ns.Icon

-- Three independent, movable/resizable panels: main (recommendation + queue),
-- cooldowns (major CD bar) and interrupt.
local D = {}
ns.Display = D
D.containers = {}

local MIN_SCALE, MAX_SCALE = 0.4, 3
local MAX_QUEUE = 4
local PLACEHOLDER = 134400

---------------------------------------------------------------------------
-- Containers with mover overlay
---------------------------------------------------------------------------
local function SavePosition(f)
	local point, _, relPoint, x, y = f:GetPoint(1)
	local cfg = ns.db.frames[f.key]
	cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint, x, y
end

local function ApplyPosition(f)
	local cfg = ns.db.frames[f.key]
	f:ClearAllPoints()
	f:SetScale(cfg.scale or 1)
	f:SetPoint(cfg.point or "CENTER", UIParent, cfg.relPoint or "CENTER", cfg.x or 0, cfg.y or 0)
end

function ns:SetFrameScale(key, value)
	local f = D.containers[key]
	local cfg = self.db.frames[key]
	if not (f and cfg) then return end
	value = U.Clamp(value, MIN_SCALE, MAX_SCALE)
	local old = f:GetScale()
	-- Keep the anchor point fixed on screen: offsets are in the frame's scale.
	cfg.x = (cfg.x or 0) * old / value
	cfg.y = (cfg.y or 0) * old / value
	cfg.scale = value
	ApplyPosition(f)
end

local function CreateGrip(f)
	local grip = CreateFrame("Button", nil, f.mover)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", 2, -2)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function(self)
		self.startX = GetCursorPosition()
		self.startScale = f:GetScale()
		self:SetScript("OnUpdate", function()
			local x = GetCursorPosition()
			local delta = (x - self.startX) / UIParent:GetEffectiveScale()
			local width = math.max(f:GetWidth() * self.startScale, 20)
			ns:SetFrameScale(f.key, self.startScale * (1 + delta / width))
		end)
	end)
	grip:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	return grip
end

local function CreateContainer(key, label)
	local f = CreateFrame("Frame", "Darkndark" .. key:gsub("^%l", string.upper) .. "Frame", UIParent)
	f.key = key
	f:SetSize(40, 40)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:SetFrameStrata("MEDIUM")

	local m = CreateFrame("Frame", nil, f, "BackdropTemplate")
	f.mover = m
	m:SetPoint("TOPLEFT", -4, 4)
	m:SetPoint("BOTTOMRIGHT", 4, -4)
	m:SetFrameLevel(f:GetFrameLevel() + 20)
	m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	m:SetBackdropColor(0.1, 0.8, 0.3, 0.25)
	m:SetBackdropBorderColor(0.2, 1, 0.4, 0.9)
	m:EnableMouse(true)
	m:EnableMouseWheel(true)
	m:RegisterForDrag("LeftButton")
	m:Hide()

	m.text = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	m.text:SetPoint("BOTTOM", m, "TOP", 0, 2)
	m.text:SetText(label)

	m:SetScript("OnDragStart", function() f:StartMoving() end)
	m:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		SavePosition(f)
	end)
	m:SetScript("OnMouseWheel", function(_, delta)
		ns:SetFrameScale(key, f:GetScale() + delta * 0.05)
	end)
	m:SetScript("OnMouseUp", function(_, button)
		if button ~= "RightButton" then return end
		if IsShiftKeyDown() and f.OnShiftRightClick then
			f:OnShiftRightClick()
		else
			ns:OpenOptions()
		end
	end)
	m:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(label)
		GameTooltip:AddLine(L.MOVER_HINT, 1, 1, 1, true)
		if f.extraHint then GameTooltip:AddLine(f.extraHint, 0.7, 0.85, 1, true) end
		GameTooltip:Show()
	end)
	m:SetScript("OnLeave", GameTooltip_Hide)

	CreateGrip(f)
	D.containers[key] = f
	return f
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------
local function HostileTarget()
	if not UnitExists("target") then return false end
	-- Unknown (secret) counts as hostile/alive so we never hide useful info.
	if U.Bool(UnitCanAttack("player", "target")) == false then return false end
	return U.Bool(UnitIsDeadOrGhost("target")) ~= true
end

function D:ShouldShow()
	local db = ns.db
	if not db.enabled then return false end
	if not db.locked then return true end
	if C_PetBattles and C_PetBattles.IsInBattle() then return false end
	if UnitHasVehicleUI and U.Bool(UnitHasVehicleUI("player")) then return false end
	if U.Bool(UnitIsDeadOrGhost("player")) then return false end
	local combat = U.InCombat()
	if db.visibility == "combat" then return combat end
	if db.visibility == "hostile" then return combat or HostileTarget() end
	return true
end

---------------------------------------------------------------------------
-- Main panel
---------------------------------------------------------------------------
function D:LayoutMain()
	local f, db = self.main, ns.db
	local size = db.iconSize
	local qsize = math.floor(size * db.queueScale + 0.5)
	local sp = db.spacing
	local n = U.Clamp(db.queueLength, 0, MAX_QUEUE)
	local qfont = math.max(8, math.floor(db.keybindSize * db.queueScale + 0.5))

	local p = f.primary
	p:SetIconSize(size, db.keybindSize)
	p:ClearAllPoints()

	local dir = db.direction
	local horizontal = dir == "RIGHT" or dir == "LEFT"
	local anchor, rel, dx, dy
	if dir == "RIGHT" then
		p:SetPoint("LEFT", f, "LEFT", 0, 0)
		anchor, rel, dx, dy = "LEFT", "RIGHT", sp, 0
	elseif dir == "LEFT" then
		p:SetPoint("RIGHT", f, "RIGHT", 0, 0)
		anchor, rel, dx, dy = "RIGHT", "LEFT", -sp, 0
	elseif dir == "UP" then
		p:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
		anchor, rel, dx, dy = "BOTTOM", "TOP", 0, sp
	else
		p:SetPoint("TOP", f, "TOP", 0, 0)
		anchor, rel, dx, dy = "TOP", "BOTTOM", 0, -sp
	end

	local prev = p
	for i = 1, MAX_QUEUE do
		local q = f.queue[i]
		q:ClearAllPoints()
		if i <= n then
			q:SetIconSize(qsize, qfont)
			q:SetPoint(anchor, prev, rel, dx, dy)
			prev = q
			q.active = true
		else
			q.active = false
			q:Hide()
		end
	end

	local extent = size + n * (qsize + sp)
	if horizontal then
		f:SetSize(extent, size)
	else
		f:SetSize(size, extent)
	end
end

local function ApplySpellState(icon, id, db)
	icon:SetSpell(id)
	icon:SetKeybind(db.showKeybinds and K:Get(id) or nil)
	local usable, noMana = S.IsUsable(id)
	local tint
	if db.rangeTint and S.InRange(id) == false then
		tint = "range"
	elseif db.usableTint and noMana then
		tint = "mana"
	elseif usable == false then
		tint = "unusable"
	end
	icon:SetTint(tint)
	icon:SetGlow(db.glowProcs and S.IsProc(id))
	icon:UpdateCooldown(id, db.showSwipe)
end

local SOURCE_LABELS = { profile = "SRC_PROFILE", blizzard = "SRC_BLIZZARD", fallback = "SRC_FALLBACK" }

function D:RefreshMain(visible)
	local f, db = self.main, ns.db
	if not visible then
		f:Hide()
		return
	end
	local res = E:Compute(db.queueLength)
	local unlocked = not db.locked

	if res.primary then
		ApplySpellState(f.primary, res.primary, db)
		f.primary:SetLabel(db.debug and L[SOURCE_LABELS[res.source]] or nil)
		f.primary:Show()
		local glowing = f.primary.glowing
		if glowing and not f.wasGlowing and db.sounds.proc and U.InCombat() then
			D:PlayAlert("proc")
		end
		f.wasGlowing = glowing
	elseif unlocked then
		f.primary:SetSpell(nil)
		f.primary:SetKeybind(nil)
		f.primary:SetGlow(false)
		f.primary:SetLabel(nil)
		f.primary:Show()
	else
		f:Hide()
		return
	end

	for i = 1, MAX_QUEUE do
		local q = f.queue[i]
		local id = res.queue[i]
		if q.active and id then
			ApplySpellState(q, id, db)
			q:Show()
		elseif q.active and unlocked then
			q:SetSpell(nil)
			q:SetKeybind(nil)
			q:SetGlow(false)
			q:Show()
		else
			q:Hide()
		end
	end

	f:SetAlpha(U.InCombat() and 1 or db.oocAlpha)
	f:Show()
end

---------------------------------------------------------------------------
-- Icon bars (major cooldowns, defensives)
---------------------------------------------------------------------------
local function GetBarIcon(f, i)
	local b = f.icons[i]
	if not b then
		b = Icon:Create(f)
		f.icons[i] = b
		if ns.Skin then ns.Skin:Register(b, f.skinGroup) end
	end
	return b
end

function D:RefreshBar(f, list, cfg, visible, heldID)
	local db = ns.db
	if not (visible and cfg.enabled) then
		f:Hide()
		return
	end
	local unlocked = not db.locked
	local size = cfg.iconSize
	local sp = db.spacing
	local shown = 0
	local limit = math.min(#list, cfg.max)

	for i = 1, limit do
		local id = list[i]
		local ready = S.IsReady(id) ~= false
		if ready or not cfg.readyOnly or unlocked then
			shown = shown + 1
			local b = GetBarIcon(f, shown)
			b:SetIconSize(size, math.max(8, math.floor(size * 0.3)))
			b:ClearAllPoints()
			b:SetPoint("LEFT", f, "LEFT", (shown - 1) * (size + sp), 0)
			b:SetSpell(id)
			b:SetKeybind(db.showKeybinds and K:Get(id) or nil)
			b:SetDesaturated(not ready)
			b:SetTint(nil)
			-- Glow when it procs, or when Blizzard wants it but we're holding it.
			b:SetGlow((db.glowProcs and S.IsProc(id)) or (ready and id == heldID))
			b:UpdateCooldown(id, db.showSwipe)
			b:Show()
		end
	end
	for i = shown + 1, #f.icons do f.icons[i]:Hide() end

	if shown == 0 and unlocked then
		local b = GetBarIcon(f, 1)
		b:SetIconSize(size, 10)
		b:ClearAllPoints()
		b:SetPoint("LEFT", f, "LEFT", 0, 0)
		b:SetSpell(nil)
		b:SetKeybind(nil)
		b:SetGlow(false)
		b:SetDesaturated(false)
		b:Show()
		shown = 1
	end

	if shown == 0 then
		f:Hide()
		return
	end
	f:SetSize(shown * size + (shown - 1) * sp, size)
	f:SetAlpha(U.InCombat() and 1 or db.oocAlpha)
	f:Show()
end

---------------------------------------------------------------------------
-- Interrupt icon
---------------------------------------------------------------------------
function D:RefreshInterrupt(visible)
	local f, db = self.interrupt, ns.db
	local cfg = db.interrupt
	local id = I.spellID
	local unlocked = not db.locked
	local casting = I.targetCasting and HostileTarget()
	if not (visible and cfg.enabled and (id or unlocked))
		or (not unlocked and cfg.onlyWhenCasting and not casting) then
		f.alerted = false
		f:Hide()
		return
	end

	local b = f.icon
	b:SetIconSize(cfg.iconSize, math.max(8, math.floor(cfg.iconSize * 0.3)))
	f:SetSize(cfg.iconSize, cfg.iconSize)
	b:SetSpell(id)
	b:SetKeybind(db.showKeybinds and id and K:Get(id) or nil)
	local ready = id and S.IsReady(id) ~= false
	local kickNow = ready and casting and not I.notInterruptible
	b:SetDesaturated(id and not ready)
	b:SetTint(casting and I.notInterruptible and "range" or nil)
	b:SetGlow(kickNow)
	b:UpdateCooldown(id, db.showSwipe)
	if kickNow and not f.alerted and db.sounds.kick and not unlocked then
		D:PlayAlert("kick")
	end
	f.alerted = kickNow
	f:SetAlpha(U.InCombat() and 1 or db.oocAlpha)
	f:Show()
end

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------
local ALERT_SOUNDS = {
	kick = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,
	proc = SOUNDKIT and SOUNDKIT.UI_GARRISON_MISSION_COMPLETE_ENCOUNTER_CHANCE or 12867,
}

function D:PlayAlert(kind)
	local id = ALERT_SOUNDS[kind]
	if id then pcall(PlaySound, id, "Master") end
end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------
function D:Refresh()
	local visible = self:ShouldShow()
	self:RefreshMain(visible)
	local C = ns.Cooldowns
	local held = E.result.held
	self:RefreshBar(self.cooldowns, C.list, ns.db.cooldowns, visible, held)
	self:RefreshBar(self.defensives, C.defensives, ns.db.defensives, visible, held)
	self:RefreshInterrupt(visible)
end

function D:ApplyLayout()
	for _, f in pairs(self.containers) do ApplyPosition(f) end
	self:LayoutMain()
	self:Refresh()
end

function D:ApplyLock()
	local unlocked = not ns.db.locked
	for _, f in pairs(self.containers) do
		f.mover:SetShown(unlocked)
	end
	self:Refresh()
end

local function HideHoveredIcon(f)
	for _, b in ipairs(f.icons) do
		if b:IsShown() and b.spell and b:IsMouseOver() then
			ns.Cooldowns:Hide(b.spell)
			return
		end
	end
end

local function CreateBar(key, label)
	local f = CreateContainer(key, label)
	f.icons = {}
	f.skinGroup = label
	f.extraHint = L.HIDE_ICON_HINT
	f.OnShiftRightClick = HideHoveredIcon
	return f
end

function D:Init()
	local Skin = ns.Skin
	self.main = CreateContainer("main", L.FRAME_MAIN)
	self.main.primary = Icon:Create(self.main)
	self.main.queue = {}
	for i = 1, MAX_QUEUE do self.main.queue[i] = Icon:Create(self.main) end
	Skin:Register(self.main.primary, L.FRAME_MAIN)
	for i = 1, MAX_QUEUE do Skin:Register(self.main.queue[i], L.FRAME_MAIN) end

	self.cooldowns = CreateBar("cooldowns", L.FRAME_COOLDOWNS)
	self.defensives = CreateBar("defensives", L.FRAME_DEFENSIVES)

	self.interrupt = CreateContainer("interrupt", L.FRAME_INTERRUPT)
	self.interrupt.icon = Icon:Create(self.interrupt)
	self.interrupt.icon:SetPoint("CENTER")
	Skin:Register(self.interrupt.icon, L.FRAME_INTERRUPT)

	-- Separate always-shown driver so hidden panels can come back.
	local driver = CreateFrame("Frame")
	local elapsed = 0
	driver:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < ns.db.updateInterval then return end
		elapsed = 0
		D:Refresh()
	end)

	self:ApplyLayout()
	self:ApplyLock()
end

ns:On("LOGIN", function() D:Init() end)
ns:On("LAYOUT_CHANGED", function() if D.main then D:ApplyLayout() end end)
ns:On("LOCK_CHANGED", function() if D.main then D:ApplyLock() end end)
ns:On("SPELLS_CHANGED", function()
	-- Spell textures can change with talents: force icon texture refresh.
	if not D.main then return end
	D.main.primary.spell = nil
	for _, q in ipairs(D.main.queue) do q.spell = nil end
end)
