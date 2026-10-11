unit djzen.win.services;

{ Windows service queries (Service Control Manager). }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils;

type
  TServiceInfo = record
    Installed: Boolean;
    State: DWORD;       // SERVICE_RUNNING, SERVICE_STOPPED, ...
    StartType: DWORD;   // SERVICE_AUTO_START, SERVICE_DEMAND_START, SERVICE_DISABLED, ...
  end;

  EService = class(Exception);

function QueryServiceInfo(const ServiceName: string): TServiceInfo;

{ These do not check the blocklist; callers must (EnsureServiceNotProtected). }
procedure SetServiceStartType(const ServiceName: string; StartType: DWORD);
procedure StopServiceAndWait(const ServiceName: string; TimeoutMs: DWORD = 30000);
procedure StartServiceAndWait(const ServiceName: string; TimeoutMs: DWORD = 30000);

function ServiceStateText(State: DWORD): string;
function ServiceStartTypeText(StartType: DWORD): string;

implementation

uses
  JwaWinSvc;

function QueryServiceInfo(const ServiceName: string): TServiceInfo;
var
  Scm, Svc: SC_HANDLE;
  Status: SERVICE_STATUS;
  Config: LPQUERY_SERVICE_CONFIGW;
  Needed: DWORD;
begin
  Result := Default(TServiceInfo);
  Scm := OpenSCManagerW(nil, nil, SC_MANAGER_CONNECT);
  if Scm = 0 then
    raise EService.CreateFmt('OpenSCManager failed: %s', [SysErrorMessage(GetLastError)]);
  try
    Svc := OpenServiceW(Scm, PWideChar(UnicodeString(ServiceName)),
      SERVICE_QUERY_STATUS or SERVICE_QUERY_CONFIG);
    if Svc = 0 then
    begin
      if GetLastError = ERROR_SERVICE_DOES_NOT_EXIST then
        Exit;
      raise EService.CreateFmt('OpenService(%s) failed: %s', [ServiceName, SysErrorMessage(GetLastError)]);
    end;
    try
      Result.Installed := True;
      Status := Default(SERVICE_STATUS);
      if not QueryServiceStatus(Svc, Status) then
        raise EService.CreateFmt('QueryServiceStatus(%s) failed: %s', [ServiceName, SysErrorMessage(GetLastError)]);
      Result.State := Status.dwCurrentState;

      Needed := 0;
      QueryServiceConfigW(Svc, nil, 0, Needed);
      Config := GetMem(Needed);
      try
        if not QueryServiceConfigW(Svc, Config, Needed, Needed) then
          raise EService.CreateFmt('QueryServiceConfig(%s) failed: %s', [ServiceName, SysErrorMessage(GetLastError)]);
        Result.StartType := Config^.dwStartType;
      finally
        FreeMem(Config);
      end;
    finally
      CloseServiceHandle(Svc);
    end;
  finally
    CloseServiceHandle(Scm);
  end;
end;

type
  TServiceProc = procedure(Svc: SC_HANDLE; const ServiceName: string; Arg: DWORD);

procedure WithService(const ServiceName: string; Access: DWORD; Proc: TServiceProc;
  Arg: DWORD);
var
  Scm, Svc: SC_HANDLE;
begin
  Scm := OpenSCManagerW(nil, nil, SC_MANAGER_CONNECT);
  if Scm = 0 then
    raise EService.CreateFmt('OpenSCManager failed: %s', [SysErrorMessage(GetLastError)]);
  try
    Svc := OpenServiceW(Scm, PWideChar(UnicodeString(ServiceName)), Access);
    if Svc = 0 then
      raise EService.CreateFmt('OpenService(%s) failed: %s', [ServiceName, SysErrorMessage(GetLastError)]);
    try
      Proc(Svc, ServiceName, Arg);
    finally
      CloseServiceHandle(Svc);
    end;
  finally
    CloseServiceHandle(Scm);
  end;
end;

procedure WaitForState(Svc: SC_HANDLE; const ServiceName: string; Wanted, TimeoutMs: DWORD);
var
  Status: SERVICE_STATUS;
  Start: QWord;
