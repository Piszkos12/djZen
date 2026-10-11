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
