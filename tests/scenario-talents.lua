local function step(name, fn)
  local ok, e = pcall(fn)
  if not ok then FAILED = (FAILED or 0) + 1 end
  io_write((ok and "PASS " or "FAIL ") .. name .. (ok and "" or ("  -> " .. tostring(e))))
end
local LO = NS.Loadout

step("load + login", function()
  FireEvent("ADDON_LOADED", "DarkndarkTalents"); FireEvent("PLAYER_LOGIN"); RunTimers()
  assert(NS.db and NS.data, "db/data")
end)

step("reader matches Blizzard's ExtractValue", function()
  local widths = { 8, 16, 1, 1, 6, 2, 3, 8, 1, 5, 6, 1, 2, 7, 4, 1, 1, 1, 6, 2 }
  local code = NS.data.specs[70].contexts.solo.builds[1].code
  local a, b = LO.NewReader(code), BlizzReader(code)
  for round = 1, 30 do
    for _, w in ipairs(widths) do
      local x, y = a:Read(w), b:Extract(w)
      assert(x == y, ("width %d: %s vs %s"):format(w, tostring(x), tostring(y)))
    end
  end
end)

step("real Ret strings parse to spec 70", function()
  for ctx, c in pairs(NS.data.specs[70].contexts) do
    for _, b in ipairs(c.builds) do
      local h = LO.ParseHeader(b.code)
      assert(h and h.specID == 70, ctx .. " spec " .. tostring(h and h.specID))
      io_write(("   %s %s: version=%d"):format(ctx, b.hero, h.version))
    end
  end
end)

