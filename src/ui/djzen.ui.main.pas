unit djzen.ui.main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls;

type
  TMainForm = class(TForm)
    ZenButton: TButton;
    StatusLabel: TLabel;
    procedure FormCreate(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

uses
  djzen.core.version;

{$R *.lfm}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := AppName + ' ' + AppVersion;
  StatusLabel.Caption := 'Ready';
end;

end.
