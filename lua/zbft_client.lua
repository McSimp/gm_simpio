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

function ZB.Init()
	MENU:Initialize()
	MENU:InitializeRemote()
	
	MENU.RemoteBrowser:BeginDirLoad()
	net.Start("ZBCL_ClientInit")
	net.SendToServer()
	
	file.CreateDir("zbft")
	
	ZB.ChatText("Loaded")
	ZB.ChatText("Bind a key to +zbft_menu to access the menu")
end

net.Receive("ZBSV_InitData", function(len)
	if net.ReadBit() == 1 then -- Error
		local errorMsg = net.ReadString()
		Derma_Message("An error occured while loading ZB:\n" .. errorMsg, "Error", "OK")
		return
	end
		
	MENU.RemoteBrowser:SetCurrentDir(net.ReadString())-- Base directory
	
	-- TODO: Better interface for drive letters
	local numDrives = net.ReadUInt(6)
	for i=1,numDrives do
		print("Drive Letter: " .. net.ReadString())
	end
end)

/*
 * ========================
 *      Container GUI
 * ========================
*/

function MENU:Show()
	if not self.Base then self:Initialize() end
	if not self.RemoteBrowser then self:InitializeRemote() end

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

function MENU:InitializeRemote()
	self.RemoteBrowser = vgui.Create("DFileBrowser")
	self.BaseTabs:AddSheet("Remote Files", self.RemoteBrowser, "icon16/server_connect.png", false, false, "Browse files on the host")
end

/*
 * ========================
 *     File Browser GUI
 * ========================
*/

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
		ZB.ChatText("Getting file list...")
		ZB.RequestDir(self:GetCurrentDir())
		self:BeginDirLoad()
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
			ZB.RequestFile(self:GetRelativeFile(name))
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
	
	local container = vgui.Create("DPanel")
	self.ProgContainer = container
	container:SetSize(400, ScrH() - 32)
	container:AlignRight(16)
	container:AlignTop(16)
	container.Paint = function() end

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

function BROWSER:GetRelativeFile(name)
	return self:GetCurrentDir() .. name
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

function BROWSER:CreateProgress(name, size)
	local bar = vgui.Create("ZBFileProgress", self.ProgContainer)
	bar:StartDownloading(name, size)
	self.ProgContainer:InvalidateLayout()
	return bar
end

function BROWSER:RemoveProgress(bar)
	bar:Remove()
	self:InvalidateLayout()
end

vgui.Register("DFileBrowser", BROWSER, "DPanelList")

/*
 * ========================
 *    Progress Bar GUI
 * ========================
*/

local PROG = {}

surface.CreateFont("ZBFTLarge",
{
    font         = "Helvetica",
    size         = 19,
    antialias    = true,
    weight       = 800
})

local matProgressCog    = Material("gui/progress_cog.png", "nocull smooth mips")

function PROG:Init()
    self.Label = self:Add("DLabel")
    self.Label:SetText("Starting download...")
    self.Label:SetFont("ZBFTLarge")
    self.Label:SetTextColor(Color(255, 255, 255, 200))
    self.Label:Dock(LEFT)
    self.Label:DockMargin(16, 10, 16, 8)
    self.Label:SetContentAlignment(4)
	self.Label:SizeToContents()

    self.ProgressLabel = self:Add("DLabel")
    self.ProgressLabel:SetText("Unknown Size")
    self.ProgressLabel:SetContentAlignment(7)
    self.ProgressLabel:SetVisible(false )
    self.ProgressLabel:SetTextColor(Color(255, 255, 255, 50))
    self.ProgressLabel:Dock(RIGHT)
	self.ProgressLabel:DockMargin(16, 10, 16, 8)
	self.ProgressLabel:SizeToContents()
	
    self.Progress = 0     
end

function PROG:PerformLayout()
    self:SetSize(400, 35)
	self:Dock(TOP)
	self:DockMargin(0, 0, 0, 10)
end

function PROG:Spawn()
    self:PerformLayout()
end

function PROG:StartDownloading(title, size)
    self.Label:SetText(title)
    self.ProgressLabel:Show()

    self:UpdateProgress(0, size)
end

function PROG:Paint()
    DisableClipping(true)
        draw.RoundedBox(4, -1, -1, self:GetWide()+2, self:GetTall()+2, Color( 0, 0, 0, 255 ))
    DisableClipping(false)

	if self.Progress > 0 then
		draw.RoundedBox(4, 0, 0, self.Progress * self:GetWide(), self:GetTall(), Color( 50, 50, 50, 255 ))
	end
    
    surface.SetDrawColor(0, 0, 0, 100)
    surface.SetMaterial(matProgressCog)
    surface.DrawTexturedRectRotated(0, 32, 64 * 4, 64 * 4, SysTime() * -20)
