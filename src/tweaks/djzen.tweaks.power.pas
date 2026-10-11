unit djzen.tweaks.power;

{ Power plan settings that cause USB dropouts, latency spikes or sleep during a set. }

{$mode objfpc}{$H+}

interface

implementation

uses
  SysUtils, Windows, fpjson, djzen.core.tweak, djzen.win.power;

type
  { One power setting that must equal OptimalValue on both AC and DC. }
  TPowerSettingTweak = class(TAuditOnlyTweak)
  private
    FId, FName, FDescription: string;
    FImpact: TTweakImpact;
    FRisk: TTweakRisk;
    FSubGroup, FSetting: TGUID;
    FOptimalValue: DWORD;
    FUnit: string;
    function ValueText(V: DWORD): string;
  public
    constructor Create(const AId, AName, ADescription: string; AImpact: TTweakImpact;
      ARisk: TTweakRisk; const ASubGroup, ASetting: TGUID; AOptimalValue: DWORD;
      const AUnit: string = '');
    function Id: string; override;
    function Name: string; override;
    function Description: string; override;
    function Category: TTweakCategory; override;
    function Impact: TTweakImpact; override;
    function Risk: TTweakRisk; override;
    function Check: TTweakCheck; override;
    function Capture: TJSONObject; override;
  end;

constructor TPowerSettingTweak.Create(const AId, AName, ADescription: string;
  AImpact: TTweakImpact; ARisk: TTweakRisk; const ASubGroup, ASetting: TGUID;
  AOptimalValue: DWORD; const AUnit: string);
begin
  inherited Create;
  FId := AId;
  FName := AName;
  FDescription := ADescription;
  FImpact := AImpact;
  FRisk := ARisk;
  FSubGroup := ASubGroup;
  FSetting := ASetting;
  FOptimalValue := AOptimalValue;
  FUnit := AUnit;
end;

function TPowerSettingTweak.Id: string; begin Result := FId; end;
function TPowerSettingTweak.Name: string; begin Result := FName; end;
function TPowerSettingTweak.Description: string; begin Result := FDescription; end;
function TPowerSettingTweak.Category: TTweakCategory; begin Result := tcPower; end;
function TPowerSettingTweak.Impact: TTweakImpact; begin Result := FImpact; end;
function TPowerSettingTweak.Risk: TTweakRisk; begin Result := FRisk; end;

function TPowerSettingTweak.ValueText(V: DWORD): string;
begin
  Result := IntToStr(V) + FUnit;
end;

function TPowerSettingTweak.Check: TTweakCheck;
var
  V: TPowerValue;
begin
  try
    V := ReadPowerSetting(ActiveSchemeGuid, FSubGroup, FSetting);
    if not V.Present then
      Exit(MakeCheck(tsNotApplicable, 'Setting not available on this machine'));
    Result := MakeCheck(tsNotOptimal,
      Format('Plugged in: %s, on battery: %s (wanted: %s)',
        [ValueText(V.AC), ValueText(V.DC), ValueText(FOptimalValue)]));
    if (V.AC = FOptimalValue) and (V.DC = FOptimalValue) then
      Result.Status := tsOptimal;
  except
    on E: Exception do
      Result := MakeCheck(tsError, E.Message);
  end;
end;

function TPowerSettingTweak.Capture: TJSONObject;
var
  Scheme: TGUID;
  V: TPowerValue;
begin
  Scheme := ActiveSchemeGuid;
  V := ReadPowerSetting(Scheme, FSubGroup, FSetting);
  Result := TJSONObject.Create;
  Result.Add('scheme', GUIDToString(Scheme));
  Result.Add('present', V.Present);
  Result.Add('ac', Int64(V.AC));
  Result.Add('dc', Int64(V.DC));
end;

initialization
  Tweaks.Add(TPowerSettingTweak.Create('power.usb-selective-suspend',
    'Disable USB selective suspend',
    'Windows may power down idle USB ports, which can disconnect DJ controllers and audio interfaces.',
    tiHigh, trSafe, SUB_USB, USB_SELECTIVE_SUSPEND, 0));
  Tweaks.Add(TPowerSettingTweak.Create('power.sleep',
    'Never sleep',
    'Prevents the laptop from going to sleep during a set.',
    tiHigh, trSafe, SUB_SLEEP, STANDBYIDLE, 0, ' s'));
  Tweaks.Add(TPowerSettingTweak.Create('power.pcie-aspm',
    'Disable PCI Express power saving',
    'Link State Power Management adds wake-up latency to PCIe devices (audio, USB controllers, GPU).',
    tiMedium, trAdvanced, SUB_PCIEXPRESS, PCIE_ASPM, 0));
  Tweaks.Add(TPowerSettingTweak.Create('power.cpu-min-state',
    'Keep CPU at full speed',
    'Minimum processor state 100% avoids frequency ramp-up delays that cause audio glitches.',
    tiMedium, trSafe, SUB_PROCESSOR, PROCTHROTTLEMIN, 100, '%'));
  Tweaks.Add(TPowerSettingTweak.Create('power.display-off',
    'Never turn off the display',
    'Keeps the screen on while you mix.',
    tiMedium, trSafe, SUB_VIDEO, VIDEOIDLE, 0, ' s'));
  Tweaks.Add(TPowerSettingTweak.Create('power.hibernate',
    'Never hibernate',
    'Prevents automatic hibernation during a set.',
    tiLow, trSafe, SUB_SLEEP, HIBERNATEIDLE, 0, ' s'));

end.
