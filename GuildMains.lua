GuildMains_Settings = nil

function GuildMains:Initialize()
	if self.Initialized then
		return
	end
	
	self.Initialized = true
	
	if not GuildMains_Settings then
		GuildMains_Settings =
		{
			Realms = {},
		}
	end
	
	if not GuildMains_Settings.Realms then
		GuildMains_Settings.Realms = {}
	end
	
	self.Orig_ChatFrame_MessageEventHandler = ChatFrame_MessageEventHandler
	ChatFrame_MessageEventHandler = function (...) return self:ChatFrame_MessageEventHandler(...) end
	
	ChatFrame_AddMessageEventFilter("CHAT_MSG_ACHIEVEMENT", function (...) return self:SystemMessageFilter(...) end)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD_ACHIEVEMENT", function (...) return self:SystemMessageFilter(...) end)
	ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function (...) return self:SystemMessageFilter(...) end)
	
	self.Orig_GetColoredName = GetColoredName
	
	function GetColoredName(event, arg1, arg2, ...)
		local vMainCharacterName = self.GuildLib.Roster:FindMainCharacter(arg2)
		
		if vMainCharacterName then
			arg2 = arg2.." ("..vMainCharacterName..")"
		end
		
		return self.Orig_GetColoredName(event, arg1, arg2, ...)
	end
	
	hooksecurefunc("SendWho", function (...) self:SendWho(...) end)
	
	self.OptionsPanel = GuildMains:New(GuildMains._OptionsPanel, UIParent)
	
	GuildMains.EventLib:RegisterEvent("PLAYER_GUILD_UPDATE", self.UpdateRosterPattern, self)
	self:UpdateRosterPattern()
	
	SlashCmdList.GWHOALL = function (...) self:slash_gwhoall(...) end
	SLASH_GWHOALL1 = "/gwhoall"
end

function GuildMains:slash_gwhoall(...)
	self:TestMessage("gwhoall")
	-- Build a map of the mains
	local mains = {}
	for playerName, mainName in pairs(self.GuildLib.Roster.Mains) do
		if not mains[mainName] then mains[mainName] = {} end
		table.insert(mains[mainName], playerName)
	end
	-- Convert the map to a list and sort it
	local sortedMains = {}
	for mainName, altNames in pairs(mains) do
		table.insert(sortedMains, {main = mainName, alts = altNames})
	end
	table.sort(sortedMains, function (a, b) return a.main < b.main end)
	-- Output the results
	for _, mainInfo in ipairs(sortedMains) do
		self:NoteMessage("%s: %s", mainInfo.main, table.concat(mainInfo.alts, ", "))
	end
end

function GuildMains:GetGuildSettings()
	local vRealmSettings = GuildMains_Settings.Realms[GetRealmName()]
	
	if not vRealmSettings then
		vRealmSettings = {}
		GuildMains_Settings.Realms[GetRealmName()] = vRealmSettings
	end
	
	local vGuildName = GetGuildInfo("player")
	
	if not vGuildName then
		return
	end
	
	local vGuildSettings = vRealmSettings[vGuildName]
	
	if not vGuildSettings then
		vGuildSettings = {}
		vRealmSettings[vGuildName] = vGuildSettings
	end
	
	return vGuildSettings
end

function GuildMains:UpdateRosterPattern()
	local vGuildSettings = self:GetGuildSettings()
	
	if vGuildSettings and vGuildSettings.UseCustomPattern then
		GuildMains.GuildLib.Roster:SetMainsPattern(vGuildSettings.CustomPattern, vGuildSettings.SkipOfficerNote)
	else
		GuildMains.GuildLib.Roster:SetMainsPattern(nil, vGuildSettings and vGuildSettings.SkipOfficerNote)
	end
end

GuildMains.cDeformat =
{
	s = "(.-)",
	d = "(-?[%d]+)",
	f = "(-?[%d%.]+)",
	g = "(-?[%d%.]+)",
	["%"] = "%%",
}

function GuildMains:ConvertFormatStringToSearchPattern(pFormat)
	local vEscapedFormat = pFormat:gsub(
			"[%[%]%.]",
			function (pChar) return "%"..pChar end)
	
	return vEscapedFormat:gsub(
			"%%[%-%d%.]-([sdgf%%])",
			self.cDeformat)
end

