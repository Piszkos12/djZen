unit djzen.tweaks.notify;

{ Things that make sounds or change the volume on their own.

  Note: these are per-user settings in HKEY_CURRENT_USER. djZen runs elevated,
  which is the same user when an administrator account confirms the UAC
  prompt, but not when a standard user elevates with another account's
  credentials. }

{$mode objfpc}{$H+}

interface

implementation

uses
  Classes, SysUtils, Windows, Registry, fpjson, djzen.core.tweak;

type
  TRegValueKind = (rvDword, rvString);

  { Optimal when a HKCU registry value equals the wanted value. }
  TRegistryValueTweak = class(TTweak)
  private
    FId, FName, FDescription: string;
    FImpact: TTweakImpact;
    FKey, FValueName, FOptimal, FMissingMeans: string;
    FKind: TRegValueKind;
    function ReadValue(out Exists: Boolean; out Kind: TRegValueKind): string;
  public
    constructor Create(const AId, AName, ADescription: string; AImpact: TTweakImpact;
      const AKey, AValueName: string; AKind: TRegValueKind; const AOptimal, AMissingMeans: string);
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

  { Clears the sound of every event in the current sound scheme and selects
    the "No Sounds" scheme. Selecting the scheme alone does not silence
    anything: Windows plays the per-event ".Current" values. }
  TSystemSoundsTweak = class(TTweak)
  private
    procedure ListSounds(Sounds: TStrings);
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
  KindText: array[TRegValueKind] of string = ('dword', 'string');

function OpenUserKey(const Key: string; Write: Boolean): TRegistry;
begin
  if Write then
    Result := TRegistry.Create(KEY_READ or KEY_WRITE)
  else
    Result := TRegistry.Create(KEY_READ);
  Result.RootKey := HKEY_CURRENT_USER;
  if Write then
  begin
    if Result.OpenKey(Key, True) then
      Exit;
  end
  else if Result.OpenKeyReadOnly(Key) then
    Exit;
  Result.Free;
  Result := nil;
  if Write then
    raise ERegistryException.CreateFmt('Cannot open HKCU\%s', [Key]);
end;

{ TRegistryValueTweak }

constructor TRegistryValueTweak.Create(const AId, AName, ADescription: string;
  AImpact: TTweakImpact; const AKey, AValueName: string; AKind: TRegValueKind;
  const AOptimal, AMissingMeans: string);
begin
  inherited Create;
  FId := AId;
  FName := AName;
  FDescription := ADescription;
  FImpact := AImpact;
  FKey := AKey;
  FValueName := AValueName;
  FKind := AKind;
  FOptimal := AOptimal;
  FMissingMeans := AMissingMeans;
end;

function TRegistryValueTweak.Id: string; begin Result := FId; end;
function TRegistryValueTweak.Name: string; begin Result := FName; end;
function TRegistryValueTweak.Description: string; begin Result := FDescription; end;
function TRegistryValueTweak.Category: TTweakCategory; begin Result := tcAudio; end;
function TRegistryValueTweak.Impact: TTweakImpact; begin Result := FImpact; end;
function TRegistryValueTweak.Risk: TTweakRisk; begin Result := trSafe; end;

{ DWORD and string values are both returned as text. }
function TRegistryValueTweak.ReadValue(out Exists: Boolean; out Kind: TRegValueKind): string;
var
  Reg: TRegistry;
begin
  Result := '';
  Exists := False;
  Kind := FKind;
  Reg := OpenUserKey(FKey, False);
  if Reg = nil then
    Exit;
  try
    if not Reg.ValueExists(FValueName) then
      Exit;
    Exists := True;
    if Reg.GetDataType(FValueName) = rdInteger then
    begin
      Kind := rvDword;
      Result := IntToStr(Reg.ReadInteger(FValueName));
    end
    else
    begin
      Kind := rvString;
      Result := Reg.ReadString(FValueName);
    end;
  finally
    Reg.Free;
  end;
end;

