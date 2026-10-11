unit djzen.win.security;

{ Hardening for the elevated helper:
  - the admin data folder (%ProgramData%\djZen) gets an explicit, protected
    ACL: SYSTEM and Administrators full control, Users read only. By default
    it would inherit "Users: create files" from %ProgramData%.
  - the folder and the fixed file names djZen uses there must not be reparse
    points (junctions/symlinks) and must be owned by Administrators or SYSTEM;
    anything else was planted and is moved aside, never trusted or followed.
  - DLLs are only loaded from System32. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils;

type
  ESecurity = class(Exception);

{ Restricts DLL search to System32 for every later LoadLibrary call. Call first
  thing at start-up. Returns False on systems without the API. }
function HardenDllSearch: Boolean;

{ LoadLibrary from System32 only (0 if missing). }
function LoadSystemLibrary(const Name: UnicodeString): HMODULE;

{ Must run elevated. Creates or repairs Dir and quarantines untrusted entries
  among Names (file or folder names directly inside Dir). }
procedure EnsureSecureDir(const Dir: string; const Names: array of string);

function IsReparsePoint(const Path: string): Boolean;
{ True if Path is owned by Administrators or SYSTEM. }
function HasTrustedOwner(const Path: string): Boolean;

function IsProcessElevated: Boolean;

implementation

const
  LOAD_LIBRARY_SEARCH_SYSTEM32 = $00000800;
  FILE_ATTRIBUTE_REPARSE_POINT = $00000400;
  SE_FILE_OBJECT = 1;
  OWNER_SECURITY_INFORMATION = $00000001;
  DACL_SECURITY_INFORMATION = $00000004;
  PROTECTED_DACL_SECURITY_INFORMATION = $80000000;
  SDDL_REVISION_1 = 1;
  WinLocalSystemSid = 22;
  WinBuiltinAdministratorsSid = 26;

  // Owner Administrators; SYSTEM + Administrators full control, Users read & execute;
  // protected (no inheritance from %ProgramData%), inherited by subfolders and files.
  SecureDirSddl = 'O:BAD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)';

function SetDefaultDllDirectories(DirectoryFlags: DWORD): BOOL; stdcall;
  external 'kernel32.dll';
function LoadLibraryExW(lpLibFileName: PWideChar; hFile: THandle; dwFlags: DWORD): HMODULE;
  stdcall; external 'kernel32.dll';
function ConvertStringSecurityDescriptorToSecurityDescriptorW(StringSecurityDescriptor: PWideChar;
  StringSDRevision: DWORD; out SecurityDescriptor: Pointer; SecurityDescriptorSize: PDWORD): BOOL;
  stdcall; external 'advapi32.dll';
function GetNamedSecurityInfoW(pObjectName: PWideChar; ObjectType: DWORD; SecurityInfo: DWORD;
  ppsidOwner, ppsidGroup, ppDacl, ppSacl: PPointer; out ppSecurityDescriptor: Pointer): DWORD;
  stdcall; external 'advapi32.dll';
function SetNamedSecurityInfoW(pObjectName: PWideChar; ObjectType: DWORD; SecurityInfo: DWORD;
  psidOwner, psidGroup, pDacl, pSacl: Pointer): DWORD; stdcall; external 'advapi32.dll';
function IsWellKnownSid(pSid: Pointer; WellKnownSidType: DWORD): BOOL; stdcall;
  external 'advapi32.dll';
function GetSecurityDescriptorOwnerP(pSecurityDescriptor: Pointer; out pOwner: Pointer;
  out lpbOwnerDefaulted: BOOL): BOOL; stdcall; external 'advapi32.dll' name 'GetSecurityDescriptorOwner';
function GetSecurityDescriptorDaclP(pSecurityDescriptor: Pointer; out lpbDaclPresent: BOOL;
  out pDacl: Pointer; out lpbDaclDefaulted: BOOL): BOOL; stdcall;
  external 'advapi32.dll' name 'GetSecurityDescriptorDacl';
function LocalFreePtr(Mem: Pointer): Pointer; stdcall; external 'kernel32.dll' name 'LocalFree';
function IsUserAnAdmin: BOOL; stdcall; external 'shell32.dll';

function HardenDllSearch: Boolean;
begin
  Result := SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32);
end;

