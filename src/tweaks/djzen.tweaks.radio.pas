unit djzen.tweaks.radio;

{ Wireless radios: their drivers are a frequent source of DPC latency spikes. }

{$mode objfpc}{$H+}

interface

implementation

uses
  SysUtils, fpjson, djzen.core.tweak, djzen.win.radio;

type
  TWifiTweak = class(TTweak)
  public
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

  TBluetoothTweak = class(TTweak)
  public
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
    List.Add(TJSONObject.Create(['guid', GUIDToString(A.Guid), 'description', A.Description,
      'state', RadioStateText[A.State]]));
  Result.Add('adapters', List);
end;

procedure TWifiTweak.Apply(Params: TJSONObject);
var
  Adapters: TWifiAdapters;
  Available: Boolean;
  A: TWifiAdapter;
begin
  Adapters := QueryWifiAdapters(Available);
  for A in Adapters do
    if A.State in [rsOn, rsUnknown] then
      SetWifiRadio(A.Guid, False);
end;

{ Only adapters that were on are switched back on; adapters removed since
  the capture are skipped. }
procedure TWifiTweak.Revert(Saved: TJSONObject);
var
  Adapters: TWifiAdapters;
  Available: Boolean;
  List: TJSONArray;
  Item: TJSONObject;
  Guid: TGUID;
  I, J: Integer;
begin
  List := Saved.Find('adapters', jtArray) as TJSONArray;
  if List = nil then
    Exit;
  Adapters := QueryWifiAdapters(Available);
  for I := 0 to List.Count - 1 do
  begin
    Item := List.Objects[I];
    if Item.Get('state', '') <> RadioStateText[rsOn] then
      Continue;
    Guid := StringToGUID(Item.Strings['guid']);
    for J := 0 to High(Adapters) do
      if IsEqualGUID(Adapters[J].Guid, Guid) then
        SetWifiRadio(Guid, True);
  end;
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

{ Radios of the Bluetooth kind as Windows radio management sees them. }
function BluetoothRadios: TWinRadios;
var
  All: TWinRadios;
  R: TWinRadio;
begin
  Result := nil;
  All := QueryWinRadios;
  for R in All do
    if R.Kind = rkBluetooth then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := R;
    end;
end;

function TBluetoothTweak.Check: TTweakCheck;
var
  Radios: TWinRadios;
  R: TWinRadio;
  Detail: string;
  AnyOn: Boolean;
begin
  try
    Radios := BluetoothRadios;
    if Length(Radios) = 0 then
      Exit(MakeCheck(tsNotApplicable, 'No Bluetooth radio'));
    Detail := '';
    AnyOn := False;
    for R in Radios do
    begin
      if Detail <> '' then
        Detail := Detail + '; ';
      Detail := Detail + R.Name + ': ' + RadioStateText[R.State];
      AnyOn := AnyOn or (R.State in [rsOn, rsUnknown]);
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

function TBluetoothTweak.Capture: TJSONObject;
var
  R: TWinRadio;
  List: TJSONArray;
begin
  List := TJSONArray.Create;
  Result := TJSONObject.Create(['radios', List]);
  for R in BluetoothRadios do
    List.Add(TJSONObject.Create(['name', R.Name, 'state', RadioStateText[R.State]]));
end;

procedure TBluetoothTweak.Apply(Params: TJSONObject);
begin
  SetWinRadioState(rkBluetooth, '', False);
end;

{ Only radios that were on are switched back on. }
procedure TBluetoothTweak.Revert(Saved: TJSONObject);
var
  List: TJSONArray;
  I: Integer;
begin
  List := Saved.Find('radios', jtArray) as TJSONArray;
  if List = nil then
    Exit;
  for I := 0 to List.Count - 1 do
    if List.Objects[I].Get('state', '') = RadioStateText[rsOn] then
      SetWinRadioState(rkBluetooth, List.Objects[I].Get('name', ''), True);
end;

initialization
  Tweaks.Add(TWifiTweak.Create);
  Tweaks.Add(TBluetoothTweak.Create);

end.
