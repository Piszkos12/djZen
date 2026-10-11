unit djzen.ui.main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  djzen.core.tweak, djzen.core.engine, djzen.profiles;

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
    RecheckButton: TButton;
    StatusLabel: TLabel;
    DisclaimerLabel: TLabel;
    OptionsBox: TScrollBox;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ZenButtonClick(Sender: TObject);
    procedure RecheckButtonClick(Sender: TObject);
    procedure ProfileComboChange(Sender: TObject);
  private
    FEngine: TZenEngine;
    FRows: TList;   // TOptionRow
    FProfiles: TProfileList;
    FModified: Boolean;       // checkboxes differ from the selected profile
    FLoadingProfile: Boolean;
    procedure BuildOptions;
    procedure LoadProfiles;
    procedure SelectProfile(Index: Integer);
    function CurrentProfileName: string;
    procedure OptionClick(Sender: TObject);
    procedure RunChecks;
    procedure UpdateState;
    procedure ShowResult(const What: string; const R: TZenResult);
  end;

var
  MainForm: TMainForm;

implementation

uses
  fpjson, djzen.core.version, djzen.core.paths, djzen.core.log;

{$R *.lfm}

const
  StatusColor: array[TTweakStatus] of TColor =
    (clGrayText, clGrayText, clGreen, $000080E0 {orange}, clRed);

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := AppName + ' ' + AppVersion;
  LogInit(LogFile);
  FEngine := TZenEngine.Create(Tweaks, SnapshotFile);
  FRows := TList.Create;
  FProfiles := TProfileList.Create(True);
  BuildOptions;
  LoadProfiles;
  RunChecks;
  UpdateState;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FRows.Count - 1 do
    TOptionRow(FRows[I]).Free;
  FRows.Free;
  FProfiles.Free;
  FEngine.Free;
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

procedure TMainForm.LoadProfiles;
var
  I: Integer;
begin
  FProfiles.LoadDir(FindBuiltinProfilesDir, True);
  FProfiles.SortByOrder;
  ProfileCombo.Items.BeginUpdate;
  try
    ProfileCombo.Items.Clear;
    for I := 0 to FProfiles.Count - 1 do
      ProfileCombo.Items.Add(FProfiles[I].Name);
  finally
    ProfileCombo.Items.EndUpdate;
  end;
  if FProfiles.Count > 0 then
  begin
    ProfileCombo.ItemIndex := 0;
    SelectProfile(0);
  end;
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
  FLoadingProfile := True;
  try
    for I := 0 to FRows.Count - 1 do
    begin
      Row := TOptionRow(FRows[I]);
      Row.CheckBox.Checked := Row.Tweak.CanApply and P.IsEnabled(Row.Tweak.Id);
    end;
  finally
    FLoadingProfile := False;
  end;
  FModified := False;
end;

function TMainForm.CurrentProfileName: string;
begin
  if ProfileCombo.ItemIndex < 0 then
    Result := 'Custom'
  else
    Result := ProfileCombo.Items[ProfileCombo.ItemIndex];
  if FModified then
    Result := Result + ' (modified)';
end;

procedure TMainForm.ProfileComboChange(Sender: TObject);
begin
  SelectProfile(ProfileCombo.ItemIndex);
end;

procedure TMainForm.OptionClick(Sender: TObject);
begin
  if not FLoadingProfile then
    FModified := True;
end;

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
  ZenOn := FEngine.IsActive;
  if ZenOn then
  begin
    ZenButton.Caption := 'ZEN ON - click to restore';
    StatusLabel.Caption := Format('Active since %s - %s',
      [StringReplace(FEngine.ActiveSince, 'T', ' ', []), FEngine.ActiveProfile]);
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
end;

procedure TMainForm.ShowResult(const What: string; const R: TZenResult);
begin
  if R.Failed = 0 then
    StatusLabel.Caption := Format('%s: %d OK', [What, R.Succeeded])
  else
    StatusLabel.Caption := Format('%s: %d OK, %d failed - see log', [What, R.Succeeded, R.Failed]);
end;

procedure TMainForm.RecheckButtonClick(Sender: TObject);
begin
  RunChecks;
end;

procedure TMainForm.ZenButtonClick(Sender: TObject);
var
  Settings: TJSONObject;
  Row: TOptionRow;
  R: TZenResult;
  I: Integer;
begin
  ZenButton.Enabled := False;
  Screen.BeginWaitCursor;
  try
    try
      if FEngine.IsActive then
      begin
        R := FEngine.Deactivate;
        UpdateState;
        ShowResult('Restored', R);
      end
      else
      begin
        Settings := TJSONObject.Create;
        try
          for I := 0 to FRows.Count - 1 do
          begin
            Row := TOptionRow(FRows[I]);
            Settings.Add(Row.Tweak.Id, Row.CheckBox.Checked);
          end;
          R := FEngine.Activate(CurrentProfileName, Settings);
        finally
          Settings.Free;
        end;
        UpdateState;
        ShowResult('Zen mode', R);
      end;
      RunChecks;
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
