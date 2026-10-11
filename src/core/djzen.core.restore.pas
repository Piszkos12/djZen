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
  Windows, SysUtils, djzen.core.tweak, djzen.core.engine, djzen.core.paths, djzen.core.log;

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

function RunCommandLineRestore: Integer;
var
  Engine: TZenEngine;
  R: TZenResult;
  Msg: string;
  E: string;
begin
  LogInit(LogFile);
  LogInfo('Command-line restore requested');
  Engine := TZenEngine.Create(Tweaks, SnapshotFile);
  try
    try
      if not Engine.IsActive then
      begin
        Msg := 'Zen mode is not active - nothing to restore.';
        Result := 0;
      end
      else
      begin
        R := Engine.Deactivate;
        Msg := Format('Restored %d setting(s).', [R.Succeeded]);
        if R.Failed > 0 then
        begin
          Msg := Msg + LineEnding + Format('%d failed:', [R.Failed]);
          for E in R.Errors do
            Msg := Msg + LineEnding + '  ' + E;
          Msg := Msg + LineEnding + LineEnding + 'Run "djZen.exe /restore" again to retry.';
        end;
        Result := Ord(R.Failed > 0);
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

  if not HasSwitch('quiet') then
    MessageBoxW(0, PWideChar(UnicodeString(Msg)), 'djZen restore',
      MB_OK or MB_ICONINFORMATION or MB_SETFOREGROUND);
end;

end.
