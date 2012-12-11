#include "GarrysMod/Lua/Interface.h"
#include <string>
#include <fstream>
#include <windows.h>

#define WINDOWS_TICK 10000000
#define SEC_TO_UNIX_EPOCH 11644473600LL

using namespace GarrysMod::Lua;
using namespace std;

int ReadFileOffset(lua_State* state)
{
	const char* filename = LUA->GetString(1);
	int start = LUA->GetNumber(2);
	int size = LUA->GetNumber(3);

	HANDLE hFile = CreateFile(filename, GENERIC_READ,FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if(hFile == INVALID_HANDLE_VALUE)
	{
		LUA->PushBool(false);
		return 1;
	}

	SetFilePointer(hFile, start, NULL, FILE_BEGIN);

	char* buff = new char[size];
	DWORD numRead = 0;
	if(!ReadFile(hFile, buff, size, &numRead, NULL))
	{
		LUA->PushBool(false);
		return 1;
	}

	LUA->PushString(buff, numRead);
	LUA->PushNumber(numRead);

	delete[] buff;
	CloseHandle(hFile);

	return 2;
}

int FileSize(lua_State* state)
{
	const char* filename = LUA->GetString(1);

	WIN32_FILE_ATTRIBUTE_DATA fad;
	if(!GetFileAttributesEx(filename, GetFileExInfoStandard, &fad))
	{
		LUA->PushBool(false);
		return 1;
	}
	LARGE_INTEGER size;
	size.HighPart = fad.nFileSizeHigh;
	size.LowPart = fad.nFileSizeLow;

	LUA->PushNumber(size.QuadPart);
	return 1;
}

int WriteFile(lua_State* state)
{
	const char* filename = LUA->GetString(1);
	const char* text = LUA->GetString(2);
	ofstream file (filename);
	if(file.is_open()) 
	{
		file << text;
		file.close();
		LUA->PushBool(true);
	} 
	else
	{
		LUA->PushBool(false);
	}
	return 1;
}

int PushWinError(lua_State* state)
{
	LPTSTR errorText = NULL;

	FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_IGNORE_INSERTS,  
		NULL,
		GetLastError(),
		MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
		(LPTSTR)&errorText,
		0,
		NULL
	); 

	LUA->PushString(errorText);
	LocalFree(errorText);
	errorText = NULL;

	return 1;
}

unsigned WindowsTickToUnixSeconds(long long windowsTicks)
{
     return (unsigned)(windowsTicks / WINDOWS_TICK - SEC_TO_UNIX_EPOCH);
}

int ListDirectory(lua_State* state)
{
	const char* dirName = LUA->GetString(1);
	string directory(dirName);

	HANDLE dir;
    WIN32_FIND_DATA file_data;

	if((dir = FindFirstFile((directory + "/*").c_str(), &file_data)) == INVALID_HANDLE_VALUE)
	{
		LUA->PushBool(false);
    	return 1; // Error occured, called simpio.lasterror
	}

	LUA->CreateTable();
	
	int idx = 1;
    do
	{
    	const string file_name = file_data.cFileName;
    	const bool is_directory = (file_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;

    	if(file_name[0] == '.')
    		continue;

		LUA->PushNumber(idx);
			LUA->CreateTable();

			LUA->PushString("isDir");
			LUA->PushBool(is_directory);
			LUA->SetTable(-3);

			LUA->PushString("name");
			LUA->PushString(file_name.c_str());
			LUA->SetTable(-3);

			if(!is_directory)
			{
				//WIN32_FILE_ATTRIBUTE_DATA fad;
				//if(!GetFileAttributesEx(file_name.c_str(), GetFileExInfoStandard, &fad))
				//{
				//	LUA->Pop(3); // Pop the inner table, index, and outer table
				//	//PushWinError(state);
				//	LUA->PushString("Fucking file attributes");
				//	return 1;
				//}

				LARGE_INTEGER size;
				size.HighPart = file_data.nFileSizeHigh;
				size.LowPart = file_data.nFileSizeLow;
				LUA->PushString("size");
				LUA->PushNumber(size.QuadPart);
				LUA->SetTable(-3);

				LARGE_INTEGER time;
				time.HighPart = file_data.ftLastWriteTime.dwHighDateTime;
				time.LowPart = file_data.ftLastWriteTime.dwLowDateTime;
				int unixTime = WindowsTickToUnixSeconds(time.QuadPart);
				LUA->PushString("mod");
				LUA->PushNumber(unixTime);
				LUA->SetTable(-3);
			}
		LUA->SetTable(-3);
		
		idx++;
    } 
	while(FindNextFile(dir, &file_data));

	CloseHandle(dir);

	// Table is at the top of the stack, return that
	return 1;
}

GMOD_MODULE_OPEN()
{
	// Create table for module functions on the stack
	LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
	LUA->PushString("simpio");

	LUA->CreateTable();
	
		LUA->PushString("read");
		LUA->PushCFunction(ReadFileOffset);
		LUA->SetTable(-3);

		LUA->PushString("filesize");
		LUA->PushCFunction(FileSize);
		LUA->SetTable(-3);

		LUA->PushString("listdir");
		LUA->PushCFunction(ListDirectory);
		LUA->SetTable(-3);

		LUA->PushString("write");
		LUA->PushCFunction(WriteFile);
		LUA->SetTable(-3);

		LUA->PushString("lasterror");
		LUA->PushCFunction(PushWinError);
		LUA->SetTable(-3);

	LUA->SetTable(-3); // Set our new table as the value for simpio in glob

	LUA->Pop(); // Pop glob

	return 0;
}

GMOD_MODULE_CLOSE()
{
	return 0;
}