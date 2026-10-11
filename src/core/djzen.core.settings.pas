unit djzen.core.settings;

(* Per-user UI state remembered between runs (%APPDATA%\djZen\settings.json):

    { "profile": "Offline zen", "app": "rekordbox",
      "modified": true, "tweaks": { "radio.wifi": false, ... } }

  "tweaks" holds the checkbox state only when it differs from the profile
  ("modified"), so unsaved edits survive a restart. *)

{$mode objfpc}{$H+}

interface

uses
  fpjson;

type
  TUiSettings = class
  public
    Profile: string;
    App: string;
    Modified: Boolean;
    Tweaks: TJSONObject;   // owned; empty unless Modified
    constructor Create;
    destructor Destroy; override;
    { Missing or broken files leave the defaults. }
    procedure Load(const FileName: string);
    procedure Save(const FileName: string);
  end;

function UiSettingsFile: string;

implementation

uses
  Classes, SysUtils, jsonparser, djzen.core.paths, djzen.core.log;

function UiSettingsFile: string;
begin
  Result := UserDataDir + 'settings.json';
end;

constructor TUiSettings.Create;
begin
  inherited Create;
  Tweaks := TJSONObject.Create;
end;

destructor TUiSettings.Destroy;
begin
  Tweaks.Free;
  inherited Destroy;
end;

procedure TUiSettings.Load(const FileName: string);
var
  Stream: TFileStream;
  Data: TJSONData;
  Root, T: TJSONObject;
begin
  if not FileExists(FileName) then
    Exit;
  Data := nil;
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      Data := GetJSON(Stream);
    finally
      Stream.Free;
    end;
    if not (Data is TJSONObject) then
      Exit;
    Root := TJSONObject(Data);
    Profile := Root.Get('profile', '');
    App := Root.Get('app', '');
    Modified := Root.Get('modified', False);
    T := Root.Find('tweaks', jtObject) as TJSONObject;
    if T <> nil then
    begin
      Tweaks.Free;
      Tweaks := T.Clone as TJSONObject;
    end;
  except
    on E: Exception do
      LogWarn('Settings ignored: ' + E.Message);
  end;
  Data.Free;
end;

procedure TUiSettings.Save(const FileName: string);
var
  Root: TJSONObject;
  Text: string;
  Stream: TFileStream;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('profile', Profile);
    Root.Add('app', App);
    Root.Add('modified', Modified);
    if Modified then
      Root.Add('tweaks', Tweaks.Clone);
    Text := Root.FormatJSON;
  finally
    Root.Free;
  end;
  try
    ForceDirectories(ExtractFileDir(FileName));
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      if Text <> '' then
        Stream.WriteBuffer(Text[1], Length(Text));
    finally
      Stream.Free;
    end;
  except
    on E: Exception do
      LogWarn('Cannot save settings: ' + E.Message);
  end;
end;

end.
