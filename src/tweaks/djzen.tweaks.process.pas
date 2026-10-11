unit djzen.tweaks.process;

{ Raises the priority class of the selected DJ software.

  The target comes from the UI (SetDJAppTarget) because it depends on the
  DJ software chosen in the profile. Priority classes are not persistent:
  they end with the process, so Revert only touches the exact processes
  (PID + creation time) that were changed. }

{$mode objfpc}{$H+}

interface

{ Processes = exe name patterns of the DJ software; empty = no DJ software selected. }
procedure SetDJAppTarget(const AppName: string; const Processes: array of string;
  const Priority: string);

implementation

uses
  SysUtils, Windows, fpjson, djzen.core.tweak, djzen.win.process;

type
  TDJPriorityTweak = class(TTweak)
  public
    function Id: string; override;
    function Name: string; override;
    function Description: string; override;
    function Category: TTweakCategory; override;
    function Impact: TTweakImpact; override;
    function Risk: TTweakRisk; override;
    function Check: TTweakCheck; override;
    function Capture: TJSONObject; override;
    procedure Apply(Params: TJSONObject); override;
    procedure Revert(Saved: TJSONObject); override;
  end;

var
  TargetName: string;
  TargetProcesses: array of string;
  TargetPriority: DWORD = HIGH_PRIORITY_CLASS;

procedure SetDJAppTarget(const AppName: string; const Processes: array of string;
  const Priority: string);
var
  I: Integer;
begin
  TargetName := AppName;
  SetLength(TargetProcesses, Length(Processes));
  for I := 0 to High(Processes) do
    TargetProcesses[I] := Processes[I];
  TargetPriority := PriorityClassFromText(Priority);
end;

function TDJPriorityTweak.Id: string; begin Result := 'process.dj-priority'; end;
function TDJPriorityTweak.Name: string; begin Result := 'Raise DJ software priority'; end;
function TDJPriorityTweak.Description: string;
begin
  Result := 'Gives the running DJ software a higher CPU priority than background tasks ' +
    '(never "realtime", which can freeze the system). Start your DJ software before Zen mode.';
end;
function TDJPriorityTweak.Category: TTweakCategory; begin Result := tcProcesses; end;
function TDJPriorityTweak.Impact: TTweakImpact; begin Result := tiMedium; end;
function TDJPriorityTweak.Risk: TTweakRisk; begin Result := trSafe; end;

function TDJPriorityTweak.Check: TTweakCheck;
var
  Procs: TProcessEntries;
  P: TProcessEntry;
  Detail: string;
  AllOk: Boolean;
  Prio: DWORD;
begin
  if Length(TargetProcesses) = 0 then
    Exit(MakeCheck(tsNotApplicable, 'No DJ software selected'));
  try
    Procs := FindProcesses(TargetProcesses);
    if Length(Procs) = 0 then
      Exit(MakeCheck(tsNotApplicable, TargetName + ' is not running'));
    Detail := '';
    AllOk := True;
    for P in Procs do
    begin
      Prio := GetProcessPriority(P.Pid);
      if Detail <> '' then
        Detail := Detail + '; ';
      Detail := Detail + P.ExeName + ': ' + PriorityClassText(Prio);
      AllOk := AllOk and (PriorityRank(Prio) >= PriorityRank(TargetPriority));
    end;
    Detail := Detail + ' (wanted: ' + PriorityClassText(TargetPriority) + ')';
    if AllOk then
      Result := MakeCheck(tsOptimal, Detail)
    else
      Result := MakeCheck(tsNotOptimal, Detail);
  except
    on E: Exception do
      Result := MakeCheck(tsError, E.Message);
  end;
end;

function TDJPriorityTweak.Capture: TJSONObject;
var
  List: TJSONArray;
  P: TProcessEntry;
begin
  List := TJSONArray.Create;
  Result := TJSONObject.Create(['processes', List]);
  if Length(TargetProcesses) = 0 then
    Exit;
  for P in FindProcesses(TargetProcesses) do
    List.Add(TJSONObject.Create(['pid', Int64(P.Pid), 'exe', P.ExeName,
      'created', P.CreationTime, 'priority', Int64(GetProcessPriority(P.Pid))]));
end;

{ Only raises, never lowers a priority the user has set higher. }
procedure TDJPriorityTweak.Apply(Params: TJSONObject);
var
  P: TProcessEntry;
begin
  if Length(TargetProcesses) = 0 then
    Exit;
  for P in FindProcesses(TargetProcesses) do
    if PriorityRank(GetProcessPriority(P.Pid)) < PriorityRank(TargetPriority) then
      SetProcessPriority(P.Pid, TargetPriority);
end;

{ Processes that have exited (or whose PID was reused) are skipped. }
procedure TDJPriorityTweak.Revert(Saved: TJSONObject);
var
  List: TJSONArray;
  Item: TJSONObject;
  Pid: DWORD;
  I: Integer;
begin
  List := Saved.Find('processes', jtArray) as TJSONArray;
  if List = nil then
    Exit;
  for I := 0 to List.Count - 1 do
  begin
    Item := List.Objects[I];
    Pid := DWORD(Item.Int64s['pid']);
    if ProcessCreationTime(Pid) <> Item.Int64s['created'] then
      Continue;
    // Apply never lowered anything, so an unchanged process needs no revert
    // (and a user-set realtime priority must not be re-set by us).
    if GetProcessPriority(Pid) = DWORD(Item.Int64s['priority']) then
      Continue;
    SetProcessPriority(Pid, DWORD(Item.Int64s['priority']));
  end;
end;

initialization
  Tweaks.Add(TDJPriorityTweak.Create);

end.
