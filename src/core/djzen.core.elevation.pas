unit djzen.core.elevation;

{ The elevated helper: the only part of djZen that runs as administrator.

    djZen.exe /elevated activate <id>,<id>,...
    djZen.exe /elevated deactivate

  The GUI runs as the normal user and starts the helper through UAC only when
  a selected tweak needs admin rights. The helper deliberately has a tiny
  attack surface: it reads no profiles, no DJ app descriptors and no user
  settings, only tweak ids from its command line (validated against the
  admin-only tweaks compiled into djZen) and its own snapshot in the
  ACL-protected %ProgramData%\djZen folder.

  Exit codes: 0 OK, 1 some tweaks failed, 2 invalid arguments, 3 not elevated,
  4 unexpected error. The details are in %ProgramData%\djZen\logs\djzen-admin.log. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

const
  HelperOk          = 0;
  HelperPartial     = 1;
  HelperBadArgs     = 2;
  HelperNotElevated = 3;
  HelperError       = 4;
  HelperCancelled   = -1;   // UAC prompt declined (launcher side only)
  HelperUnsafeFolder = -2;  // a DLL next to djZen.exe: elevation refused (launcher side only)

function IsHelperRequested: Boolean;
{ Runs the helper and returns its exit code. }
function RunHelper: Integer;

{ Admin tweak ids among the given ids (unknown ids are dropped). }
function AdminTweakIds(const Ids: array of string): TStringArray;
function AdminSnapshotExists: Boolean;

{ Starts "djZen.exe /elevated ..." through UAC and waits for it.
  Returns the helper's exit code or HelperCancelled. }
function LaunchHelperActivate(const Ids: array of string): Integer;
function LaunchHelperDeactivate: Integer;

function HelperResultText(Code: Integer): string;

implementation

uses
  Windows, djzen.core.tweak, djzen.core.engine, djzen.core.paths, djzen.core.log,
  djzen.win.security, fpjson;

type
  TShellExecuteInfoW = record
    cbSize: DWORD;
    fMask: ULONG;
    Wnd: HWND;
    lpVerb: PWideChar;
    lpFile: PWideChar;
    lpParameters: PWideChar;
    lpDirectory: PWideChar;
    nShow: Integer;
    hInstApp: HINST;
    lpIDList: Pointer;
    lpClass: PWideChar;
    hkeyClass: HKEY;
    dwHotKey: DWORD;
    hIconOrMonitor: THandle;
    hProcess: THandle;
  end;

const
  SEE_MASK_NOCLOSEPROCESS = $00000040;
  SEE_MASK_NOASYNC        = $00000100;
  ERROR_CANCELLED_UAC     = 1223;

function ShellExecuteExW(var Info: TShellExecuteInfoW): BOOL; stdcall; external 'shell32.dll';

function IsHelperRequested: Boolean;
begin
  Result := (ParamCount >= 1) and SameText(ParamStr(1), '/elevated');
end;

function IsValidId(const Id: string): Boolean;
var
  C: Char;
begin
  Result := (Id <> '') and (Length(Id) <= 64);
  for C in Id do
    if not (C in ['a'..'z', '0'..'9', '.', '-']) then
      Exit(False);
end;

function AdminTweakIds(const Ids: array of string): TStringArray;
var
  Id: string;
  T: TTweak;
begin
  Result := nil;
  for Id in Ids do
  begin
    T := Tweaks.Find(Id);
    if (T <> nil) and T.RequiresAdmin and T.CanApply then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := T.Id;
    end;
  end;
end;

function AdminSnapshotExists: Boolean;
begin
  Result := FileExists(AdminSnapshotFile);
end;

function RunHelper: Integer;
var
  Action: string;
  Ids: TStringArray;
  Id: string;
  T: TTweak;
  Settings: TJSONObject;
  Engine: TZenEngine;
  R: TZenResult;
begin
  if not IsProcessElevated then
    Exit(HelperNotElevated);
  Action := LowerCase(ParamStr(2));
  if not ((Action = 'activate') and (ParamCount = 3)) and
     not ((Action = 'deactivate') and (ParamCount = 2)) then
    Exit(HelperBadArgs);

  // validate everything before touching anything
  Ids := nil;
  if Action = 'activate' then
  begin
    Ids := ParamStr(3).Split([',']);
    if Length(Ids) = 0 then
      Exit(HelperBadArgs);
    for Id in Ids do
    begin
      if not IsValidId(Id) then
        Exit(HelperBadArgs);
      T := Tweaks.Find(Id);
      if (T = nil) or not T.RequiresAdmin or not T.CanApply then
        Exit(HelperBadArgs);
    end;
  end;

  try
    EnsureSecureDir(MachineDataDir, ['snapshot.json', 'snapshot.json.tmp', 'logs',
      'logs\djzen-admin.log', 'running.lock']);
    LogInit(AdminLogFile);
    LogInfo('Elevated helper: ' + Action);
    Engine := TZenEngine.Create(Tweaks, AdminSnapshotFile, esAdmin);
    try
      if Action = 'activate' then
      begin
        if Engine.IsActive then
        begin
          LogWarn('Admin part already active; nothing changed');
          Exit(HelperOk);
        end;
        Settings := TJSONObject.Create;
        try
          for Id in Ids do
            Settings.Add(Id, True);
          R := Engine.Activate('djZen', Settings);
        finally
          Settings.Free;
        end;
      end
      else
        R := Engine.Deactivate;
    finally
      Engine.Free;
    end;
    if R.Failed > 0 then
      Result := HelperPartial
    else
      Result := HelperOk;
  except
    on E: Exception do
    begin
      LogError('Elevated helper failed: ' + E.Message);
      Result := HelperError;
    end;
  end;
end;

{ djZen ships no DLLs. A DLL next to the exe (e.g. version.dll in Downloads)
  would be loaded by the elevated helper before any of our code runs, so
  elevation is refused while one is there. }
function FindDllNextToExe: string;
var
  SR: TSearchRec;
begin
  Result := '';
  if FindFirst(AppDir + '*.dll', faAnyFile and not faDirectory, SR) = 0 then
  try
    Result := SR.Name;
  finally
    SysUtils.FindClose(SR);
  end;
end;

function Launch(const Params: string): Integer;
var
  Info: TShellExecuteInfoW;
  ExeName, P: UnicodeString;
  Code: DWORD;
  Dll: string;
begin
  Dll := FindDllNextToExe;
  if Dll <> '' then
  begin
    LogError(Format('Elevation refused: "%s" found next to djZen.exe. djZen ships no DLLs; ' +
      'move djZen to its own folder.', [Dll]));
    Exit(HelperUnsafeFolder);
  end;

  ExeName := UnicodeString(ParamStr(0));
  P := UnicodeString(Params);
  Info := Default(TShellExecuteInfoW);
  Info.cbSize := SizeOf(Info);
  Info.fMask := SEE_MASK_NOCLOSEPROCESS or SEE_MASK_NOASYNC;
  Info.lpVerb := 'runas';
  Info.lpFile := PWideChar(ExeName);
  Info.lpParameters := PWideChar(P);
  Info.nShow := SW_HIDE;
  if not ShellExecuteExW(Info) then
  begin
    if GetLastError = ERROR_CANCELLED_UAC then
      Exit(HelperCancelled);
    LogError('Cannot start elevated helper: ' + SysErrorMessage(GetLastError));
    Exit(HelperError);
  end;
  try
    WaitForSingleObject(Info.hProcess, INFINITE);
    Code := HelperError;
    GetExitCodeProcess(Info.hProcess, Code);
    Result := Integer(Code);
  finally
    CloseHandle(Info.hProcess);
  end;
end;

function LaunchHelperActivate(const Ids: array of string): Integer;
begin
  if Length(Ids) = 0 then
    Exit(HelperOk);
  Result := Launch('/elevated activate ' + string.Join(',', Ids));
  LogInfo(Format('Elevated helper (activate): %s', [HelperResultText(Result)]));
end;

function LaunchHelperDeactivate: Integer;
begin
  if not AdminSnapshotExists then
    Exit(HelperOk);
  Result := Launch('/elevated deactivate');
  LogInfo(Format('Elevated helper (deactivate): %s', [HelperResultText(Result)]));
end;

function HelperResultText(Code: Integer): string;
begin
  case Code of
    HelperOk:          Result := 'OK';
    HelperPartial:     Result := 'some admin options failed (see djzen-admin.log)';
    HelperBadArgs:     Result := 'invalid helper arguments';
    HelperNotElevated: Result := 'helper is not elevated';
    HelperCancelled:   Result := 'administrator permission was declined';
    HelperUnsafeFolder: Result := 'skipped: a DLL file is next to djZen.exe - move djZen to its own folder';
  else
    Result := 'admin helper failed (see djzen-admin.log)';
  end;
end;

end.
