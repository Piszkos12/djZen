unit djzen.win.process;

{ Running process enumeration and priority classes. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils;

type
  TProcessEntry = record
    Pid: DWORD;
    ExeName: string;
    CreationTime: Int64;   // FILETIME as Int64; identifies the process together with the PID
  end;
  TProcessEntries = array of TProcessEntry;

  EProcess = class(Exception);

{ Running processes whose exe name matches any pattern ('*' and '?' wildcards). }
function FindProcesses(const Patterns: array of string): TProcessEntries;
{ 0 if the process is gone or cannot be opened. }
function ProcessCreationTime(Pid: DWORD): Int64;
function GetProcessPriority(Pid: DWORD): DWORD;
procedure SetProcessPriority(Pid, PriorityClass: DWORD);

function PriorityClassText(PriorityClass: DWORD): string;
{ 'normal', 'abovenormal' or 'high'; anything else (including 'realtime') raises. }
function PriorityClassFromText(const S: string): DWORD;
{ Orders priority classes from idle (0) to realtime (5). }
function PriorityRank(PriorityClass: DWORD): Integer;

implementation

uses
  JwaTlHelp32, djzen.core.blocklist;

const
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

function FindProcesses(const Patterns: array of string): TProcessEntries;
var
  Snap: THandle;
  Entry: TProcessEntry32W;
  Name, P: string;
begin
  Result := nil;
  Snap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then
    raise EProcess.CreateFmt('CreateToolhelp32Snapshot failed: %s', [SysErrorMessage(GetLastError)]);
  try
    Entry.dwSize := SizeOf(Entry);
    if not Process32FirstW(Snap, Entry) then
      Exit;
    repeat
      Name := UTF8Encode(UnicodeString(PWideChar(@Entry.szExeFile[0])));
      for P in Patterns do
        if WildcardMatch(P, Name) then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)].Pid := Entry.th32ProcessID;
          Result[High(Result)].ExeName := Name;
          Result[High(Result)].CreationTime := ProcessCreationTime(Entry.th32ProcessID);
          Break;
        end;
    until not Process32NextW(Snap, Entry);
  finally
    CloseHandle(Snap);
  end;
end;

function ProcessCreationTime(Pid: DWORD): Int64;
var
  H: THandle;
  Created, Exited, Kernel, User: TFileTime;
begin
  Result := 0;
  H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, Pid);
  if H = 0 then
    Exit;
  try
    Created := Default(TFileTime);
    Exited := Created;
    Kernel := Created;
    User := Created;
    if GetProcessTimes(H, Created, Exited, Kernel, User) then
      Result := Int64(Created);
  finally
    CloseHandle(H);
  end;
end;

function GetProcessPriority(Pid: DWORD): DWORD;
var
  H: THandle;
begin
  H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, Pid);
  if H = 0 then
    raise EProcess.CreateFmt('Cannot open process %d: %s', [Pid, SysErrorMessage(GetLastError)]);
  try
    Result := GetPriorityClass(H);
    if Result = 0 then
      raise EProcess.CreateFmt('GetPriorityClass(%d) failed: %s', [Pid, SysErrorMessage(GetLastError)]);
  finally
    CloseHandle(H);
  end;
end;

procedure SetProcessPriority(Pid, PriorityClass: DWORD);
var
  H: THandle;
begin
  if PriorityClass = REALTIME_PRIORITY_CLASS then
    raise EProcess.Create('Realtime priority is never used: it can freeze the whole system');
  H := OpenProcess(PROCESS_SET_INFORMATION, False, Pid);
  if H = 0 then
    raise EProcess.CreateFmt('Cannot open process %d: %s', [Pid, SysErrorMessage(GetLastError)]);
  try
    if not SetPriorityClass(H, PriorityClass) then
      raise EProcess.CreateFmt('SetPriorityClass(%d) failed: %s', [Pid, SysErrorMessage(GetLastError)]);
  finally
    CloseHandle(H);
  end;
end;

function PriorityClassText(PriorityClass: DWORD): string;
begin
  case PriorityClass of
    IDLE_PRIORITY_CLASS:         Result := 'idle';
    BELOW_NORMAL_PRIORITY_CLASS: Result := 'belownormal';
    NORMAL_PRIORITY_CLASS:       Result := 'normal';
    ABOVE_NORMAL_PRIORITY_CLASS: Result := 'abovenormal';
    HIGH_PRIORITY_CLASS:         Result := 'high';
    REALTIME_PRIORITY_CLASS:     Result := 'realtime';
  else
    Result := IntToStr(PriorityClass);
  end;
end;

function PriorityClassFromText(const S: string): DWORD;
begin
  if SameText(S, 'normal') then
    Result := NORMAL_PRIORITY_CLASS
  else if SameText(S, 'abovenormal') then
    Result := ABOVE_NORMAL_PRIORITY_CLASS
  else if SameText(S, 'high') then
    Result := HIGH_PRIORITY_CLASS
  else
    raise EProcess.CreateFmt('Unsupported priority "%s" (use normal, abovenormal or high)', [S]);
end;

function PriorityRank(PriorityClass: DWORD): Integer;
begin
  case PriorityClass of
    IDLE_PRIORITY_CLASS:         Result := 0;
    BELOW_NORMAL_PRIORITY_CLASS: Result := 1;
    NORMAL_PRIORITY_CLASS:       Result := 2;
    ABOVE_NORMAL_PRIORITY_CLASS: Result := 3;
    HIGH_PRIORITY_CLASS:         Result := 4;
    REALTIME_PRIORITY_CLASS:     Result := 5;
  else
    Result := 2;
  end;
end;

end.
