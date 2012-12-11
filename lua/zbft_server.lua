local ZB = {}

function ZB.LogMessage(text)
	MsgC(Color(255,20,147), "[ZB]")
	MsgC(Color(255,255,255), " ", text, "\n")
end

ZB.LogMessage("Loading Server...")

require("simpio")

util.AddNetworkString("ZB_Request")
util.AddNetworkString("ZB_DirList")
util.AddNetworkString("ZB_BeginFileStream")
util.AddNetworkString("ZB_FileData")

net.Receive("ZB_Request", function(len, ply)
	local isFile = net.ReadBit() == 1
	local name = net.ReadString()
	if isFile then
		ZB.LogMessage("Player is requesting file (Ply = " .. ply:Nick() .. ", File = " .. name .. ")")
		ZB.StreamFile(name, ply)
		ZB.LogMessage("File transfer started")
	else
		ZB.LogMessage("Player is requesting directory (Ply = " .. ply:Nick() .. ", Dir = " .. name .. ")")
		ZB.SendDir(name, ply)
		ZB.LogMessage("Directory listing sent")
	end
end)

function ZB.SendDir(dir, ply)
	local result = simpio.listdir(dir)
	
	if not result then -- It's an error
		net.Start("ZB_DirList")
			net.WriteBit(true)
			net.WriteString(string.Trim(simpio.lasterror()))
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

ZB.NetMaxPayload = 262144
/*
__text:0028A7AF                 mov     eax, [esi]
__text:0028A7B1                 mov     dword ptr [esp+0Ch], 0; false
__text:0028A7B9                 mov     dword ptr [esp+8], 262144 ; NET_MAX_PAYLOAD
__text:0028A7C1                 mov     dword ptr [esp+4], 1 ; true
__text:0028A7C9                 mov     [esp], esi      ; int
__text:0028A7CC                 call    ds:off_100[eax] ; SetMaxBufferSize
*/
ZB.MaxChunkSize = 61440 -- 60KB
ZB.ChunksPerTick = 3
ZB.TransferID = 1
ZB.Transfers = {}

function ZB.StreamFile(filename, ply)
	local size = simpio.filesize(filename)
	
	if not size then -- Error occurred
		net.Start("ZB_BeginFileStream")
			net.WriteBit(true)
			net.WriteString(filename)
			net.WriteString(string.Trim(simpio.lasterror()))
		net.Send(ply)
		
		ZB.LogMessage("An error occured while sending the file (Ply = " .. ply:Nick() .. ", Dir = " .. filename .. ")")
		return
	end
	
	net.Start("ZB_BeginFileStream")
		net.WriteBit(false)
		net.WriteUInt(ZB.TransferID, 16)
		net.WriteString(filename)
		net.WriteUInt(size, 32)
	net.Send(ply)
	
	table.insert(ZB.Transfers, { filename = filename, size = size, offset = 0, id = ZB.TransferID, player = ply })
	ZB.TransferID = ZB.TransferID + 1
end

function ZB.SendChunk(transfer)
	if not IsValid(transfer.player) then
		ZB.LogMessage("Player for transfer " .. transfer.id .. " has gone away")
		return false
	end

	local remaining = transfer.size - transfer.offset
	if remaining == 0 then
		return false
	end
	
	local send = math.Min(remaining, ZB.MaxChunkSize)
	local data, numRead = simpio.read(transfer.filename, transfer.offset, send) -- Read send bytes starting from transfer.offset
	
	if not data then -- Error occurred
		net.Start("ZB_FileData")
			net.WriteUInt(transfer.id, 16)
			net.WriteBit(true)
			net.WriteString(string.Trim(simpio.lasterror()))
		net.Send(transfer.player)
		
		ZB.LogMessage("An error occured while reading data (Ply = " .. transfer.player:Nick() .. ", TID = " .. transfer.id .. ")")
		return false
	end
	
	ZB.LogMessage("Sending " .. numRead .. " byte chunk to " .. transfer.player:Nick() .. " starting from " .. transfer.offset)
	
	net.Start("ZB_FileData")
		net.WriteUInt(transfer.id, 16)
		net.WriteBit(false)
		net.WriteUInt(numRead, 16)
		net.WriteData(data, numRead)
	net.Send(transfer.player)
	
	transfer.offset = transfer.offset + numRead
	
	return true
end

timer.Create("SendChunks", 1, 0, function()
	for k,tbl in ipairs(ZB.Transfers) do
		for i = 1, ZB.ChunksPerTick do
			if not ZB.SendChunk(tbl) then -- Completed or errored, so remove from transfers
				table.remove(ZB.Transfers, k)
				continue
			end
		end
	end
end) 