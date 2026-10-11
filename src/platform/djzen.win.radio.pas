unit djzen.win.radio;

{ Wi-Fi (wlanapi.dll) and Bluetooth (bthprops.cpl) radio queries.
  Both DLLs are loaded dynamically: they may be missing on machines without
  the hardware or with the service components removed. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils;

type
  TRadioState = (rsAbsent, rsOff, rsOn, rsUnknown);

  TWifiAdapter = record
    Description: string;
    State: TRadioState;
  end;
  TWifiAdapters = array of TWifiAdapter;

{ Empty result if there is no Wi-Fi adapter or the WLAN service is not running. }
function QueryWifiAdapters(out ServiceAvailable: Boolean): TWifiAdapters;

{ rsOn if a Bluetooth radio is present and enabled, rsAbsent otherwise. }
function QueryBluetoothRadio: TRadioState;

implementation

{ --- WLAN API ------------------------------------------------------------ }

const
  wlan_intf_opcode_radio_state = 4;
  dot11_radio_state_on  = 1;
  dot11_radio_state_off = 2;

type
  WLAN_INTERFACE_INFO = record
    InterfaceGuid: TGUID;
    strInterfaceDescription: array[0..255] of WideChar;
    isState: DWORD;
  end;
  PWLAN_INTERFACE_INFO_LIST = ^WLAN_INTERFACE_INFO_LIST;
  WLAN_INTERFACE_INFO_LIST = record
    dwNumberOfItems: DWORD;
    dwIndex: DWORD;
    InterfaceInfo: array[0..0] of WLAN_INTERFACE_INFO;
  end;
  WLAN_PHY_RADIO_STATE = record
    dwPhyIndex: DWORD;
    dot11SoftwareRadioState: DWORD;
    dot11HardwareRadioState: DWORD;
  end;
  PWLAN_RADIO_STATE = ^WLAN_RADIO_STATE;
  WLAN_RADIO_STATE = record
    dwNumberOfPhys: DWORD;
    PhyRadioState: array[0..63] of WLAN_PHY_RADIO_STATE;
  end;

  TWlanOpenHandle = function(dwClientVersion: DWORD; pReserved: Pointer;
    pdwNegotiatedVersion: PDWORD; phClientHandle: PHANDLE): DWORD; stdcall;
  TWlanCloseHandle = function(hClientHandle: THandle; pReserved: Pointer): DWORD; stdcall;
  TWlanEnumInterfaces = function(hClientHandle: THandle; pReserved: Pointer;
    ppInterfaceList: Pointer): DWORD; stdcall;
  TWlanQueryInterface = function(hClientHandle: THandle; pInterfaceGuid: PGUID; OpCode: DWORD;
    pReserved: Pointer; pdwDataSize: PDWORD; ppData: PPointer; pWlanOpcodeValueType: PDWORD): DWORD; stdcall;
  TWlanFreeMemory = procedure(pMemory: Pointer); stdcall;

function QueryWifiAdapters(out ServiceAvailable: Boolean): TWifiAdapters;
var
  Lib: HMODULE;
  WlanOpenHandle: TWlanOpenHandle;
  WlanCloseHandle: TWlanCloseHandle;
  WlanEnumInterfaces: TWlanEnumInterfaces;
  WlanQueryInterface: TWlanQueryInterface;
  WlanFreeMemory: TWlanFreeMemory;
  Client: THandle;
  Version, Size: DWORD;
  List: PWLAN_INTERFACE_INFO_LIST;
  Radio: PWLAN_RADIO_STATE;
  Info: ^WLAN_INTERFACE_INFO;
  I, P: Integer;
  AnyOn, AnyOff: Boolean;
begin
  Result := nil;
  ServiceAvailable := False;
  Lib := LoadLibrary('wlanapi.dll');
  if Lib = 0 then
    Exit;
  try
    Pointer(WlanOpenHandle) := GetProcAddress(Lib, 'WlanOpenHandle');
    Pointer(WlanCloseHandle) := GetProcAddress(Lib, 'WlanCloseHandle');
    Pointer(WlanEnumInterfaces) := GetProcAddress(Lib, 'WlanEnumInterfaces');
    Pointer(WlanQueryInterface) := GetProcAddress(Lib, 'WlanQueryInterface');
    Pointer(WlanFreeMemory) := GetProcAddress(Lib, 'WlanFreeMemory');
    if not Assigned(WlanOpenHandle) or not Assigned(WlanCloseHandle) or
       not Assigned(WlanEnumInterfaces) or not Assigned(WlanQueryInterface) or
       not Assigned(WlanFreeMemory) then
      Exit;

    if WlanOpenHandle(2, nil, @Version, @Client) <> ERROR_SUCCESS then
      Exit;   // WLAN AutoConfig service not running
    ServiceAvailable := True;
    try
      List := nil;
      if WlanEnumInterfaces(Client, nil, @List) <> ERROR_SUCCESS then
        Exit;
      try
        SetLength(Result, List^.dwNumberOfItems);
        for I := 0 to Integer(List^.dwNumberOfItems) - 1 do
        begin
          {$PUSH}{$R-}
          Info := @List^.InterfaceInfo[I];
          {$POP}
          Result[I].Description := UTF8Encode(UnicodeString(PWideChar(@Info^.strInterfaceDescription[0])));
          Result[I].State := rsUnknown;
          Radio := nil;
          if WlanQueryInterface(Client, @Info^.InterfaceGuid, wlan_intf_opcode_radio_state,
            nil, @Size, @Radio, nil) = ERROR_SUCCESS then
          try
            AnyOn := False;
            AnyOff := False;
            for P := 0 to Integer(Radio^.dwNumberOfPhys) - 1 do
              if (Radio^.PhyRadioState[P].dot11SoftwareRadioState = dot11_radio_state_on) and
                 (Radio^.PhyRadioState[P].dot11HardwareRadioState = dot11_radio_state_on) then
                AnyOn := True
              else
                AnyOff := True;
            if AnyOn then
              Result[I].State := rsOn
            else if AnyOff then
              Result[I].State := rsOff;
          finally
            WlanFreeMemory(Radio);
          end;
        end;
      finally
        WlanFreeMemory(List);
      end;
    finally
      WlanCloseHandle(Client, nil);
    end;
  finally
    FreeLibrary(Lib);
  end;
end;

{ --- Bluetooth ------------------------------------------------------------ }

type
  BLUETOOTH_FIND_RADIO_PARAMS = record
    dwSize: DWORD;
  end;
  TBluetoothFindFirstRadio = function(const pbtfrp: BLUETOOTH_FIND_RADIO_PARAMS;
    phRadio: PHANDLE): THandle; stdcall;
  TBluetoothFindRadioClose = function(hFind: THandle): BOOL; stdcall;

function QueryBluetoothRadio: TRadioState;
var
  Lib: HMODULE;
  FindFirst: TBluetoothFindFirstRadio;
  FindClose: TBluetoothFindRadioClose;
  Params: BLUETOOTH_FIND_RADIO_PARAMS;
  Find, Radio: THandle;
begin
  Result := rsAbsent;
  Lib := LoadLibrary('bthprops.cpl');
  if Lib = 0 then
    Exit;
  try
    Pointer(FindFirst) := GetProcAddress(Lib, 'BluetoothFindFirstRadio');
    Pointer(FindClose) := GetProcAddress(Lib, 'BluetoothFindRadioClose');
    if not Assigned(FindFirst) or not Assigned(FindClose) then
      Exit(rsUnknown);
    Params.dwSize := SizeOf(Params);
    Radio := 0;
    Find := FindFirst(Params, @Radio);
    if Find = 0 then
      Exit;   // no enabled radio
    CloseHandle(Radio);
    FindClose(Find);
    Result := rsOn;
  finally
    FreeLibrary(Lib);
  end;
end;

end.
