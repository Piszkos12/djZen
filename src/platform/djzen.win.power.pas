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

uses
  djzen.win.security;

{ powrprof.dll is not a KnownDLL: a static import would be searched in the
  exe's folder first (DLL planting, e.g. in Downloads). It is loaded from
  System32 only, on first use. }
type
  TPowerGetActiveScheme = function(UserRootPowerKey: HKEY; ActivePolicyGuid: Pointer): DWORD; stdcall;
  TPowerReadValueIndex = function(RootPowerKey: HKEY; SchemeGuid, SubGroupOfPowerSettingsGuid,
    PowerSettingGuid: PGUID; ValueIndex: LPDWORD): DWORD; stdcall;
  TPowerWriteValueIndex = function(RootPowerKey: HKEY; SchemeGuid, SubGroupOfPowerSettingsGuid,
    PowerSettingGuid: PGUID; ValueIndex: DWORD): DWORD; stdcall;
  TPowerSetActiveScheme = function(UserRootPowerKey: HKEY; SchemeGuid: PGUID): DWORD; stdcall;

var
  PowrProf: HMODULE;
  PowerGetActiveScheme: TPowerGetActiveScheme;
  PowerReadACValueIndex, PowerReadDCValueIndex: TPowerReadValueIndex;
  PowerWriteACValueIndex, PowerWriteDCValueIndex: TPowerWriteValueIndex;
  PowerSetActiveScheme: TPowerSetActiveScheme;

{ LocalFree taking a pointer: the memory comes back from powrprof as a pointer. }
function LocalFreePtr(Mem: Pointer): Pointer; stdcall; external 'kernel32.dll' name 'LocalFree';

procedure LoadPowrProf;
begin
  if PowrProf <> 0 then
    Exit;
  PowrProf := LoadSystemLibrary('powrprof.dll');
  if PowrProf = 0 then
    raise EPower.CreateFmt('Cannot load powrprof.dll: %s', [SysErrorMessage(GetLastError)]);
  Pointer(PowerGetActiveScheme) := GetProcAddress(PowrProf, 'PowerGetActiveScheme');
  Pointer(PowerReadACValueIndex) := GetProcAddress(PowrProf, 'PowerReadACValueIndex');
  Pointer(PowerReadDCValueIndex) := GetProcAddress(PowrProf, 'PowerReadDCValueIndex');
  Pointer(PowerWriteACValueIndex) := GetProcAddress(PowrProf, 'PowerWriteACValueIndex');
  Pointer(PowerWriteDCValueIndex) := GetProcAddress(PowrProf, 'PowerWriteDCValueIndex');
  Pointer(PowerSetActiveScheme) := GetProcAddress(PowrProf, 'PowerSetActiveScheme');
  if not Assigned(PowerGetActiveScheme) or not Assigned(PowerReadACValueIndex) or
     not Assigned(PowerReadDCValueIndex) or not Assigned(PowerWriteACValueIndex) or
     not Assigned(PowerWriteDCValueIndex) or not Assigned(PowerSetActiveScheme) then
  begin
    FreeLibrary(PowrProf);
    PowrProf := 0;
    raise EPower.Create('powrprof.dll lacks a required function');
  end;
end;

procedure WritePowerSetting(const Scheme, SubGroup, Setting: TGUID; AC, DC: DWORD);
var
  S, G, T: TGUID;
  Err: DWORD;
begin
  LoadPowrProf;
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
  LoadPowrProf;
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
  LoadPowrProf;
  P := nil;
  Err := PowerGetActiveScheme(0, @P);
  if Err <> ERROR_SUCCESS then
    raise EPower.CreateFmt('PowerGetActiveScheme failed: %s', [SysErrorMessage(Err)]);
  Result := P^;
  LocalFreePtr(P);
end;

function ReadPowerSetting(const Scheme, SubGroup, Setting: TGUID): TPowerValue;
var
  S, G, T: TGUID;
  Err: DWORD;
begin
  LoadPowrProf;
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
