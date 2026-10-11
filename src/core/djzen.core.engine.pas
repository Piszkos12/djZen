unit djzen.core.engine;

{ Switches Zen mode on and off.

  Activate: for each tweak enabled in the settings (in registry order)
    Capture -> save snapshot -> Apply -> mark applied -> save snapshot.
  Deactivate: revert entries in reverse order; each successfully reverted
    entry is removed from the snapshot immediately. Failed entries stay, so
    the user can retry. The snapshot file is deleted once it is empty.

  Entries whose Apply failed are reverted too: Apply may have changed part of
  the state before failing, and the captured original is still valid. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpjson, djzen.core.tweak, djzen.core.snapshot;

type
  EZenEngine = class(Exception);

  TZenResult = record
    Succeeded: Integer;
    Failed: Integer;
    Errors: array of string;
  end;

  TZenEngine = class
  private
    FRegistry: TTweakRegistry;
    FSnapshotFile: string;
  public
    constructor Create(ARegistry: TTweakRegistry; const ASnapshotFile: string);
    function IsActive: Boolean;
    function ActiveProfile: string;
    { ISO timestamp of the activation, '' if not active. }
    function ActiveSince: string;
    // Settings: {"<tweak id>": {params} | true, ...}. Raises if already active.
    function Activate(const ProfileName: string; Settings: TJSONObject): TZenResult;
    function Deactivate: TZenResult;
  end;

implementation

uses
  djzen.core.log;

procedure AddError(var R: TZenResult; const Msg: string);
begin
  Inc(R.Failed);
  SetLength(R.Errors, Length(R.Errors) + 1);
  R.Errors[High(R.Errors)] := Msg;
  LogError(Msg);
end;

constructor TZenEngine.Create(ARegistry: TTweakRegistry; const ASnapshotFile: string);
begin
  inherited Create;
  FRegistry := ARegistry;
  FSnapshotFile := ASnapshotFile;
end;

function TZenEngine.IsActive: Boolean;
begin
  Result := FileExists(FSnapshotFile);
end;

function TZenEngine.ActiveProfile: string;
var
  Snap: TSnapshot;
begin
  Result := '';
  if not IsActive then
    Exit;
  Snap := TSnapshot.Create(FSnapshotFile);
  try
    Snap.Load;
    Result := Snap.Profile;
  finally
    Snap.Free;
  end;
end;

function TZenEngine.ActiveSince: string;
var
  Snap: TSnapshot;
begin
  Result := '';
  if not IsActive then
    Exit;
  Snap := TSnapshot.Create(FSnapshotFile);
  try
    Snap.Load;
    Result := Snap.Created;
  finally
    Snap.Free;
  end;
end;

function TZenEngine.Activate(const ProfileName: string; Settings: TJSONObject): TZenResult;
var
  Snap: TSnapshot;
  Tweak: TTweak;
  Setting: TJSONData;
  Params, EmptyParams: TJSONObject;
  Data: TJSONObject;
  I: Integer;
begin
  Result := Default(TZenResult);
  if IsActive then
    raise EZenEngine.Create('Zen mode is already active; switch it off first');

  LogInfo(Format('Activating Zen mode, profile "%s"', [ProfileName]));
  EmptyParams := TJSONObject.Create;
  Snap := TSnapshot.Create(FSnapshotFile);
  try
    Snap.New(ProfileName);
    Snap.Save;

    for I := 0 to FRegistry.Count - 1 do
    begin
      Tweak := FRegistry[I];
      if not Tweak.CanApply then
        Continue;
      Setting := Settings.Find(Tweak.Id);
      if Setting is TJSONObject then
        Params := TJSONObject(Setting)
      else if (Setting is TJSONBoolean) and Setting.AsBoolean then
        Params := EmptyParams
      else
        Continue;

      try
        Data := Tweak.Capture;
      except
        on E: Exception do
        begin
          AddError(Result, Format('%s: capture failed: %s', [Tweak.Id, E.Message]));
          Continue;
        end;
      end;
      Snap.AddEntry(Tweak.Id, Data);
      Snap.Save;

      try
        Tweak.Apply(Params);
        Snap.SetState(Tweak.Id, 'applied');
        Snap.Save;
        Inc(Result.Succeeded);
        LogInfo(Tweak.Id + ': applied');
      except
        on E: Exception do
          AddError(Result, Format('%s: apply failed: %s', [Tweak.Id, E.Message]));
      end;
    end;

    if Snap.Count = 0 then
      Snap.Delete;   // nothing changed, nothing to restore
  finally
    Snap.Free;
    EmptyParams.Free;
  end;
  LogInfo(Format('Activation done: %d applied, %d failed', [Result.Succeeded, Result.Failed]));
end;

function TZenEngine.Deactivate: TZenResult;
var
  Snap: TSnapshot;
  Tweak: TTweak;
  Id: string;
  I: Integer;
begin
  Result := Default(TZenResult);
  if not IsActive then
    Exit;

  LogInfo('Deactivating Zen mode');
  Snap := TSnapshot.Create(FSnapshotFile);
  try
    Snap.Load;
    for I := Snap.Count - 1 downto 0 do
    begin
      Id := Snap.EntryId(I);
      Tweak := FRegistry.Find(Id);
      if Tweak = nil then
      begin
        AddError(Result, Format('%s: unknown tweak, cannot revert', [Id]));
        Continue;
      end;
      try
        Tweak.Revert(Snap.EntryData(I));
        Snap.RemoveEntry(I);
        Snap.Save;
        Inc(Result.Succeeded);
        LogInfo(Id + ': reverted');
      except
        on E: Exception do
          AddError(Result, Format('%s: revert failed: %s', [Id, E.Message]));
      end;
    end;

    if Snap.Count = 0 then
      Snap.Delete;
  finally
    Snap.Free;
  end;
  LogInfo(Format('Deactivation done: %d reverted, %d failed', [Result.Succeeded, Result.Failed]));
end;

end.
