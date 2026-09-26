local _, ns = ...
local L = ns.L

-- Talent import strings -> loadouts. Mirrors Blizzard's own importer
-- (Blizzard_ClassTalentImportExport.lua) so strings from any site work, but
-- writes into named "DND ..." loadouts and switches to them in one click.
local Loadout = {}
ns.Loadout = Loadout

---------------------------------------------------------------------------
-- Bit stream (6 bits per base64 char, least significant bits first)
---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_VALUE = {}
for i = 1, #B64 do B64_VALUE[B64:sub(i, i)] = i - 1 end

local Reader = {}
Reader.__index = Reader

function Loadout.NewReader(text)
	local values = {}
	for i = 1, #text do
		local v = B64_VALUE[text:sub(i, i)]
		if v == nil then return nil end
		values[i] = v
	end
	return setmetatable({ values = values, index = 1, bitPos = 0 }, Reader)
end

function Reader:Bits()
	return #self.values * 6
end

function Reader:Read(width)
	local value, shift = 0, 0
	while width > 0 do
		local cur = self.values[self.index]
		if cur == nil then return nil end
		local take = math.min(6 - self.bitPos, width)
		local chunk = math.floor(cur / 2 ^ self.bitPos) % 2 ^ take
		value = value + chunk * 2 ^ shift
		shift = shift + take
		width = width - take
		self.bitPos = self.bitPos + take
		if self.bitPos == 6 then
			self.index = self.index + 1
			self.bitPos = 0
		end
	end
	return value
end

-- Header: version (8), specID (16), tree hash (16 x 8)
function Loadout.ReadHeader(reader)
	if not reader or reader:Bits() < 8 + 16 + 128 then return nil end
	local header = { version = reader:Read(8), specID = reader:Read(16), hash = {} }
	for i = 1, 16 do header.hash[i] = reader:Read(8) end
	return header
end

function Loadout.ParseHeader(code)
	return Loadout.ReadHeader(Loadout.NewReader(code or ""))
end

-- Per-node content, in C_Traits.GetTreeNodes order.
local function ReadContent(reader, treeID)
	local results = {}
	for i = 1, #C_Traits.GetTreeNodes(treeID) do
		local r = { selected = reader:Read(1) == 1 }
		if r.selected then
			r.purchased = reader:Read(1) == 1
			if r.purchased then
				if reader:Read(1) == 1 then r.partialRanks = reader:Read(6) end
				if reader:Read(1) == 1 then r.choice = reader:Read(2) + 1 end
			end
		end
		results[i] = r
	end
	return results
end

