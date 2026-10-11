unit djzen.win.winrt;

{ Minimal Windows Runtime plumbing for Free Pascal: HSTRING, activation
  factories and waiting for IAsyncOperation results.

  Parameterized interfaces (IAsyncOperation<T>, IVectorView<T>) have
  generated IIDs; we never QueryInterface for them, we only call them
  through their fixed vtable layout, so their IIDs here are placeholders. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils;

type
  HSTRING = Pointer;

  EWinRT = class(Exception);

  IInspectable = interface(IUnknown)
    ['{AF86E2E0-B12D-4C6A-9C5A-D7AA65101E90}']
    function GetIids(out IidCount: Cardinal; out Iids: PGUID): HRESULT; stdcall;
    function GetRuntimeClassName(out ClassName: HSTRING): HRESULT; stdcall;
    function GetTrustLevel(out TrustLevel: Integer): HRESULT; stdcall;
  end;

  IAsyncInfo = interface(IInspectable)
    ['{00000036-0000-0000-C000-000000000046}']
    function get_Id(out Id: Cardinal): HRESULT; stdcall;
    function get_Status(out Status: Integer): HRESULT; stdcall;
    function get_ErrorCode(out ErrorCode: HRESULT): HRESULT; stdcall;
    function Cancel: HRESULT; stdcall;
    function Close: HRESULT; stdcall;
  end;

  { Vtable shape of every IAsyncOperation<T>. GetResults writes a T:
    an interface pointer or a 32-bit enum. }
  IAsyncOperationRaw = interface(IInspectable)
    ['{D3B7A1E0-0000-4000-8000-000000000001}']
    function put_Completed(Handler: Pointer): HRESULT; stdcall;
    function get_Completed(out Handler: Pointer): HRESULT; stdcall;
    function GetResults(out Results): HRESULT; stdcall;
  end;

  { Vtable shape of every IVectorView<T> with an interface T. }
  IVectorViewRaw = interface(IInspectable)
    ['{D3B7A1E0-0000-4000-8000-000000000002}']
    function GetAt(Index: Cardinal; out Item: Pointer): HRESULT; stdcall;
    function get_Size(out Size: Cardinal): HRESULT; stdcall;
  end;

const
  RO_INIT_MULTITHREADED = 1;

function RoInitialize(InitType: Integer): HRESULT; stdcall; external 'combase.dll';
procedure RoUninitialize; stdcall; external 'combase.dll';

procedure Check(Hr: HRESULT; const What: string);
function GetActivationFactory(const ClassName: UnicodeString; const Iid: TGUID): Pointer;
function HStringToString(S: HSTRING): string;
procedure FreeHString(S: HSTRING);

{ Polls the operation until it completes; raises on error, cancel or timeout. }
procedure WaitAsync(const Op: IAsyncOperationRaw; TimeoutMs: DWORD = 10000);

implementation

function RoGetActivationFactory(ActivatableClassId: HSTRING; const Iid: TGUID;
  out Factory: Pointer): HRESULT; stdcall; external 'combase.dll';
function WindowsCreateString(SourceString: PWideChar; Length: Cardinal;
  out Str: HSTRING): HRESULT; stdcall; external 'combase.dll';
function WindowsDeleteString(Str: HSTRING): HRESULT; stdcall; external 'combase.dll';
function WindowsGetStringRawBuffer(Str: HSTRING; Length: PCardinal): PWideChar;
  stdcall; external 'combase.dll';

const
  AsyncStarted   = 0;
  AsyncCompleted = 1;
  AsyncCanceled  = 2;

procedure Check(Hr: HRESULT; const What: string);
begin
  if Failed(Hr) then
    raise EWinRT.CreateFmt('%s failed: 0x%.8x %s', [What, Hr, SysErrorMessage(Hr)]);
end;

function GetActivationFactory(const ClassName: UnicodeString; const Iid: TGUID): Pointer;
var
  H: HSTRING;
begin
  Check(WindowsCreateString(PWideChar(ClassName), Length(ClassName), H), 'WindowsCreateString');
  try
    Result := nil;
    Check(RoGetActivationFactory(H, Iid, Result), 'RoGetActivationFactory(' + string(ClassName) + ')');
  finally
    WindowsDeleteString(H);
  end;
end;

function HStringToString(S: HSTRING): string;
var
  Len: Cardinal;
  P: PWideChar;
  U: UnicodeString;
begin
  Result := '';
  if S = nil then
    Exit;
  P := WindowsGetStringRawBuffer(S, @Len);
  SetString(U, P, Len);
  Result := UTF8Encode(U);
end;

procedure FreeHString(S: HSTRING);
begin
  if S <> nil then
    WindowsDeleteString(S);
end;

procedure WaitAsync(const Op: IAsyncOperationRaw; TimeoutMs: DWORD);
var
  Info: IAsyncInfo;
  Status: Integer;
  Err: HRESULT;
  Start: QWord;
begin
  Check(Op.QueryInterface(IAsyncInfo, Info), 'QueryInterface(IAsyncInfo)');
  Start := GetTickCount64;
  repeat
    Check(Info.get_Status(Status), 'IAsyncInfo.Status');
    if Status <> AsyncStarted then
      Break;
    if GetTickCount64 - Start > TimeoutMs then
    begin
      Info.Cancel;
      raise EWinRT.Create('Asynchronous Windows operation timed out');
    end;
    Sleep(10);
  until False;
  if Status = AsyncCompleted then
    Exit;
  if Status = AsyncCanceled then
    raise EWinRT.Create('Asynchronous Windows operation was canceled');
  Info.get_ErrorCode(Err);
  Check(Err, 'Asynchronous Windows operation');
  raise EWinRT.Create('Asynchronous Windows operation failed');
end;

end.
