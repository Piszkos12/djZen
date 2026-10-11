unit djzen.ui.main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics, Menus, Dialogs,
  djzen.core.tweak, djzen.core.engine, djzen.profiles, djzen.apps;

type
  { One option row: checkbox + audit status. }
  TOptionRow = class
    Tweak: TTweak;
    CheckBox: TCheckBox;
    StatusLabel: TLabel;
  end;

  TMainForm = class(TForm)
    TopPanel: TPanel;
    ZenButton: TButton;
    ProfileLabel: TLabel;
    ProfileCombo: TComboBox;
    ProfileMenuButton: TButton;
    AppLabel: TLabel;
    AppCombo: TComboBox;
    RecheckButton: TButton;
    StatusLabel: TLabel;
    DisclaimerLabel: TLabel;
    OptionsBox: TScrollBox;
    ProfileMenu: TPopupMenu;
    MenuSave: TMenuItem;
    MenuSaveAs: TMenuItem;
    MenuDelete: TMenuItem;
    MenuSep: TMenuItem;
    MenuImport: TMenuItem;
    MenuExport: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ZenButtonClick(Sender: TObject);
    procedure RecheckButtonClick(Sender: TObject);
    procedure ProfileComboChange(Sender: TObject);
    procedure AppComboChange(Sender: TObject);
    procedure ProfileMenuButtonClick(Sender: TObject);
    procedure ProfileMenuPopup(Sender: TObject);
    procedure MenuSaveClick(Sender: TObject);
    procedure MenuSaveAsClick(Sender: TObject);
    procedure MenuDeleteClick(Sender: TObject);
    procedure MenuImportClick(Sender: TObject);
    procedure MenuExportClick(Sender: TObject);
  private
    FEngine: TZenEngine;        // user part, this process
    FAdminEngine: TZenEngine;   // admin part: read-only here, changed by the elevated helper
    FRows: TList;   // TOptionRow
    FProfiles: TProfileList;
    FApps: TDJAppList;
    FModified: Boolean;       // checkboxes or DJ software differ from the selected profile
    FLoading: Boolean;        // suppresses FModified while controls are filled in code
    FStartupChecked: Boolean;
    procedure BuildOptions;
    procedure RestoreUiSettings;
    procedure SaveUiSettings;
    procedure OfferStartupRestore(Data: PtrInt);
    procedure DoRestore;
    procedure LoadApps;
    procedure ReloadProfiles(const SelectName: string);
    procedure SelectProfile(Index: Integer);
    function SelectedProfile: TProfile;
    function SelectedApp: TDJApp;
    procedure SelectApp(const AppId: string);
    procedure ApplyAppTarget;
    function CurrentProfileName: string;
    { The current checkboxes and DJ software as a profile (caller frees). }
    function ProfileFromState(const AName: string): TProfile;
    procedure SaveStateAs(const AName: string);
    procedure OptionClick(Sender: TObject);
    procedure RunChecks;
    procedure UpdateState;
    procedure ShowResult(const What: string; const R: TZenResult; const AdminNote: string = '');
    function ZenActive: Boolean;
    function ZenSince: string;
    function ZenProfile: string;
  end;

var
  MainForm: TMainForm;

implementation

uses
  fpjson, djzen.core.version, djzen.core.paths, djzen.core.log, djzen.core.blocklist,
  djzen.core.session, djzen.core.settings, djzen.core.elevation, djzen.tweaks.process;

{$R *.lfm}

const
  StatusColor: array[TTweakStatus] of TColor =
    (clGrayText, clGrayText, clGreen, $000080E0 {orange}, clRed);
  NoAppText = '(none)';

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := AppName + ' ' + AppVersion;
  FEngine := TZenEngine.Create(Tweaks, UserSnapshotFile, esUser);
  FAdminEngine := TZenEngine.Create(Tweaks, AdminSnapshotFile, esAdmin);
  FRows := TList.Create;
  FProfiles := TProfileList.Create(True);
  FApps := TDJAppList.Create(True);
  BuildOptions;
  LoadApps;
  ReloadProfiles('');
  RestoreUiSettings;
  RunChecks;
  UpdateState;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  if FStartupChecked then
    Exit;
  FStartupChecked := True;
  // after the window is visible, so the question has a parent on screen
  Application.QueueAsyncCall(@OfferStartupRestore, 0);
end;