-- Build a synthetic string for the mock tree with a known selection.
local function Encode(selection)
  local e = { { 8, 2 }, { 16, 70 } }
  for _ = 1, 16 do e[#e + 1] = { 8, 0 } end
  for i = 1, #TREE do
    local s = selection[i]
    if not s then
      e[#e + 1] = { 1, 0 }
    else
      e[#e + 1] = { 1, 1 }; e[#e + 1] = { 1, 1 }
      if s.partial then e[#e + 1] = { 1, 1 }; e[#e + 1] = { 6, s.partial } else e[#e + 1] = { 1, 0 } end
      if s.choice then e[#e + 1] = { 1, 1 }; e[#e + 1] = { 2, s.choice - 1 } else e[#e + 1] = { 1, 0 } end
    end
  end
  return BlizzEncode(e)
end

local selection = { [1] = {}, [3] = {}, [7] = { partial = 1 }, [10] = { choice = 2 }, [14] = {}, [20] = { choice = 1 }, [33] = {} }
local code = Encode(selection)

step("apply creates DND loadout with exact entries", function()
  NS.Loadout.Apply(code, "DND Shuffle")
  assert(IMPORTED and IMPORTED.name == "DND Shuffle", "imported")
  local byNode = {}
  for _, en in ipairs(IMPORTED.entries) do byNode[en.nodeID - 1000] = en end
  local n = 0
  for i in pairs(byNode) do n = n + 1; assert(selection[i], "unexpected node " .. i) end
  assert(n == 7, "entries " .. n)
  assert(byNode[7].ranksPurchased == 1, "partial rank")
  assert(byNode[14].ranksPurchased == 2, "max ranks for 2-rank node")
  assert(byNode[10].selectionEntryID == TREE[10].entryIDs[2], "choice 2")
  assert(byNode[20].selectionEntryID == TREE[20].entryIDs[1], "choice 1")
  FireEvent("TRAIT_CONFIG_CREATED", PENDING_CREATED); RunTimers()
  assert(LOADED[#LOADED] == PENDING_CREATED.ID, "switched to new loadout")
  assert(LO.ActiveName() == "DND Shuffle")
end)

step("re-apply same build just switches", function()
  local before = #DELETED
  IMPORTED = nil
  NS.Loadout.Apply(code, "DND Shuffle")
  assert(IMPORTED == nil and #DELETED == before, "no reimport")
end)

step("updated build replaces old loadout", function()
  selection[40] = {}
  local code2 = Encode(selection)
  NS.Loadout.Apply(code2, "DND Shuffle")
  assert(#DELETED >= 1, "old deleted")
  FireEvent("TRAIT_CONFIG_DELETED", PENDING_DELETED); RunTimers()
  assert(IMPORTED and IMPORTED.code == code2, "reimported")
  FireEvent("TRAIT_CONFIG_CREATED", PENDING_CREATED); RunTimers()
end)

step("wrong spec / version rejected", function()
  SPEC_ID = 66
  IMPORTED = nil
  NS.Loadout.Apply(code, "DND X"); RunTimers()
  assert(IMPORTED == nil, "spec mismatch must not import")
  SPEC_ID = 70
  C_Traits.GetLoadoutSerializationVersion = function() return 3 end
  NS.Loadout.Apply(code, "DND X")
  assert(IMPORTED == nil, "version mismatch must not import")
  C_Traits.GetLoadoutSerializationVersion = function() return 2 end
end)

step("combat blocks apply", function()
  IN_COMBAT = true; IMPORTED = nil
  NS.Loadout.Apply(code, "DND Y")
  assert(IMPORTED == nil); IN_COMBAT = false
end)

step("similarity", function()
  for i, s in pairs(selection) do
    TREE[i].ranksPurchased = s.partial or TREE[i].maxRanks
    if s.choice then TREE[i].activeEntryID = TREE[i].entryIDs[s.choice] end
  end
  local sim = LO.Similarity(Encode(selection))
  assert(sim == 100, "full match " .. tostring(sim))
  TREE[3].ranksPurchased = 0
  TREE[50].ranksPurchased = 1
  sim = LO.Similarity(Encode(selection))
  io_write("   partial similarity=" .. sim)
  assert(sim < 100 and sim > 60)
end)

step("context detection", function()
  INSTANCE_TYPE = "arena"; SOLO_SHUFFLE = true; assert(NS.Context:Detect() == "solo")
  SOLO_SHUFFLE = false; GROUP_SIZE = 2; assert(NS.Context:Detect() == "2v2")
  GROUP_SIZE = 3; assert(NS.Context:Detect() == "3v3")
  INSTANCE_TYPE = "party"; assert(NS.Context:Detect() == "mplus")
  INSTANCE_TYPE = "raid"; assert(NS.Context:Detect() == "raid")
  INSTANCE_TYPE = "pvp"; assert(NS.Context:Detect() == "rbg")
  INSTANCE_TYPE = nil; assert(NS.Context:Detect() == nil)
end)

step("no prompt when build already active", function()
  INSTANCE_TYPE = "arena"; SOLO_SHUFFLE = true
  NS.Context:Check(false)
  assert(not (_G.DarkndarkTalentsPrompt and _G.DarkndarkTalentsPrompt._shown))
  INSTANCE_TYPE = nil; NS.Context:Check(false)
end)

step("prompt on entering arena", function()
  LAST_SELECTED = 1
  INSTANCE_TYPE = "arena"; SOLO_SHUFFLE = true
  NS.Context:Check(false)
  local p = _G.DarkndarkTalentsPrompt
  assert(p and p._shown, "prompt shown")
  io_write("   prompt: " .. tostring(p.text._text):gsub("\n", " | "))
  for i, o in ipairs(p.options) do if o._shown then io_write("   option " .. i .. ": " .. tostring(o._text)) end end
  assert(p.options[3]._text:find("top"), "pick-from-players option")
  IMPORTED = nil
  p.options[1]._scripts.OnClick(p.options[1])
  FireEvent("TRAIT_CONFIG_DELETED", PENDING_DELETED); RunTimers()
  assert(IMPORTED and IMPORTED.name == "DND Shuffle", "prompt apply imports")
  INSTANCE_TYPE = nil; SOLO_SHUFFLE = false
end)

step("raid falls back to M+ data", function()
  local build, _, _, fromMplus = NS:GetBuilds("raid", 70)
  assert(build and fromMplus)
end)

step("custom build overrides", function()
  NS.db.custom[70] = { mplus = { code = "MYBUILD" } }
  local b = NS:GetBuilds("mplus", 70)
  assert(b.custom and b.code == "MYBUILD")
  NS.db.custom[70] = nil
end)

step("gear analysis", function()
  local r = NS.Gear.Analyze("solo")
  io_write(("   mine crit/haste/mastery/vers = %d/%d/%d/%d ilvl=%s top=%s"):format(r.mine.crit, r.mine.haste, r.mine.mastery, r.mine.vers, tostring(r.ilvl), tostring(r.topIlvl)))
  for _, i in ipairs(r.issues) do io_write("   issue: " .. i) end
  assert(#r.issues >= 3, "expected stat/enchant/gem issues")
end)

step("window: talents + gear tabs, scale, copy", function()
  SlashCmdList.DARKNDARKTALENTS("")
  local f = _G.DarkndarkTalentsWindow
  assert(f and f._shown)
  for _, row in ipairs(f.rows) do io_write("   " .. row.ctx .. ": " .. tostring(row.info._text)) end
  f.tabGear._scripts.OnClick(f.tabGear)
  assert(f.gear._shown and not f.talents._shown)
  io_write("   gear issues:\n" .. tostring(f.gear.issues._text))
  f.tabTalents._scripts.OnClick(f.tabTalents)
  f.rows[3].copy._scripts.OnClick(f.rows[3].copy)
  assert(_G.DarkndarkTalentsCopy and _G.DarkndarkTalentsCopy.edit._text == f.rows[3].code)
  f.rows[1].save._scripts.OnClick(f.rows[1].save)
  assert(NS.db.custom[70].mplus.code == "MYBUILD")
  SlashCmdList.DARKNDARKTALENTS("")
  assert(not f._shown)
end)

step("bar layout: groups", function()
  local g = NS.ActionBars.GroupSpells()
  for _, k in ipairs(NS.ActionBars.GROUP_ORDER) do io_write("   " .. k .. ": " .. table.concat(g[k], ",")) end
  assert(g.interrupt[1] == 1766, "interrupt")
  assert(g.cooldowns[1] == 13750, "13750 is a cooldown")
  assert(#g.defensives == 4, "rogue defensives")
end)

step("bar layout: apply", function()
  NS.db.layout.confirmed = true
  assert(NS.ActionBars.Apply())
  assert(ACTIONS[5][1] == "macro", "macro kept")
  assert(ACTIONS[62][1] == "item", "item kept")
  assert(ACTIONS[1][2] == 1752 or ACTIONS[1][2] == 196819, "core on slot 1: " .. tostring(ACTIONS[1] and ACTIONS[1][2]))
  for slot, a in pairs(ACTIONS) do assert(a[2] ~= 99999, "old talent spell removed") end
  assert(BINDINGS["1"] == "ACTIONBUTTON1", "key 1")
  assert(BINDINGS["G"] ~= "SOMETHING_ELSE", "interrupt key G rebound")
  local where = {}
  for slot, a in pairs(ACTIONS) do where[a[2]] = slot end
  io_write("   slots: 1752@" .. tostring(where[1752]) .. " 13750@" .. tostring(where[13750]) .. " 1766@" .. tostring(where[1766]))
  io_write("   keys: SHIFT-1=" .. tostring(BINDINGS["SHIFT-1"]) .. " G=" .. tostring(BINDINGS["G"]) .. " CTRL-1=" .. tostring(BINDINGS["CTRL-1"]))
  assert(SAVED_BINDINGS and SAVED_BINDINGS > 0)
end)

step("bar layout: undo restores", function()
  NS.ActionBars.Restore()
  assert(ACTIONS[7] and ACTIONS[7][2] == 99999, "old spell back")
  assert(ACTIONS[3][2] == 1752 and ACTIONS[5][1] == "macro")
  assert(BINDINGS["G"] == "SOMETHING_ELSE", "binding restored")
end)

step("bar layout: auto after build + first-time confirm", function()
  NS.db.layout.confirmed = false; POPUP = nil
  NS:Fire("LOADOUT_CHANGED"); RunTimers()
  assert(POPUP and POPUP.which == "DARKNDARK_TALENTS_LAYOUT", "confirm popup")
  StaticPopupDialogs.DARKNDARK_TALENTS_LAYOUT.OnAccept()
  assert(NS.db.layout.confirmed and ACTIONS[7] == nil or ACTIONS[7][2] ~= 99999)
  IN_COMBAT = true; assert(not NS.ActionBars.Apply(), "blocked in combat"); IN_COMBAT = false
end)

step("top players tab + use + share", function()
  NS:ShowWindow("players", "solo")
  local f = _G.DarkndarkTalentsWindow
  assert(f.players._shown and not f.talents._shown, "players tab shown")
  io_write("   " .. tostring(f.players.subtitle._text))
  for i = 1, 3 do local r = f.players.rows[i]; io_write(("   %s %s | %s"):format(r.rank._text, r.name._text, r.info._text)) end
  local r3 = f.players.rows[3]
  IMPORTED = nil; LAST_SELECTED = 1
  for id, c in pairs(CONFIGS) do if c.name == "DND Shuffle" then CONFIGS[id] = nil end end
  r3.use._scripts.OnClick(r3.use)
  assert(IMPORTED and IMPORTED.code == r3.player.code and IMPORTED.name == "DND Shuffle", "used #3's build")
  r3.share._scripts.OnClick(r3.share)
  io_write("   chat link: " .. tostring(CHAT_LINK):sub(1, 70) .. "...")
  assert(CHAT_LINK and CHAT_LINK:find("talentbuild:70:90:" .. r3.player.code, 1, true), "talent link")
  f.players.rows[1].copy._scripts.OnClick(f.players.rows[1].copy)
  assert(_G.DarkndarkTalentsCopy.edit._text == f.players.rows[1].player.code)
end)

step("chooser: pick-from-players opens list on that content", function()
  NS.db.playersContext = "mplus"
  NS:ShowPrompt("3v3")
  local p = _G.DarkndarkTalentsPrompt
  p.options[3]._scripts.OnClick(p.options[3])
  local f = _G.DarkndarkTalentsWindow
  assert(f.players._shown and NS.db.playersContext == "3v3", "opened players for 3v3")
  assert(not p._shown, "chooser closed")
end)

step("minimap button + talents menu", function()
  local b = _G.DarkndarkMinimapButton
  assert(b and b._shown, "button")
  NS:ShowWindow("gear"); _G.DarkndarkTalentsWindow:Hide()
  b._scripts.OnClick(b, "LeftButton")
  assert(_G.DarkndarkTalentsWindow._shown, "left click opens window")
  b._scripts.OnClick(b, "LeftButton")
  assert(not _G.DarkndarkTalentsWindow._shown, "left click again closes it")
  b._scripts.OnClick(b, "RightButton")
  io_write("   menu: " .. table.concat(MENU_LOG, " | "))
  MENU_FN["Top Players"]()
  assert(_G.DarkndarkTalentsWindow.players._shown)
  DarkndarkTalents_OnAddonCompartmentClick()
end)

step("bar layout keeps skyriding/racial spells, skips while mounted", function()
  ACTIONS[8] = { "spell", 372608 }; ACTIONS[63] = { "spell", 20549 }; ACTIONS[7] = { "spell", 99999 }
  MOUNTED = true
  assert(not NS.ActionBars.Apply(), "blocked while mounted")
  assert(ACTIONS[7][2] == 99999, "nothing changed while mounted")
  MOUNTED = false
  FireEvent("PLAYER_MOUNT_DISPLAY_CHANGED"); RunTimers()
  assert(ACTIONS[8] and ACTIONS[8][2] == 372608, "skyriding spell kept")
  assert(ACTIONS[63] and ACTIONS[63][2] == 20549, "racial kept")
  assert(not (ACTIONS[7] and ACTIONS[7][2] == 99999), "old talent spell cleared after dismount")
end)
