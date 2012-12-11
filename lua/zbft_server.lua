local ZB = {}

function ZB.LogMessage(text)
	MsgC(Color(255,20,147), "[ZB]")
	MsgC(Color(255,255,255), " ", text, "\n")
end

ZB.LogMessage("Loading Server...")

require("simpio")

util.AddNetworkString("ZB_RequestDir")
util.AddNetworkString("ZB_DirList")
util.AddNetworkString("ZB_RequestFile")
util.AddNetworkString("ZB_BeginFileStream")
util.AddNetworkString("ZB_FileData")

net.Receive("ZB_RequestDir", function(len, ply)
	local dir = net.ReadString()
	ZB.LogMessage("Player is requesting directory (Ply = " .. ply:Nick() .. ", Dir = " .. dir .. ")")
	ZB.SendDir(dir, ply)
	ZB.LogMessage("Directory listing sent")
end)

function ZB.SendDir(dir, ply)
	local result = simpio.listdir(dir)
	
	if type(result) == "string" then -- It's an error
		net.Start("ZB_DirList")
			net.WriteBit(true)
			net.WriteString(string.Trim(result))
		net.Send(ply)
	else
		net.Start("ZB_DirList")
			net.WriteBit(false)
			net.WriteString(dir)
			net.WriteUInt(#result, 16)
			
			for _,v in pairs(result) do
				net.WriteBit(v.isDir)
				if v.isDir then 
					net.WriteString(v.name)
				else
					net.WriteString(v.name)
					net.WriteUInt(v.mod, 32)
					net.WriteUInt(v.size, 32)
				end
			end
		net.Send(ply)
	end
end

ZB.MaxChunkSize = 61440 -- 60KB
ZB.ChunksPerTick = 3
ZB.TransferID = 1
ZB.Transfers = {}

function ZB.StreamFile(filename, ply)
	local size = simpio.filesize(filename)
	
	net.Start("ZB_BeginFileStream")
		net.WriteUInt(ZB.TransferID, 16)
		net.WriteString(filename)
		net.WriteUInt(size, 32)
	net.Send(ply)
	
	table.insert(ZB.Transfers, { filename = filename, size = size, offset = 0, transferID = ZB.TransferID, player = ply })
	ZB.TransferID = ZB.TransferID + 1
end

concommand.Add("downloadfile", function(ply, cmd, args)
	ZB.StreamFile(args[1], ply)
end)

function ZB.SendChunk(transfer)
	local remaining = transfer.size - transfer.offset
	if remaining == 0 then
		return false
	end
	
	local send = math.Min(remaining, ZB.MaxChunkSize)
	local data, numRead = simpio.read(transfer.filename, transfer.offset, send) -- Read send bytes starting from transfer.offset
	
	ZB.LogMessage("Sending " .. numRead .. " byte chunk to " .. transfer.player:Nick() .. " starting from " .. transfer.offset)
	
	net.Start("ZB_FileData")
		net.WriteUInt(transfer.transferID, 16)
		net.WriteUInt(numRead, 16)
		net.WriteData(data, numRead)
	net.Send(transfer.player)
	
	transfer.offset = transfer.offset + numRead
	
	return true
end

timer.Create("SendChunks", 1, 0, function()
	for k,tbl in ipairs(ZB.Transfers) do
		for i = 1, ZB.ChunksPerTick do
			if not ZB.SendChunk(tbl) then -- Completed
				table.remove(ZB.Transfers, k)
				continue
			end
		end
	end
end) 