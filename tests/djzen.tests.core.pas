unit djzen.tests.core;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson,
  djzen.core.tweak, djzen.core.snapshot, djzen.core.engine, djzen.core.blocklist;

type
  { Simulates a system setting held in a global variable. }
  TFakeTweak = class(TTweak)
  public
    FId: string;
    FailApply, FailRevert: Boolean;
    constructor Create(const AId: string);
    function Id: string; override;
    function Name: string; override;
    function Description: string; override;
    function Category: TTweakCategory; override;
    function Impact: TTweakImpact; override;
    function Risk: TTweakRisk; override;
    function Check: TTweakCheck; override;
    function Capture: TJSONObject; override;
    procedure Apply(Params: TJSONObject); override;
    procedure Revert(Saved: TJSONObject); override;
  end;

  TEngineTests = class(TTestCase)
  private
    FRegistry: TTweakRegistry;
    FA, FB: TFakeTweak;
    FFile: string;
    function NewEngine: TZenEngine;
    function Settings(const Json: string): TJSONObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ActivateAppliesAndWritesSnapshot;
    procedure DeactivateRestoresAndDeletesSnapshot;
    procedure SurvivesRestart;
    procedure SecondActivateRaises;
    procedure FailedApplyIsStillReverted;
    procedure FailedRevertKeepsEntry;
    procedure DisabledTweakIsSkipped;
    procedure NothingEnabledLeavesNoSnapshot;
  end;

  TBlocklistTests = class(TTestCase)
  protected
    procedure TearDown; override;
  published
    procedure DefenderIsProtected;
    procedure ThirdPartyAntivirusIsProtected;
    procedure CaseInsensitive;
    procedure OrdinaryItemsAreNotProtected;
    procedure RuntimeProtection;
    procedure EnsureRaises;
    procedure Wildcards;
  end;

var
  { The fake "system state": tweak id -> value. }
  FakeState: TJSONObject;

implementation

uses
  djzen.core.log;

{ TFakeTweak }

constructor TFakeTweak.Create(const AId: string);
begin
  inherited Create;
  FId := AId;
end;

function TFakeTweak.Id: string; begin Result := FId; end;
function TFakeTweak.Name: string; begin Result := 'Fake ' + FId; end;
function TFakeTweak.Description: string; begin Result := ''; end;
function TFakeTweak.Category: TTweakCategory; begin Result := tcMisc; end;
function TFakeTweak.Impact: TTweakImpact; begin Result := tiLow; end;
function TFakeTweak.Risk: TTweakRisk; begin Result := trSafe; end;

function TFakeTweak.Check: TTweakCheck;
begin
  if FakeState.Get(FId, '') = 'zen' then
    Result := MakeCheck(tsOptimal)
  else
    Result := MakeCheck(tsNotOptimal);
end;

function TFakeTweak.Capture: TJSONObject;
begin
  Result := TJSONObject.Create(['value', FakeState.Get(FId, '')]);
end;

procedure TFakeTweak.Apply(Params: TJSONObject);
begin
  FakeState.Strings[FId] := Params.Get('to', 'zen');
  if FailApply then
    raise Exception.Create('simulated apply failure');
end;

procedure TFakeTweak.Revert(Saved: TJSONObject);
begin
  if FailRevert then
    raise Exception.Create('simulated revert failure');
  FakeState.Strings[FId] := Saved.Get('value', '');
end;

{ TEngineTests }

procedure TEngineTests.SetUp;
begin
  FakeState.Clear;
  FakeState.Add('a', 'original-a');
  FakeState.Add('b', 'original-b');
  FRegistry := TTweakRegistry.Create;
  FA := TFakeTweak.Create('a');
  FB := TFakeTweak.Create('b');
  FRegistry.Add(FA);
  FRegistry.Add(FB);
  FFile := GetTempDir + 'djzen-test-snapshot.json';
  DeleteFile(FFile);
end;

procedure TEngineTests.TearDown;
begin
  FRegistry.Free;
  DeleteFile(FFile);
  DeleteFile(FFile + '.tmp');
end;

