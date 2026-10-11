unit djzen.win.radio;

{ Wi-Fi (wlanapi.dll) and Windows radio management (WinRT) access.
  wlanapi.dll is loaded dynamically: it may be missing on machines without
  the hardware or with the service components removed. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils;

type
  TRadioState = (rsAbsent, rsOff, rsOn, rsUnknown);

  TWifiAdapter = record
    Guid: TGUID;
    Description: string;
    State: TRadioState;
  end;
  TWifiAdapters = array of TWifiAdapter;

  ERadio = class(Exception);

  { Radios as seen by Windows radio management (the switches in Settings). }
  TRadioKind = (rkOther, rkWifi, rkMobileBroadband, rkBluetooth, rkFM);
  TWinRadio = record
    Name: string;
    Kind: TRadioKind;
    State: TRadioState;   // rsOn, rsOff or rsUnknown; "disabled" by the system is rsOff
  end;
  TWinRadios = array of TWinRadio;

{ Empty result if there is no Wi-Fi adapter or the WLAN service is not running. }
function QueryWifiAdapters(out ServiceAvailable: Boolean): TWifiAdapters;

{ Switches the software radio of every PHY of the adapter. }
procedure SetWifiRadio(const AdapterGuid: TGUID; On: Boolean);

{ All radios known to Windows radio management. }
function QueryWinRadios: TWinRadios;
{ Switches every radio of the kind whose name matches ('' = all of that kind). }
procedure SetWinRadioState(Kind: TRadioKind; const Name: string; On: Boolean);


implementation

uses
  Classes, djzen.win.winrt;

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
  TWlanSetInterface = function(hClientHandle: THandle; pInterfaceGuid: PGUID; OpCode: DWORD;
    dwDataSize: DWORD; pData: Pointer; pReserved: Pointer): DWORD; stdcall;
  TWlanFreeMemory = procedure(pMemory: Pointer); stdcall;

  { An open WLAN client session. }
  TWlan = record
    Lib: HMODULE;
    Client: THandle;
    OpenHandle: TWlanOpenHandle;
    CloseHandle: TWlanCloseHandle;
    EnumInterfaces: TWlanEnumInterfaces;
    QueryInterface: TWlanQueryInterface;
    SetInterface: TWlanSetInterface;
    FreeMemory: TWlanFreeMemory;
  end;

{ False if the API or the WLAN service is not available. }
function WlanOpen(out W: TWlan): Boolean;
var
  Version: DWORD;
begin
  Result := False;
  W := Default(TWlan);
  W.Lib := LoadLibrary('wlanapi.dll');
  if W.Lib = 0 then
    Exit;
  Pointer(W.OpenHandle) := GetProcAddress(W.Lib, 'WlanOpenHandle');
  Pointer(W.CloseHandle) := GetProcAddress(W.Lib, 'WlanCloseHandle');
  Pointer(W.EnumInterfaces) := GetProcAddress(W.Lib, 'WlanEnumInterfaces');
  Pointer(W.QueryInterface) := GetProcAddress(W.Lib, 'WlanQueryInterface');
  Pointer(W.SetInterface) := GetProcAddress(W.Lib, 'WlanSetInterface');
  Pointer(W.FreeMemory) := GetProcAddress(W.Lib, 'WlanFreeMemory');
  if Assigned(W.OpenHandle) and Assigned(W.CloseHandle) and Assigned(W.EnumInterfaces) and
     Assigned(W.QueryInterface) and Assigned(W.SetInterface) and Assigned(W.FreeMemory) and
     (W.OpenHandle(2, nil, @Version, @W.Client) = ERROR_SUCCESS) then
    Exit(True);
  FreeLibrary(W.Lib);
  W.Lib := 0;
end;

procedure WlanClose(var W: TWlan);
begin
  if W.Lib = 0 then
    Exit;
  W.CloseHandle(W.Client, nil);
  FreeLibrary(W.Lib);
  W.Lib := 0;
end;

{ Caller frees the result with W.FreeMemory. nil on failure. }
function QueryRadio(var W: TWlan; const Guid: TGUID): PWLAN_RADIO_STATE;
var
  G: TGUID;
  Size: DWORD;
begin
  G := Guid;
  Result := nil;
  if W.QueryInterface(W.Client, @G, wlan_intf_opcode_radio_state, nil, @Size,
    @Result, nil) <> ERROR_SUCCESS then
    Result := nil;
end;

function QueryWifiAdapters(out ServiceAvailable: Boolean): TWifiAdapters;
var
  W: TWlan;
  List: PWLAN_INTERFACE_INFO_LIST;
  Radio: PWLAN_RADIO_STATE;
  Info: ^WLAN_INTERFACE_INFO;
  I, P: Integer;
  AnyOn: Boolean;
begin
  Result := nil;
  ServiceAvailable := WlanOpen(W);
  if not ServiceAvailable then
    Exit;
  try
    List := nil;
    if W.EnumInterfaces(W.Client, nil, @List) <> ERROR_SUCCESS then
      Exit;
    try
      SetLength(Result, List^.dwNumberOfItems);
      for I := 0 to Integer(List^.dwNumberOfItems) - 1 do
      begin
        {$PUSH}{$R-}
        Info := @List^.InterfaceInfo[I];
        {$POP}
        Result[I].Guid := Info^.InterfaceGuid;
        Result[I].Description := UTF8Encode(UnicodeString(PWideChar(@Info^.strInterfaceDescription[0])));
        Result[I].State := rsUnknown;
        Radio := QueryRadio(W, Info^.InterfaceGuid);
        if Radio <> nil then
        try
          AnyOn := False;
          for P := 0 to Integer(Radio^.dwNumberOfPhys) - 1 do
            if (Radio^.PhyRadioState[P].dot11SoftwareRadioState = dot11_radio_state_on) and
               (Radio^.PhyRadioState[P].dot11HardwareRadioState = dot11_radio_state_on) then
              AnyOn := True;
          if AnyOn then
            Result[I].State := rsOn
          else if Radio^.dwNumberOfPhys > 0 then
            Result[I].State := rsOff;
        finally
          W.FreeMemory(Radio);
        end;
      end;
    finally
      W.FreeMemory(List);
    end;
  finally
    WlanClose(W);
  end;
end;

procedure SetWifiRadio(const AdapterGuid: TGUID; On: Boolean);
var
  W: TWlan;
  G: TGUID;
  Radio: PWLAN_RADIO_STATE;
  Phy: WLAN_PHY_RADIO_STATE;
  P: Integer;
  Err: DWORD;
begin
  if not WlanOpen(W) then
    raise ERadio.Create('WLAN service is not available');
  try
    Radio := QueryRadio(W, AdapterGuid);
    if Radio = nil then
      raise ERadio.Create('Cannot read Wi-Fi radio state');
    try
      G := AdapterGuid;
      for P := 0 to Integer(Radio^.dwNumberOfPhys) - 1 do
      begin
        Phy.dwPhyIndex := Radio^.PhyRadioState[P].dwPhyIndex;
        if On then
          Phy.dot11SoftwareRadioState := dot11_radio_state_on
        else
          Phy.dot11SoftwareRadioState := dot11_radio_state_off;
        Phy.dot11HardwareRadioState := Phy.dot11SoftwareRadioState;
        Err := W.SetInterface(W.Client, @G, wlan_intf_opcode_radio_state, SizeOf(Phy), @Phy, nil);
        if Err <> ERROR_SUCCESS then
          raise ERadio.CreateFmt('Switching Wi-Fi radio failed: %s', [SysErrorMessage(Err)]);
      end;
    finally
      W.FreeMemory(Radio);
    end;
  finally
    WlanClose(W);
  end;
end;

{ --- Windows radio management (Windows.Devices.Radios, WinRT) ------------ }

const
  IID_IRadioStatics: TGUID = '{5FB6A12E-67CB-46AE-AAE9-65919F86EFF4}';

  RadioState_On       = 1;
  RadioState_Off      = 2;
  RadioState_Disabled = 3;
  RadioAccess_Allowed = 1;

type
  IRadio = interface(IInspectable)
    ['{252118DF-B33E-416A-875F-1CF38AE2D83E}']
    function SetStateAsync(Value: Integer; out Op: IAsyncOperationRaw): HRESULT; stdcall;
    function add_StateChanged(Handler: Pointer; out Token: Int64): HRESULT; stdcall;
    function remove_StateChanged(Token: Int64): HRESULT; stdcall;
    function get_State(out Value: Integer): HRESULT; stdcall;
    function get_Name(out Value: HSTRING): HRESULT; stdcall;
    function get_Kind(out Value: Integer): HRESULT; stdcall;
  end;

  IRadioStatics = interface(IInspectable)
    ['{5FB6A12E-67CB-46AE-AAE9-65919F86EFF4}']
    function GetRadiosAsync(out Op: IAsyncOperationRaw): HRESULT; stdcall;
    function GetDeviceSelector(out Selector: HSTRING): HRESULT; stdcall;
    function FromIdAsync(Id: HSTRING; out Op: IAsyncOperationRaw): HRESULT; stdcall;
    function RequestAccessAsync(out Op: IAsyncOperationRaw): HRESULT; stdcall;
  end;

  TRadioAction = (raQuery, raSet);

  { WinRT calls run on their own MTA thread: the GUI thread is an STA, and
    blocking an STA while polling async operations is asking for trouble. }
  TRadioWorker = class(TThread)
  protected
    procedure Execute; override;
  public
    Action: TRadioAction;
    Kind: TRadioKind;
    Name: string;
    TurnOn: Boolean;
    Radios: TWinRadios;
    Error: string;
  end;

function RadioStatics: IRadioStatics;
begin
  Pointer(Result) := GetActivationFactory('Windows.Devices.Radios.Radio', IID_IRadioStatics);
end;

function MapState(S: Integer): TRadioState;
begin
  case S of
    RadioState_On:                      Result := rsOn;
    RadioState_Off, RadioState_Disabled: Result := rsOff;
  else
    Result := rsUnknown;
  end;
end;

function MapKind(K: Integer): TRadioKind;
begin
  if (K >= Ord(Low(TRadioKind))) and (K <= Ord(High(TRadioKind))) then
    Result := TRadioKind(K)
  else
    Result := rkOther;
end;

{ Caller owns the returned vector. }
function GetRadioVector(const Statics: IRadioStatics): IVectorViewRaw;
var
  Op: IAsyncOperationRaw;
  P: Pointer;
begin
  Check(Statics.GetRadiosAsync(Op), 'Radio.GetRadiosAsync');
  WaitAsync(Op);
  P := nil;
  Check(Op.GetResults(P), 'GetRadiosAsync results');
  Pointer(Result) := P;   // takes over the reference returned by GetResults
end;

function GetRadio(const Vec: IVectorViewRaw; Index: Cardinal): IRadio;
var
  P: Pointer;
begin
  P := nil;
  Check(Vec.GetAt(Index, P), 'IVectorView.GetAt');
  Pointer(Result) := P;
end;

function RadioName(const R: IRadio): string;
var
  H: HSTRING;
begin
  H := nil;
  Check(R.get_Name(H), 'Radio.Name');
  try
    Result := HStringToString(H);
  finally
    FreeHString(H);
  end;
end;

procedure DoQuery(W: TRadioWorker);
var
  Vec: IVectorViewRaw;
  R: IRadio;
  Count, I: Cardinal;
  V: Integer;
begin
  Vec := GetRadioVector(RadioStatics);
  Check(Vec.get_Size(Count), 'IVectorView.Size');
  SetLength(W.Radios, Count);
  for I := 0 to Count - 1 do
  begin
    R := GetRadio(Vec, I);
    W.Radios[I].Name := RadioName(R);
    Check(R.get_Kind(V), 'Radio.Kind');
    W.Radios[I].Kind := MapKind(V);
    Check(R.get_State(V), 'Radio.State');
    W.Radios[I].State := MapState(V);
  end;
end;

procedure DoSet(W: TRadioWorker);
var
  Statics: IRadioStatics;
  Vec: IVectorViewRaw;
  R: IRadio;
  Op: IAsyncOperationRaw;
  Count, I: Cardinal;
  V, Access: Integer;
begin
  Statics := RadioStatics;
  Check(Statics.RequestAccessAsync(Op), 'Radio.RequestAccessAsync');
  WaitAsync(Op);
  Access := 0;
  Check(Op.GetResults(Access), 'RequestAccessAsync results');
  if Access <> RadioAccess_Allowed then
    raise ERadio.CreateFmt('Windows denied access to the radios (status %d)', [Access]);

  Vec := GetRadioVector(Statics);
  Check(Vec.get_Size(Count), 'IVectorView.Size');
  for I := 0 to Count - 1 do
  begin
    R := GetRadio(Vec, I);
    Check(R.get_Kind(V), 'Radio.Kind');
    if MapKind(V) <> W.Kind then
      Continue;
    if (W.Name <> '') and (RadioName(R) <> W.Name) then
      Continue;
    Check(R.get_State(V), 'Radio.State');
    if V = RadioState_Disabled then
      Continue;   // switched off by hardware or policy; not ours to change
    if W.TurnOn then
      V := RadioState_On
    else
      V := RadioState_Off;
    Op := nil;
    Check(R.SetStateAsync(V, Op), 'Radio.SetStateAsync');
    WaitAsync(Op);
    Access := 0;
    Check(Op.GetResults(Access), 'SetStateAsync results');
    if Access <> RadioAccess_Allowed then
      raise ERadio.CreateFmt('Switching radio "%s" was denied (status %d)', [RadioName(R), Access]);
  end;
end;

procedure TRadioWorker.Execute;
var
  Hr: HRESULT;
begin
  Hr := RoInitialize(RO_INIT_MULTITHREADED);
  try
    try
      case Action of
        raQuery: DoQuery(Self);
        raSet:   DoSet(Self);
      end;
    except
      on E: Exception do
        Error := E.Message;
    end;
  finally
    if Succeeded(Hr) then
      RoUninitialize;
  end;
end;

function RunWorker(Action: TRadioAction; Kind: TRadioKind; const Name: string;
  TurnOn: Boolean): TWinRadios;
var
  W: TRadioWorker;
begin
  W := TRadioWorker.Create(True);
  try
    W.Action := Action;
    W.Kind := Kind;
    W.Name := Name;
    W.TurnOn := TurnOn;
    W.Start;
    W.WaitFor;
    if W.Error <> '' then
      raise ERadio.Create(W.Error);
    Result := W.Radios;
  finally
    W.Free;
  end;
end;

function QueryWinRadios: TWinRadios;
begin
  Result := RunWorker(raQuery, rkOther, '', False);
end;

procedure SetWinRadioState(Kind: TRadioKind; const Name: string; On: Boolean);
begin
  RunWorker(raSet, Kind, Name, On);
end;

end.
