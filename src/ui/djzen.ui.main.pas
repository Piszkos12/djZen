unit djzen.ui.main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls,
  djzen.core.tweak, djzen.core.engine;

type
  TMainForm = class(TForm)
    TopPanel: TPanel;
    ZenButton: TButton;
    StatusLabel: TLabel;
    OptionsBox: TScrollBox;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ZenButtonClick(Sender: TObject);
  private
    FEngine: TZenEngine;
    FCheckBoxes: TList;   // TCheckBox, Tag = index into Tweaks
    procedure BuildOptions;
    procedure UpdateState;
    procedure ShowResult(const What: string; const R: TZenResult);
  end;

var
  MainForm: TMainForm;

implementation

uses
  fpjson, djzen.core.version, djzen.core.paths, djzen.core.log;

{$R *.lfm}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := AppName + ' ' + AppVersion;
  LogInit(LogFile);
  FEngine := TZenEngine.Create(Tweaks, SnapshotFile);
  FCheckBoxes := TList.Create;
  BuildOptions;
  UpdateState;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FCheckBoxes.Free;
  FEngine.Free;
end;

{ One group box per impact level, one checkbox per tweak. Groups with no
  tweaks are not shown. }
procedure TMainForm.BuildOptions;
var
  Impact: TTweakImpact;
  Group: TGroupBox;
  Box: TCheckBox;
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
        Group.ChildSizing.VerticalSpacing := 4;
        Group.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
        Group.ChildSizing.ControlsPerLine := 1;
        Group.Parent := OptionsBox;
      end;
      Box := TCheckBox.Create(Self);
      Box.Caption := Tweak.Name;
      Box.Hint := Tweak.Description + LineEnding +
        'Risk: ' + TweakRiskText[Tweak.Risk] + ' | ' + TweakCategoryText[Tweak.Category];
      Box.Checked := Tweak.Risk = trSafe;
      Box.Tag := I;
      Box.Parent := Group;
      FCheckBoxes.Add(Box);
    end;
  end;

  if Tweaks.Count = 0 then
    with TLabel.Create(Self) do
    begin
      Caption := 'No Zen options available yet.';
      Parent := OptionsBox;
    end;
end;

procedure TMainForm.UpdateState;
var
  ZenOn: Boolean;
  I: Integer;
begin
  ZenOn := FEngine.IsActive;
  if ZenOn then
  begin
    ZenButton.Caption := 'ZEN ON';
    StatusLabel.Caption := 'Zen mode active - profile: ' + FEngine.ActiveProfile;
  end
  else
  begin
    ZenButton.Caption := 'ZEN';
    StatusLabel.Caption := 'Ready';
  end;
  for I := 0 to FCheckBoxes.Count - 1 do
    TCheckBox(FCheckBoxes[I]).Enabled := not ZenOn;
end;

procedure TMainForm.ShowResult(const What: string; const R: TZenResult);
begin
  if R.Failed = 0 then
    StatusLabel.Caption := Format('%s: %d OK', [What, R.Succeeded])
  else
    StatusLabel.Caption := Format('%s: %d OK, %d failed - see log', [What, R.Succeeded, R.Failed]);
end;

procedure TMainForm.ZenButtonClick(Sender: TObject);
var
  Settings: TJSONObject;
  Box: TCheckBox;
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
          for I := 0 to FCheckBoxes.Count - 1 do
          begin
            Box := TCheckBox(FCheckBoxes[I]);
            Settings.Add(Tweaks[Box.Tag].Id, Box.Checked);
          end;
          R := FEngine.Activate('Custom', Settings);
        finally
          Settings.Free;
        end;
        UpdateState;
        ShowResult('Zen mode', R);
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
