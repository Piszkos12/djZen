unit djzen.win.power;

{ Power scheme access through powrprof.dll. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils;

const
  // Subgroups
  SUB_USB:          TGUID = '{2A737441-1930-4402-8D77-B2BEBBA308A3}';
  SUB_PCIEXPRESS:   TGUID = '{501A4D13-42AF-4429-9FD1-A8218C268E20}';
  SUB_PROCESSOR:    TGUID = '{54533251-82BE-4824-96C1-47B60B740D00}';
  SUB_SLEEP:        TGUID = '{238C9FA8-0AAD-41ED-83F4-97BE242C8F20}';
  SUB_VIDEO:        TGUID = '{7516B95F-F776-4464-8C53-06167F40CC99}';
  // Settings
  USB_SELECTIVE_SUSPEND: TGUID = '{48E6B7A6-50F5-4782-A5D4-53BB8F07E226}';  // 0 = disabled
  PCIE_ASPM:             TGUID = '{EE12F906-D277-404B-B6DA-E5FA1A576DF5}';  // 0 = off
  PROCTHROTTLEMIN:       TGUID = '{893DEE8E-2BEF-41E0-89C6-B55D0929964C}';  // percent
  STANDBYIDLE:           TGUID = '{29F6C1DB-86DA-48C5-9FDB-F2B67B1F44DA}';  // seconds, 0 = never
  HIBERNATEIDLE:         TGUID = '{9D7815A6-7EE4-497E-8888-515A05F02364}';  // seconds, 0 = never
  VIDEOIDLE:             TGUID = '{3C0BC021-C8A8-4E07-A973-6B14CBCB2B7E}';  // seconds, 0 = never

type
  EPower = class(Exception);

  TPowerValue = record
    Present: Boolean;   // False if the setting does not exist on this machine
    AC, DC: DWORD;
  end;

function ActiveSchemeGuid: TGUID;
procedure WritePowerSetting(const Scheme, SubGroup, Setting: TGUID; AC, DC: DWORD);
{ Re-activates the scheme so changed values take effect immediately. }
procedure ActivateScheme(const Scheme: TGUID);
function ReadPowerSetting(const Scheme, SubGroup, Setting: TGUID): TPowerValue;

implementation

const
  powrprof = 'powrprof.dll';

function PowerGetActiveScheme(UserRootPowerKey: HKEY; ActivePolicyGuid: Pointer): DWORD;
  stdcall; external powrprof;
function PowerReadACValueIndex(RootPowerKey: HKEY; SchemeGuid, SubGroupOfPowerSettingsGuid,
  PowerSettingGuid: PGUID; AcValueIndex: LPDWORD): DWORD; stdcall; external powrprof;
function PowerReadDCValueIndex(RootPowerKey: HKEY; SchemeGuid, SubGroupOfPowerSettingsGuid,
  PowerSettingGuid: PGUID; DcValueIndex: LPDWORD): DWORD; stdcall; external powrprof;
function PowerWriteACValueIndex(RootPowerKey: HKEY; SchemeGuid, SubGroupOfPowerSettingsGuid,
  PowerSettingGuid: PGUID; AcValueIndex: DWORD): DWORD; stdcall; external powrprof;
function PowerWriteDCValueIndex(RootPowerKey: HKEY; SchemeGuid, SubGroupOfPowerSettingsGuid,
  PowerSettingGuid: PGUID; DcValueIndex: DWORD): DWORD; stdcall; external powrprof;
function PowerSetActiveScheme(UserRootPowerKey: HKEY; SchemeGuid: PGUID): DWORD;
  stdcall; external powrprof;

procedure WritePowerSetting(const Scheme, SubGroup, Setting: TGUID; AC, DC: DWORD);
var
  S, G, T: TGUID;
  Err: DWORD;
begin
  S := Scheme;
  G := SubGroup;
  T := Setting;
  Err := PowerWriteACValueIndex(0, @S, @G, @T, AC);
  if Err <> ERROR_SUCCESS then
    raise EPower.CreateFmt('PowerWriteACValueIndex failed: %s', [SysErrorMessage(Err)]);
  Err := PowerWriteDCValueIndex(0, @S, @G, @T, DC);
  if Err <> ERROR_SUCCESS then
    raise EPower.CreateFmt('PowerWriteDCValueIndex failed: %s', [SysErrorMessage(Err)]);
end;

procedure ActivateScheme(const Scheme: TGUID);
var
  S: TGUID;
  Err: DWORD;
begin
  S := Scheme;
  Err := PowerSetActiveScheme(0, @S);
  if Err <> ERROR_SUCCESS then
    raise EPower.CreateFmt('PowerSetActiveScheme failed: %s', [SysErrorMessage(Err)]);
end;

function ActiveSchemeGuid: TGUID;
var
  P: PGUID;
  Err: DWORD;
begin
  P := nil;
  Err := PowerGetActiveScheme(0, @P);
  if Err <> ERROR_SUCCESS then
    raise EPower.CreateFmt('PowerGetActiveScheme failed: %s', [SysErrorMessage(Err)]);
  Result := P^;
  LocalFree(HLOCAL(P));
end;

function ReadPowerSetting(const Scheme, SubGroup, Setting: TGUID): TPowerValue;
var
  S, G, T: TGUID;
  Err: DWORD;
begin
  S := Scheme;
  G := SubGroup;
  T := Setting;
  Result := Default(TPowerValue);
  Err := PowerReadACValueIndex(0, @S, @G, @T, @Result.AC);
  if Err = ERROR_FILE_NOT_FOUND then
    Exit;
  if Err <> ERROR_SUCCESS then
    raise EPower.CreateFmt('PowerReadACValueIndex failed: %s', [SysErrorMessage(Err)]);
  Err := PowerReadDCValueIndex(0, @S, @G, @T, @Result.DC);
  if Err <> ERROR_SUCCESS then
    raise EPower.CreateFmt('PowerReadDCValueIndex failed: %s', [SysErrorMessage(Err)]);
  Result.Present := True;
end;

end.