function TRegistryValueTweak.Check: TTweakCheck;
var
  Exists: Boolean;
  Kind: TRegValueKind;
  Value: string;
begin
  try
    Value := ReadValue(Exists, Kind);
    if not Exists then
      Value := FMissingMeans;
    Result := MakeCheck(tsNotOptimal, Format('Current: %s (wanted: %s)', [Value, FOptimal]));
    if SameText(Value, FOptimal) then
      Result.Status := tsOptimal;
  except
    on E: Exception do
      Result := MakeCheck(tsError, E.Message);
  end;
end;

function TRegistryValueTweak.Capture: TJSONObject;
var
  Exists: Boolean;
  Kind: TRegValueKind;
  Value: string;
begin
  Value := ReadValue(Exists, Kind);
  Result := TJSONObject.Create;
  Result.Add('key', 'HKCU\' + FKey);
  Result.Add('value', FValueName);
  Result.Add('exists', Exists);
  Result.Add('type', KindText[Kind]);
  Result.Add('data', Value);
end;

procedure TRegistryValueTweak.Apply(Params: TJSONObject);
var
  Reg: TRegistry;
begin
  Reg := OpenUserKey(FKey, True);
  try
    if FKind = rvDword then
      Reg.WriteInteger(FValueName, StrToInt(FOptimal))
    else
      Reg.WriteString(FValueName, FOptimal);
  finally
    Reg.Free;
  end;
end;

{ A value that did not exist before is deleted again. }
procedure TRegistryValueTweak.Revert(Saved: TJSONObject);
var
  Reg: TRegistry;
begin
  if not Saved.Get('exists', False) then
  begin
    Reg := OpenUserKey(FKey, False);
    if Reg = nil then
      Exit;
    Reg.Free;
    Reg := OpenUserKey(FKey, True);
    try
      if Reg.ValueExists(FValueName) then
        Reg.DeleteValue(FValueName);
    finally
      Reg.Free;
    end;
    Exit;
  end;

  Reg := OpenUserKey(FKey, True);
  try
    if Saved.Get('type', '') = KindText[rvDword] then
      Reg.WriteInteger(FValueName, StrToInt(Saved.Get('data', '0')))
    else
      Reg.WriteString(FValueName, Saved.Get('data', ''));
  finally
    Reg.Free;
  end;
end;

{ TSystemSoundsTweak }

const
  SchemesKey = 'AppEvents\Schemes';
  AppsKey = 'AppEvents\Schemes\Apps';

function TSystemSoundsTweak.Id: string; begin Result := 'notify.system-sounds'; end;
function TSystemSoundsTweak.Name: string; begin Result := 'Mute system sounds'; end;
function TSystemSoundsTweak.Description: string;
begin
  Result := 'Silences every Windows event sound (errors, device connect, notifications) ' +
    'so no beep ever reaches the mix.';
end;
function TSystemSoundsTweak.Category: TTweakCategory; begin Result := tcAudio; end;
function TSystemSoundsTweak.Impact: TTweakImpact; begin Result := tiHigh; end;
function TSystemSoundsTweak.Risk: TTweakRisk; begin Result := trSafe; end;

{ Fills Sounds with "App\Event=file" for every event that has a sound. }
procedure TSystemSoundsTweak.ListSounds(Sounds: TStrings);
var
  Reg: TRegistry;
  Apps, Events: TStringList;
  App, Event, Path, Value: string;
begin
  Sounds.Clear;
  Apps := TStringList.Create;
  Events := TStringList.Create;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly(AppsKey) then
      Exit;
    Reg.GetKeyNames(Apps);
    Reg.CloseKey;
    for App in Apps do
    begin
      if not Reg.OpenKeyReadOnly(AppsKey + '\' + App) then
        Continue;
      Reg.GetKeyNames(Events);
      Reg.CloseKey;
      for Event in Events do
      begin
        Path := AppsKey + '\' + App + '\' + Event + '\.Current';
        if not Reg.OpenKeyReadOnly(Path) then
          Continue;
        try
          if Reg.ValueExists('') then
          begin
            Value := Reg.ReadString('');
            if Value <> '' then
              Sounds.Add(App + '\' + Event + '=' + Value);
          end;
        finally
          Reg.CloseKey;
        end;
      end;
    end;
  finally
    Reg.Free;
    Events.Free;
    Apps.Free;
  end;
end;

function TSystemSoundsTweak.Check: TTweakCheck;
var
  Sounds: TStringList;
begin
  Sounds := TStringList.Create;
  try
    try
      ListSounds(Sounds);
      if Sounds.Count = 0 then
        Result := MakeCheck(tsOptimal, 'No event sounds are set')
      else
        Result := MakeCheck(tsNotOptimal, Format('%d event sounds are set', [Sounds.Count]));
    except
      on E: Exception do
        Result := MakeCheck(tsError, E.Message);
    end;
  finally
    Sounds.Free;
  end;
end;

function TSystemSoundsTweak.Capture: TJSONObject;
var
  Sounds: TStringList;
  Map: TJSONObject;
  Reg: TRegistry;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Reg := OpenUserKey(SchemesKey, False);
  if Reg <> nil then
  try
    Result.Add('schemeExists', Reg.ValueExists(''));
    if Reg.ValueExists('') then
      Result.Add('scheme', Reg.ReadString(''));
  finally
    Reg.Free;
  end
  else
    Result.Add('schemeExists', False);

  Map := TJSONObject.Create;
  Result.Add('sounds', Map);
  Sounds := TStringList.Create;
  try
    ListSounds(Sounds);
    for I := 0 to Sounds.Count - 1 do
      Map.Add(Sounds.Names[I], Sounds.ValueFromIndex[I]);
  finally
    Sounds.Free;
  end;
end;

procedure TSystemSoundsTweak.Apply(Params: TJSONObject);
var
  Sounds: TStringList;
  Reg: TRegistry;
  I: Integer;
begin
  Sounds := TStringList.Create;
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    ListSounds(Sounds);
    for I := 0 to Sounds.Count - 1 do
      if Reg.OpenKey(AppsKey + '\' + Sounds.Names[I] + '\.Current', False) then
      begin
        Reg.WriteString('', '');
        Reg.CloseKey;
      end;
    if Reg.OpenKey(SchemesKey, True) then
    begin
      Reg.WriteString('', '.None');
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
    Sounds.Free;
  end;
end;

procedure TSystemSoundsTweak.Revert(Saved: TJSONObject);
var
  Map: TJSONObject;
  Reg: TRegistry;
  I: Integer;
begin
  Reg := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    Map := Saved.Find('sounds', jtObject) as TJSONObject;
    if Map <> nil then
      for I := 0 to Map.Count - 1 do
        if Reg.OpenKey(AppsKey + '\' + Map.Names[I] + '\.Current', True) then
        begin
          Reg.WriteString('', Map.Items[I].AsString);
          Reg.CloseKey;
        end;
    if Reg.OpenKey(SchemesKey, True) then
    begin
      if Saved.Get('schemeExists', False) then
        Reg.WriteString('', Saved.Get('scheme', ''))
      else if Reg.ValueExists('') then
        Reg.DeleteValue('');
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end;

initialization
  Tweaks.Add(TRegistryValueTweak.Create('notify.toasts',
    'Turn off notifications',
    'Hides toast notifications and their sounds (mail, chat, updates, reminders).',
    tiHigh, 'Software\Microsoft\Windows\CurrentVersion\PushNotifications',
    'ToastEnabled', rvDword, '0', '1'));
  Tweaks.Add(TSystemSoundsTweak.Create);
  Tweaks.Add(TRegistryValueTweak.Create('notify.audio-ducking',
    'Disable communication ducking',
    'Windows lowers other sounds by up to 80% when it detects a call. "Do nothing" keeps your volume.',
    tiMedium, 'Software\Microsoft\Multimedia\Audio', 'UserDuckingPreference', rvDword, '3', '1'));

end.