{ Zen mode still active at start-up is expected after a normal exit with
  "keep Zen mode". It is offered for restore when djZen did not exit cleanly
  or the PC has restarted since Zen mode was switched on. }
procedure TMainForm.OfferStartupRestore(Data: PtrInt);
var
  Since: TDateTime;
  Rebooted: Boolean;
  Reason: string;
begin
  if not ZenActive then
    Exit;
  try
    Since := ParseIsoLocal(ZenSince);
    Rebooted := (Since > 0) and (Since < SystemBootTime);
    if PreviousSessionUnclean then
      Reason := 'djZen did not shut down properly last time (crash, forced close or power loss).'
    else if Rebooted then
      Reason := 'The computer has restarted since Zen mode was switched on.'
    else
      Exit;
    LogInfo('Offering restore at start-up: ' + Reason);
    if QuestionDlg('djZen', Reason + LineEnding + LineEnding +
      Format('Zen mode is still active (since %s, profile "%s").',
        [StringReplace(ZenSince, 'T', ' ', []), ZenProfile]) +
      LineEnding + 'Restore your original settings now?',
      mtWarning, [mrYes, 'Restore now', mrNo, 'Keep Zen mode'], 0) = mrYes then
      DoRestore;
  except
    on E: Exception do
    begin
      LogError(E.Message);
      StatusLabel.Caption := 'Error: ' + E.Message;
    end;
  end;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if not ZenActive then
    Exit;
  case QuestionDlg('djZen', 'Zen mode is active.' + LineEnding + LineEnding +
    'Restore your original settings before exiting?',
    mtConfirmation, [mrYes, 'Restore and exit', mrNo, 'Exit, keep Zen mode', mrCancel, 'Cancel'], 0) of
    mrYes:
      begin
        DoRestore;
        CanClose := not ZenActive;   // stay open if something could not be restored
      end;
    mrNo:
      CanClose := True;
  else
    CanClose := False;
  end;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  SaveUiSettings;
end;

{ User part first (no prompt), then the admin part through UAC if active. }
procedure TMainForm.DoRestore;
var
  R: TZenResult;
  AdminNote: string;
begin
  Screen.BeginWaitCursor;
  try
    R := FEngine.Deactivate;
    AdminNote := '';
    if AdminSnapshotExists then
      AdminNote := HelperResultText(LaunchHelperDeactivate);
  finally
    Screen.EndWaitCursor;
  end;
  UpdateState;
  ShowResult('Restored', R, AdminNote);
  RunChecks;
end;

{ --- Remembered UI state ----------------------------------------------- }

procedure TMainForm.RestoreUiSettings;
var
  S: TUiSettings;
  Row: TOptionRow;
  I: Integer;
  D: TJSONData;
begin
  S := TUiSettings.Create;
  try
    S.Load(UiSettingsFile);
    for I := 0 to FProfiles.Count - 1 do
      if SameText(FProfiles[I].Name, S.Profile) then
      begin
        ProfileCombo.ItemIndex := I;
        SelectProfile(I);
      end;
    if not S.Modified then
      Exit;
    // unsaved edits from last time
    FLoading := True;
    try
      SelectApp(S.App);
      for I := 0 to FRows.Count - 1 do
      begin
        Row := TOptionRow(FRows[I]);
        D := S.Tweaks.Find(Row.Tweak.Id);
        if D is TJSONBoolean then
          Row.CheckBox.Checked := Row.Tweak.CanApply and D.AsBoolean;
      end;
    finally
      FLoading := False;
    end;
    FModified := True;
  finally
    S.Free;
  end;
end;

procedure TMainForm.SaveUiSettings;
var
  S: TUiSettings;
  Row: TOptionRow;
  I: Integer;
begin
  S := TUiSettings.Create;
  try
    if SelectedProfile <> nil then
      S.Profile := SelectedProfile.Name;
    if SelectedApp <> nil then
      S.App := SelectedApp.Id;
    S.Modified := FModified;
    for I := 0 to FRows.Count - 1 do
    begin
      Row := TOptionRow(FRows[I]);
      if Row.Tweak.CanApply then
        S.Tweaks.Add(Row.Tweak.Id, Row.CheckBox.Checked);
    end;
    S.Save(UiSettingsFile);
  finally
    S.Free;
  end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FRows.Count - 1 do
    TOptionRow(FRows[I]).Free;
  FRows.Free;
  FProfiles.Free;
  FApps.Free;
  FEngine.Free;
  FAdminEngine.Free;
