unit djzen.core.tweak;

{ TTweak: one thing djZen can check, change and restore.

  Lifecycle when Zen mode is switched on:
    1. Capture  - read the current (original) state, returned as JSON and
                  written to the snapshot BEFORE anything changes
    2. Apply    - make the change, using the profile's parameters
  When Zen mode is switched off (possibly after a reboot, in a new process):
    3. Revert   - restore the state captured in step 1

  Check is read-only and used by the audit view. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Contnrs, fpjson;

type
  TTweakCategory = (tcAudio, tcLatency, tcPower, tcServices, tcProcesses, tcNetwork, tcMisc);
  { How much the tweak helps a live DJ set; the UI groups options by this. }
  TTweakImpact = (tiHigh, tiMedium, tiLow);
  TTweakRisk = (trSafe, trAdvanced, trExpert);
  TTweakStatus = (tsUnknown, tsNotApplicable, tsOptimal, tsNotOptimal, tsError);

  TTweakCheck = record
    Status: TTweakStatus;
    Detail: string;
  end;

  TTweak = class
  public
    function Id: string; virtual; abstract;            // stable, used in profiles and snapshots
    function Name: string; virtual; abstract;
    function Description: string; virtual; abstract;
    function Category: TTweakCategory; virtual; abstract;
    function Impact: TTweakImpact; virtual; abstract;
    function Risk: TTweakRisk; virtual; abstract;

    { False while only the audit (Check/Capture) is implemented; the engine
      skips such tweaks and the UI shows them read-only. }
    function CanApply: Boolean; virtual;

    function Check: TTweakCheck; virtual; abstract;
    { Caller owns the result. }
    function Capture: TJSONObject; virtual; abstract;
    { Params is never nil (empty object when the profile gives none). }
    procedure Apply(Params: TJSONObject); virtual; abstract;
    procedure Revert(Saved: TJSONObject); virtual; abstract;
  end;

  ETweakNotImplemented = class(Exception);

  { Base for tweaks that can only be audited so far. }
  TAuditOnlyTweak = class(TTweak)
  public
    function CanApply: Boolean; override;
    procedure Apply(Params: TJSONObject); override;
    procedure Revert(Saved: TJSONObject); override;
  end;

  ETweakRegistry = class(Exception);

  TTweakRegistry = class
  private
    FItems: TFPObjectList;
    function GetCount: Integer;
    function GetItem(Index: Integer): TTweak;
  public
    constructor Create;
    destructor Destroy; override;
    { Takes ownership. Raises on duplicate Id. }
    procedure Add(Tweak: TTweak);
    function Find(const Id: string): TTweak;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TTweak read GetItem; default;
  end;

function MakeCheck(Status: TTweakStatus; const Detail: string = ''): TTweakCheck;

{ Global registry; tweak units register themselves in their initialization. }
function Tweaks: TTweakRegistry;

const
  TweakCategoryText: array[TTweakCategory] of string =
    ('Audio', 'Latency', 'Power', 'Services', 'Processes', 'Network', 'Misc');
  TweakImpactText: array[TTweakImpact] of string = ('High impact', 'Medium impact', 'Low impact');
  TweakRiskText: array[TTweakRisk] of string = ('Safe', 'Advanced', 'Expert');
  TweakStatusText: array[TTweakStatus] of string =
    ('Unknown', 'N/A', 'OK', 'Needs change', 'Error');

implementation

var
  GlobalTweaks: TTweakRegistry;

function MakeCheck(Status: TTweakStatus; const Detail: string): TTweakCheck;
begin
  Result.Status := Status;
  Result.Detail := Detail;
end;

function Tweaks: TTweakRegistry;
begin
  if GlobalTweaks = nil then
    GlobalTweaks := TTweakRegistry.Create;
  Result := GlobalTweaks;
end;

{ TTweak }

function TTweak.CanApply: Boolean;
begin
  Result := True;
end;

{ TAuditOnlyTweak }

function TAuditOnlyTweak.CanApply: Boolean;
begin
  Result := False;
end;

procedure TAuditOnlyTweak.Apply(Params: TJSONObject);
begin
  raise ETweakNotImplemented.CreateFmt('%s: apply is not implemented yet', [Id]);
end;

procedure TAuditOnlyTweak.Revert(Saved: TJSONObject);
begin
  raise ETweakNotImplemented.CreateFmt('%s: revert is not implemented yet', [Id]);
end;

{ TTweakRegistry }

constructor TTweakRegistry.Create;
begin
  inherited Create;
  FItems := TFPObjectList.Create(True);
end;

destructor TTweakRegistry.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TTweakRegistry.Add(Tweak: TTweak);
begin
  if Find(Tweak.Id) <> nil then
  begin
    Tweak.Free;
    raise ETweakRegistry.CreateFmt('Duplicate tweak id "%s"', [Tweak.Id]);
  end;
  FItems.Add(Tweak);
end;

function TTweakRegistry.Find(const Id: string): TTweak;
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    if SameText(TTweak(FItems[I]).Id, Id) then
      Exit(TTweak(FItems[I]));
  Result := nil;
end;

function TTweakRegistry.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TTweakRegistry.GetItem(Index: Integer): TTweak;
begin
  Result := TTweak(FItems[Index]);
end;

finalization
  GlobalTweaks.Free;

end.
