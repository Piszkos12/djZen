unit djzen.profiles;

(* Zen profiles: a named set of enabled tweaks.

  File format (JSON):
    { "name": "Offline zen", "order": 1, "description": "...",
      "tweaks": { "<tweak id>": true, ... } }
  Tweaks that are missing or false are not applied. *)

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Contnrs, fpjson;

type
  TProfile = class
  private
    FName, FDescription, FFileName: string;
    FOrder: Integer;
    FBuiltin: Boolean;
    FTweaks: TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    function IsEnabled(const TweakId: string): Boolean;
    property Name: string read FName;
    property Description: string read FDescription;
    property FileName: string read FFileName;
    property Order: Integer read FOrder;
    property Builtin: Boolean read FBuiltin;
    { tweak id -> true/false }
    property Tweaks: TJSONObject read FTweaks;
  end;

  TProfileList = class(TFPObjectList)
  private
    function GetItem(Index: Integer): TProfile;
  public
    { Loads every *.json in Dir; invalid files are logged and skipped. }
    procedure LoadDir(const Dir: string; ABuiltin: Boolean);
    procedure SortByOrder;
    function FindByName(const AName: string): TProfile;
    property Items[Index: Integer]: TProfile read GetItem; default;
  end;

function LoadProfile(const AFileName: string; ABuiltin: Boolean): TProfile;

{ Built-in profiles folder; falls back to the source tree when running from
  bin\dev or bin\prod without build.bat having copied them. }
function FindBuiltinProfilesDir: string;

implementation

uses
  Classes, jsonparser, djzen.core.log, djzen.core.paths;

{ TProfile }

constructor TProfile.Create;
begin
  inherited Create;
  FTweaks := TJSONObject.Create;
end;

destructor TProfile.Destroy;
begin
  FTweaks.Free;
  inherited Destroy;
end;

function TProfile.IsEnabled(const TweakId: string): Boolean;
var
  D: TJSONData;
begin
  D := FTweaks.Find(TweakId);
  Result := (D is TJSONBoolean) and D.AsBoolean;
end;

function LoadProfile(const AFileName: string; ABuiltin: Boolean): TProfile;
var
  Stream: TFileStream;
  Data: TJSONData;
  Root, T: TJSONObject;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    Data := GetJSON(Stream);
  finally
    Stream.Free;
  end;
  try
    if not (Data is TJSONObject) then
      raise Exception.Create('not a JSON object');
    Root := TJSONObject(Data);
    if Root.Get('name', '') = '' then
      raise Exception.Create('missing "name"');
    Result := TProfile.Create;
    Result.FName := Root.Get('name', '');
    Result.FDescription := Root.Get('description', '');
    Result.FOrder := Root.Get('order', 100);
    Result.FFileName := AFileName;
    Result.FBuiltin := ABuiltin;
    T := Root.Find('tweaks', jtObject) as TJSONObject;
    if T <> nil then
    begin
      Result.FTweaks.Free;
      Result.FTweaks := T.Clone as TJSONObject;
    end;
  finally
    Data.Free;
  end;
end;

{ TProfileList }

function TProfileList.GetItem(Index: Integer): TProfile;
begin
  Result := TProfile(inherited Items[Index]);
end;

procedure TProfileList.LoadDir(const Dir: string; ABuiltin: Boolean);
var
  SR: TSearchRec;
  Path: string;
begin
  Path := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(Path + '*.json', faAnyFile and not faDirectory, SR) <> 0 then
    Exit;
  try
    repeat
      try
        Add(LoadProfile(Path + SR.Name, ABuiltin));
      except
        on E: Exception do
          LogWarn(Format('Profile "%s" skipped: %s', [Path + SR.Name, E.Message]));
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function CompareOrder(A, B: Pointer): Integer;
begin
  Result := TProfile(A).Order - TProfile(B).Order;
  if Result = 0 then
    Result := CompareText(TProfile(A).Name, TProfile(B).Name);
end;

procedure TProfileList.SortByOrder;
begin
  Sort(@CompareOrder);
end;

function TProfileList.FindByName(const AName: string): TProfile;
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    if SameText(Items[I].Name, AName) then
      Exit(Items[I]);
  Result := nil;
end;

function FindBuiltinProfilesDir: string;
begin
  Result := BuiltinProfilesDir;
  if not DirectoryExists(Result) then
    Result := ExpandFileName(AppDir + '..\..\profiles\');
end;

end.