end;

{ One group box per impact level, one row per tweak. Empty groups are not shown. }
procedure TMainForm.BuildOptions;
var
  Impact: TTweakImpact;
  Group: TGroupBox;
  Panel: TPanel;
  Row: TOptionRow;
  Tweak: TTweak;
  I: Integer;
begin
  for Impact := Low(TTweakImpact) to High(TTweakImpact) do
  begin
    Group := nil;
    for I := 0 to Tweaks.Count - 1 do
    begin
      Tweak := Tweaks[I];
      if Tweak.Impact <> Impact then
        Continue;
      if Group = nil then
      begin
        Group := TGroupBox.Create(Self);
        Group.Caption := TweakImpactText[Impact];
        Group.AutoSize := True;
        Group.ChildSizing.LeftRightSpacing := 10;
        Group.ChildSizing.TopBottomSpacing := 6;
        Group.ChildSizing.VerticalSpacing := 2;
        Group.ChildSizing.EnlargeHorizontal := crsHomogenousChildResize;
        Group.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
        Group.ChildSizing.ControlsPerLine := 1;
        Group.Parent := OptionsBox;
      end;

      Panel := TPanel.Create(Self);
      Panel.BevelOuter := bvNone;
      Panel.Height := 26;
      Panel.Parent := Group;

      Row := TOptionRow.Create;
      Row.Tweak := Tweak;

      Row.StatusLabel := TLabel.Create(Self);
      Row.StatusLabel.Align := alRight;
      Row.StatusLabel.AutoSize := False;
      Row.StatusLabel.Width := 110;
      Row.StatusLabel.Alignment := taRightJustify;
      Row.StatusLabel.Layout := tlCenter;
      Row.StatusLabel.Parent := Panel;

      Row.CheckBox := TCheckBox.Create(Self);
      Row.CheckBox.Align := alClient;
      Row.CheckBox.Caption := Tweak.Name;
      if Tweak.RequiresAdmin then
        Row.CheckBox.Caption := Tweak.Name + '  (admin)';
      Row.CheckBox.OnClick := @OptionClick;
      Row.CheckBox.Parent := Panel;

      FRows.Add(Row);
    end;
  end;

  if Tweaks.Count = 0 then
    with TLabel.Create(Self) do
    begin
      Caption := 'No Zen options available yet.';
      Parent := OptionsBox;
    end;
end;

{ --- DJ software ------------------------------------------------------- }

procedure TMainForm.LoadApps;
var
  I: Integer;
begin
  FApps.LoadDir(FindBuiltinAppsDir, True);
  FApps.LoadDir(UserAppsDir, False);
  FApps.SortByName;
  AppCombo.Items.BeginUpdate;
  try
    AppCombo.Items.Clear;
    AppCombo.Items.Add(NoAppText);
    for I := 0 to FApps.Count - 1 do
      AppCombo.Items.AddObject(FApps[I].Name, FApps[I]);
  finally
    AppCombo.Items.EndUpdate;
  end;
  AppCombo.ItemIndex := 0;
end;

function TMainForm.SelectedApp: TDJApp;
begin
  if AppCombo.ItemIndex <= 0 then
    Result := nil
  else
    Result := TDJApp(AppCombo.Items.Objects[AppCombo.ItemIndex]);
end;

procedure TMainForm.SelectApp(const AppId: string);
var
  I: Integer;
begin
  AppCombo.ItemIndex := 0;
  for I := 1 to AppCombo.Items.Count - 1 do
    if SameText(TDJApp(AppCombo.Items.Objects[I]).Id, AppId) then
      AppCombo.ItemIndex := I;
  ApplyAppTarget;
end;

procedure TMainForm.ApplyAppTarget;
var
  App: TDJApp;
begin
  App := SelectedApp;
  if App = nil then
  begin
    SetDJAppTarget('', [], 'high');
    AppCombo.Hint := 'No DJ software selected';
  end
  else
  begin
    SetDJAppTarget(App.Name, App.Processes, App.Priority);
    AppCombo.Hint := App.Notes;
  end;
end;

procedure TMainForm.AppComboChange(Sender: TObject);
begin
  ApplyAppTarget;
  if not FLoading then
    FModified := True;
  RunChecks;
end;

{ --- Profiles ---------------------------------------------------------- }

