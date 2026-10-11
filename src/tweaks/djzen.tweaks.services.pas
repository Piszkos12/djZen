unit djzen.tweaks.services;

{ Background services that eat disk, CPU or network during a set. }

{$mode objfpc}{$H+}

interface

implementation

uses
  SysUtils, Windows, fpjson, JwaWinSvc,
  djzen.core.tweak, djzen.core.blocklist, djzen.win.services;

type
  { Optimal when the service is not running. }
  TServiceTweak = class(TTweak)
  private
    FId, FName, FDescription, FServiceName: string;
    FImpact: TTweakImpact;
    FRisk: TTweakRisk;
  public
    constructor Create(const AId, AName, ADescription, AServiceName: string;
      AImpact: TTweakImpact; ARisk: TTweakRisk);
    function Id: string; override;
    function Name: string; override;
    function Description: string; override;
    function Category: TTweakCategory; override;
    function Impact: TTweakImpact; override;
    function Risk: TTweakRisk; override;
    function Check: TTweakCheck; override;
    function Capture: TJSONObject; override;
    procedure Apply(Params: TJSONObject); override;
    procedure Revert(Saved: TJSONObject); override;
  end;

constructor TServiceTweak.Create(const AId, AName, ADescription, AServiceName: string;
  AImpact: TTweakImpact; ARisk: TTweakRisk);
begin
  inherited Create;
  // A protected service must never become a tweak, not even by mistake.
  EnsureServiceNotProtected(AServiceName);
  FId := AId;
  FName := AName;
  FDescription := ADescription;
  FServiceName := AServiceName;
  FImpact := AImpact;
  FRisk := ARisk;
end;

function TServiceTweak.Id: string; begin Result := FId; end;
function TServiceTweak.Name: string; begin Result := FName; end;
function TServiceTweak.Description: string; begin Result := FDescription; end;
function TServiceTweak.Category: TTweakCategory; begin Result := tcServices; end;
function TServiceTweak.Impact: TTweakImpact; begin Result := FImpact; end;
function TServiceTweak.Risk: TTweakRisk; begin Result := FRisk; end;

function TServiceTweak.Check: TTweakCheck;
var
  Info: TServiceInfo;
begin
  try
    Info := QueryServiceInfo(FServiceName);
    if not Info.Installed then
      Exit(MakeCheck(tsNotApplicable, FServiceName + ' is not installed'));
    Result := MakeCheck(tsNotOptimal, Format('%s: %s, start: %s',
      [FServiceName, ServiceStateText(Info.State), ServiceStartTypeText(Info.StartType)]));
    if Info.State = SERVICE_STOPPED then
      Result.Status := tsOptimal;
  except
    on E: Exception do
      Result := MakeCheck(tsError, E.Message);
  end;
end;

function TServiceTweak.Capture: TJSONObject;
var
  Info: TServiceInfo;
begin
  Info := QueryServiceInfo(FServiceName);
  Result := TJSONObject.Create;
  Result.Add('service', FServiceName);
  Result.Add('installed', Info.Installed);
  Result.Add('running', Info.State = SERVICE_RUNNING);
  Result.Add('startType', Int64(Info.StartType));
end;

{ Disabling the start type keeps trigger-started services (e.g. Windows
  Update) from coming straight back. }
procedure TServiceTweak.Apply(Params: TJSONObject);
var
  Info: TServiceInfo;
begin
  EnsureServiceNotProtected(FServiceName);
  Info := QueryServiceInfo(FServiceName);
  if not Info.Installed then
    Exit;
  SetServiceStartType(FServiceName, SERVICE_DISABLED);
  StopServiceAndWait(FServiceName);
end;

procedure TServiceTweak.Revert(Saved: TJSONObject);
begin
  if not Saved.Get('installed', False) then
    Exit;
  SetServiceStartType(FServiceName, DWORD(Saved.Int64s['startType']));
  if Saved.Get('running', False) then
    StartServiceAndWait(FServiceName);
end;

initialization
  Tweaks.Add(TServiceTweak.Create('service.windows-update',
    'Pause Windows Update',
    'Stops update downloads and installs that hog disk, network and CPU.',
    'wuauserv', tiHigh, trSafe));
  Tweaks.Add(TServiceTweak.Create('service.windows-search',
    'Pause search indexing',
    'The search indexer reads the disk heavily, e.g. when you add new tracks.',
    'WSearch', tiMedium, trSafe));
  Tweaks.Add(TServiceTweak.Create('service.sysmain',
    'Pause SysMain (Superfetch)',
    'SysMain preloads applications in the background and causes disk activity.',
    'SysMain', tiLow, trSafe));

end.
