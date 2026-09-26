local function step(name, fn)
  local ok, e = pcall(fn)
  if not ok then FAILED = (FAILED or 0) + 1 end
  io_write((ok and "PASS " or "FAIL ") .. name .. (ok and "" or ("  -> " .. tostring(e))))
end
local D = NS.Display
step("addon loaded + login", function()
  FireEvent("ADDON_LOADED", "Darkndark"); FireEvent("PLAYER_LOGIN"); FireEvent("PLAYER_ENTERING_WORLD")
  RunTimers(); RunTimers()
end)
step("refresh out of combat", function()
  RunOnUpdate(0.1)
  local p = D.main.primary
  assert(p.spell == 1752, "primary " .. tostring(p.spell))
  assert(p.keyText == "S1", "key " .. tostring(p.keyText))
  io_write("   primary=" .. p.spell .. " key=" .. p.keyText .. " source=" .. tostring(NS.Engine.result.source))
  io_write("   queue=" .. table.concat(NS.Engine.result.queue, ","))
  assert(NS.Engine.result.queue[1] == 196819, "proc should be first in queue")
  assert(D.main.queue[1].keyText == "M4", "macro key " .. tostring(D.main.queue[1].keyText))
  assert(D.main.queue[1].glowing, "proc glow")
  io_write("   cooldowns=" .. table.concat(NS.Cooldowns.list, ","))
  assert(#NS.Cooldowns.list == 1 and NS.Cooldowns.list[1] == 13750, "cd list")
  io_write("   interrupt=" .. tostring(NS.Interrupt.spellID))
  assert(NS.Interrupt.spellID == 1766)
end)
step("combat with secrets + target casting", function()
  SECRET_MODE = true; IN_COMBAT = true; HAS_TARGET = true; TARGET_CASTING = true
  FireEvent("PLAYER_REGEN_DISABLED"); FireEvent("UNIT_SPELLCAST_START", "target"); FireEvent("SPELL_UPDATE_COOLDOWN")
  RunTimers(); RunOnUpdate(0.1)
  assert(NS.Interrupt.targetCasting, "target casting")
  assert(D.interrupt._shown, "interrupt shown")
  assert(D.interrupt.icon.glowing, "interrupt glow")
  assert(D.main.primary.spell == 1752)
  assert(D.cooldowns.icons[1].desat == true, "13750 on cd -> desaturated")
end)
step("profile override with secret power", function()
  NS:RegisterProfile(260, { key = "t", priority = {
    { spell = 315496, when = function(s) return s.powerAtLeast(4, 5) end },   -- secret -> nil -> skip
    { spell = 51690, when = function(s) return s.enemiesAtLeast(2) end },      -- enemies secret-ish
    { spell = 196819, when = function(s) return s.proc(196819) end },
  }})
  RunOnUpdate(0.1)
  io_write("   primary=" .. tostring(NS.Engine.result.primary) .. " source=" .. tostring(NS.Engine.result.source) .. " queue=" .. table.concat(NS.Engine.result.queue, ","))
  assert(NS.Engine.result.primary == 196819 and NS.Engine.result.source == "profile")
  assert(NS.Engine.result.queue[1] == 1752, "blizzard pick queued first")
end)
step("unlock / scale / lock", function()
  SlashCmdList.DARKNDARK("unlock"); RunOnUpdate(0.1)
  assert(D.main.mover._shown)
  D.main.mover._scripts.OnMouseWheel(D.main.mover, 1)
  assert(math.abs(NS.db.frames.main.scale - 1.05) < 1e-9, "scale " .. NS.db.frames.main.scale)
  SlashCmdList.DARKNDARK("scale 5"); assert(NS.db.frames.main.scale == 3)
  D.main.mover._scripts.OnDragStop(D.main.mover)
  SlashCmdList.DARKNDARK("lock"); assert(not D.main.mover._shown)
  SlashCmdList.DARKNDARK("reset"); assert(NS.db.frames.main.scale == 1)
end)
step("all settings get/set", function()
  for _, s in ipairs(SETTINGS) do s.set(s.get()) end
  io_write("   settings=" .. #SETTINGS)
  RunOnUpdate(0.1)
end)
step("directions + queue lengths", function()
  for _, dir in ipairs({ "LEFT", "UP", "DOWN", "RIGHT" }) do
    for n = 0, 4 do NS.db.direction = dir; NS.db.queueLength = n; NS:Fire("LAYOUT_CHANGED"); RunOnUpdate(0.1) end
  end
end)
step("probe (secret mode)", function()
  SlashCmdList.DARKNDARK("probe")
  io_write(_G.DarkndarkProbeWindow.edit._text)
end)
step("visibility combat-only out of combat hides", function()
  SECRET_MODE = false; IN_COMBAT = false; TARGET_CASTING = false
  NS.db.visibility = "combat"; RunOnUpdate(0.1)
  assert(not D.main._shown)
end)
step("help + toggle + debug + cdreset + config", function()
  SlashCmdList.DARKNDARK(""); SlashCmdList.DARKNDARK("toggle"); SlashCmdList.DARKNDARK("toggle")
  SlashCmdList.DARKNDARK("debug"); SlashCmdList.DARKNDARK("cdreset"); SlashCmdList.DARKNDARK("config")
  assert(OPENED == 42)
end)
step("defensives bar", function()
  NS.db.visibility = "always"; NS.db.enabled = true
  RunOnUpdate(0.1)
  io_write("   defensives=" .. table.concat(NS.Cooldowns.defensives, ","))
  assert(#NS.Cooldowns.defensives == 4, "rogue defensives")
  assert(D.defensives._shown and D.defensives.icons[4]._shown, "defensive icons shown")
  for _, id in ipairs(NS.Cooldowns.list) do assert(not NS.Cooldowns.defensiveSet[id], "no overlap") end
end)
step("hold cooldowns", function()
  NS.db.holdCooldowns = true; CD_ACTIVE[13750] = false; NEXT_SPELL = 13750
  RunOnUpdate(0.1)
  local r = NS.Engine.result
  io_write("   primary=" .. tostring(r.primary) .. " source=" .. tostring(r.source) .. " held=" .. tostring(r.held))
  assert(r.held == 13750 and r.primary ~= 13750, "held cd not primary")
  for _, q in ipairs(r.queue) do assert(q ~= 13750, "held cd not queued") end
  assert(D.cooldowns.icons[1].spell == 13750 and D.cooldowns.icons[1].glowing, "held cd glows on bar")
  NS.db.holdCooldowns = false; NEXT_SPELL = nil; CD_ACTIVE[13750] = true
end)
step("kick sound once per cast", function()
  NS.db.interrupt.onlyWhenCasting = true
  TARGET_CASTING = false; FireEvent("UNIT_SPELLCAST_STOP", "target"); RunTimers(); RunOnUpdate(0.1)
  IN_COMBAT = true; HAS_TARGET = true; TARGET_CASTING = true
  local before = #SOUNDS_PLAYED
  FireEvent("UNIT_SPELLCAST_START", "target"); RunTimers()
  RunOnUpdate(0.1); RunOnUpdate(0.1); RunOnUpdate(0.1)
  assert(#SOUNDS_PLAYED == before + 1, "played " .. (#SOUNDS_PLAYED - before))
  TARGET_CASTING = false; FireEvent("UNIT_SPELLCAST_STOP", "target"); RunTimers(); RunOnUpdate(0.1)
  TARGET_CASTING = true; FireEvent("UNIT_SPELLCAST_START", "target"); RunTimers(); RunOnUpdate(0.1)
  assert(#SOUNDS_PLAYED == before + 2, "second cast plays again")
  IN_COMBAT = false; TARGET_CASTING = false
end)
step("masque integration", function()
  local added = 0
  LibStub = function() return { Group = function() return { AddButton = function() added = added + 1 end } end } end
  NS.Skin:Register(D.main.primary, "x")
  assert(added == 1)
  LibStub = nil
end)
step("addon compartment opens settings", function()
  OPENED = nil
  Darkndark_OnAddonCompartmentClick()
  assert(OPENED == 42)
  assert(_G.DarkndarkMinimapButton == nil, "no minimap button in the rotation addon")
end)
