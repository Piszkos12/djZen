unit djzen.core.snapshot;

(* Persistent record of the original state of everything Zen mode changed.

  The file is rewritten atomically (temp file + MoveFileEx with write-through)
  after every step, so a crash or power loss at any point leaves a snapshot
  that can still be reverted.

  Format:
    { "version": 1, "app": "0.1.0", "created": "2026-10-11T12:00:00",
      "profile": "Offline gig",
      "entries": [ { "id": "...", "state": "captured|applied", "data": {...} } ] } *)

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson;

type
  ESnapshot = class(Exception);

  TSnapshot = class
  private
    FFileName: string;
    FRoot: TJSONObject;
    function Entries: TJSONArray;
    function Entry(Index: Integer): TJSONObject;
    function GetProfile: string;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;

    function Exists: Boolean;
    procedure New(const AProfile: string);
    procedure Load;
    procedure Save;
    procedure Delete;

    { Takes ownership of Data. }
    procedure AddEntry(const Id: string; Data: TJSONObject);
    procedure SetState(const Id, State: string);
    procedure RemoveEntry(Index: Integer);
    function Count: Integer;
    function EntryId(Index: Integer): string;
    function EntryState(Index: Integer): string;
    function EntryData(Index: Integer): TJSONObject;

    property FileName: string read FFileName;
    property Profile: string read GetProfile;
  end;

const
  SnapshotFormatVersion = 1;

  MOVEFILE_WRITE_THROUGH = $8;

implementation

uses
  Classes, Windows, jsonparser, djzen.core.version;

constructor TSnapshot.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
end;

destructor TSnapshot.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TSnapshot.Exists: Boolean;
begin
  Result := FileExists(FFileName);
end;

procedure TSnapshot.New(const AProfile: string);
begin
  FreeAndNil(FRoot);
  FRoot := TJSONObject.Create;
  FRoot.Add('version', SnapshotFormatVersion);
  FRoot.Add('app', AppVersion);
  FRoot.Add('created', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
  FRoot.Add('profile', AProfile);
  FRoot.Add('entries', TJSONArray.Create);
end;

procedure TSnapshot.Load;
var
  Stream: TFileStream;
  Data: TJSONData;
begin
  FreeAndNil(FRoot);
  Stream := TFileStream.Create(FFileName, fmOpenRead or fmShareDenyWrite);
  try
    try
      Data := GetJSON(Stream);
    except
      on E: Exception do
        raise ESnapshot.CreateFmt('Snapshot "%s" is corrupt: %s', [FFileName, E.Message]);
    end;
  finally
    Stream.Free;
  end;
  if not (Data is TJSONObject) or (TJSONObject(Data).Find('entries', jtArray) = nil) then
  begin
    Data.Free;
    raise ESnapshot.CreateFmt('Snapshot "%s" has an invalid structure', [FFileName]);
  end;
  FRoot := TJSONObject(Data);
  if FRoot.Get('version', 0) > SnapshotFormatVersion then
    raise ESnapshot.CreateFmt('Snapshot "%s" was written by a newer djZen version', [FFileName]);
end;

procedure TSnapshot.Save;
var
  TempName, Text: string;
  Stream: TFileStream;
begin
  if FRoot = nil then
    raise ESnapshot.Create('No snapshot to save');
  ForceDirectories(ExtractFileDir(FFileName));
  TempName := FFileName + '.tmp';
  Text := FRoot.FormatJSON;
  Stream := TFileStream.Create(TempName, fmCreate);
  try
    if Text <> '' then
      Stream.WriteBuffer(Text[1], Length(Text));
    FlushFileBuffers(Stream.Handle);
  finally
    Stream.Free;
  end;
  if not MoveFileExW(PWideChar(UnicodeString(TempName)), PWideChar(UnicodeString(FFileName)),
    MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
    raise ESnapshot.CreateFmt('Cannot write snapshot "%s": %s',
      [FFileName, SysErrorMessage(GetLastError)]);
end;

procedure TSnapshot.Delete;
begin
  FreeAndNil(FRoot);
  if FileExists(FFileName) and not SysUtils.DeleteFile(FFileName) then
    raise ESnapshot.CreateFmt('Cannot delete snapshot "%s"', [FFileName]);
end;

function TSnapshot.Entries: TJSONArray;
begin
  if FRoot = nil then
    raise ESnapshot.Create('Snapshot not loaded');
  Result := FRoot.Arrays['entries'];
end;

function TSnapshot.Entry(Index: Integer): TJSONObject;
begin
  Result := Entries.Objects[Index];
end;

function TSnapshot.GetProfile: string;
begin
  if FRoot = nil then
    Result := ''
  else
    Result := FRoot.Get('profile', '');
end;

procedure TSnapshot.AddEntry(const Id: string; Data: TJSONObject);
var
  E: TJSONObject;
begin
  E := TJSONObject.Create;
  E.Add('id', Id);
  E.Add('state', 'captured');
  E.Add('data', Data);
  Entries.Add(E);
end;

procedure TSnapshot.SetState(const Id, State: string);
var
  I: Integer;
begin
  for I := Count - 1 downto 0 do
    if SameText(EntryId(I), Id) then
    begin
      Entry(I).Strings['state'] := State;
      Exit;
    end;
  raise ESnapshot.CreateFmt('No snapshot entry for "%s"', [Id]);
end;

procedure TSnapshot.RemoveEntry(Index: Integer);
begin
  Entries.Delete(Index);
end;

function TSnapshot.Count: Integer;
begin
  Result := Entries.Count;
end;

function TSnapshot.EntryId(Index: Integer): string;
begin
  Result := Entry(Index).Get('id', '');
end;

function TSnapshot.EntryState(Index: Integer): string;
begin
  Result := Entry(Index).Get('state', '');
end;

function TSnapshot.EntryData(Index: Integer): TJSONObject;
begin
  Result := Entry(Index).Objects['data'];
end;

end.
