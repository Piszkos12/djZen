unit djzen.tests.live;

{ LIVE round-trip test: really applies and reverts every applicable tweak on
  this machine, then checks that the captured state is identical to before.

  It changes system settings, so it only runs when explicitly requested with
  the environment variable DJZEN_LIVE_TESTS=1:
    set "DJZEN_LIVE_TESTS=1" && tests.bat
  From an elevated prompt every tweak must work. From a normal prompt it is a
  privilege probe: it lists which tweaks work without admin rights. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson,
  djzen.core.tweak,
  djzen.tweaks.notify, djzen.tweaks.power, djzen.tweaks.radio, djzen.tweaks.services,
  djzen.tweaks.process;

type
  TLiveTests = class(TTestCase)
  published
    procedure ApplyThenRevertRestoresEveryTweak;
  end;

implementation

uses
  Windows;

function IsUserAnAdmin: BOOL; stdcall; external 'shell32.dll';

{ Elevated: every tweak must apply, and revert to exactly the captured state.
  Not elevated (privilege probe): a failing apply means "needs admin" and is
  only reported; the state must still be unchanged afterwards. }
procedure TLiveTests.ApplyThenRevertRestoresEveryTweak;
var
  I: Integer;
  T: TTweak;
  Before, After: TJSONObject;
  Params: TJSONObject;
  Failures, Line, NoAdmin, NeedsAdmin, RevertError: string;
  Elevated, Applied: Boolean;
begin
  Elevated := IsUserAnAdmin;
  if Elevated then
    WriteLn('  Live test: ELEVATED')
  else
    WriteLn('  Live test: NOT elevated (privilege probe)');
  Failures := '';
  NoAdmin := '';
  NeedsAdmin := '';
  Params := TJSONObject.Create;
  try
    for I := 0 to Tweaks.Count - 1 do
    begin
      T := Tweaks[I];
      if not T.CanApply then
        Continue;
      Before := T.Capture;
      try
        Line := Format('  %-32s ', [T.Id]);
        Applied := False;
        try
          T.Apply(Params);
          Applied := True;
          Line := Line + 'applied -> ' + TweakStatusText[T.Check.Status];
          NoAdmin := NoAdmin + '    ' + T.Id + LineEnding;
        except
          on E: Exception do
          begin
            Line := Line + 'APPLY FAILED: ' + E.Message;
            if Elevated then
              Failures := Failures + T.Id + ' apply: ' + E.Message + LineEnding
            else
              NeedsAdmin := NeedsAdmin + '    ' + T.Id + ' (' + E.Message + ')' + LineEnding;
          end;
        end;

        RevertError := '';
        try
          T.Revert(Before);
        except
          on E: Exception do
            RevertError := E.Message;
        end;
        if (RevertError <> '') and (Elevated or Applied) then
        begin
          Line := Line + ', REVERT FAILED: ' + RevertError;
          Failures := Failures + T.Id + ' revert: ' + RevertError + LineEnding;
        end;

        // whatever happened, the system must be back in its original state
        After := T.Capture;
        try
          if After.AsJSON = Before.AsJSON then
            Line := Line + ', state OK'
          else
          begin
            Line := Line + ', STATE CHANGED';
            Failures := Failures + T.Id + ' state changed:' + LineEnding +
              '    before: ' + Before.AsJSON + LineEnding +
              '    after:  ' + After.AsJSON + LineEnding;
          end;
        finally
          After.Free;
        end;
        WriteLn(Line);
      finally
        Before.Free;
      end;
    end;
  finally
    Params.Free;
  end;
  if not Elevated then
  begin
    WriteLn;
    WriteLn('  Works WITHOUT admin rights:');
    Write(NoAdmin);
    WriteLn('  Needs admin rights:');
    Write(NeedsAdmin);
    WriteLn;
  end;
  AssertEquals('Live round-trip failures', '', Failures);
end;

initialization
  // Trim: 'set X=1 && tests.bat' in cmd stores "1 " with the trailing space.
  if Trim(SysUtils.GetEnvironmentVariable('DJZEN_LIVE_TESTS')) = '1' then
    RegisterTest(TLiveTests);

end.
