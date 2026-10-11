{ djZen - one-click DJ Zen mode for Windows laptops.
  Copyright (C) 2026 Piszkos12
  Licensed under the GNU General Public License v3.0 - see LICENSE. }

program djZen;

{$mode objfpc}{$H+}

uses
  {$IFDEF DEBUG}heaptrc, SysUtils,{$ENDIF}
  Interfaces, Forms,
  // tweak units register themselves; their order here is the apply order
  djzen.tweaks.notify, djzen.tweaks.power, djzen.tweaks.radio, djzen.tweaks.services,
  djzen.core.restore, djzen.ui.main;

{$R *.res}

begin
  {$IFDEF DEBUG}
  // Leak report goes to a file instead of a message box on exit.
  if UseHeapTrace then
  begin
    DeleteFile(ChangeFileExt(ParamStr(0), '.heap.log'));
    SetHeapTraceOutput(ChangeFileExt(ParamStr(0), '.heap.log'));
  end;
  {$ENDIF}
  if IsRestoreRequested then
  begin
    ExitCode := RunCommandLineRestore;
    Exit;
  end;

  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Title := 'djZen';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
