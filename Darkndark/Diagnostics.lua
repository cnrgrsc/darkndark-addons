local _, ns = ...
local U = ns.U
local S = ns.Spells
local issecret = U.issecret

-- /dnd probe: reports which combat data is readable right now and shows the
-- report in a copyable window so it can be pasted back for development.

local function Desc(v)
	if issecret(v) then return "SECRET" end
	if v == nil then return "nil" end
	return tostring(v)
end

local function Call(fn, ...)
	if not fn then return "missing" end
	local function pack(ok, ...)
		if not ok then return "error: " .. tostring((...)) end
		local n = select("#", ...)
		if n == 0 then return "(nothing)" end
		local parts = {}
		for i = 1, math.min(n, 4) do parts[i] = Desc((select(i, ...))) end
		return table.concat(parts, ", ")
	end
	return pack(pcall(fn, ...))
end

local function SpellReport(lines, id)
	local name = S.Name(id) or "?"
	lines[#lines + 1] = ("  [%d] %s"):format(id, name)
	local ok, info = pcall(C_Spell.GetSpellCooldown, id)
	if ok and info then
		lines[#lines + 1] = ("    cooldown: start=%s dur=%s isActive=%s isOnGCD=%s"):format(
			Desc(info.startTime), Desc(info.duration), Desc(info.isActive), Desc(info.isOnGCD))
	else
		lines[#lines + 1] = "    cooldown: " .. (ok and "nil" or "error")
	end
	local okc, ch = pcall(C_Spell.GetSpellCharges, id)
	if okc and not issecret(ch) and ch then
		lines[#lines + 1] = ("    charges: cur=%s max=%s"):format(Desc(ch.currentCharges), Desc(ch.maxCharges))
	end
	local okd, dur = pcall(C_Spell.GetSpellCooldownDuration, id)
	lines[#lines + 1] = ("    durationObject=%s  usable=%s  inRange=%s  overlay=%s  baseCD=%s"):format(
		okd and (issecret(dur) and "SECRET" or type(dur)) or "error",
		Call(C_Spell.IsSpellUsable, id), Call(C_Spell.IsSpellInRange, id, "target"),
		Call(C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed, id),
		Desc(S.baseCD[id]))
	lines[#lines + 1] = ("    => ready=%s castable=%s proc=%s key=%s"):format(
		Desc(S.IsReady(id)), Desc(S.IsCastable(id)), Desc(S.IsProc(id)), Desc(ns.Keybinds:Get(id)))
end

function ns:BuildProbeReport()
	S:BeginTick()
	local lines = {}
	local function add(fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

	local _, build, _, toc = GetBuildInfo()
	add("Darkndark %s | build %s | toc %s | %s", ns.version, Desc(build), Desc(toc), date("%Y-%m-%d %H:%M:%S"))
	add("class=%s spec=%s inCombat=%s instance=%s", S.class, Desc(S.specID), Desc(U.InCombat()),
		Call(IsInInstance))

	add("")
	add("Restrictions:")
	if Enum.AddOnRestrictionType then
		for name in pairs(Enum.AddOnRestrictionType) do
			add("  %s = %s", name, tostring(U.IsRestricted(name)))
		end
	else
		add("  (Enum.AddOnRestrictionType missing)")
	end

	add("")
	add("AssistedCombat:")
	add("  IsAvailable: %s", Call(C_AssistedCombat and C_AssistedCombat.IsAvailable))
	add("  GetNextCastSpell: %s", Call(C_AssistedCombat and C_AssistedCombat.GetNextCastSpell, false))
	add("  GetActionSpell: %s", Call(C_AssistedCombat and C_AssistedCombat.GetActionSpell))
	add("  rotation spells: %d", #S.rotation)

	add("")
	add("Spells:")
	local seen = {}
	local next = ns.Engine:BlizzardSuggestion()
	if next then
		SpellReport(lines, next)
		seen[next] = true
	end
	for i = 1, math.min(#S.rotation, 6) do
		local id = S.rotation[i]
		if not seen[id] then
			SpellReport(lines, id)
			seen[id] = true
		end
	end
	if ns.Interrupt.spellID then
		add("  interrupt:")
		SpellReport(lines, ns.Interrupt.spellID)
	end

	add("")
	add("Power (player):")
	if Enum.PowerType then
		for name, ptype in pairs(Enum.PowerType) do
			if type(ptype) == "number" and ptype >= 0 then
				local okm, max = pcall(UnitPowerMax, "player", ptype)
				if okm and (issecret(max) or (max and max > 0)) then
					add("  %s(%d): cur=%s max=%s", name, ptype, Call(UnitPower, "player", ptype), Desc(max))
				end
			end
		end
	end

	add("")
	add("Auras (player):")
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 5 do
			local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
			if not ok then add("  #%d error", i) break end
			if issecret(a) then
				add("  #%d SECRET", i)
			elseif a == nil then
				break
			else
				add("  #%d id=%s name=%s stacks=%s dur=%s", i, Desc(a.spellId), Desc(a.name), Desc(a.applications), Desc(a.duration))
			end
		end
	end

	add("")
	add("Target:")
	add("  exists=%s canAttack=%s health=%s healthPct=%s", Desc(UnitExists("target")),
		Call(UnitCanAttack, "player", "target"), Call(UnitHealth, "target"), Call(UnitHealthPercent, "target"))
	add("  castingInfo: %s", Call(UnitCastingInfo, "target"))
	add("  targetCasting(tracked)=%s notInterruptible=%s", tostring(ns.Interrupt.targetCasting), tostring(ns.Interrupt.notInterruptible))
	add("  enemies(nameplates)=%s", Desc(S.EnemyCount()))

	add("")
	add("Engine: primary=%s source=%s profile=%s", Desc(ns.Engine.result.primary), Desc(ns.Engine.result.source),
		ns.Engine.result.profile and ns.Engine.result.profile.name or "none")
	add("Cooldown bar: %d spells", #ns.Cooldowns.list)

	return table.concat(lines, "\n")
end

local window
local function GetWindow()
	if window then return window end
	local f = CreateFrame("Frame", "DarkndarkProbeWindow", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(640, 480)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -6)
	title:SetText("Darkndark probe  (Ctrl+A, Ctrl+C)")

	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 12, -32)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(590)
	edit:SetAutoFocus(false)
	edit:SetScript("OnEscapePressed", function() f:Hide() end)
	scroll:SetScrollChild(edit)
	f.edit = edit

	tinsert(UISpecialFrames, "DarkndarkProbeWindow")
	window = f
	return f
end

function ns:RunProbe()
	local ok, report = pcall(self.BuildProbeReport, self)
	if not ok then report = "probe failed: " .. tostring(report) end
	local f = GetWindow()
	f.edit:SetText(report)
	f.edit:HighlightText()
	f.edit:SetFocus()
	f:Show()
end
