local _, ns = ...

-- Optional Masque support. Each panel is its own Masque group so they can be
-- skinned separately. Without Masque, icons keep their built-in thin border.
local Skin = {}
ns.Skin = Skin
local groups = {}

local function GetMasque()
	return LibStub and LibStub("Masque", true)
end

function Skin:IsActive()
	return GetMasque() ~= nil
end

function Skin:Register(icon, groupName)
	local Masque = GetMasque()
	if not (Masque and icon) then return end
	local group = groups[groupName]
	if not group then
		local ok, g = pcall(Masque.Group, Masque, "Darkndark", groupName)
		if not ok or not g then return end
		group = g
		groups[groupName] = group
	end
	local ok = pcall(group.AddButton, group, icon, {
		Icon = icon.icon,
		Cooldown = icon.cd,
		HotKey = icon.hotkey,
		Normal = false,
		Pushed = false,
		Highlight = false,
		Checked = false,
		Border = false,
		Flash = false,
	})
	if ok then
		-- Let the skin draw the border instead of our backdrop.
		icon:SetBackdrop(nil)
		icon.icon:ClearAllPoints()
		icon.icon:SetAllPoints()
	end
end
