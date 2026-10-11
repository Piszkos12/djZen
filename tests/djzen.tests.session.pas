unit djzen.tests.session;

{ Remembered UI settings and session helpers. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson,
  djzen.core.settings, djzen.core.session;

type
  TSessionTests = class(TTestCase)
  published
    procedure SettingsRoundTrip;
    procedure UnmodifiedSettingsDropTweaks;
    procedure MissingSettingsFileGivesDefaults;
    procedure ParsesSnapshotTimestamp;
    procedure BootTimeIsInThePast;
  end;

implementation

function TempFile: string;
begin
  Result := GetTempDir + 'djzen-test-settings.json';
end;

procedure TSessionTests.SettingsRoundTrip;
var
  A, B: TUiSettings;
begin
  A := TUiSettings.Create;
  B := TUiSettings.Create;
  try
    A.Profile := 'Club night';
    A.App := 'mixxx';
    A.Modified := True;
    A.Tweaks.Add('radio.wifi', False);
    A.Tweaks.Add('power.sleep', True);
    A.Save(TempFile);
    B.Load(TempFile);
    AssertEquals('Club night', B.Profile);
    AssertEquals('mixxx', B.App);
    AssertTrue(B.Modified);
    AssertFalse(B.Tweaks.Booleans['radio.wifi']);
    AssertTrue(B.Tweaks.Booleans['power.sleep']);
  finally
    A.Free;
    B.Free;
    DeleteFile(TempFile);
  end;
end;

procedure TSessionTests.UnmodifiedSettingsDropTweaks;
var
  A, B: TUiSettings;
begin
  A := TUiSettings.Create;
  B := TUiSettings.Create;
  try
    A.Profile := 'Offline zen';
    A.Tweaks.Add('radio.wifi', True);
    A.Save(TempFile);
    B.Load(TempFile);
    AssertFalse(B.Modified);
    AssertEquals(0, B.Tweaks.Count);
  finally
    A.Free;
    B.Free;
    DeleteFile(TempFile);
  end;
end;

procedure TSessionTests.MissingSettingsFileGivesDefaults;
var
  S: TUiSettings;
begin
  DeleteFile(TempFile);
  S := TUiSettings.Create;
  try
    S.Load(TempFile);
    AssertEquals('', S.Profile);
    AssertFalse(S.Modified);
  finally
    S.Free;
  end;
end;

procedure TSessionTests.ParsesSnapshotTimestamp;
begin
  AssertEquals(EncodeDate(2026, 10, 11) + EncodeTime(21, 5, 9, 0),
    ParseIsoLocal('2026-10-11T21:05:09'), 1e-9);
  AssertEquals(0, ParseIsoLocal(''), 0);
  AssertEquals(0, ParseIsoLocal('garbage-not-a-date'), 0);
  AssertEquals(0, ParseIsoLocal('2026-13-45T99:00:00'), 0);
end;

procedure TSessionTests.BootTimeIsInThePast;
begin
  AssertTrue(SystemBootTime < Now);
end;

initialization
  RegisterTest(TSessionTests);

end.