function TEngineTests.NewEngine: TZenEngine;
begin
  Result := TZenEngine.Create(FRegistry, FFile);
end;

function TEngineTests.Settings(const Json: string): TJSONObject;
begin
  Result := GetJSON(Json) as TJSONObject;
end;

procedure TEngineTests.ActivateAppliesAndWritesSnapshot;
var
  E: TZenEngine;
  S: TJSONObject;
  R: TZenResult;
begin
  E := NewEngine;
  S := Settings('{"a": true, "b": {"to": "custom"}}');
  try
    R := E.Activate('Test', S);
    AssertEquals('succeeded', 2, R.Succeeded);
    AssertEquals('failed', 0, R.Failed);
    AssertEquals('zen', FakeState.Strings['a']);
    AssertEquals('custom', FakeState.Strings['b']);
    AssertTrue('snapshot exists', FileExists(FFile));
    AssertTrue('active', E.IsActive);
    AssertEquals('Test', E.ActiveProfile);
  finally
    S.Free;
    E.Free;
  end;
end;

procedure TEngineTests.DeactivateRestoresAndDeletesSnapshot;
var
  E: TZenEngine;
  S: TJSONObject;
  R: TZenResult;
begin
  E := NewEngine;
  S := Settings('{"a": true, "b": true}');
  try
    E.Activate('Test', S);
    R := E.Deactivate;
    AssertEquals('reverted', 2, R.Succeeded);
    AssertEquals('original-a', FakeState.Strings['a']);
    AssertEquals('original-b', FakeState.Strings['b']);
    AssertFalse('snapshot deleted', FileExists(FFile));
    AssertFalse('inactive', E.IsActive);
  finally
    S.Free;
    E.Free;
  end;
end;

procedure TEngineTests.SurvivesRestart;
var
  E: TZenEngine;
  S: TJSONObject;
begin
  E := NewEngine;
  S := Settings('{"a": true}');
  try
    E.Activate('Test', S);
  finally
    S.Free;
    E.Free;   // "reboot": the engine is gone, only the file remains
  end;

  E := NewEngine;
  try
    AssertTrue('still active after restart', E.IsActive);
    E.Deactivate;
    AssertEquals('original-a', FakeState.Strings['a']);
  finally
    E.Free;
  end;
end;

procedure TEngineTests.SecondActivateRaises;
var
  E: TZenEngine;
  S: TJSONObject;
  Raised: Boolean;
begin
  E := NewEngine;
  S := Settings('{"a": true}');
  try
    E.Activate('Test', S);
    Raised := False;
    try
      E.Activate('Test', S);
    except
      on EZenEngine do Raised := True;
    end;
    AssertTrue('must not overwrite original state', Raised);
    E.Deactivate;
    AssertEquals('original-a', FakeState.Strings['a']);
  finally
    S.Free;
    E.Free;
  end;
end;

procedure TEngineTests.FailedApplyIsStillReverted;
var
  E: TZenEngine;
  S: TJSONObject;
  R: TZenResult;
begin
  FA.FailApply := True;
  E := NewEngine;
  S := Settings('{"a": true, "b": true}');
  try
    R := E.Activate('Test', S);
    AssertEquals('succeeded', 1, R.Succeeded);
    AssertEquals('failed', 1, R.Failed);
    E.Deactivate;
    AssertEquals('partial change undone', 'original-a', FakeState.Strings['a']);
    AssertEquals('original-b', FakeState.Strings['b']);
  finally
    S.Free;
    E.Free;
  end;
end;

procedure TEngineTests.FailedRevertKeepsEntry;
var
  E: TZenEngine;
  S: TJSONObject;
  R: TZenResult;
begin
  E := NewEngine;
  S := Settings('{"a": true, "b": true}');
  try
    E.Activate('Test', S);
    FA.FailRevert := True;
    R := E.Deactivate;
    AssertEquals('reverted', 1, R.Succeeded);
    AssertEquals('failed', 1, R.Failed);
    AssertEquals('original-b', FakeState.Strings['b']);
    AssertTrue('snapshot kept for retry', E.IsActive);

    FA.FailRevert := False;
    R := E.Deactivate;
    AssertEquals('retry reverted', 1, R.Succeeded);
    AssertEquals('original-a', FakeState.Strings['a']);
    AssertFalse(E.IsActive);
  finally
    S.Free;
    E.Free;
  end;
