unit djzen.apps;

(* DJ software descriptors: data-only JSON files, one per application.

    { "id": "rekordbox", "name": "Pioneer rekordbox",
      "processes": ["rekordbox.exe"], "priority": "high",
      "protectServices": [], "protectDevices": [],
      "needsNetwork": false, "notes": "..." }

  Descriptors can only ADD protection and request a priority up to "high".
  They never contain actions (see PLAN.md, principle 4). *)

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Contnrs, fpjson;

type
  TDJApp = class
  public
    Id, Name, Notes, FileName: string;
    Processes, ProtectServices, ProtectDevices: array of string;
    Priority: string;
    NeedsNetwork: Boolean;
    Builtin: Boolean;
  end;

  TDJAppList = class(TFPObjectList)
  private
    function GetItem(Index: Integer): TDJApp;
  public
    { Loads every *.json in Dir; invalid files are logged and skipped.
      A user descriptor with the same id replaces the built-in one. }
    procedure LoadDir(const Dir: string; ABuiltin: Boolean);
    procedure SortByName;
    function FindById(const AId: string): TDJApp;
    property Items[Index: Integer]: TDJApp read GetItem; default;
  end;

function LoadDJApp(const AFileName: string; ABuiltin: Boolean): TDJApp;

{ Adds the app's processes and services to the runtime blocklist. }
procedure ProtectDJApp(App: TDJApp);

{ Built-in apps folder; falls back to the source tree when running from
  bin\dev or bin\prod without build.bat having copied it. }
function FindBuiltinAppsDir: string;

implementation

uses
  Classes, jsonparser, djzen.core.log, djzen.core.paths, djzen.core.blocklist,
  djzen.win.process;

function StringArray(Root: TJSONObject; const Key: string): TStringArray;
var
  A: TJSONArray;
  I: Integer;
begin
  Result := nil;
  A := Root.Find(Key, jtArray) as TJSONArray;
  if A = nil then
    Exit;
  SetLength(Result, A.Count);
  for I := 0 to A.Count - 1 do
    Result[I] := A.Strings[I];
end;

function LoadDJApp(const AFileName: string; ABuiltin: Boolean): TDJApp;
var
  Stream: TFileStream;
  Data: TJSONData;
  Root: TJSONObject;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    Data := GetJSON(Stream);
  finally
    Stream.Free;
  end;
  Result := nil;
  try
    if not (Data is TJSONObject) then
      raise Exception.Create('not a JSON object');
    Root := TJSONObject(Data);
    Result := TDJApp.Create;
    Result.Id := Root.Get('id', '');
    Result.Name := Root.Get('name', '');
    Result.Notes := Root.Get('notes', '');
    Result.Priority := Root.Get('priority', 'high');
    Result.NeedsNetwork := Root.Get('needsNetwork', False);
    Result.Processes := StringArray(Root, 'processes');
    Result.ProtectServices := StringArray(Root, 'protectServices');
    Result.ProtectDevices := StringArray(Root, 'protectDevices');
    Result.FileName := AFileName;
    Result.Builtin := ABuiltin;

    if Result.Id = '' then
      raise Exception.Create('missing "id"');
    if Result.Name = '' then
      raise Exception.Create('missing "name"');
    if Length(Result.Processes) = 0 then
      raise Exception.Create('"processes" must list at least one exe name');
    PriorityClassFromText(Result.Priority);   // raises for realtime or unknown values
  except
    Result.Free;
    Data.Free;
    raise;
  end;
  Data.Free;
end;

procedure ProtectDJApp(App: TDJApp);
var
  S: string;
begin
  if App = nil then
    Exit;
  for S in App.Processes do
    ProtectProcess(S);
  for S in App.ProtectServices do
    ProtectService(S);
end;

function FindBuiltinAppsDir: string;
begin
  Result := BuiltinAppsDir;
  if not DirectoryExists(Result) then
    Result := ExpandFileName(AppDir + '..\..\apps\');
end;

{ TDJAppList }

function TDJAppList.GetItem(Index: Integer): TDJApp;
begin
  Result := TDJApp(inherited Items[Index]);
end;

procedure TDJAppList.LoadDir(const Dir: string; ABuiltin: Boolean);
var
  SR: TSearchRec;
  Path: string;
  App, Old: TDJApp;
begin
  Path := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(Path + '*.json', faAnyFile and not faDirectory, SR) <> 0 then
    Exit;
  try
    repeat
      try
        App := LoadDJApp(Path + SR.Name, ABuiltin);
        Old := FindById(App.Id);
        if Old <> nil then
          Remove(Old);
        Add(App);
      except
        on E: Exception do
          LogWarn(Format('DJ app descriptor "%s" skipped: %s', [Path + SR.Name, E.Message]));
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function CompareName(A, B: Pointer): Integer;
begin
  Result := CompareText(TDJApp(A).Name, TDJApp(B).Name);
end;

procedure TDJAppList.SortByName;
begin
  Sort(@CompareName);
end;

function TDJAppList.FindById(const AId: string): TDJApp;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if SameText(Items[I].Id, AId) then
      Exit(Items[I]);
  Result := nil;
end;

end.