-- Converts parsed content to ImportLoadoutEntryInfo entries (same rules as Blizzard).
local function ToEntries(configID, treeID, content)
	local entries = {}
	local tiered = Enum.TraitNodeType and Enum.TraitNodeType.Tiered
	for index, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
		local r = content[index]
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		if node and r and r.selected then
			local granted = not r.purchased
			local purchased = granted and 0 or (r.partialRanks or node.maxRanks)
			if tiered and node.type == tiered then
				local remaining = purchased
				for i, entryID in ipairs(node.entryIDs) do
					local entry = C_Traits.GetEntryInfo(configID, entryID)
					if entry then
						local ranks = math.min(remaining, entry.maxRanks)
						local isGranted = granted and i == 1
						if ranks > 0 or isGranted then
							entries[#entries + 1] = { nodeID = nodeID, ranksGranted = isGranted and 1 or 0, ranksPurchased = ranks, selectionEntryID = entryID }
						end
						remaining = remaining - ranks
					end
				end
			else
				local entryID
				if r.choice then
					entryID = node.entryIDs[r.choice]
				elseif node.activeEntry then
					entryID = node.activeEntry.entryID
				end
				entryID = entryID or node.entryIDs[1]
				if entryID then
					entries[#entries + 1] = { nodeID = nodeID, ranksGranted = granted and 1 or 0, ranksPurchased = purchased, selectionEntryID = entryID }
				end
			end
		end
	end
	return entries
end

---------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------
-- Returns header or nil, errorText.
function Loadout.Validate(code, specID)
	local header = Loadout.ParseHeader(code)
	if not header then return nil, L.ERR_IMPORT:format("bad string") end
	if header.specID ~= specID then return nil, L.ERR_SPEC end
	local current = C_Traits.GetLoadoutSerializationVersion and C_Traits.GetLoadoutSerializationVersion()
	if current and header.version ~= current then return nil, L.ERR_VERSION end
	return header
end

-- Percentage of the build's purchased talents that the active talents match.
function Loadout.Similarity(code)
	local specID = ns:GetSpecID()
	local configID = C_ClassTalents.GetActiveConfigID()
	if not (specID and configID) or not Loadout.Validate(code, specID) then return nil end
	local reader = Loadout.NewReader(code)
	Loadout.ReadHeader(reader)
	local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
	if not treeID then return nil end
	local ok, content = pcall(ReadContent, reader, treeID)
	if not ok then return nil end

	local total, same = 0, 0
	for index, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
		local r = content[index]
		local node = C_Traits.GetNodeInfo(configID, nodeID)
		local mine = node and node.ranksPurchased and node.ranksPurchased > 0
		local want = r and r.selected and r.purchased
		if want or mine then
			total = total + 1
			if want and mine then
				local choiceOK = true
				if r.choice and node.activeEntry then
					choiceOK = node.entryIDs[r.choice] == node.activeEntry.entryID
				end
				if choiceOK then same = same + 1 end
			end
		end
	end
	if total == 0 then return nil end
	return math.floor(100 * same / total + 0.5)
end

---------------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------------
local pending -- { code, name, step }

local function FindConfigByName(specID, name)
	for _, id in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do
		local info = C_Traits.GetConfigInfo(id)
		if info and info.name == name then return id end
	end
	return nil
end

local function Switch(configID, name)
	local specID = ns:GetSpecID()
	local result, err = C_ClassTalents.LoadConfig(configID, true)
	if Enum.LoadConfigResult and result == Enum.LoadConfigResult.Error then
		ns:Print(L.ERR_LOAD, err or "?")
		return false
	end
	if C_ClassTalents.UpdateLastSelectedSavedConfigID then
		C_ClassTalents.UpdateLastSelectedSavedConfigID(specID, configID)
	end
	ns:Print(L.APPLIED, name)
	ns:Fire("LOADOUT_CHANGED")
	return true
end

local function Import(code, name)
	local specID = ns:GetSpecID()
	if C_ClassTalents.CanCreateNewConfig and not C_ClassTalents.CanCreateNewConfig() then
		ns:Print(L.ERR_SLOTS)
		pending = nil
		return
	end
	local configID = C_ClassTalents.GetActiveConfigID()
	local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
	local reader = Loadout.NewReader(code)
	Loadout.ReadHeader(reader)
	local entries = ToEntries(configID, treeID, ReadContent(reader, treeID))
	pending = { code = code, name = name, step = "create" }
	local ok, err = C_ClassTalents.ImportLoadout(configID, entries, name, code)
	if not ok then
		pending = nil
		ns:Print(L.ERR_IMPORT, err or "?")
	end
end

function Loadout.Apply(code, name)
	if InCombatLockdown() then
		ns:Print(L.ERR_COMBAT)
		return
	end
	local specID = ns:GetSpecID()
	local header, err = Loadout.Validate(code, specID)
	if not header then
		ns:Print(err)
		return
	end
	ns:Print(L.APPLYING, name)

	local existing = FindConfigByName(specID, name)
	if existing and ns.db.applied[existing] == code then
		Switch(existing, name)
		return
	end
	if existing then
		-- Outdated contents: delete and re-create once the server confirms.
		pending = { code = code, name = name, step = "delete", configID = existing }
		ns.db.applied[existing] = nil
		C_ClassTalents.DeleteConfig(existing)
		C_Timer.After(3, function()
			if pending and pending.step == "delete" and pending.configID == existing then
				Import(code, name)
			end
		end)
		return
	end
	Import(code, name)
end

ns:RegisterEvent("TRAIT_CONFIG_DELETED", function(_, configID)
	if pending and pending.step == "delete" and pending.configID == configID then
		local code, name = pending.code, pending.name
		C_Timer.After(0.2, function() Import(code, name) end)
	end
end)

ns:RegisterEvent("TRAIT_CONFIG_CREATED", function(_, configInfo)
	if not (pending and pending.step == "create" and configInfo) then return end
	if configInfo.name ~= pending.name then return end
	local code, name = pending.code, pending.name
	pending = nil
	ns.db.applied[configInfo.ID] = code
	C_Timer.After(0.3, function() Switch(configInfo.ID, name) end)
end)

-- The player's current talents as an import string.
function Loadout.Export()
	local configID = C_ClassTalents.GetActiveConfigID()
	if not configID or not C_Traits.GenerateImportString then return nil end
	return C_Traits.GenerateImportString(configID)
end

function Loadout.ActiveName()
	local specID = ns:GetSpecID()
	local id = specID and C_ClassTalents.GetLastSelectedSavedConfigID(specID)
	local info = id and C_Traits.GetConfigInfo(id)
	return info and info.name
end