begin
  Start := GetTickCount64;
  repeat
    Status := Default(SERVICE_STATUS);
    if not QueryServiceStatus(Svc, Status) then
      raise EService.CreateFmt('QueryServiceStatus(%s) failed: %s', [ServiceName, SysErrorMessage(GetLastError)]);
    if Status.dwCurrentState = Wanted then
      Exit;
    Sleep(200);
  until GetTickCount64 - Start > TimeoutMs;
  raise EService.CreateFmt('%s did not become %s in time', [ServiceName, ServiceStateText(Wanted)]);
end;

procedure DoSetStartType(Svc: SC_HANDLE; const ServiceName: string; Arg: DWORD);
begin
  if not ChangeServiceConfigW(Svc, SERVICE_NO_CHANGE, Arg, SERVICE_NO_CHANGE,
    nil, nil, nil, nil, nil, nil, nil) then
    raise EService.CreateFmt('ChangeServiceConfig(%s) failed: %s', [ServiceName, SysErrorMessage(GetLastError)]);
end;

procedure DoStop(Svc: SC_HANDLE; const ServiceName: string; TimeoutMs: DWORD);
var
  Status: SERVICE_STATUS;
begin
  Status := Default(SERVICE_STATUS);
  if not QueryServiceStatus(Svc, Status) then
    raise EService.CreateFmt('QueryServiceStatus(%s) failed: %s', [ServiceName, SysErrorMessage(GetLastError)]);
  if Status.dwCurrentState = SERVICE_STOPPED then
    Exit;
  if not ControlService(Svc, SERVICE_CONTROL_STOP, Status) and
     (GetLastError <> ERROR_SERVICE_NOT_ACTIVE) then
    raise EService.CreateFmt('Stopping %s failed: %s', [ServiceName, SysErrorMessage(GetLastError)]);
  WaitForState(Svc, ServiceName, SERVICE_STOPPED, TimeoutMs);
end;

procedure DoStart(Svc: SC_HANDLE; const ServiceName: string; TimeoutMs: DWORD);
begin
  if not StartServiceW(Svc, 0, nil) and (GetLastError <> ERROR_SERVICE_ALREADY_RUNNING) then
    raise EService.CreateFmt('Starting %s failed: %s', [ServiceName, SysErrorMessage(GetLastError)]);
  WaitForState(Svc, ServiceName, SERVICE_RUNNING, TimeoutMs);
end;

procedure SetServiceStartType(const ServiceName: string; StartType: DWORD);
begin
  WithService(ServiceName, SERVICE_CHANGE_CONFIG, @DoSetStartType, StartType);
end;

procedure StopServiceAndWait(const ServiceName: string; TimeoutMs: DWORD);
begin
  WithService(ServiceName, SERVICE_STOP or SERVICE_QUERY_STATUS, @DoStop, TimeoutMs);
end;

procedure StartServiceAndWait(const ServiceName: string; TimeoutMs: DWORD);
begin
  WithService(ServiceName, SERVICE_START or SERVICE_QUERY_STATUS, @DoStart, TimeoutMs);
end;

function ServiceStateText(State: DWORD): string;
begin
  case State of
    SERVICE_STOPPED:          Result := 'stopped';
    SERVICE_START_PENDING:    Result := 'starting';
    SERVICE_STOP_PENDING:     Result := 'stopping';
    SERVICE_RUNNING:          Result := 'running';
    SERVICE_CONTINUE_PENDING: Result := 'resuming';
    SERVICE_PAUSE_PENDING:    Result := 'pausing';
    SERVICE_PAUSED:           Result := 'paused';
  else
    Result := 'unknown';
  end;
end;

function ServiceStartTypeText(StartType: DWORD): string;
begin
  case StartType of
    SERVICE_BOOT_START:   Result := 'boot';
    SERVICE_SYSTEM_START: Result := 'system';
    SERVICE_AUTO_START:   Result := 'automatic';
    SERVICE_DEMAND_START: Result := 'manual';
    SERVICE_DISABLED:     Result := 'disabled';
  else
    Result := 'unknown';
  end;
end;

end.
