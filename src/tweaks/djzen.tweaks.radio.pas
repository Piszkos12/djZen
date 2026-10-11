unit djzen.tweaks.radio;

{ Wireless radios: their drivers are a frequent source of DPC latency spikes. }

{$mode objfpc}{$H+}

interface

implementation

uses
  SysUtils, fpjson, djzen.core.tweak, djzen.win.radio;

type
  TWifiTweak = class(TAuditOnlyTweak)
  public
    function Id: string; override;
    function Name: string; override;
    function Description: string; override;
    function Category: TTweakCategory; override;
    function Impact: TTweakImpact; override;
    function Risk: TTweakRisk; override;
    function Check: TTweakCheck; override;
    function Capture: TJSONObject; override;
  end;

  TBluetoothTweak = class(TAuditOnlyTweak)
  public
    function Id: string; override;
    function Name: string; override;
    function Description: string; override;
    function Category: TTweakCategory; override;
    function Impact: TTweakImpact; override;
    function Risk: TTweakRisk; override;
    function Check: TTweakCheck; override;
    function Capture: TJSONObject; override;
  end;

const
  RadioStateText: array[TRadioState] of string = ('absent', 'off', 'on', 'unknown');

{ TWifiTweak }

function TWifiTweak.Id: string; begin Result := 'radio.wifi'; end;
function TWifiTweak.Name: string; begin Result := 'Turn off Wi-Fi'; end;
function TWifiTweak.Description: string;
begin
  Result := 'Wi-Fi drivers scan for networks in the background and are a top cause of audio dropouts.';
end;
function TWifiTweak.Category: TTweakCategory; begin Result := tcNetwork; end;
function TWifiTweak.Impact: TTweakImpact; begin Result := tiHigh; end;
function TWifiTweak.Risk: TTweakRisk; begin Result := trSafe; end;

function TWifiTweak.Check: TTweakCheck;
var
  Adapters: TWifiAdapters;
  Available: Boolean;
  A: TWifiAdapter;
  Detail: string;
  AnyOn: Boolean;
begin
  try
    Adapters := QueryWifiAdapters(Available);
    if not Available then
      Exit(MakeCheck(tsOptimal, 'WLAN service not running'));
    if Length(Adapters) = 0 then
      Exit(MakeCheck(tsNotApplicable, 'No Wi-Fi adapter'));
    Detail := '';
    AnyOn := False;
    for A in Adapters do
    begin
      if Detail <> '' then
        Detail := Detail + '; ';
      Detail := Detail + A.Description + ': ' + RadioStateText[A.State];
      AnyOn := AnyOn or (A.State in [rsOn, rsUnknown]);
    end;
    if AnyOn then
      Result := MakeCheck(tsNotOptimal, Detail)
    else
      Result := MakeCheck(tsOptimal, Detail);
  except
    on E: Exception do
      Result := MakeCheck(tsError, E.Message);
  end;
end;

function TWifiTweak.Capture: TJSONObject;
var
  Adapters: TWifiAdapters;
  Available: Boolean;
  A: TWifiAdapter;
  List: TJSONArray;
begin
  Adapters := QueryWifiAdapters(Available);
  Result := TJSONObject.Create;
  Result.Add('serviceAvailable', Available);
  List := TJSONArray.Create;
  for A in Adapters do
    List.Add(TJSONObject.Create(['description', A.Description, 'state', RadioStateText[A.State]]));
  Result.Add('adapters', List);
end;

{ TBluetoothTweak }

function TBluetoothTweak.Id: string; begin Result := 'radio.bluetooth'; end;
function TBluetoothTweak.Name: string; begin Result := 'Turn off Bluetooth'; end;
function TBluetoothTweak.Description: string;
begin
  Result := 'Bluetooth scanning adds latency, and a connected headset can steal the audio output.';
end;
function TBluetoothTweak.Category: TTweakCategory; begin Result := tcNetwork; end;
function TBluetoothTweak.Impact: TTweakImpact; begin Result := tiMedium; end;
function TBluetoothTweak.Risk: TTweakRisk; begin Result := trSafe; end;

function TBluetoothTweak.Check: TTweakCheck;
begin
  try
    case QueryBluetoothRadio of
      rsOn:      Result := MakeCheck(tsNotOptimal, 'Bluetooth radio is on');
      rsUnknown: Result := MakeCheck(tsUnknown, 'Bluetooth state cannot be read');
    else
      Result := MakeCheck(tsOptimal, 'No active Bluetooth radio');
    end;
  except
    on E: Exception do
      Result := MakeCheck(tsError, E.Message);
  end;
end;

function TBluetoothTweak.Capture: TJSONObject;
begin
  Result := TJSONObject.Create(['state', RadioStateText[QueryBluetoothRadio]]);
end;

initialization
  Tweaks.Add(TWifiTweak.Create);
  Tweaks.Add(TBluetoothTweak.Create);

end.