GuildMains.cFriendOnlinePattern = GuildMains:ConvertFormatStringToSearchPattern(ERR_FRIEND_ONLINE_SS)
GuildMains.cFriendOfflinePattern = GuildMains:ConvertFormatStringToSearchPattern(ERR_FRIEND_OFFLINE_S)
GuildMains.cLeftGuildPattern = GuildMains:ConvertFormatStringToSearchPattern(ERR_GUILD_LEAVE_S)

function GuildMains:ChatFrame_MessageEventHandler(pChatFrame, pEvent, ...)
	if pEvent ~= "CHAT_MSG_WHISPER"
	and pEvent ~= "CHAT_MSG_WHISPER_INFORM"
	and pEvent ~= "CHAT_MSG_SAY"
	and pEvent ~= "CHAT_MSG_CHANNEL"
	and pEvent ~= "CHAT_MSG_GUILD"
	and pEvent ~= "CHAT_MSG_OFFICER"
	and pEvent ~= "CHAT_MSG_YELL"
	and pEvent ~= "CHAT_MSG_RAID"
	and pEvent ~= "CHAT_MSG_RAID_LEADER"
	and pEvent ~= "CHAT_MSG_PARTY" then
		return self.Orig_ChatFrame_MessageEventHandler(pChatFrame, pEvent, ...)
	end
	
	-- Temporarily hook the AddMessage function in the frame to capture the output and modify it
	
	pChatFrame.GuildMains_AddMessage = pChatFrame.AddMessage
	pChatFrame.AddMessage = self.ChatFrame_AddMessage
	
	local vResult = self.Orig_ChatFrame_MessageEventHandler(pChatFrame, pEvent, ...)
	
	pChatFrame.AddMessage = pChatFrame.GuildMains_AddMessage
	pChatFrame.GuildMains_AddMessage = nil
end

function GuildMains.ChatFrame_AddMessage(pChatFrame, pMessage, ...)
	local vMessage = GuildMains:ReplacePlayerLinks(pMessage)
	
	return pChatFrame:GuildMains_AddMessage(vMessage, ...)
end

function GuildMains:SystemMessageFilter(pChatFrame, pEvent, ...)
	local vMessage = select(1, ...)
	
	vMessage = self:ReplacePlayerLinks(vMessage)
	
	-- Look for names that aren't links
	
	local _, _, vPlayerName = vMessage:find(GuildMains.cFriendOfflinePattern)
	local vPattern = ERR_FRIEND_OFFLINE_S
	
	if not vPlayerName then
		_, _, vPlayerName = vMessage:find(GuildMains.cLeftGuildPattern)
		vPattern = ERR_GUILD_LEAVE_S
	end
	
	if vPlayerName then
		local vMainCharacterName = self.GuildLib.Roster:FindMainCharacter(vPlayerName)
		local vDisplayName
		
		if vMainCharacterName then
			vMessage = vPattern:format(vPlayerName.." ("..vMainCharacterName..")")
		end
	end
	
	return false, vMessage, select(2, ...)
end

function GuildMains:ReplacePlayerLinks(pMessage)
	return pMessage:gsub("(|Hplayer:.-|h%[.-%]|h)", function (pPlayerLink)
		local _, _, vPlayerName, vMessageID = pPlayerLink:find("|Hplayer:([^:]*)(.-)|h%[.-%]|h")
		local _, _, vPlayerColor = pPlayerLink:find("|Hplayer:[^:]*.-|h%[(|c........).-%]|h")
		
		local vMainCharacterName = self.GuildLib.Roster:FindMainCharacter(vPlayerName)
		
		local vDisplayName
		
		if vMainCharacterName and vMainCharacterName ~= vPlayerName then
			vDisplayName = vPlayerName.." ("..vMainCharacterName..")"
		else
			vDisplayName = vPlayerName
		end
		
		if vPlayerColor then
			vDisplayName = vPlayerColor..vDisplayName.."|r"
		end
		
		return string.format("|Hplayer:%s%s|h[%s]|h", vPlayerName, vMessageID, vDisplayName)
	end)
end

function GuildMains:SendWho(pPlayerName)
	local vAltName, vPlayerName = self.GuildLib.Roster:FindOnlineCharacter(pPlayerName)
	
	if vAltName and vAltName ~= vPlayerName then
		self:NoteMessage(string.format(NORMAL_FONT_COLOR_CODE.."%s is online on %s"..FONT_COLOR_CODE_CLOSE, vPlayerName, string.format("|Hplayer:%s|h[%s]|h", vAltName, vAltName)))
	end
