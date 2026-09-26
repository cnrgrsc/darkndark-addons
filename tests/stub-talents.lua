-- Extra mocks for DarkndarkTalents: a fake 60-node talent tree, loadout APIs,
-- gear/stat APIs, plus a port of Blizzard's ExportUtil writer to build test strings.
unpack = unpack or table.unpack
function CopyTable(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
function IsControlKeyDown() return false end
PlayerUtil = { GetCurrentSpecID = function() return SPEC_ID or 70 end }
function GetSpecializationInfoByID(id) return id, "Retribution", "", 135873, "DAMAGER", "PALADIN", "Paladin" end

TREE = {}
for i = 1, 60 do
	local choice = (i % 10 == 0)
	TREE[i] = {
		ID = 1000 + i, maxRanks = (i % 7 == 0) and 2 or 1,
		type = choice and 2 or 0,
		entryIDs = choice and { 50000 + i * 2, 50001 + i * 2 } or { 50000 + i * 2 },
		ranksPurchased = 0, activeRank = 0,
	}
end
Enum.TraitNodeType = { Single = 0, Tiered = 1, Selection = 2, SubTreeSelection = 3 }
Enum.LoadConfigResult = { Error = 0, NoChangesNecessary = 1, LoadInProgress = 2, Ready = 3 }

CONFIGS = { [1] = { ID = 1, name = "Default" } }
IMPORTED, LOADED, DELETED = nil, {}, {}
local nextConfig = 100
C_ClassTalents = {
	GetActiveConfigID = function() return 1 end,
	GetTraitTreeForSpec = function() return 790 end,
	GetConfigIDsBySpecID = function() local t = {} for id in pairs(CONFIGS) do if id ~= 1 then t[#t + 1] = id end end return t end,
	CanCreateNewConfig = function() return true end,
	ImportLoadout = function(configID, entries, name, code)
		IMPORTED = { configID = configID, entries = entries, name = name, code = code }
		nextConfig = nextConfig + 1
		CONFIGS[nextConfig] = { ID = nextConfig, name = name }
		PENDING_CREATED = CONFIGS[nextConfig]
		return true
	end,
	DeleteConfig = function(id) CONFIGS[id] = nil; DELETED[#DELETED + 1] = id; PENDING_DELETED = id end,
	LoadConfig = function(id) LOADED[#LOADED + 1] = id; LAST_SELECTED = id; return Enum.LoadConfigResult.Ready end,
	UpdateLastSelectedSavedConfigID = function(_, id) LAST_SELECTED = id end,
	GetLastSelectedSavedConfigID = function() return LAST_SELECTED end,
}
C_Traits = {
	GetLoadoutSerializationVersion = function() return 2 end,
	GetTreeNodes = function() local t = {} for i, n in ipairs(TREE) do t[i] = n.ID end return t end,
	GetNodeInfo = function(_, nodeID)
		local n = TREE[nodeID - 1000]
		if not n then return nil end
		n.activeEntry = n.activeEntryID and { entryID = n.activeEntryID } or nil
		return n
	end,
	GetEntryInfo = function(_, entryID) return { maxRanks = 1 } end,
	GetConfigInfo = function(id) return CONFIGS[id] end,
	GenerateImportString = function() return "MYBUILD" end,
}

-- Port of Blizzard's ExportUtil.ConvertToBase64 (bit ops via math).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function BlizzEncode(entries)
	local out, cur, reserved = {}, 0, 0
	for _, e in ipairs(entries) do
		local value, need = e[2], e[1]
		while need > 0 do
			local space = 6 - reserved
			local maxStore = 2 ^ space
			local rem = value % maxStore
			value = math.floor(value / maxStore)
			cur = cur + rem * 2 ^ reserved
			if space > need then
				reserved = (reserved + need) % 6
				need = 0
			else
				out[#out + 1] = B64:sub(cur + 1, cur + 1)
				cur, reserved = 0, 0
				need = need - space
			end
		end
	end
	if reserved > 0 then out[#out + 1] = B64:sub(cur + 1, cur + 1) end
	return table.concat(out)
end

-- Port of Blizzard's ImportDataStreamMixin:ExtractValue.
function BlizzReader(text)
	local vals = {}
	for i = 1, #text do vals[i] = B64:find(text:sub(i, i), 1, true) - 1 end
	local r = { idx = 1, extracted = 0, remaining = vals[1] }
	function r:Extract(width)
		if self.idx > #vals then return nil end
		local value, need, got = 0, width, 0
		while need > 0 do
			local remBits = 6 - self.extracted
			local take = math.min(remBits, need)
			self.extracted = self.extracted + take
			local maxStore = 2 ^ take
			local rem = self.remaining % maxStore
			self.remaining = math.floor(self.remaining / maxStore)
			value = value + rem * 2 ^ got
			got = got + take
			need = need - take
			if take < remBits then break end
			self.idx = self.idx + 1
			self.extracted = 0
			self.remaining = vals[self.idx]
		end
		return value
	end
	return r
end

-- Gear
RATINGS = { [9] = 1000, [18] = 400, [26] = 2500, [29] = 300 }
function GetCombatRating(cr) return RATINGS[cr] or 0 end
function GetAverageItemLevel() return 300, 290 end
ITEM_LINKS = {
	[1] = "|Hitem:1001::::::::|h", [5] = "|Hitem:1005:7000:::::::|h", [7] = "|Hitem:1007::::::::|h",
	[11] = "|Hitem:1011:7100:::::::|h", [12] = "|Hitem:1012::::::::|h", [2] = "|Hitem:1002::240::::::|h",
}
function GetInventoryItemLink(_, slot) return ITEM_LINKS[slot] end
C_Item = { GetItemStats = function(link) if link:find("1002") then return { EMPTY_SOCKET_PRISMATIC = 2 } end return {} end }
function IsInInstance() return INSTANCE_TYPE ~= nil, INSTANCE_TYPE or "none" end
function GetInstanceInfo() return "X", INSTANCE_TYPE or "none", DIFFICULTY or 0, "", 5, 0, false, 1234 end
function GetNumGroupMembers() return GROUP_SIZE or 0 end
function GetNumArenaOpponentSpecs() return 0 end
C_PvP = { IsSoloShuffle = function() return SOLO_SHUFFLE or false end, IsSoloRBG = function() return false end }

-- Action bars / bindings
ACTIONS = { [5] = { "macro", 7 }, [7] = { "spell", 99999 }, [3] = { "spell", 1752 }, [62] = { "item", 6948 }, [8] = { "spell", 372608 }, [63] = { "spell", 20549 } }
function GetActionInfo(slot) local a = ACTIONS[slot]; if a then return a[1], a[2] end end
CURSOR = nil
function ClearCursor() CURSOR = nil end
function GetCursorInfo() return CURSOR and CURSOR[1] end
function PickupAction(slot) CURSOR = ACTIONS[slot]; ACTIONS[slot] = nil end
function PlaceAction(slot) local old = ACTIONS[slot]; ACTIONS[slot] = CURSOR; CURSOR = old end
C_Spell.PickupSpell = function(id) CURSOR = { "spell", id } end
function PickupMacro(id) CURSOR = { "macro", id } end
C_Item.PickupItem = function(id) CURSOR = { "item", id } end
BINDINGS = { ["1"] = "ACTIONBUTTON1", ["G"] = "SOMETHING_ELSE" }
function SetBinding(key, cmd) BINDINGS[key] = cmd; return true end
function GetBindingAction(key) return BINDINGS[key] or "" end
function SaveBindings() SAVED_BINDINGS = (SAVED_BINDINGS or 0) + 1 end
function GetCurrentBindingSet() return 2 end
YES, NO = "Yes", "No"
StaticPopupDialogs = {}
function StaticPopup_Show(which, text) POPUP = { which = which, text = text } end
C_Spell.IsSpellHarmful = function() return false end
for i = 1, 12 do
  local a = CreateFrame("CheckButton", "ActionButton" .. i); a.action = i; a.bindingAction = "ACTIONBUTTON" .. i
  local b = CreateFrame("CheckButton", "MultiBarBottomLeftButton" .. i); b.action = 60 + i; b.bindingAction = "MULTIACTIONBAR1BUTTON" .. i
end
LinkUtil = { FormatLink = function(t, text, ...) return ("|H%s:%s|h%s|h"):format(t, table.concat({ ... }, ":"), text) end }
LinkTypes = { TalentBuild = "talentbuild" }
TALENT_BUILD_CHAT_LINK_TEXT = "%s %s Talents"
ChatFrameUtil = { InsertLink = function(l) CHAT_LINK = l; return true end, OpenChat = function(l) CHAT_LINK = l end }
function UnitLevel() return 90 end
C_Spell.IsClassTalentSpell = function(id) return id == 99999 end
MOUNTED = false
function IsMounted() return MOUNTED end
