local _, ns = ...
local L = ns.L

-- Shares a build in chat as a real talent build link (the same link Blizzard's
-- talent window creates), so anyone can click it to view the build.
function ns:ShareBuild(code)
	if not code then return end
	local specID = self:GetSpecID()
	local specName, _, className = self:GetSpecName(specID)
	local label = TALENT_BUILD_CHAT_LINK_TEXT and TALENT_BUILD_CHAT_LINK_TEXT:format(specName or "", className or "")
		or ((specName or "") .. " " .. (className or ""))
	local linkType = (LinkTypes and LinkTypes.TalentBuild) or "talentbuild"
	local ok, link = pcall(LinkUtil.FormatLink, linkType, ("[%s]"):format(label), specID, UnitLevel("player"), code)
	if not ok or not link then
		ns:Print(L.SHARE_FAILED)
		return
	end
	local color = PlayerUtil and PlayerUtil.GetClassColor and PlayerUtil.GetClassColor()
	if color and color.WrapTextInColorCode then link = color:WrapTextInColorCode(link) end

	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		if not ChatFrameUtil.InsertLink(link) then ChatFrameUtil.OpenChat(link) end
	elseif ChatEdit_InsertLink then
		if not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
	end
end
