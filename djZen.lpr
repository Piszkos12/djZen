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
  djzen.tweaks.process,
  Windows, djzen.core.log, djzen.core.paths, djzen.core.restore, djzen.core.session,
  djzen.core.elevation, djzen.win.security, djzen.ui.main;

{$R *.res}

begin
  // Only System32 for every DLL loaded from now on (no DLL planting from the
  // exe's folder, e.g. Downloads).
  HardenDllSearch;

  {$IFDEF DEBUG}
  // Leak report goes to a file instead of a message box on exit. The hidden
  // elevated helper must not write next to the exe (user-writable folder).
  if UseHeapTrace then
  begin
    if IsHelperRequested then
      SetHeapTraceOutput('nul')
    else
    begin
      SysUtils.DeleteFile(ChangeFileExt(ParamStr(0), '.heap.log'));
      SetHeapTraceOutput(ChangeFileExt(ParamStr(0), '.heap.log'));
    end;
  end;
  {$ENDIF}

  // Elevated helper: no GUI, admin-only tweaks, see djzen.core.elevation.
  if IsHelperRequested then
  begin
    ExitCode := RunHelper;
    Exit;
  end;

  if IsRestoreRequested then
  begin
    ExitCode := RunCommandLineRestore;
    Exit;
  end;

  if not AcquireSingleInstance then
  begin
    MessageBoxW(0, 'djZen is already running.', 'djZen', MB_OK or MB_ICONINFORMATION);
    Exit;
  end;
  LogInit(UserLogFile);
  BeginSession;

  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Title := 'djZen';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
  EndSession;   // not reached after a crash: the lock file then marks the unclean exit
end.
