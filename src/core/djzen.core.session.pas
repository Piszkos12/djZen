unit djzen.core.session;

{ Process session bookkeeping:
  - single instance (two instances would race on the snapshot)
  - unclean shutdown detection: a lock file exists while djZen runs and is
    deleted on a normal exit; finding it at start-up means the previous run
    crashed, was killed, or the machine lost power / was reset
  - system boot time, to tell whether the PC restarted since Zen mode was
    switched on }

{$mode objfpc}{$H+}

interface

{ False if another djZen instance is already running. }
function AcquireSingleInstance: Boolean;

{ Creates the lock file. Returns True if the previous session did not end
  cleanly (the lock file was still there). }
function BeginSession: Boolean;
procedure EndSession;

function PreviousSessionUnclean: Boolean;
function SystemBootTime: TDateTime;

{ Parses the snapshot's 'yyyy-mm-ddThh:nn:ss' local timestamp; 0 if invalid. }
function ParseIsoLocal(const S: string): TDateTime;

implementation

uses
  Windows, SysUtils, djzen.core.paths, djzen.core.log;

var
  Mutex: THandle;
  Unclean: Boolean;

function LockFile: string;
begin
  Result := MachineDataDir + 'running.lock';
end;

function AcquireSingleInstance: Boolean;
begin
  Mutex := CreateMutexW(nil, True, 'Global\djZen.SingleInstance');
  Result := (Mutex <> 0) and (GetLastError <> ERROR_ALREADY_EXISTS);
end;

function BeginSession: Boolean;
var
  F: TextFile;
begin
  Unclean := FileExists(LockFile);
  if Unclean then
    LogWarn('Previous djZen session did not end cleanly');
  try
    ForceDirectories(ExtractFileDir(LockFile));
    AssignFile(F, LockFile);
    Rewrite(F);
    try
      WriteLn(F, GetCurrentProcessId, ' ', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
    finally
      CloseFile(F);
    end;
  except
    on E: Exception do
      LogWarn('Cannot write lock file: ' + E.Message);
  end;
  Result := Unclean;
end;

procedure EndSession;
begin
  if FileExists(LockFile) then
    DeleteFile(LockFile);
  if Mutex <> 0 then
  begin
    ReleaseMutex(Mutex);
    CloseHandle(Mutex);
    Mutex := 0;
  end;
end;

function PreviousSessionUnclean: Boolean;
begin
  Result := Unclean;
end;

function SystemBootTime: TDateTime;
begin
  Result := Now - GetTickCount64 / MSecsPerDay;
end;

function ParseIsoLocal(const S: string): TDateTime;
var
  Y, Mo, D, H, Mi, Se: Integer;
begin
  Result := 0;
  if (Length(S) < 19) or (S[5] <> '-') or (S[11] <> 'T') then
    Exit;
  if TryStrToInt(Copy(S, 1, 4), Y) and TryStrToInt(Copy(S, 6, 2), Mo) and
     TryStrToInt(Copy(S, 9, 2), D) and TryStrToInt(Copy(S, 12, 2), H) and
     TryStrToInt(Copy(S, 15, 2), Mi) and TryStrToInt(Copy(S, 18, 2), Se) then
    try
      Result := EncodeDate(Y, Mo, D) + EncodeTime(H, Mi, Se, 0);
    except
      Result := 0;
    end;
end;

end.