function LoadSystemLibrary(const Name: UnicodeString): HMODULE;
begin
  Result := LoadLibraryExW(PWideChar(Name), 0, LOAD_LIBRARY_SEARCH_SYSTEM32);
end;

function IsProcessElevated: Boolean;
begin
  Result := IsUserAnAdmin;
end;

function IsReparsePoint(const Path: string): Boolean;
var
  Attr: DWORD;
begin
  Attr := GetFileAttributesW(PWideChar(UnicodeString(Path)));
  Result := (Attr <> INVALID_FILE_ATTRIBUTES) and ((Attr and FILE_ATTRIBUTE_REPARSE_POINT) <> 0);
end;

function HasTrustedOwner(const Path: string): Boolean;
var
  Owner, SD: Pointer;
begin
  Result := False;
  Owner := nil;
  SD := nil;
  if GetNamedSecurityInfoW(PWideChar(UnicodeString(Path)), SE_FILE_OBJECT,
    OWNER_SECURITY_INFORMATION, @Owner, nil, nil, nil, SD) <> ERROR_SUCCESS then
    Exit;
  try
    Result := (Owner <> nil) and (IsWellKnownSid(Owner, WinBuiltinAdministratorsSid) or
      IsWellKnownSid(Owner, WinLocalSystemSid));
  finally
    LocalFreePtr(SD);
  end;
end;

procedure ApplySecureAcl(const Dir: string; SD: Pointer);
var
  Owner, Dacl: Pointer;
  Present, Defaulted: BOOL;
  Err: DWORD;
begin
  if not GetSecurityDescriptorOwnerP(SD, Owner, Defaulted) or
     not GetSecurityDescriptorDaclP(SD, Present, Dacl, Defaulted) then
    raise ESecurity.Create('Invalid security descriptor');
  Err := SetNamedSecurityInfoW(PWideChar(UnicodeString(Dir)), SE_FILE_OBJECT,
    OWNER_SECURITY_INFORMATION or DACL_SECURITY_INFORMATION or PROTECTED_DACL_SECURITY_INFORMATION,
    Owner, nil, Dacl, nil);
  if Err <> ERROR_SUCCESS then
    raise ESecurity.CreateFmt('Cannot secure "%s": %s', [Dir, SysErrorMessage(Err)]);
end;

{ Renames the entry itself; for a junction or symlink this moves the link, not
  its target. }
procedure Quarantine(const Path: string);
var
  NewName: string;
begin
  NewName := Path + '.untrusted-' + FormatDateTime('yyyymmddhhnnsszzz', Now);
  if not MoveFileW(PWideChar(UnicodeString(Path)), PWideChar(UnicodeString(NewName))) then
    raise ESecurity.CreateFmt('Untrusted "%s" cannot be moved aside: %s',
      [Path, SysErrorMessage(GetLastError)]);
end;

procedure EnsureSecureDir(const Dir: string; const Names: array of string);
var
  D, Path: string;
  N: string;
  SD: Pointer;
  SA: TSecurityAttributes;
begin
  if not IsProcessElevated then
    raise ESecurity.Create('EnsureSecureDir must run elevated');
  D := ExcludeTrailingPathDelimiter(Dir);
  if not ConvertStringSecurityDescriptorToSecurityDescriptorW(SecureDirSddl, SDDL_REVISION_1, SD, nil) then
    raise ESecurity.CreateFmt('Cannot build security descriptor: %s', [SysErrorMessage(GetLastError)]);
  try
    if IsReparsePoint(D) then
      Quarantine(D);   // a junction to elsewhere: never write through it
    if not DirectoryExists(D) then
    begin
      SA.nLength := SizeOf(SA);
      SA.lpSecurityDescriptor := SD;
      SA.bInheritHandle := False;
      if not CreateDirectoryW(PWideChar(UnicodeString(D)), @SA) then
        raise ESecurity.CreateFmt('Cannot create "%s": %s', [D, SysErrorMessage(GetLastError)]);
    end
    else
      ApplySecureAcl(D, SD);   // repairs folders created with the inherited, too open ACL
  finally
    LocalFreePtr(SD);
  end;

  for N in Names do
  begin
    Path := D + '\' + N;
    if (GetFileAttributesW(PWideChar(UnicodeString(Path))) <> INVALID_FILE_ATTRIBUTES) and
       (IsReparsePoint(Path) or not HasTrustedOwner(Path)) then
      Quarantine(Path);
  end;
end;

end.
