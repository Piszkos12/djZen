unit djzen.tests.live;

{ LIVE round-trip test: really applies and reverts every applicable tweak on
  this machine, then checks that the captured state is identical to before.

  It changes system settings, so it only runs when explicitly requested:
    - environment variable DJZEN_LIVE_TESTS=1
    - from an elevated (administrator) command prompt
  Example:  set "DJZEN_LIVE_TESTS=1" && test.bat }

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

{ Apply errors are reported but do not stop the loop: every tweak that was
  applied must still be reverted. }
procedure TLiveTests.ApplyThenRevertRestoresEveryTweak;
var
  I: Integer;
  T: TTweak;
  Before, After: TJSONObject;
  Params: TJSONObject;
  Failures, Line: string;
begin
  Failures := '';
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
        try
          T.Apply(Params);
          Line := Line + 'applied -> ' + TweakStatusText[T.Check.Status];
        except
          on E: Exception do
          begin
            Line := Line + 'APPLY FAILED: ' + E.Message;
            Failures := Failures + T.Id + ' apply: ' + E.Message + LineEnding;
          end;
        end;
        try
          T.Revert(Before);
          After := T.Capture;
          try
            if After.AsJSON = Before.AsJSON then
              Line := Line + ', reverted OK'
            else
            begin
              Line := Line + ', REVERT MISMATCH';
              Failures := Failures + T.Id + ' revert mismatch:' + LineEnding +
                '    before: ' + Before.AsJSON + LineEnding +
                '    after:  ' + After.AsJSON + LineEnding;
            end;
          finally
            After.Free;
          end;
        except
          on E: Exception do
          begin
            Line := Line + ', REVERT FAILED: ' + E.Message;
            Failures := Failures + T.Id + ' revert: ' + E.Message + LineEnding;
          end;
        end;
        WriteLn(Line);
      finally
        Before.Free;
      end;
    end;
  finally
    Params.Free;
  end;
  AssertEquals('Live round-trip failures', '', Failures);
end;

initialization
  // Trim: 'set X=1 && test.bat' in cmd stores "1 " with the trailing space.
  if Trim(SysUtils.GetEnvironmentVariable('DJZEN_LIVE_TESTS')) = '1' then
  begin
    if IsUserAnAdmin then
      RegisterTest(TLiveTests)
    else
      WriteLn('DJZEN_LIVE_TESTS=1 ignored: live tests need an elevated (administrator) prompt.');
  end;

end.