end

----------------------------------------
GuildMains._OptionsPanel = {}
----------------------------------------

function GuildMains._OptionsPanel:New(pParent)
	return CreateFrame("Frame", nil, pParent)
end

function GuildMains._OptionsPanel:Construct(pParent)
	self:Hide()
	
	self.name = "Guild Mains"
	self.okay = function () self:SaveSettings() end
	self.default = function () self:DefaultSettings() end
	self.refresh = function () self:Refresh() end
	
	InterfaceOptions_AddCategory(self)
	
	self.Title = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	self.Title:SetPoint("TOPLEFT", self, "TOPLEFT", 15, -15)
	self.Title:SetText(self.name)
	
	self.Description = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	self.Description:SetPoint("TOPLEFT", self.Title, "BOTTOMLEFT", 0, -15)
	self.Description:SetWidth(380)
	self.Description:SetJustifyH("LEFT")
	self.Description:SetText("Normally Guild Mains finds the first word in a player's note which matches a guild member's name to identify their main.  You may instead use a custom pattern by setting the pattern to the format used in your own guild.  Use the name playername (not case sensitive) to specify where the name appears.  For example \"Alt of playername\" or \"AKA playername\" or \"(playername)\"")
	
	self.UseFirstName = GuildMains:New(GuildMains._CheckButton, self, "Use first name found in notes")
	self.UseFirstName:SetPoint("TOPLEFT", self.Description, "BOTTOMLEFT", 0, -20)
	self.UseFirstName:SetScript("OnClick", function () self.UseCustomPattern:SetChecked(not self.UseFirstName:GetChecked()) end)
	
	self.UseCustomPattern = GuildMains:New(GuildMains._CheckButton, self, "Use custom note format")
	self.UseCustomPattern:SetPoint("TOPLEFT", self.UseFirstName, "BOTTOMLEFT", 0, -20)
	self.UseCustomPattern:SetScript("OnClick", function () self.UseFirstName:SetChecked(not self.UseCustomPattern:GetChecked()) end)
	
	self.PatternText = GuildMains:New(GuildMains._EditBox, self, "Pattern", 100, 220)
	self.PatternText:SetPoint("TOPLEFT", self.UseCustomPattern, "BOTTOMLEFT", 100, -20)
	
	self.SearchOfficerNote = GuildMains:New(GuildMains._CheckButton, self, "Search officer note (if available)")
	self.SearchOfficerNote:SetPoint("TOPLEFT", self.PatternText, "BOTTOMLEFT", -100, -20)
end

function GuildMains._OptionsPanel:SaveSettings()
	local vGuildSettings = GuildMains:GetGuildSettings()
	
	vGuildSettings.UseCustomPattern = self.UseCustomPattern:GetChecked()
	vGuildSettings.CustomPattern = self.PatternText:GetText()
	vGuildSettings.SkipOfficerNote = not self.SearchOfficerNote:GetChecked()
	
	GuildMains:UpdateRosterPattern()
end

function GuildMains._OptionsPanel:DefaultSettings()
	local vGuildSettings = GuildMains:GetGuildSettings()
	
	vGuildSettings.UseCustomPattern = false
	vGuildSettings.SkipOfficerNote = false
end

function GuildMains._OptionsPanel:Refresh()
	local vGuildSettings = GuildMains:GetGuildSettings()
	
	self.UseFirstName:SetChecked(not vGuildSettings.UseCustomPattern)
	self.UseCustomPattern:SetChecked(vGuildSettings.UseCustomPattern)
	self.PatternText:SetText(vGuildSettings.CustomPattern)
	self.SearchOfficerNote:SetChecked(not vGuildSettings.SkipOfficerNote)
end

----------------------------------------
GuildMains._EditBox = {}
----------------------------------------

function GuildMains._EditBox:New(pParent, pLabel, pMaxLetters, pWidth, pPlain)
	return CreateFrame("EditBox", nil, pParent)
end

