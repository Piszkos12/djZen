unit djzen.tests.apps;

{ DJ software descriptors and user profile files. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, fpcunit, testregistry, fpjson,
  djzen.apps, djzen.profiles, djzen.core.blocklist;

type
  TAppTests = class(TTestCase)
  private
    FTempDir: string;
    procedure WriteFile(const Name, Text: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure BuiltinAppsLoad;
    procedure AppIdsAreUnique;
    procedure RealtimePriorityIsRejected;
    procedure MissingProcessesIsRejected;
    procedure UserDescriptorReplacesBuiltin;
    procedure ProtectDJAppAddsToBlocklist;
  end;

  TUserProfileTests = class(TTestCase)
  private
    FTempDir: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure SaveAndLoadRoundTrip;
    procedure FileNameIsSanitized;
    procedure BuiltinNameIsRefused;
    procedure EmptyNameIsRefused;
    procedure BuiltinCannotBeDeleted;
  end;

implementation

function RepoDir(const Sub: string): string;
begin
  Result := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\..\' + Sub + '\');
end;

procedure DeleteTree(const Dir: string);
var
  SR: TSearchRec;
begin
  if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) = 0 then
        DeleteFile(Dir + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(Dir);
end;

{ TAppTests }

procedure TAppTests.SetUp;
begin
  FTempDir := GetTempDir + 'djzen-test-apps\';
  DeleteTree(FTempDir);
  ForceDirectories(FTempDir);
end;

procedure TAppTests.TearDown;
begin
  ClearRuntimeProtection;
  DeleteTree(FTempDir);
end;

procedure TAppTests.WriteFile(const Name, Text: string);
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.Text := Text;
    S.SaveToFile(FTempDir + Name);
  finally
    S.Free;
  end;
end;

procedure TAppTests.BuiltinAppsLoad;
var
  L: TDJAppList;
begin
  L := TDJAppList.Create(True);
  try
    L.LoadDir(RepoDir('apps'), True);
    AssertEquals('built-in app count', 6, L.Count);
    AssertNotNull(L.FindById('rekordbox'));
    AssertNotNull(L.FindById('traktor'));
  finally
    L.Free;
  end;
end;

procedure TAppTests.AppIdsAreUnique;
var
  L: TDJAppList;
  I, J: Integer;
begin
  L := TDJAppList.Create(True);
  try
    L.LoadDir(RepoDir('apps'), True);
    for I := 0 to L.Count - 1 do
      for J := I + 1 to L.Count - 1 do
        AssertFalse(L[I].Id, SameText(L[I].Id, L[J].Id));
  finally
    L.Free;
  end;
end;

procedure TAppTests.RealtimePriorityIsRejected;
var
  Raised: Boolean;
begin
  WriteFile('bad.json', '{"id":"x","name":"X","processes":["x.exe"],"priority":"realtime"}');
  Raised := False;
  try
    LoadDJApp(FTempDir + 'bad.json', False).Free;
  except
    Raised := True;
  end;
  AssertTrue('realtime must be rejected', Raised);
end;

procedure TAppTests.MissingProcessesIsRejected;
var
  Raised: Boolean;
begin
  WriteFile('bad.json', '{"id":"x","name":"X","processes":[]}');
  Raised := False;
  try
    LoadDJApp(FTempDir + 'bad.json', False).Free;
  except
    Raised := True;
  end;
  AssertTrue(Raised);
end;

procedure TAppTests.UserDescriptorReplacesBuiltin;
var
  L: TDJAppList;
begin
  WriteFile('mine.json', '{"id":"rekordbox","name":"My rekordbox","processes":["rekordbox.exe"],' +
    '"needsNetwork":true}');
  L := TDJAppList.Create(True);
  try
    L.LoadDir(RepoDir('apps'), True);
    L.LoadDir(FTempDir, False);
    AssertEquals('still 6 apps', 6, L.Count);
    AssertEquals('My rekordbox', L.FindById('rekordbox').Name);
    AssertTrue(L.FindById('rekordbox').NeedsNetwork);
    AssertFalse(L.FindById('rekordbox').Builtin);
  finally
    L.Free;
  end;
end;

procedure TAppTests.ProtectDJAppAddsToBlocklist;
var
  App: TDJApp;
begin
  WriteFile('a.json', '{"id":"a","name":"A","processes":["mydj*.exe"],"protectServices":["MyDjAudio"]}');
  App := LoadDJApp(FTempDir + 'a.json', False);
  try
    AssertFalse(IsProtectedProcess('mydj64.exe'));
    ProtectDJApp(App);
    AssertTrue(IsProtectedProcess('mydj64.exe'));
    AssertTrue(IsProtectedService('MyDjAudio'));
  finally
    App.Free;
  end;
end;

{ TUserProfileTests }

procedure TUserProfileTests.SetUp;
begin
  FTempDir := GetTempDir + 'djzen-test-profiles\';
  DeleteTree(FTempDir);
  ForceDirectories(FTempDir);
end;

procedure TUserProfileTests.TearDown;
begin
  DeleteTree(FTempDir);
end;

procedure TUserProfileTests.SaveAndLoadRoundTrip;
var
  P, Q: TProfile;
begin
  P := TProfile.Create;
  try
    P.Name := 'Club night';
    P.App := 'traktor';
    P.Tweaks.Add('radio.wifi', False);
    P.Tweaks.Add('power.sleep', True);
    P.SaveToFile(FTempDir + 'club.json');
  finally
    P.Free;
  end;
  Q := LoadProfile(FTempDir + 'club.json', False);
  try
    AssertEquals('Club night', Q.Name);
    AssertEquals('traktor', Q.App);
    AssertTrue(Q.IsEnabled('power.sleep'));
    AssertFalse(Q.IsEnabled('radio.wifi'));
    AssertFalse(Q.Builtin);
  finally
    Q.Free;
  end;
end;

procedure TUserProfileTests.FileNameIsSanitized;
begin
  AssertEquals('club-night-2.json', ExtractFileName(UserProfileFileName('  Club Night #2  ')));
  AssertEquals('profile.json', ExtractFileName(UserProfileFileName('***')));
  AssertEquals('dj-set.json', ExtractFileName(UserProfileFileName('..\..\DJ set')));
end;

procedure TUserProfileTests.BuiltinNameIsRefused;
var
  L: TProfileList;
  P: TProfile;
  Raised: Boolean;
begin
  L := TProfileList.Create(True);
  P := TProfile.Create;
  try
    L.LoadDir(RepoDir('profiles'), True);
    P.Name := 'offline ZEN';
    Raised := False;
    try
      SaveUserProfile(P, L);
    except
      on EProfile do Raised := True;
    end;
    AssertTrue('built-in name must be refused', Raised);
  finally
    P.Free;
    L.Free;
  end;
end;

procedure TUserProfileTests.EmptyNameIsRefused;
var
  P: TProfile;
  Raised: Boolean;
begin
  P := TProfile.Create;
  try
    P.Name := '   ';
    Raised := False;
    try
      SaveUserProfile(P, nil);
    except
      on EProfile do Raised := True;
    end;
    AssertTrue(Raised);
  finally
    P.Free;
  end;
end;

procedure TUserProfileTests.BuiltinCannotBeDeleted;
var
  L: TProfileList;
  Raised: Boolean;
begin
  L := TProfileList.Create(True);
  try
    L.LoadDir(RepoDir('profiles'), True);
    Raised := False;
    try
      DeleteUserProfile(L[0]);
    except
      on EProfile do Raised := True;
    end;
    AssertTrue(Raised);
    AssertTrue('file still there', FileExists(L[0].FileName));
  finally
    L.Free;
  end;
end;

initialization
  RegisterTest(TAppTests);
  RegisterTest(TUserProfileTests);

end.
