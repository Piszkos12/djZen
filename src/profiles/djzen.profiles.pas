unit djzen.profiles;

(* Zen profiles: a named set of enabled tweaks plus the DJ software to protect.

  File format (JSON):
    { "name": "Offline zen", "order": 1, "description": "...",
      "app": "rekordbox",
      "tweaks": { "<tweak id>": true, ... } }
  Tweaks that are missing or false are not applied.

  Built-in profiles live next to djZen.exe and are read-only; user profiles
  live in %APPDATA%\djZen\profiles\. *)

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Contnrs, fpjson;

type
  EProfile = class(Exception);

  TProfile = class
  private
    FName, FDescription, FFileName, FApp: string;
    FOrder: Integer;
    FBuiltin: Boolean;
    FTweaks: TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    function IsEnabled(const TweakId: string): Boolean;
    function ToJSON: TJSONObject;
    procedure SaveToFile(const AFileName: string);
    property Name: string read FName write FName;
    property Description: string read FDescription write FDescription;
    property FileName: string read FFileName;
    property App: string read FApp write FApp;   // DJ app id, '' = none
    property Order: Integer read FOrder write FOrder;
    property Builtin: Boolean read FBuiltin;
    { tweak id -> true/false }
    property Tweaks: TJSONObject read FTweaks;
  end;

  TProfileList = class(TFPObjectList)
  private
    function GetItem(Index: Integer): TProfile;
  public
    { Loads every *.json in Dir; invalid files and duplicate names are
      logged and skipped. }
    procedure LoadDir(const Dir: string; ABuiltin: Boolean);
    procedure SortByOrder;
    function FindByName(const AName: string): TProfile;
    property Items[Index: Integer]: TProfile read GetItem; default;
  end;

function LoadProfile(const AFileName: string; ABuiltin: Boolean): TProfile;

{ Built-in profiles folder; falls back to the source tree when running from
  bin\dev or bin\prod without build.bat having copied them. }
function FindBuiltinProfilesDir: string;

{ File name for a user profile: safe characters only, in UserProfilesDir. }
function UserProfileFileName(const AName: string): string;

{ Writes P as a user profile, overwriting a user profile of the same name.
  Refuses names used by built-in profiles. Returns the file name. }
function SaveUserProfile(P: TProfile; Existing: TProfileList): string;
procedure DeleteUserProfile(P: TProfile);

const
  UserProfileOrder = 1000;   // user profiles are listed after the built-in ones

implementation

uses
  Classes, jsonparser, djzen.core.log, djzen.core.paths;

{ TProfile }

constructor TProfile.Create;
begin
  inherited Create;
  FTweaks := TJSONObject.Create;
  FOrder := UserProfileOrder;
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

function TProfile.ToJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('name', FName);
  Result.Add('order', FOrder);
  if FDescription <> '' then
    Result.Add('description', FDescription);
  if FApp <> '' then
    Result.Add('app', FApp);
  Result.Add('tweaks', FTweaks.Clone);
end;

procedure TProfile.SaveToFile(const AFileName: string);
var
  J: TJSONObject;
  Text: string;
  Stream: TFileStream;
begin
  J := ToJSON;
  try
    Text := J.FormatJSON;
  finally
    J.Free;
  end;
  ForceDirectories(ExtractFileDir(AFileName));
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if Text <> '' then
      Stream.WriteBuffer(Text[1], Length(Text));
  finally
    Stream.Free;
  end;
  FFileName := AFileName;
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
      raise EProfile.Create('not a JSON object');
    Root := TJSONObject(Data);
    if Trim(Root.Get('name', '')) = '' then
      raise EProfile.Create('missing "name"');
    Result := TProfile.Create;
    Result.FName := Trim(Root.Get('name', ''));
    Result.FDescription := Root.Get('description', '');
    Result.FApp := Root.Get('app', '');
    Result.FOrder := Root.Get('order', UserProfileOrder);
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
  P: TProfile;
begin
  Path := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(Path + '*.json', faAnyFile and not faDirectory, SR) <> 0 then
    Exit;
  try
    repeat
      try
        P := LoadProfile(Path + SR.Name, ABuiltin);
        if FindByName(P.Name) <> nil then
        begin
          LogWarn(Format('Profile "%s" skipped: name "%s" already exists', [Path + SR.Name, P.Name]));
          P.Free;
        end
        else
          Add(P);
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
    if SameText(Items[I].Name, Trim(AName)) then
      Exit(Items[I]);
  Result := nil;
end;

function FindBuiltinProfilesDir: string;
begin
  Result := BuiltinProfilesDir;
  if not DirectoryExists(Result) then
    Result := ExpandFileName(AppDir + '..\..\profiles\');
end;

function UserProfileFileName(const AName: string): string;
var
  C: Char;
  S: string;
begin
  S := '';
  for C in LowerCase(Trim(AName)) do
    if C in ['a'..'z', '0'..'9', '_'] then
      S := S + C
    else if (S <> '') and (S[Length(S)] <> '-') then
      S := S + '-';
  while (S <> '') and (S[Length(S)] = '-') do
    SetLength(S, Length(S) - 1);
  if S = '' then
    S := 'profile';
  Result := UserProfilesDir + S + '.json';
end;

function SaveUserProfile(P: TProfile; Existing: TProfileList): string;
var
  Other: TProfile;
  N: Integer;
begin
  P.Name := Trim(P.Name);
  if P.Name = '' then
    raise EProfile.Create('The profile name cannot be empty');
  Other := nil;
  if Existing <> nil then
    Other := Existing.FindByName(P.Name);
  if (Other <> nil) and Other.Builtin then
    raise EProfile.CreateFmt('"%s" is a built-in profile; choose another name', [P.Name]);
  P.Order := UserProfileOrder;
  if (Other <> nil) and (Other.FileName <> '') then
    Result := Other.FileName          // overwrite the existing user profile
  else
  begin
    // different names can map to the same file name ("Club 1" / "club-1")
    Result := UserProfileFileName(P.Name);
    N := 2;
    while FileExists(Result) do
    begin
      Result := ChangeFileExt(UserProfileFileName(P.Name), '') + '-' + IntToStr(N) + '.json';
      Inc(N);
    end;
  end;
  P.SaveToFile(Result);
end;

procedure DeleteUserProfile(P: TProfile);
begin
  if P.Builtin then
    raise EProfile.Create('Built-in profiles cannot be deleted');
  if (P.FileName <> '') and FileExists(P.FileName) and not DeleteFile(P.FileName) then
    raise EProfile.CreateFmt('Cannot delete "%s"', [P.FileName]);
end;

end.
