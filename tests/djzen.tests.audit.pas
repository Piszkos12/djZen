unit djzen.tests.audit;

{ Runs every real tweak's read-only Check and Capture against this machine.
  Nothing is changed. Results are printed so the audit can be eyeballed. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson,
  djzen.core.tweak,
  djzen.tweaks.notify, djzen.tweaks.power, djzen.tweaks.radio, djzen.tweaks.services;

type
  TAuditTests = class(TTestCase)
  published
    procedure AllChecksRunWithoutError;
    procedure AllCapturesProduceJson;
    procedure IdsAreUniqueAndNamespaced;
  end;

implementation

procedure TAuditTests.AllChecksRunWithoutError;
var
  I: Integer;
  C: TTweakCheck;
begin
  AssertTrue('tweaks registered', Tweaks.Count > 0);
  for I := 0 to Tweaks.Count - 1 do
  begin
    C := Tweaks[I].Check;
    WriteLn(Format('  %-32s %-13s %s', [Tweaks[I].Id, TweakStatusText[C.Status], C.Detail]));
    AssertTrue(Tweaks[I].Id + ': ' + C.Detail, C.Status <> tsError);
  end;
end;

procedure TAuditTests.AllCapturesProduceJson;
var
  I: Integer;
  J: TJSONObject;
begin
  for I := 0 to Tweaks.Count - 1 do
  begin
    J := Tweaks[I].Capture;
    try
      AssertNotNull(Tweaks[I].Id, J);
      AssertTrue(Tweaks[I].Id + ' capture empty', J.Count > 0);
    finally
      J.Free;
    end;
  end;
end;

procedure TAuditTests.IdsAreUniqueAndNamespaced;
var
  I: Integer;
begin
  // uniqueness is enforced by the registry; check the "<group>.<name>" format
  for I := 0 to Tweaks.Count - 1 do
    AssertTrue(Tweaks[I].Id, Pos('.', Tweaks[I].Id) > 1);
end;

initialization
  RegisterTest(TAuditTests);

end.
