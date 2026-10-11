unit djzen.core.paths;

{ Well-known file locations. }

{$mode objfpc}{$H+}

interface

function AppDir: string;              // folder of djZen.exe
function MachineDataDir: string;      // %ProgramData%\djZen\  (snapshot, logs)
function UserDataDir: string;         // %APPDATA%\djZen\      (user profiles, app scripts)

function SnapshotFile: string;
function LogFile: string;
function BuiltinProfilesDir: string;
function BuiltinAppsDir: string;
function UserProfilesDir: string;
function UserAppsDir: string;

implementation

uses
  SysUtils, WinDirs;

const
  CSIDL_APPDATA        = $001A;
  CSIDL_COMMON_APPDATA = $0023;

function SpecialDir(Csidl: Integer): string;
begin
  Result := IncludeTrailingPathDelimiter(GetWindowsSpecialDir(Csidl, True)) + 'djZen\';
end;

function AppDir: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function MachineDataDir: string;
begin
  Result := SpecialDir(CSIDL_COMMON_APPDATA);
end;

function UserDataDir: string;
begin
  Result := SpecialDir(CSIDL_APPDATA);
end;

function SnapshotFile: string;
begin
  Result := MachineDataDir + 'snapshot.json';
end;

function LogFile: string;
begin
  Result := MachineDataDir + 'logs\djzen.log';
end;

function BuiltinProfilesDir: string;
begin
  Result := AppDir + 'profiles\';
end;

function BuiltinAppsDir: string;
begin
  Result := AppDir + 'apps\';
end;

function UserProfilesDir: string;
begin
  Result := UserDataDir + 'profiles\';
end;

function UserAppsDir: string;
begin
  Result := UserDataDir + 'apps\';
end;

end.
