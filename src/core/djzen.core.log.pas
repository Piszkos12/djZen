unit djzen.core.log;

{ Minimal thread-safe append-only file logger.
  Opens and closes the file on every write: log volume is low and this keeps
  the log intact if djZen is killed. }

{$mode objfpc}{$H+}

interface

type
  TLogLevel = (llDebug, llInfo, llWarn, llError);

procedure LogInit(const AFileName: string);
procedure Log(Level: TLogLevel; const Msg: string);
procedure LogInfo(const Msg: string);
procedure LogWarn(const Msg: string);
procedure LogError(const Msg: string);

implementation

uses
  SysUtils, SyncObjs;

const
  LevelText: array[TLogLevel] of string = ('DEBUG', 'INFO ', 'WARN ', 'ERROR');

var
  Lock: TCriticalSection;
  FileName: string;

procedure LogInit(const AFileName: string);
begin
  Lock.Enter;
  try
    FileName := AFileName;
    if FileName <> '' then
      ForceDirectories(ExtractFileDir(FileName));
  finally
    Lock.Leave;
  end;
end;

procedure Log(Level: TLogLevel; const Msg: string);
var
  F: TextFile;
  Line: string;
begin
  Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' ' + LevelText[Level] + ' ' + Msg;
  Lock.Enter;
  try
    if FileName = '' then
      Exit;
    try
      AssignFile(F, FileName);
      if FileExists(FileName) then
        Append(F)
      else
        Rewrite(F);
      try
        WriteLn(F, Line);
      finally
        CloseFile(F);
      end;
    except
      // logging must never break the caller
    end;
  finally
    Lock.Leave;
  end;
end;

procedure LogInfo(const Msg: string);
begin
  Log(llInfo, Msg);
end;

procedure LogWarn(const Msg: string);
begin
  Log(llWarn, Msg);
end;

procedure LogError(const Msg: string);
begin
  Log(llError, Msg);
end;

initialization
  Lock := TCriticalSection.Create;

finalization
  Lock.Free;

end.