function GuildMains._EditBox:Construct(pParent, pLabel, pMaxLetters, pWidth, pPlain)
	self.cursorOffset = 0
	self.cursorHeight = 0
	
	self:SetWidth(pWidth or 150)
	self:SetHeight(25)
	
	self:SetFontObject(ChatFontNormal)
	
	self:SetMultiLine(false)
	self:EnableMouse(true)
	self:SetAutoFocus(false)
	self:SetMaxLetters(pMaxLetters or 200)
	
	if not pPlain then
		self.LeftTexture = self:CreateTexture(nil, "BACKGROUND")
		self.LeftTexture:SetTexture("Interface\\Common\\Common-Input-Border")
		self.LeftTexture:SetWidth(8)
		self.LeftTexture:SetHeight(20)
		self.LeftTexture:SetPoint("LEFT", self, "LEFT", -5, 0)
		self.LeftTexture:SetTexCoord(0, 0.0625, 0, 0.625)
		
		self.RightTexture = self:CreateTexture(nil, "BACKGROUND")
		self.RightTexture:SetTexture("Interface\\Common\\Common-Input-Border")
		self.RightTexture:SetWidth(8)
		self.RightTexture:SetHeight(20)
		self.RightTexture:SetPoint("RIGHT", self, "RIGHT", 0, 0)
		self.RightTexture:SetTexCoord(0.9375, 1, 0, 0.625)
		
		self.MiddleTexture = self:CreateTexture(nil, "BACKGROUND")
		self.MiddleTexture:SetHeight(20)
		self.MiddleTexture:SetTexture("Interface\\Common\\Common-Input-Border")
		self.MiddleTexture:SetPoint("LEFT", self.LeftTexture, "RIGHT")
		self.MiddleTexture:SetPoint("RIGHT", self.RightTexture, "LEFT")
		self.MiddleTexture:SetTexCoord(0.0625, 0.9375, 0, 0.625)
		
		self.Title = self:CreateFontString(nil, "BACKGROUND", "GameFontNormalSmall")
		self.Title:SetJustifyH("RIGHT")
		self.Title:SetPoint("RIGHT", self, "TOPLEFT", -10, -13)
		self.Title:SetText(pLabel or "")
	end
	
	self:SetScript("OnEscapePressed", function (self) self:ClearFocus() end)
	self:SetScript("OnEditFocusLost", self.EditFocusLost)
	self:SetScript("OnEditFocusGained", self.EditFocusGained)
end

function GuildMains._EditBox:SetAnchorMode(pMode)
	self.Title:ClearAllPoints()
	self:ClearAllPoints()
	
	if pMode == "TITLE" then
		self:SetPoint("TOPLEFT", self.Title, "RIGHT", 10, 12)
	else
		self.Title:SetPoint("RIGHT", self, "TOPLEFT", -10, -13)
	end
end

function GuildMains._EditBox:EditFocusLost()
	self:HighlightText(0, 0)
end

function GuildMains._EditBox:EditFocusGained()
	self:HighlightText()
end

function GuildMains._EditBox:SetVertexColor(pRed, pGreen, pBlue, pAlpha)
	self.LeftTexture:SetVertexColor(pRed, pGreen, pBlue, pAlpha)
	self.MiddleTexture:SetVertexColor(pRed, pGreen, pBlue, pAlpha)
	self.RightTexture:SetVertexColor(pRed, pGreen, pBlue, pAlpha)
end

----------------------------------------
GuildMains._CheckButton = {}
----------------------------------------

function GuildMains._CheckButton:New(pParent, pTitle)
	return CreateFrame("CheckButton", nil, pParent)
end

function GuildMains._CheckButton:Construct(pParent, pTitle)
	self:SetWidth(23)
	self:SetHeight(21)
	
	self.Title = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	self.Title:SetPoint("LEFT", self, "RIGHT", 2, 0)
	self.Title:SetJustifyH("LEFT")
	self.Title:SetText(pTitle or "")
	
	self:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
	self:GetDisabledCheckedTexture():SetTexCoord(0.125, 0.84375, 0.15625, 0.8125)
	
	self:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	self:GetNormalTexture():SetTexCoord(0.125, 0.84375, 0.15625, 0.8125)
	
	self:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	self:GetCheckedTexture():SetTexCoord(0.125, 0.84375, 0.15625, 0.8125)
	
	self:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	self:GetPushedTexture():SetTexCoord(0.125, 0.84375, 0.15625, 0.8125)
	
	self:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
	self:GetHighlightTexture():SetTexCoord(0.125, 0.84375, 0.15625, 0.8125)
	self:GetHighlightTexture():SetBlendMode("ADD")
end

----------------------------------------
--
----------------------------------------

GuildMains.EventLib:RegisterEvent("ADDON_LOADED", GuildMains.Initialize, GuildMains)
