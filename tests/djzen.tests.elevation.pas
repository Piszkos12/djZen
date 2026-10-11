unit djzen.tests.elevation;

{ User/admin split: engine scopes, helper id filtering, file trust checks. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpcunit, testregistry, fpjson,
  djzen.core.tweak, djzen.core.engine, djzen.core.snapshot, djzen.core.elevation,
  djzen.win.security,
  djzen.tweaks.notify, djzen.tweaks.power, djzen.tweaks.radio, djzen.tweaks.services,
  djzen.tweaks.process;

type
  TScopeTests = class(TTestCase)
  private
    FRegistry: TTweakRegistry;
    FFile: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure UserEngineSkipsAdminTweaks;
    procedure AdminEngineSkipsUserTweaks;
    procedure AdminEngineRefusesUserEntryInSnapshot;
  end;

  THelperTests = class(TTestCase)
  published
    procedure OnlyServicesNeedAdmin;
    procedure AdminTweakIdsDropsUserAndUnknownIds;
    procedure HelperRefusesWhenNotElevated;
  end;

  TTrustTests = class(TTestCase)
  published
    procedure UserCreatedFileIsNotTrusted;
    procedure ProgramDataIsTrusted;
    procedure PlainFileIsNoReparsePoint;
  end;

var
  FakeValues: TJSONObject;

implementation

type
  TFakeTweak = class(TTweak)
  public
    FId: string;
    FAdmin: Boolean;
    constructor Create(const AId: string; AAdmin: Boolean);
    function Id: string; override;
    function Name: string; override;
    function Description: string; override;
    function Category: TTweakCategory; override;
    function Impact: TTweakImpact; override;
    function Risk: TTweakRisk; override;
    function RequiresAdmin: Boolean; override;
    function Check: TTweakCheck; override;
    function Capture: TJSONObject; override;
    procedure Apply(Params: TJSONObject); override;
    procedure Revert(Saved: TJSONObject); override;
  end;

function IsUserAnAdmin: LongBool; stdcall; external 'shell32.dll';

constructor TFakeTweak.Create(const AId: string; AAdmin: Boolean);
begin
  inherited Create;
  FId := AId;
  FAdmin := AAdmin;
end;

function TFakeTweak.Id: string; begin Result := FId; end;
function TFakeTweak.Name: string; begin Result := FId; end;
function TFakeTweak.Description: string; begin Result := ''; end;
function TFakeTweak.Category: TTweakCategory; begin Result := tcMisc; end;
function TFakeTweak.Impact: TTweakImpact; begin Result := tiLow; end;
function TFakeTweak.Risk: TTweakRisk; begin Result := trSafe; end;
function TFakeTweak.RequiresAdmin: Boolean; begin Result := FAdmin; end;
function TFakeTweak.Check: TTweakCheck; begin Result := MakeCheck(tsUnknown); end;

function TFakeTweak.Capture: TJSONObject;
begin
  Result := TJSONObject.Create(['value', FakeValues.Get(FId, '')]);
end;

procedure TFakeTweak.Apply(Params: TJSONObject);
begin
  FakeValues.Strings[FId] := 'zen';
end;

procedure TFakeTweak.Revert(Saved: TJSONObject);
begin
  FakeValues.Strings[FId] := Saved.Get('value', '');
end;

{ TScopeTests }

procedure TScopeTests.SetUp;
begin
  FakeValues.Clear;
  FakeValues.Add('user.a', 'orig');
  FakeValues.Add('admin.b', 'orig');
  FRegistry := TTweakRegistry.Create;
  FRegistry.Add(TFakeTweak.Create('user.a', False));
  FRegistry.Add(TFakeTweak.Create('admin.b', True));
  FFile := GetTempDir + 'djzen-test-scope.json';
  DeleteFile(FFile);
end;

procedure TScopeTests.TearDown;
begin
  FRegistry.Free;
  DeleteFile(FFile);
  DeleteFile(FFile + '.tmp');
end;

procedure TScopeTests.UserEngineSkipsAdminTweaks;
var
  E: TZenEngine;
  S: TJSONObject;
begin
  E := TZenEngine.Create(FRegistry, FFile, esUser);
  S := TJSONObject.Create(['user.a', True, 'admin.b', True]);
  try
    AssertEquals(1, E.Activate('t', S).Succeeded);
    AssertEquals('zen', FakeValues.Strings['user.a']);
    AssertEquals('admin tweak untouched', 'orig', FakeValues.Strings['admin.b']);
    E.Deactivate;
  finally
    S.Free;
    E.Free;
  end;
end;

procedure TScopeTests.AdminEngineSkipsUserTweaks;
var
  E: TZenEngine;
  S: TJSONObject;
begin
  E := TZenEngine.Create(FRegistry, FFile, esAdmin);
  S := TJSONObject.Create(['user.a', True, 'admin.b', True]);
  try
    AssertEquals(1, E.Activate('t', S).Succeeded);
    AssertEquals('user tweak untouched', 'orig', FakeValues.Strings['user.a']);
    AssertEquals('zen', FakeValues.Strings['admin.b']);
    E.Deactivate;
    AssertEquals('orig', FakeValues.Strings['admin.b']);
  finally
    S.Free;
    E.Free;
  end;
end;

{ A planted or corrupted admin snapshot must not make the admin side revert
  something outside its scope. }
procedure TScopeTests.AdminEngineRefusesUserEntryInSnapshot;
var
  Snap: TSnapshot;
  E: TZenEngine;
  R: TZenResult;
begin
  Snap := TSnapshot.Create(FFile);
  try
    Snap.New('planted');
    Snap.AddEntry('user.a', TJSONObject.Create(['value', 'evil']));
    Snap.Save;
  finally
    Snap.Free;
  end;
  E := TZenEngine.Create(FRegistry, FFile, esAdmin);
  try
    R := E.Deactivate;
    AssertEquals('refused', 1, R.Failed);
    AssertEquals('not reverted', 'orig', FakeValues.Strings['user.a']);
  finally
    E.Free;
  end;
end;

{ THelperTests }

procedure THelperTests.OnlyServicesNeedAdmin;
var
  I: Integer;
begin
  for I := 0 to Tweaks.Count - 1 do
    AssertEquals(Tweaks[I].Id, Tweaks[I].Category = tcServices, Tweaks[I].RequiresAdmin);
end;

procedure THelperTests.AdminTweakIdsDropsUserAndUnknownIds;
var
  Ids: TStringArray;
begin
  Ids := AdminTweakIds(['notify.toasts', 'service.sysmain', 'no.such', 'service.windows-update']);
  AssertEquals(2, Length(Ids));
  AssertEquals('service.sysmain', Ids[0]);
  AssertEquals('service.windows-update', Ids[1]);
end;

procedure THelperTests.HelperRefusesWhenNotElevated;
begin
  if IsUserAnAdmin then
    Exit;   // only meaningful from a normal prompt
  AssertEquals(HelperNotElevated, RunHelper);
end;

{ TTrustTests }

procedure TTrustTests.UserCreatedFileIsNotTrusted;
var
  F: string;
  S: TStringList;
begin
  if IsUserAnAdmin then
    Exit;   // elevated, new files are owned by Administrators
  F := GetTempDir + 'djzen-test-owner.txt';
  S := TStringList.Create;
  try
    S.Text := 'x';
    S.SaveToFile(F);
    AssertFalse('a file created by a normal user must not be trusted', HasTrustedOwner(F));
  finally
    S.Free;
    DeleteFile(F);
  end;
end;

procedure TTrustTests.ProgramDataIsTrusted;
begin
  // %ProgramData% is owned by SYSTEM (System32 belongs to TrustedInstaller instead)
  AssertTrue(HasTrustedOwner(GetEnvironmentVariable('ProgramData')));
end;

procedure TTrustTests.PlainFileIsNoReparsePoint;
begin
  AssertFalse(IsReparsePoint(ParamStr(0)));
end;

initialization
  FakeValues := TJSONObject.Create;
  RegisterTest(TScopeTests);
  RegisterTest(THelperTests);
  RegisterTest(TTrustTests);

finalization
  FakeValues.Free;

end.