procedure TMainForm.ReloadProfiles(const SelectName: string);
var
  I, Index: Integer;
begin
  FProfiles.Clear;
  FProfiles.LoadDir(FindBuiltinProfilesDir, True);
  FProfiles.LoadDir(UserProfilesDir, False);
  FProfiles.SortByOrder;
  Index := 0;
  ProfileCombo.Items.BeginUpdate;
  try
    ProfileCombo.Items.Clear;
    for I := 0 to FProfiles.Count - 1 do
    begin
      if FProfiles[I].Builtin then
        ProfileCombo.Items.Add(FProfiles[I].Name)
      else
        ProfileCombo.Items.Add(FProfiles[I].Name + '  (my profile)');
      if SameText(FProfiles[I].Name, SelectName) then
        Index := I;
    end;
  finally
    ProfileCombo.Items.EndUpdate;
  end;
  if FProfiles.Count > 0 then
  begin
    ProfileCombo.ItemIndex := Index;
    SelectProfile(Index);
  end;
end;

function TMainForm.SelectedProfile: TProfile;
begin
  if (ProfileCombo.ItemIndex < 0) or (ProfileCombo.ItemIndex >= FProfiles.Count) then
    Result := nil
  else
    Result := FProfiles[ProfileCombo.ItemIndex];
end;

procedure TMainForm.SelectProfile(Index: Integer);
var
  P: TProfile;
  Row: TOptionRow;
  I: Integer;
begin
  if (Index < 0) or (Index >= FProfiles.Count) then
    Exit;
  P := FProfiles[Index];
  ProfileCombo.Hint := P.Description;
  FLoading := True;
  try
    for I := 0 to FRows.Count - 1 do
    begin
      Row := TOptionRow(FRows[I]);
      Row.CheckBox.Checked := Row.Tweak.CanApply and P.IsEnabled(Row.Tweak.Id);
    end;
    SelectApp(P.App);
  finally
    FLoading := False;
  end;
  FModified := False;
end;

function TMainForm.CurrentProfileName: string;
var
  P: TProfile;
begin
  P := SelectedProfile;
  if P = nil then
    Result := 'Custom'
  else
    Result := P.Name;
  if FModified then
    Result := Result + ' (modified)';
end;

procedure TMainForm.ProfileComboChange(Sender: TObject);
begin
  SelectProfile(ProfileCombo.ItemIndex);
  RunChecks;
end;

procedure TMainForm.OptionClick(Sender: TObject);
begin
  if not FLoading then
    FModified := True;
end;

function TMainForm.ProfileFromState(const AName: string): TProfile;
var
  Row: TOptionRow;
  Old: TProfile;
  I: Integer;
begin
  Result := TProfile.Create;
  Result.Name := AName;
  Old := FProfiles.FindByName(AName);
  if Old <> nil then
    Result.Description := Old.Description;
  if SelectedApp <> nil then
    Result.App := SelectedApp.Id;
  for I := 0 to FRows.Count - 1 do
  begin
    Row := TOptionRow(FRows[I]);
    if Row.Tweak.CanApply then
      Result.Tweaks.Add(Row.Tweak.Id, Row.CheckBox.Checked);
  end;
end;

procedure TMainForm.SaveStateAs(const AName: string);
var
  P: TProfile;
begin
  P := ProfileFromState(AName);
  try
    SaveUserProfile(P, FProfiles);
    StatusLabel.Caption := Format('Profile "%s" saved', [P.Name]);
    ReloadProfiles(P.Name);
  finally
    P.Free;
  end;
end;

procedure TMainForm.ProfileMenuButtonClick(Sender: TObject);
var
  Pt: TPoint;
begin
  Pt := ProfileMenuButton.ClientToScreen(Point(0, ProfileMenuButton.Height));
  ProfileMenu.PopUp(Pt.X, Pt.Y);
end;

procedure TMainForm.ProfileMenuPopup(Sender: TObject);
var
  P: TProfile;
begin
  P := SelectedProfile;
  MenuSave.Enabled := (P <> nil) and not P.Builtin;
  MenuDelete.Enabled := (P <> nil) and not P.Builtin;
end;

procedure TMainForm.MenuSaveClick(Sender: TObject);
var
  P: TProfile;
