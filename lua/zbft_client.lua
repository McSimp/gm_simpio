require("Json")

local ZB = {}
local MENU = {}

local Width, Height = 600, 600
local XPosition, YPosition = ScrW() / 2 - Width / 2, ScrH() - Height + 25

function ZB.ChatText(text)
	chat.AddText(Color(255,20,147,255), "[ZB]", Color(255,255,255,255), " ", text)
end

function ZB.ChatError(text)
	surface.PlaySound("Resource/warning.wav")
	chat.AddText(Color(255,20,147,255), "[ZB]", Color(208,31,60,255), " Error: ", text)
end

function ZB.Welcome()
	ZB.ChatText("Loaded")
	ZB.ChatText("Bind a key to +zbft_menu to access the menu")
end

function ZB.RequestDir(dir)
	ZB.ChatText("Requesting directory: " .. dir)

	net.Start("ZB_RequestDir")
		net.WriteString(dir)
	net.SendToServer()
end

if IsValid(LocalPlayer()) then
	ZB.Welcome()
else
	hook.Add("InitPostEntity", "PrintZBLoaded", ZB.Welcome)
end

function MENU:Show()
	if not self.Base then self:Initialize() end
	if not self.Remote_Panel then self:Initialize_Remote() end

	self.Base:SetVisible(true)
	self.Base:MakePopup()
end
concommand.Add("+zbft_menu", function()
	MENU:Show()
end)

function MENU:Hide()
	self.Base:Close()
end
concommand.Add("-zbft_menu", function()
	MENU:Hide()
end)

function MENU:Initialize()
	self.Base = vgui.Create("DFrame")
	self.Base:ShowCloseButton(false)
	self.Base:SetDraggable(false)
	self.Base:SetTitle("")
	self.Base:SetSize(Width, Height)
	self.Base:SetPos(XPosition, YPosition)
	self.Base:SetVisible(false)
	self.Base:SetDeleteOnClose(false)
	self.Base.Paint = function() end

	self.BaseTabs = vgui.Create("DPropertySheet", self.Base)
	self.BaseTabs:Dock(TOP)
	self.BaseTabs:DockMargin(8, 2, 8, 2)
	self.BaseTabs:SetSize(Width, Height)
end

function MENU:Initialize_Remote()
	self.Remote_Panel = vgui.Create("DFileBrowser")
	self.BaseTabs:AddSheet("Remote Files", self.Remote_Panel, "icon16/server_connect.png", false, false, "Browse files on the host")
end

local BROWSER = {}

function BROWSER:Init()
	self:SetSpacing(4)
	self:SetPadding(8)
	self:EnableVerticalScrollbar(true)
	
	local current = vgui.Create("DTextEntry", self)
	self.CurrentDir = current
	current:Dock(TOP)
	current:DockMargin(8, 2, 8, 2)
	current:SetText("C:\\")
	current.OnEnter = function(entry)
		ZB.ChatError("Changing directory manually not yet implemented")
	end
	
	local fileList = vgui.Create("DListView", self)
	self.FileList = fileList
	fileList:Dock(TOP)
	fileList:DockMargin(8, 2, 8, 2)
	fileList:SetSize(550, 425)
	fileList:AddColumn("Type")
	fileList:AddColumn("File")
	fileList:AddColumn("Date Modified")
	fileList:AddColumn("Size")
	fileList.DoDoubleClick = function(parent, index, line)
		local isDir = line:GetValue(1) == "Dir"
		local name = line:GetValue(2)
		if name == ".." then -- Go to parent directory
			ZB.RequestDir(self:GetParentDir())
			self:BeginDirLoad()
		elseif isDir then
			ZB.RequestDir(self:GetRelativeDir(name))
			self:BeginDirLoad()
		else
			ZB.ChatError("Downloading files not yet implemented")
		end
	end
	
	local mkdir = vgui.Create("DButton", self)
	self.CreateDirectoryBtn = mkdir
	mkdir:SetText("Create Directory")
	mkdir:Dock(TOP)
	mkdir:DockMargin(8, 2, 8, 2)
	mkdir.DoClick = function(btn)
		ZB.ChatError("Creating directories not yet implemented")
	end
	
	local refresh = vgui.Create("DButton", self)
	self.RefreshBtn = refresh
	refresh:SetText("Refresh")
	refresh:Dock(TOP)
	refresh:DockMargin(8, 2, 8, 2)
	refresh.DoClick = function(btn)
		ZB.ChatText("Refreshing file list...")
		ZB.RequestDir(self:GetCurrentDir())
		self:BeginDirLoad()
	end
end

