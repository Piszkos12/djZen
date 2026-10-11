unit djzen.core.restore;

{ Emergency restore without the GUI:
    djZen.exe /restore          restore and show the result in a message box
    djZen.exe /restore /quiet   restore silently (exit code 0 = OK, 1 = failures) }

{$mode objfpc}{$H+}

interface

function IsRestoreRequested: Boolean;
{ Returns the process exit code. }
function RunCommandLineRestore: Integer;

implementation

uses
  Windows, SysUtils, djzen.core.tweak, djzen.core.engine, djzen.core.paths, djzen.core.log,
  djzen.core.elevation;

function HasSwitch(const Name: string): Boolean;
var
  I: Integer;
  S: string;
begin
  for I := 1 to ParamCount do
  begin
    S := ParamStr(I);
    if (S <> '') and (S[1] in ['/', '-']) then
    begin
      Delete(S, 1, 1);
      if (S <> '') and (S[1] = '-') then
        Delete(S, 1, 1);
      if SameText(S, Name) then
        Exit(True);
    end;
  end;
  Result := False;
end;

function IsRestoreRequested: Boolean;
begin
  Result := HasSwitch('restore');
end;

{ Restores the user part in this process, then the admin part through the
  elevated helper (one UAC prompt, only if the admin part is active). }
function RunCommandLineRestore: Integer;
var
  Engine: TZenEngine;
  R: TZenResult;
  Msg: string;
  E: string;
  HelperCode: Integer;
begin
  LogInit(UserLogFile);
  LogInfo('Command-line restore requested');
  Result := 0;
  Msg := '';
  Engine := TZenEngine.Create(Tweaks, UserSnapshotFile, esUser);
  try
    try
      if Engine.IsActive then
      begin
        R := Engine.Deactivate;
        Msg := Format('Restored %d setting(s).', [R.Succeeded]);
        if R.Failed > 0 then
        begin
          Msg := Msg + LineEnding + Format('%d failed:', [R.Failed]);
          for E in R.Errors do
            Msg := Msg + LineEnding + '  ' + E;
          Result := 1;
        end;
      end;
    except
      on Ex: Exception do
      begin
        Msg := 'Restore failed: ' + Ex.Message;
        LogError(Msg);
        Result := 1;
      end;
    end;
  finally
    Engine.Free;
  end;

  if AdminSnapshotExists then
  begin
    HelperCode := LaunchHelperDeactivate;
    if Msg <> '' then
      Msg := Msg + LineEnding;
    Msg := Msg + 'Admin options: ' + HelperResultText(HelperCode) + '.';
    if HelperCode <> HelperOk then
      Result := 1;
  end;

  if Msg = '' then
    Msg := 'Zen mode is not active - nothing to restore.'
  else if Result <> 0 then
    Msg := Msg + LineEnding + LineEnding + 'Run "djZen.exe /restore" again to retry.';

  if not HasSwitch('quiet') then
    MessageBoxW(0, PWideChar(UnicodeString(Msg)), 'djZen restore',
      MB_OK or MB_ICONINFORMATION or MB_SETFOREGROUND);
end;

end.
