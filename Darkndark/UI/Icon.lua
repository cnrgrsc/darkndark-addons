local _, ns = ...
local U = ns.U
local S = ns.Spells

-- Reusable spell icon: texture, cooldown swipe, keybind text, proc glow, tints.
local Icon = {}
ns.Icon = Icon

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local QUESTION_MARK = 134400
local WHITE = "Interface\\Buttons\\WHITE8X8"
local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"

local IconMixin = {}

function IconMixin:SetIconSize(size, fontSize)
	self:SetSize(size, size)
	self.glow:SetSize(size * 1.9, size * 1.9)
	self.hotkey:SetFont(FONT, fontSize or 12, "OUTLINE")
	self.label:SetFont(FONT, math.max(8, math.floor((fontSize or 12) * 0.75)), "OUTLINE")
end

function IconMixin:SetSpell(id)
	if self.spell == id then return end
	self.spell = id
	self.cdSpell = nil
	if id then
		self.icon:SetTexture(S.Texture(id) or QUESTION_MARK)
	else
		self.icon:SetTexture(QUESTION_MARK)
	end
end

function IconMixin:SetKeybind(text)
	if self.keyText == text then return end
	self.keyText = text
	self.hotkey:SetText(text or "")
end

function IconMixin:SetLabel(text)
	self.label:SetText(text or "")
end

function IconMixin:SetGlow(on)
	on = on and true or false
	if self.glowing == on then return end
	self.glowing = on
	if on then
		self.glow:Show()
		self.glowAnim:Play()
	else
		self.glowAnim:Stop()
		self.glow:Hide()
	end
end

-- state: "range" (red), "mana" (blue), "unusable" (grey) or nil.
function IconMixin:SetTint(state)
	if self.tint == state then return end
	self.tint = state
	if state == "range" then
		self.icon:SetVertexColor(1, 0.3, 0.3)
	elseif state == "mana" then
		self.icon:SetVertexColor(0.4, 0.55, 1)
	elseif state == "unusable" then
		self.icon:SetVertexColor(0.55, 0.55, 0.55)
	else
		self.icon:SetVertexColor(1, 1, 1)
	end
end

function IconMixin:SetDesaturated(on)
	on = on and true or false
	if self.desat == on then return end
	self.desat = on
	self.icon:SetDesaturated(on)
end

-- Refreshes the swipe only when the spell or cooldown state changed.
function IconMixin:UpdateCooldown(id, enabled)
	if not enabled or not id then
		if self.cdSpell then
			self.cd:Clear()
			self.cdSpell = nil
		end
		return
	end
	local serial = S.cdSerial
	if self.cdSpell == id and self.cdSerial == serial then return end
	self.cdSpell, self.cdSerial = id, serial

	-- Preferred: duration objects work even when the numbers are secret.
	if self.cd.SetCooldownFromDurationObject and C_Spell.GetSpellCooldownDuration then
		local ok, d = pcall(C_Spell.GetSpellCooldownDuration, id)
		if ok and (U.issecret(d) or d) then
			if pcall(self.cd.SetCooldownFromDurationObject, self.cd, d, true) then return end
		end
	end
	local ok, info = pcall(C_Spell.GetSpellCooldown, id)
	local start = ok and info and U.Safe(info.startTime)
	local dur = ok and info and U.Safe(info.duration)
	if start and dur and dur > 0 then
		self.cd:SetCooldown(start, dur)
	else
		self.cd:Clear()
	end
end

function Icon:Create(parent)
	local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	Mixin(b, IconMixin)
	b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	b:SetBackdropColor(0, 0, 0, 0.5)
	b:SetBackdropBorderColor(0, 0, 0, 1)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.icon:SetTexture(QUESTION_MARK)

	b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cd:SetAllPoints(b.icon)
	b.cd:SetDrawEdge(false)
	b.cd:SetDrawBling(false)
	b.cd:SetHideCountdownNumbers(true)

	b.overlay = CreateFrame("Frame", nil, b)
	b.overlay:SetAllPoints()
	b.overlay:SetFrameLevel(b.cd:GetFrameLevel() + 2)

	b.glow = b.overlay:CreateTexture(nil, "OVERLAY")
	b.glow:SetTexture(GLOW_TEXTURE)
	b.glow:SetBlendMode("ADD")
	b.glow:SetVertexColor(1, 0.82, 0.2)
	b.glow:SetPoint("CENTER")
	b.glow:Hide()
	b.glowAnim = b.glow:CreateAnimationGroup()
	b.glowAnim:SetLooping("BOUNCE")
	local a = b.glowAnim:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.35)
	a:SetDuration(0.45)

	b.hotkey = b.overlay:CreateFontString(nil, "OVERLAY")
	b.hotkey:SetPoint("TOPRIGHT", -2, -3)
	b.hotkey:SetJustifyH("RIGHT")
	b.hotkey:SetTextColor(1, 1, 1)

	b.label = b.overlay:CreateFontString(nil, "OVERLAY")
	b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
	b.label:SetTextColor(0.7, 0.85, 1)

	b:SetIconSize(40, 12)
	return b
end