end;

procedure TEngineTests.DisabledTweakIsSkipped;
var
  E: TZenEngine;
  S: TJSONObject;
begin
  E := NewEngine;
  S := Settings('{"a": false, "b": true}');
  try
    E.Activate('Test', S);
    AssertEquals('original-a', FakeState.Strings['a']);
    AssertEquals('zen', FakeState.Strings['b']);
    E.Deactivate;
  finally
    S.Free;
    E.Free;
  end;
end;

procedure TEngineTests.NothingEnabledLeavesNoSnapshot;
var
  E: TZenEngine;
  S: TJSONObject;
begin
  E := NewEngine;
  S := Settings('{}');
  try
    E.Activate('Test', S);
    AssertFalse(E.IsActive);
  finally
    S.Free;
    E.Free;
  end;
end;

{ TBlocklistTests }

procedure TBlocklistTests.TearDown;
begin
  ClearRuntimeProtection;
end;

procedure TBlocklistTests.DefenderIsProtected;
begin
  AssertTrue(IsProtectedService('WinDefend'));
  AssertTrue(IsProtectedService('mpssvc'));
  AssertTrue(IsProtectedService('SecurityHealthService'));
  AssertTrue(IsProtectedService('webthreatdefusersvc_3f2a1'));
  AssertTrue(IsProtectedProcess('MsMpEng.exe'));
  AssertTrue(IsProtectedProcess('C:\ProgramData\Microsoft\Windows Defender\Platform\MsMpEng.exe'));
end;

procedure TBlocklistTests.ThirdPartyAntivirusIsProtected;
begin
  AssertTrue(IsProtectedService('AvastWscReporter'));
  AssertTrue(IsProtectedService('ekrn'));
  AssertTrue(IsProtectedService('MBAMService'));
  AssertTrue(IsProtectedProcess('avp.exe'));
end;

procedure TBlocklistTests.CaseInsensitive;
begin
  AssertTrue(IsProtectedService('WINDEFEND'));
  AssertTrue(IsProtectedProcess('msmpeng.EXE'));
end;

procedure TBlocklistTests.OrdinaryItemsAreNotProtected;
begin
  AssertFalse(IsProtectedService('WSearch'));
  AssertFalse(IsProtectedService('SysMain'));
  AssertFalse(IsProtectedProcess('OneDrive.exe'));
  AssertFalse(IsProtectedProcess(''));
end;

procedure TBlocklistTests.RuntimeProtection;
begin
  AssertFalse(IsProtectedProcess('rekordbox.exe'));
  ProtectProcess('rekordbox*.exe');
  AssertTrue(IsProtectedProcess('rekordbox.exe'));
  ClearRuntimeProtection;
  AssertFalse(IsProtectedProcess('rekordbox.exe'));
  AssertTrue('built-in survives clear', IsProtectedService('WinDefend'));
end;

procedure TBlocklistTests.EnsureRaises;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    EnsureServiceNotProtected('WinDefend');
  except
    on EProtectedItem do Raised := True;
  end;
  AssertTrue(Raised);
  EnsureServiceNotProtected('WSearch');
end;

procedure TBlocklistTests.Wildcards;
begin
  AssertTrue(WildcardMatch('a*c', 'abbbc'));
  AssertTrue(WildcardMatch('a?c', 'abc'));
  AssertTrue(WildcardMatch('*', ''));
  AssertFalse(WildcardMatch('a?c', 'ac'));
  AssertFalse(WildcardMatch('abc', 'abcd'));
end;

initialization
  FakeState := TJSONObject.Create;
  LogInit(GetTempDir + 'djzen-test.log');
  RegisterTest(TEngineTests);
  RegisterTest(TBlocklistTests);

finalization
  FakeState.Free;

end.
