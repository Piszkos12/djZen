unit djzen.tests.profiles;

{ Validates the built-in profiles in the repository's profiles\ folder. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson,
  djzen.core.tweak, djzen.profiles,
  djzen.tweaks.notify, djzen.tweaks.power, djzen.tweaks.radio, djzen.tweaks.services;

type
  TProfileTests = class(TTestCase)
  private
    FProfiles: TProfileList;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure BuiltinProfilesLoad;
    procedure ProfilesOnlyReferenceKnownTweaks;
    procedure NamesAreUnique;
    procedure OfflineZenDisablesWifi;
    procedure StreamingZenKeepsWifi;
  end;

implementation

function RepoProfilesDir: string;
begin
  // tests run from bin\tests\
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\..\profiles\');
end;

procedure TProfileTests.SetUp;
begin
  FProfiles := TProfileList.Create(True);
  FProfiles.LoadDir(RepoProfilesDir, True);
  FProfiles.SortByOrder;
end;

procedure TProfileTests.TearDown;
begin
  FProfiles.Free;
end;

procedure TProfileTests.BuiltinProfilesLoad;
begin
  AssertEquals('built-in profile count', 3, FProfiles.Count);
  AssertEquals('Offline zen', FProfiles[0].Name);
end;

procedure TProfileTests.ProfilesOnlyReferenceKnownTweaks;
var
  I, J: Integer;
  P: TProfile;
begin
  for I := 0 to FProfiles.Count - 1 do
  begin
    P := FProfiles[I];
    for J := 0 to P.Tweaks.Count - 1 do
      AssertNotNull(Format('%s: unknown tweak "%s"', [P.Name, P.Tweaks.Names[J]]),
        Tweaks.Find(P.Tweaks.Names[J]));
  end;
end;

procedure TProfileTests.NamesAreUnique;
var
  I, J: Integer;
begin
  for I := 0 to FProfiles.Count - 1 do
    for J := I + 1 to FProfiles.Count - 1 do
      AssertFalse(FProfiles[I].Name, SameText(FProfiles[I].Name, FProfiles[J].Name));
end;

procedure TProfileTests.OfflineZenDisablesWifi;
begin
  AssertTrue(FProfiles.FindByName('Offline zen').IsEnabled('radio.wifi'));
end;

procedure TProfileTests.StreamingZenKeepsWifi;
begin
  AssertFalse(FProfiles.FindByName('Streaming zen').IsEnabled('radio.wifi'));
end;

initialization
  RegisterTest(TProfileTests);

end.