end

function PROG:UpdateProgress(downloaded, expected)
    self.Progress = downloaded / expected
    self.ProgressLabel:SetText(string.NiceSize(downloaded) .. " of " .. string.NiceSize(expected))
	self.ProgressLabel:SizeToContents()
end

vgui.Register("ZBFileProgress", PROG, "DPanel")

/*
 * ========================
 *    Directory Listing
 * ========================
*/

function ZB.RequestDir(dir)
	ZB.ChatText("Requesting directory: " .. dir)

	net.Start("ZBCL_Request")
		net.WriteBit(false)
		net.WriteString(dir)
	net.SendToServer()
end


net.Receive("ZBSV_DirList", function(len)
	local browser = MENU.RemoteBrowser
	
	if net.ReadBit() == 1 then -- There's been an error
		local errorMsg = net.ReadString()
		Derma_Message("An error occurred while loading the directory:\n" .. errorMsg, "Error", "OK")
		browser:EndDirLoad()
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

/*
 * ========================
 *     File transfers
 * ========================
*/

ZB.Transfers = {}

function ZB.RequestFile(name)
	ZB.ChatText("Requesting file: " .. name)

	net.Start("ZBCL_Request")
		net.WriteBit(true)
		net.WriteString(name)
	net.SendToServer()
end

function ZB.RemoteToLocalName(name)
	return string.GetFileFromFilename(name)
end

function ZB.BeginReceive(transferID, filename, size)
	
	local shortName = ZB.RemoteToLocalName(filename)
	local handle = file.Open("zbft/" .. shortName .. ".txt", "wb", "DATA")
	
	local bar = MENU.RemoteBrowser:CreateProgress(shortName, size)
	
	ZB.Transfers[transferID] = { filename = filename, localfile = shortName, size = size, offset = 0, transferID = transferID, handle = handle, progressBar = bar }
	
	ZB.ChatText("Receiving " .. filename .. " from server (ID = " .. transferID .. ")")
end

function ZB.ReceivedChunk(transferID, data, size)
	local transfer = ZB.Transfers[transferID]
	
	transfer.handle:Write(data)
	transfer.offset = transfer.offset + size
	
	local progress = math.Round((transfer.offset / transfer.size) * 100, 2)
	
	transfer.progressBar:UpdateProgress(transfer.offset, transfer.size)
	
	ZB.ChatText("Receieved chunk of " .. size .. " bytes from server (ID = " .. transfer.transferID .. ", " .. progress .. "%)")
	
	ZB.AcknowledgeChunk(transferID)
	
	if transfer.offset == transfer.size then
		ZB.EndReceive(transferID)
		ZB.ChatText("Transfer complete (ID = " .. transferID .. ")")
	end
end

function ZB.AcknowledgeChunk(transferID)
	net.Start("ZBCL_ChunkAck")
		net.WriteUInt(transferID, 16)
	net.SendToServer()
end

function ZB.EndReceive(transferID)
	local transfer = ZB.Transfers[transferID]
	
	MENU.RemoteBrowser:RemoveProgress(transfer.progressBar)
	
	transfer.handle:Close()
	
	ZB.Transfers[transferID] = nil
end

net.Receive("ZBSV_BeginFileStream", function(len)
	local isError = net.ReadBit() == 1
	
	if isError then
		local filename = net.ReadString()
		local errorMsg = net.ReadString()
		
		ZB.ChatError("An error occurred downloading '" .. filename .. "'. Msg = '" .. errorMsg .. "'")
		return
	end
	
	local transferID = net.ReadUInt(16)
	local filename = net.ReadString()
	local size = net.ReadUInt(32)
	
	ZB.BeginReceive(transferID, filename, size)
end)

net.Receive("ZBSV_FileData", function(len)
	local transferID = net.ReadUInt(16)
	local isError = net.ReadBit() == 1
	
	if isError then
		local errorMsg = net.ReadString()
		ZB.ChatError("An error occurred with transfer ID = " .. transferID .. ". Msg = '" .. errorMsg .. "'")
		ZB.EndReceive(transferID)
		return
	end
	
	local incoming = net.ReadUInt(16)
	local data = net.ReadData(incoming)
	
	ZB.ReceivedChunk(transferID, data, incoming)
end)

if IsValid(LocalPlayer()) then
	ZB.Init()
else
	hook.Add("InitPostEntity", "PrintZBLoaded", ZB.Init)
end