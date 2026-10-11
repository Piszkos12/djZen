unit djzen.core.blocklist;

{ Things djZen must never stop, disable or kill.

  The built-in lists are constants: no profile, app script or setting can
  remove an entry. Security software (Defender, firewall, SmartScreen,
  third-party antivirus) is untouchable by design.

  Additional entries (DJ software, its services and devices) can be added at
  runtime with Protect*, but never removed from the built-in set.

  Patterns are case-insensitive and support the '*' and '?' wildcards. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  EProtectedItem = class(Exception);

function IsProtectedService(const ServiceName: string): Boolean;
function IsProtectedProcess(const ExeName: string): Boolean;

{ Raise EProtectedItem if the item is protected. Every tweak that stops a
  service or kills a process must call these first. }
procedure EnsureServiceNotProtected(const ServiceName: string);
procedure EnsureProcessNotProtected(const ExeName: string);

{ Runtime additions (e.g. from the selected DJ app script). }
procedure ProtectService(const Pattern: string);
procedure ProtectProcess(const Pattern: string);
procedure ClearRuntimeProtection;

function WildcardMatch(const Pattern, Text: string): Boolean;

implementation

uses
  Classes;

const
  BuiltinServices: array[0..47] of string = (
    // --- Microsoft Defender / Windows Security ---
    'WinDefend', 'WdNisSvc', 'WdNisDrv', 'WdFilter', 'WdBoot', 'Sense',
    'MDCoreSvc', 'SecurityHealthService', 'wscsvc', 'SgrmBroker', 'SgrmAgent',
    'webthreatdefsvc', 'webthreatdefusersvc*',
    // --- Firewall and network security ---
    'mpssvc', 'mpsdrv', 'BFE', 'IKEEXT', 'PolicyAgent',
    // --- Code integrity, crypto, identity ---
    'CryptSvc', 'AppIDSvc', 'KeyIso', 'SamSs', 'VaultSvc', 'EFS',
    // --- Third-party antivirus / EDR (common vendors) ---
    '*avast*', 'avg*', '*kaspersky*', 'avp*', 'klif*', 'ekrn', '*eset*',
    '*norton*', '*symantec*', '*mcafee*', '*bitdefender*', 'vsserv*',
    '*sophos*', '*malwarebytes*', 'mbam*', 'CSFalcon*', '*sentinel*',
    '*trendmicro*', '*f-secure*', '*panda*',
    // --- Core OS and audio: stopping these breaks the system or the sound ---
    'Audiosrv', 'AudioEndpointBuilder', 'RpcSs', 'Schedule'
  );

  BuiltinProcesses: array[0..30] of string = (
    // --- Security ---
    'MsMpEng.exe', 'NisSrv.exe', 'MpDefenderCoreService.exe', 'MsSense.exe',
    'SecurityHealthService.exe', 'SecurityHealthSystray.exe', 'smartscreen.exe',
    '*avast*', 'avg*', 'avp*.exe', 'ekrn.exe', 'egui.exe', '*norton*',
    '*mcafee*', '*bitdefender*', 'vsserv*', '*sophos*', 'mbam*',
    'CSFalcon*', '*sentinel*',
    // --- Critical system processes ---
    'System', 'smss.exe', 'csrss.exe', 'wininit.exe', 'winlogon.exe',
    'services.exe', 'lsass.exe', 'svchost.exe', 'dwm.exe', 'explorer.exe',
    // --- djZen itself ---
    'djZen.exe'
  );

var
  RuntimeServices: TStringList;
  RuntimeProcesses: TStringList;

function WildcardMatch(const Pattern, Text: string): Boolean;

  function Match(P, T: PChar): Boolean;
  begin
    while P^ <> #0 do
    begin
      case P^ of
        '*':
          begin
            while P^ = '*' do
              Inc(P);
            if P^ = #0 then
              Exit(True);
            while T^ <> #0 do
            begin
              if Match(P, T) then
                Exit(True);
              Inc(T);
            end;
            Exit(False);
          end;
        '?':
          if T^ = #0 then
            Exit(False);
      else
        if P^ <> T^ then
          Exit(False);
      end;
      Inc(P);
      Inc(T);
    end;
    Result := T^ = #0;
  end;

var
  LP, LT: string;
begin
  LP := LowerCase(Pattern);
  LT := LowerCase(Text);
  Result := Match(PChar(LP), PChar(LT));
end;

function MatchesAny(const Name: string; const Builtin: array of string;
  Runtime: TStringList): Boolean;
var
  S: string;
begin
  if Name = '' then
    Exit(False);
  for S in Builtin do
    if WildcardMatch(S, Name) then
      Exit(True);
  for S in Runtime do
    if WildcardMatch(S, Name) then
      Exit(True);
  Result := False;
end;

function IsProtectedService(const ServiceName: string): Boolean;
begin
  Result := MatchesAny(ServiceName, BuiltinServices, RuntimeServices);
end;

function IsProtectedProcess(const ExeName: string): Boolean;
begin
  Result := MatchesAny(ExtractFileName(ExeName), BuiltinProcesses, RuntimeProcesses);
end;

procedure EnsureServiceNotProtected(const ServiceName: string);
begin
  if IsProtectedService(ServiceName) then
    raise EProtectedItem.CreateFmt('Service "%s" is protected and cannot be changed', [ServiceName]);
end;

procedure EnsureProcessNotProtected(const ExeName: string);
begin
  if IsProtectedProcess(ExeName) then
    raise EProtectedItem.CreateFmt('Process "%s" is protected and cannot be stopped', [ExeName]);
end;

procedure ProtectService(const Pattern: string);
begin
  if (Pattern <> '') and (RuntimeServices.IndexOf(Pattern) < 0) then
    RuntimeServices.Add(Pattern);
end;

procedure ProtectProcess(const Pattern: string);
begin
  if (Pattern <> '') and (RuntimeProcesses.IndexOf(Pattern) < 0) then
    RuntimeProcesses.Add(Pattern);
end;

procedure ClearRuntimeProtection;
begin
  RuntimeServices.Clear;
  RuntimeProcesses.Clear;
end;

initialization
  RuntimeServices := TStringList.Create;
  RuntimeServices.CaseSensitive := False;
  RuntimeProcesses := TStringList.Create;
  RuntimeProcesses.CaseSensitive := False;

finalization
  RuntimeServices.Free;
  RuntimeProcesses.Free;

end.
