{ djZen - one-click DJ Zen mode for Windows laptops.
  Copyright (C) 2026 Piszkos12
  Licensed under the GNU General Public License v3.0 - see LICENSE. }

program djZen;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms,
  // tweak units register themselves; their order here is the apply order
  djzen.tweaks.notify, djzen.tweaks.power, djzen.tweaks.radio, djzen.tweaks.services,
  djzen.ui.main;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Title := 'djZen';
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
