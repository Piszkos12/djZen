program djZenTests;

{$mode objfpc}{$H+}

uses
  Classes, consoletestrunner,
  djzen.tests.core, djzen.tests.audit, djzen.tests.profiles, djzen.tests.apps, djzen.tests.session,
  djzen.tests.live;

var
  App: TTestRunner;

begin
  DefaultFormat := fPlain;
  DefaultRunAllTests := True;
  App := TTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'djZen tests';
    App.Run;
  finally
    App.Free;
  end;
end.