begin
  P := SelectedProfile;
  if (P = nil) or P.Builtin then
    Exit;
  try
    SaveStateAs(P.Name);
  except
    on E: Exception do
      MessageDlg('Save profile', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.MenuSaveAsClick(Sender: TObject);
var
  NewName: string;
  Existing: TProfile;
begin
  NewName := '';
  if not InputQuery('Save as new profile', 'Profile name:', NewName) then
    Exit;
  NewName := Trim(NewName);
  if NewName = '' then
    Exit;
  Existing := FProfiles.FindByName(NewName);
  if (Existing <> nil) and not Existing.Builtin and
     (MessageDlg('Save profile', Format('Overwrite your profile "%s"?', [Existing.Name]),
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  try
    SaveStateAs(NewName);
  except
    on E: Exception do
      MessageDlg('Save profile', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.MenuDeleteClick(Sender: TObject);
var
  P: TProfile;
begin
  P := SelectedProfile;
  if (P = nil) or P.Builtin then
    Exit;
  if MessageDlg('Delete profile', Format('Delete your profile "%s"?', [P.Name]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  try
    DeleteUserProfile(P);
    StatusLabel.Caption := 'Profile deleted';
    ReloadProfiles('');
  except
    on E: Exception do
      MessageDlg('Delete profile', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.MenuImportClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  P: TProfile;
  Existing: TProfile;
begin
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title := 'Import profile';
    Dlg.Filter := 'djZen profile (*.json)|*.json';
    if not Dlg.Execute then
      Exit;
    try
      P := LoadProfile(Dlg.FileName, False);
      try
        Existing := FProfiles.FindByName(P.Name);
        if (Existing <> nil) and not Existing.Builtin and
           (MessageDlg('Import profile', Format('Overwrite your profile "%s"?', [P.Name]),
             mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
          Exit;
        SaveUserProfile(P, FProfiles);
        StatusLabel.Caption := Format('Profile "%s" imported', [P.Name]);
        ReloadProfiles(P.Name);
      finally
        P.Free;
      end;
    except
      on E: Exception do
        MessageDlg('Import profile', E.Message, mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.MenuExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
  P: TProfile;
  Base: string;
begin
  Base := CurrentProfileName;
  Dlg := TSaveDialog.Create(nil);
  try
    Dlg.Title := 'Export profile';
    Dlg.Filter := 'djZen profile (*.json)|*.json';
    Dlg.DefaultExt := 'json';
    Dlg.FileName := ExtractFileName(UserProfileFileName(Base));
    Dlg.Options := Dlg.Options + [ofOverwritePrompt];
    if not Dlg.Execute then
      Exit;
    P := ProfileFromState(Base);
    try
      try
        P.SaveToFile(Dlg.FileName);
        StatusLabel.Caption := 'Profile exported';
      except
        on E: Exception do
          MessageDlg('Export profile', E.Message, mtError, [mbOK], 0);
      end;
    finally
      P.Free;
    end;
  finally
    Dlg.Free;
  end;
end;

{ --- Checks and Zen mode ----------------------------------------------- }

procedure TMainForm.RunChecks;
var
  Row: TOptionRow;
  C: TTweakCheck;
  Tip: string;
  I: Integer;
begin
  Screen.BeginWaitCursor;
  try
    for I := 0 to FRows.Count - 1 do
    begin
      Row := TOptionRow(FRows[I]);
      C := Row.Tweak.Check;
      Row.StatusLabel.Caption := TweakStatusText[C.Status];
      Row.StatusLabel.Font.Color := StatusColor[C.Status];

      Tip := Row.Tweak.Description + LineEnding + LineEnding +
        'Status: ' + C.Detail + LineEnding +
        'Risk: ' + TweakRiskText[Row.Tweak.Risk] + ' | ' + TweakCategoryText[Row.Tweak.Category];
      if Row.Tweak.RequiresAdmin then
        Tip := Tip + LineEnding + '(Needs administrator rights: Windows asks for permission when Zen mode starts and stops)';
      if not Row.Tweak.CanApply then
        Tip := Tip + LineEnding + '(Audit only - applying is not implemented yet)';
      Row.CheckBox.Hint := Tip;
      Row.StatusLabel.Hint := Tip;
    end;
  finally
    Screen.EndWaitCursor;
  end;
end;

procedure TMainForm.UpdateState;
var
  ZenOn: Boolean;
  Row: TOptionRow;
  I: Integer;
begin
  ZenOn := ZenActive;
  if ZenOn then
  begin
    ZenButton.Caption := 'ZEN ON - click to restore';
    StatusLabel.Caption := Format('Active since %s - %s',
      [StringReplace(ZenSince, 'T', ' ', []), ZenProfile]);
  end
  else
  begin
    ZenButton.Caption := 'ZEN';
    StatusLabel.Caption := 'Ready';
  end;
  for I := 0 to FRows.Count - 1 do
  begin
    Row := TOptionRow(FRows[I]);
    Row.CheckBox.Enabled := not ZenOn and Row.Tweak.CanApply;
  end;
  ProfileCombo.Enabled := not ZenOn;
  ProfileMenuButton.Enabled := not ZenOn;
  AppCombo.Enabled := not ZenOn;
end;

procedure TMainForm.ShowResult(const What: string; const R: TZenResult; const AdminNote: string);
var
  S: string;
begin
  if R.Failed = 0 then
    S := Format('%s: %d OK', [What, R.Succeeded])
  else
    S := Format('%s: %d OK, %d failed - see log', [What, R.Succeeded, R.Failed]);
  if AdminNote <> '' then
    S := S + '; admin options: ' + AdminNote;
  StatusLabel.Caption := S;
  StatusLabel.Hint := S;
end;

function TMainForm.ZenActive: Boolean;
begin
  Result := FEngine.IsActive or AdminSnapshotExists;
end;

{ The user snapshot has the profile name; with admin options only, the
  admin snapshot (readable by users) is the only one. }
function TMainForm.ZenSince: string;
begin
  if FEngine.IsActive then
    Result := FEngine.ActiveSince
  else
    Result := FAdminEngine.ActiveSince;
end;

function TMainForm.ZenProfile: string;
begin
  if FEngine.IsActive then
    Result := FEngine.ActiveProfile
  else
    Result := 'admin options only';
end;

procedure TMainForm.RecheckButtonClick(Sender: TObject);
begin
  RunChecks;
end;

procedure TMainForm.ZenButtonClick(Sender: TObject);
var
  Settings: TJSONObject;
  Row: TOptionRow;
  App: TDJApp;
  R: TZenResult;
  I: Integer;
  WifiOff: Boolean;
  AdminIds: TStringArray;
  AdminNote: string;
begin
  if not ZenActive then
  begin
    // Warn before cutting the network the selected DJ software relies on.
    App := SelectedApp;
    WifiOff := False;
    for I := 0 to FRows.Count - 1 do
    begin
      Row := TOptionRow(FRows[I]);
      if (Row.Tweak.Id = 'radio.wifi') and Row.CheckBox.Checked then
        WifiOff := True;
    end;
    if (App <> nil) and App.NeedsNetwork and WifiOff and
       (MessageDlg('djZen', Format('%s needs the network, but "Turn off Wi-Fi" is selected.' +
         LineEnding + 'Switch Zen mode on anyway?', [App.Name]),
         mtWarning, [mbYes, mbNo], 0) <> mrYes) then
      Exit;
  end;

  ZenButton.Enabled := False;
  Screen.BeginWaitCursor;
  try
    try
      if ZenActive then
        DoRestore
      else
      begin
        ClearRuntimeProtection;
        ProtectDJApp(SelectedApp);
        Settings := TJSONObject.Create;
        try
          AdminIds := nil;
          for I := 0 to FRows.Count - 1 do
          begin
            Row := TOptionRow(FRows[I]);
            Settings.Add(Row.Tweak.Id, Row.CheckBox.Checked);
            if Row.CheckBox.Checked and Row.Tweak.RequiresAdmin then
            begin
              SetLength(AdminIds, Length(AdminIds) + 1);
              AdminIds[High(AdminIds)] := Row.Tweak.Id;
            end;
          end;
          // user part in this process (skips admin tweaks), admin part via UAC
          R := FEngine.Activate(CurrentProfileName, Settings);
        finally
          Settings.Free;
        end;
        AdminNote := '';
        if Length(AdminIds) > 0 then
          AdminNote := HelperResultText(LaunchHelperActivate(AdminIds));
        UpdateState;
        ShowResult('Zen mode', R, AdminNote);
        SaveUiSettings;
        RunChecks;
      end;
    except
      on E: Exception do
      begin
        LogError(E.Message);
        StatusLabel.Caption := 'Error: ' + E.Message;
      end;
    end;
  finally
    Screen.EndWaitCursor;
    ZenButton.Enabled := True;
  end;
end;

end.