function BROWSER:BeginDirLoad()
	self.RefreshBtn:SetDisabled(true)
	self.CreateDirectoryBtn:SetDisabled(true)
	self.CurrentDir:SetDisabled(true)
	self.CurrentDir:SetEditable(false)
	
	self.FileList.PaintOver = function()
		surface.SetDrawColor(0, 0, 0, 220)
		surface.DrawRect(0, 0, self:GetWide(), self:GetTall())
		
		surface.SetFont("Trebuchet24")
		local tw, th = surface.GetTextSize("Loading...")
		
		draw.SimpleText("Loading...", "Trebuchet24", (self:GetWide() - tw)/2, 50, Color(255, 255, 255, 255))
	end
	
	self.FileList.Dirs = {}
	self.FileList.Files = {}
end

function BROWSER:EndDirLoad()
	for _,dir in pairs(self.FileList.Dirs) do
		self.FileList:AddLine("Dir", dir, "", "")
	end
	self.FileList.Dirs = nil
	
	for _,file in pairs(self.FileList.Files) do
		self.FileList:AddLine("File", file.name,  os.date("%x %I:%M %p", file.date), string.NiceSize(file.size))
	end
	self.FileList.Files = nil

	self.RefreshBtn:SetDisabled(false)
	self.CreateDirectoryBtn:SetDisabled(false)
	self.CurrentDir:SetDisabled(false)
	self.CurrentDir:SetEditable(true)
	
	self.FileList.PaintOver = function() end
end

function BROWSER:SetCurrentDir(dir)
	dir = string.gsub(dir, "/", "\\")
	self.CurrentDir:SetText(dir)
end

function BROWSER:GetCurrentDir()
	return self.CurrentDir:GetValue()
end

function BROWSER:GetParentDir()
	local tbl = string.Explode("\\", self:GetCurrentDir())
	local parent = ""
	for i=1,(#tbl-2) do
		parent = parent .. tbl[i] .. "\\"
	end
	return parent
end

function BROWSER:GetRelativeDir(name)
	return self:GetCurrentDir() .. name .. "\\"
end

function BROWSER:AddFolder(name)
	table.insert(self.FileList.Dirs, name)
end

function BROWSER:AddFile(name, date, size)
	table.insert(self.FileList.Files, { name = name, date = date, size = size })
end

function BROWSER:AddParentFolder()
	local dir = self:GetCurrentDir()
	
	local _, count = string.gsub(dir, "\\", "")
	if count > 1 then 
		self:AddFolder("..")
	end	
end

function BROWSER:ClearList()
	self.FileList:Clear()
end

vgui.Register("DFileBrowser", BROWSER, "DPanelList")

net.Receive("ZB_DirList", function(len)
	local browser = MENU.Remote_Panel
	
	if net.ReadBit() == 1 then -- There's been an error
		local errorMsg = net.ReadString()
		Derma_Message("And error occurred while loading the directory:\n" .. errorMsg, "Error", "OK")
		browser:EndLoad()
		return
	end
	
	local dir = net.ReadString()
	
	browser:ClearList()
	browser:SetCurrentDir(dir)
	browser:AddParentFolder()
	
	local tblSize = net.ReadUInt(16)
	for i = 1, tblSize do -- Foreach file entry
		if net.ReadBit() == 1 then -- If true, entry is a folder
			browser:AddFolder(net.ReadString())
		else -- Otherwise it's a file
			browser:AddFile(net.ReadString(), net.ReadUInt(32), net.ReadUInt(32))
		end
	end
	
	browser:EndDirLoad()
end)

ZB.Transfers = {}

function ZB.BeginReceive(transferID, filename, size)
	local handle = file.Open("shazbot.txt", "wb", "DATA") -- TODO: Get a proper local filename
	
	ZB.Transfers[transferID] = { filename = filename, localfile = "shazbot.txt", size = size, offset = 0, transferID = transferID, handle = handle }
	
	ZB.ChatText("Receiving " .. filename .. " from server (ID = " .. transferID .. ")")
end

function ZB.ReceivedChunk(transferID, data, size)
	local transfer = ZB.Transfers[transferID]
	
	transfer.handle:Write(data)
	transfer.offset = transfer.offset + size
	
	local progress = math.Round((transfer.offset / transfer.size) * 100, 2)
	
	ZB.ChatText("Receieved chunk of " .. size .. " bytes from server (ID = " .. transfer.transferID .. ", " .. progress .. "%)")
	
	if transfer.offset == transfer.size then
		ZB.EndReceive(transferID)
	end
end

function ZB.EndReceive(transferID)
	local transfer = ZB.Transfers[transferID]
	
	transfer.handle:Close()
	
	ZB.Transfers[transferID] = nil
	ZB.ChatText("Transfer complete (ID = " .. transferID .. ")")
end

net.Receive("ZB_BeginFileStream", function(len)
	local transferID = net.ReadUInt(16)
	local filename = net.ReadString()
	local size = net.ReadUInt(32)
	
	ZB.BeginReceive(transferID, filename, size)
end)

net.Receive("ZB_FileData", function(len)
	local transferID = net.ReadUInt(16)
	local incoming = net.ReadUInt(16)
	local data = net.ReadData(incoming)
	
	ZB.ReceivedChunk(transferID, data, incoming)
end)