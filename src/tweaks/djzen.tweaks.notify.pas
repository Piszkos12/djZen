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
  SysUtils, Windows, Registry, fpjson, djzen.core.tweak;

type
  { Optimal when a HKCU registry value equals the wanted value. }
  TRegistryValueTweak = class(TAuditOnlyTweak)
  private
    FId, FName, FDescription: string;
    FImpact: TTweakImpact;
    FKey, FValueName, FOptimal, FMissingMeans: string;
    function ReadValue(out Exists: Boolean): string;
  public
    constructor Create(const AId, AName, ADescription: string; AImpact: TTweakImpact;
      const AKey, AValueName, AOptimal, AMissingMeans: string);
    function Id: string; override;
    function Name: string; override;
    function Description: string; override;
    function Category: TTweakCategory; override;
    function Impact: TTweakImpact; override;
    function Risk: TTweakRisk; override;
    function Check: TTweakCheck; override;
    function Capture: TJSONObject; override;
  end;

constructor TRegistryValueTweak.Create(const AId, AName, ADescription: string;
  AImpact: TTweakImpact; const AKey, AValueName, AOptimal, AMissingMeans: string);
begin
  inherited Create;
  FId := AId;
  FName := AName;
  FDescription := ADescription;
  FImpact := AImpact;
  FKey := AKey;
  FValueName := AValueName;
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
function TRegistryValueTweak.ReadValue(out Exists: Boolean): string;
var
  Reg: TRegistry;
begin
  Result := '';
  Exists := False;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly(FKey) then
      Exit;
    if not Reg.ValueExists(FValueName) then
      Exit;
    Exists := True;
    case Reg.GetDataType(FValueName) of
      rdInteger: Result := IntToStr(Reg.ReadInteger(FValueName));
    else
      Result := Reg.ReadString(FValueName);
    end;
  finally
    Reg.Free;
  end;
end;

function TRegistryValueTweak.Check: TTweakCheck;
var
  Exists: Boolean;
  Value: string;
begin
  try
    Value := ReadValue(Exists);
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
  Value: string;
begin
  Value := ReadValue(Exists);
  Result := TJSONObject.Create;
  Result.Add('key', 'HKCU\' + FKey);
  Result.Add('value', FValueName);
  Result.Add('exists', Exists);
  Result.Add('data', Value);
end;

initialization
  Tweaks.Add(TRegistryValueTweak.Create('notify.toasts',
    'Turn off notifications',
    'Hides toast notifications and their sounds (mail, chat, updates, reminders).',
    tiHigh, 'Software\Microsoft\Windows\CurrentVersion\PushNotifications',
    'ToastEnabled', '0', '1'));
  Tweaks.Add(TRegistryValueTweak.Create('notify.system-sounds',
    'Mute system sounds',
    'Switches the Windows sound scheme to "No Sounds" so error and device beeps never reach the mix.',
    tiHigh, 'AppEvents\Schemes', '', '.None', '.Default'));
  Tweaks.Add(TRegistryValueTweak.Create('notify.audio-ducking',
    'Disable communication ducking',
    'Windows lowers other sounds by up to 80% when it detects a call. "Do nothing" keeps your volume.',
    tiMedium, 'Software\Microsoft\Multimedia\Audio', 'UserDuckingPreference', '3', '1'));

end.
