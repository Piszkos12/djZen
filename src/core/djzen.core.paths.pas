unit djzen.core.paths;

{ Well-known file locations.

  djZen runs as the normal user; only the small elevated helper
  (djZen.exe /elevated) runs as administrator. Each side keeps its own state:
    user side   %LOCALAPPDATA%\djZen\   snapshot, log, running.lock
    admin side  %ProgramData%\djZen\    snapshot, log (ACL: only admins can write)
    settings    %APPDATA%\djZen\        settings, user profiles, DJ app descriptors }

{$mode objfpc}{$H+}

interface

function AppDir: string;              // folder of djZen.exe
function UserStateDir: string;        // %LOCALAPPDATA%\djZen\
function MachineDataDir: string;      // %ProgramData%\djZen\
function UserDataDir: string;         // %APPDATA%\djZen\

function UserSnapshotFile: string;
function UserLogFile: string;
function AdminSnapshotFile: string;
function AdminLogFile: string;

function BuiltinProfilesDir: string;
function BuiltinAppsDir: string;
function UserProfilesDir: string;
function UserAppsDir: string;

implementation

uses
  SysUtils, WinDirs;

const
  CSIDL_APPDATA        = $001A;
  CSIDL_LOCAL_APPDATA  = $001C;
  CSIDL_COMMON_APPDATA = $0023;

function SpecialDir(Csidl: Integer): string;
begin
  Result := IncludeTrailingPathDelimiter(GetWindowsSpecialDir(Csidl, True)) + 'djZen\';
end;

function AppDir: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function UserStateDir: string;
begin
  Result := SpecialDir(CSIDL_LOCAL_APPDATA);
end;

function MachineDataDir: string;
begin
  Result := SpecialDir(CSIDL_COMMON_APPDATA);
end;

function UserDataDir: string;
begin
  Result := SpecialDir(CSIDL_APPDATA);
end;

function UserSnapshotFile: string;
begin
  Result := UserStateDir + 'snapshot.json';
end;

function UserLogFile: string;
begin
  Result := UserStateDir + 'logs\djzen.log';
end;

function AdminSnapshotFile: string;
begin
  Result := MachineDataDir + 'snapshot.json';
end;

function AdminLogFile: string;
begin
  Result := MachineDataDir + 'logs\djzen-admin.log';
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
