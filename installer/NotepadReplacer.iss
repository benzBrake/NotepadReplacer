#define MyAppName "Notepad Replacer"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Notepad Replacer"
#define MyAppExeName "NotepadReplacerLauncher-x64.exe"
#ifndef BuildConfiguration
  #define BuildConfiguration "Release"
#endif

[Setup]
AppId={{9F5E1BD7-34A9-4B2E-9E44-4E12B9BFA8F0}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={sd}\Program Files\NotepadReplacer
DisableDirPage=yes
DisableProgramGroupPage=yes
DefaultGroupName={#MyAppName}
OutputDir=..\dist
OutputBaseFilename=NotepadReplacerSetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x86 x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Uninstallable=yes
UninstallDisplayName={#MyAppName}
SetupIconFile=..\replacer.ico
LicenseFile=LicenseEN.txt
LanguageDetectionMethod=locale

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"; LicenseFile: "LicenseEN.txt"
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"; LicenseFile: "LicenseZH.txt"

[CustomMessages]
english.SelectTitle=Select replacement program
english.SelectDescription=Choose the EXE file that will replace Windows Notepad.
english.SelectPrompt=Replacement program:
english.StoreWarning=Warning: installation will remove the Microsoft Store version of Notepad. It will not be restored automatically during uninstall; you will need to reinstall it from the Microsoft Store. Continue?
english.InvalidTarget=Please select an existing EXE file as the replacement program.
english.ExistingIfeo=An IFEO Debugger configuration for notepad.exe already exists:%n%n%s%n%nInstallation will stop to avoid overwriting it.
english.StoreRemoveFailed=Failed to remove the Microsoft Store version of Notepad. Installation has been cancelled.
english.IfeoWriteFailed=Failed to write the IFEO configuration. Installation will be rolled back.
english.ContextMenuRegisterFailed=The File Explorer context-menu extension could not be registered. Details were written to:%n%n%s
english.UninstallNotice=Notepad Replacer has been uninstalled. The Microsoft Store version of Notepad is not restored automatically; reinstall it from the Microsoft Store if needed.
english.MenuTitle=Open with Notepad
chinesesimp.SelectTitle=选择替代程序
chinesesimp.SelectDescription=请选择用于替代 Windows 记事本的 EXE 文件。
chinesesimp.SelectPrompt=替代程序：
chinesesimp.StoreWarning=警告：安装将删除 Microsoft Store 版 Notepad。卸载时不会自动恢复，之后需要通过 Microsoft Store 手动安装。是否继续？
chinesesimp.InvalidTarget=请选择一个存在的 EXE 文件作为替代程序。
chinesesimp.ExistingIfeo=检测到 notepad.exe 已存在 IFEO Debugger 配置：%n%n%s%n%n为避免覆盖现有配置，安装将终止。
chinesesimp.StoreRemoveFailed=删除 Microsoft Store 版 Notepad 失败，安装已中止。
chinesesimp.IfeoWriteFailed=写入 IFEO 配置失败，安装将回滚。
chinesesimp.ContextMenuRegisterFailed=文件资源管理器右键菜单扩展注册失败。详细错误已写入：%n%n%s
chinesesimp.UninstallNotice=Notepad Replacer 已卸载。Microsoft Store 版 Notepad 不会自动恢复，请按需从 Microsoft Store 重新安装。
chinesesimp.MenuTitle=使用记事本打开

[Files]
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion restartreplace
Source: "..\ADDITIONAL-TERMS.md"; DestDir: "{app}"; Flags: ignoreversion restartreplace
Source: "..\dist\x86\{#BuildConfiguration}\NotepadReplacerLauncher.exe"; DestDir: "{app}"; DestName: "NotepadReplacerLauncher-x86.exe"; Flags: ignoreversion restartreplace
Source: "..\dist\x64\{#BuildConfiguration}\NotepadReplacerLauncher.exe"; DestDir: "{app}"; DestName: "NotepadReplacerLauncher-x64.exe"; Flags: ignoreversion restartreplace; Check: IsWin64
Source: "..\replacer.ico"; DestDir: "{app}"; Flags: ignoreversion restartreplace; Check: IsWin64
Source: "..\dist\context-menu-package\NotepadReplacer.msix"; DestDir: "{app}\context-menu"; Flags: ignoreversion restartreplace; Check: IsWin64
Source: "..\dist\context-menu-package\NotepadReplacer.cer"; DestDir: "{app}\context-menu"; Flags: ignoreversion restartreplace; Check: IsWin64
Source: "RegisterContextMenu.ps1"; DestDir: "{app}\context-menu"; Flags: ignoreversion restartreplace; Check: IsWin64
Source: "RemoveNotepad.ps1"; DestDir: "{app}"; Flags: deleteafterinstall ignoreversion dontcopy

[Icons]
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
var
  TargetPage: TInputFileWizardPage;
  StoreRemovalCompleted: Boolean;
  Ifeo32Written: Boolean;
  Ifeo64Written: Boolean;
  TargetWritten: Boolean;
  TargetPath: String;

procedure SHChangeNotify(wEventId, uFlags: Integer; dwItem1, dwItem2: Integer);
  external 'SHChangeNotify@shell32.dll stdcall';

function QuoteArg(const Value: String): String;
var
  I: Integer;
  Slashes: Integer;
begin
  Result := '"';
  Slashes := 0;
  for I := 1 to Length(Value) do begin
    if Value[I] = '\' then
      Slashes := Slashes + 1
    else if Value[I] = '"' then begin
      Result := Result + StringOfChar('\', Slashes * 2 + 1) + '"';
      Slashes := 0;
    end else begin
      Result := Result + StringOfChar('\', Slashes) + Value[I];
      Slashes := 0;
    end;
  end;
  Result := Result + StringOfChar('\', Slashes * 2) + '"';
end;

function IfeoSubKey(): String;
begin
  Result := 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\notepad.exe';
end;

function ConfigSubKey(): String;
begin
  Result := 'SOFTWARE\NotepadReplacer';
end;

function RunContextMenuRegistration(const Action: String): Boolean;
var
  Code: Integer;
  Script: String;
  Params: String;
begin
  Script := AddBackslash(ExpandConstant('{app}')) + 'context-menu\RegisterContextMenu.ps1';
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
    QuoteArg(Script) + ' -Action ' + Action + ' -InstallDirectory ' + QuoteArg(ExpandConstant('{app}'));
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
end;

function RegisterContextMenu(): Boolean;
begin
  Result := RunContextMenuRegistration('Install');
end;

function UnregisterContextMenu(): Boolean;
begin
  Result := RunContextMenuRegistration('Uninstall');
end;

procedure RefreshShell;
begin
  SHChangeNotify($08000000, 0, 0, 0);
end;

procedure RemoveContextMenuRegistration;
begin
  if not IsWin64 then Exit;
  UnregisterContextMenu();
  RefreshShell;
end;

function ReadDebugger(const View: Integer; var Value: String): Boolean;
begin
  if IsWin64 and (View = 64) then
    Result := RegQueryStringValue(HKLM64, IfeoSubKey(), 'Debugger', Value)
  else
    Result := RegQueryStringValue(HKLM32, IfeoSubKey(), 'Debugger', Value);
end;

function ExpectedDebugger(const View: Integer): String;
var
  Launcher: String;
begin
  if IsWin64 and (View = 64) then
    Launcher := AddBackslash(ExpandConstant('{app}')) + 'NotepadReplacerLauncher-x64.exe'
  else
    Launcher := AddBackslash(ExpandConstant('{app}')) + 'NotepadReplacerLauncher-x86.exe';
  Result := QuoteArg(Launcher) + ' ' + QuoteArg(TargetPath);
end;

function ExpectedLauncherPrefix(const View: Integer): String;
var
  Launcher: String;
begin
  if IsWin64 and (View = 64) then
    Launcher := AddBackslash(ExpandConstant('{app}')) + 'NotepadReplacerLauncher-x64.exe'
  else
    Launcher := AddBackslash(ExpandConstant('{app}')) + 'NotepadReplacerLauncher-x86.exe';
  Result := QuoteArg(Launcher) + ' ';
end;

function IsOwnedDebugger(const View: Integer; const Value: String): Boolean;
var
  Prefix: String;
begin
  Prefix := ExpectedLauncherPrefix(View);
  Result := (Length(Value) >= Length(Prefix)) and
    (CompareText(Copy(Value, 1, Length(Prefix)), Prefix) = 0);
end;

procedure DeleteIfeoDebugger(const View: Integer);
begin
  if IsWin64 and (View = 64) then begin
    RegDeleteValue(HKLM64, IfeoSubKey(), 'Debugger');
    RegDeleteKeyIfEmpty(HKLM64, IfeoSubKey());
  end else begin
    RegDeleteValue(HKLM32, IfeoSubKey(), 'Debugger');
    RegDeleteKeyIfEmpty(HKLM32, IfeoSubKey());
  end;
end;

function CheckExistingIfeo(): Boolean;
var
  Existing: String;
begin
  Result := True;
  if ReadDebugger(32, Existing) and (Existing <> '') then begin
    if IsOwnedDebugger(32, Existing) then begin
      DeleteIfeoDebugger(32);
    end else begin
      MsgBox(Format(CustomMessage('ExistingIfeo'), [Existing]), mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;
  if IsWin64 and ReadDebugger(64, Existing) and (Existing <> '') then begin
    if IsOwnedDebugger(64, Existing) then begin
      DeleteIfeoDebugger(64);
    end else begin
      MsgBox(Format(CustomMessage('ExistingIfeo'), [Existing]), mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function RemoveStoreNotepad(): Boolean;
var
  ResultCode: Integer;
  ScriptPath: String;
  Params: String;
begin
  ExtractTemporaryFile('RemoveNotepad.ps1');
  ScriptPath := AddBackslash(ExpandConstant('{tmp}')) + 'RemoveNotepad.ps1';
  Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' + QuoteArg(ScriptPath);
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  if not Result then
    MsgBox(CustomMessage('StoreRemoveFailed'), mbError, MB_OK);
end;

function WriteTargetConfiguration(): Boolean;
begin
  if IsWin64 then
    Result := RegWriteStringValue(HKLM64, ConfigSubKey(), 'TargetPath', TargetPath)
  else
    Result := RegWriteStringValue(HKLM32, ConfigSubKey(), 'TargetPath', TargetPath);
end;

procedure RemoveTargetConfiguration;
begin
  if IsWin64 then begin
    RegDeleteValue(HKLM64, ConfigSubKey(), 'TargetPath');
    RegDeleteKeyIfEmpty(HKLM64, ConfigSubKey());
  end else begin
    RegDeleteValue(HKLM32, ConfigSubKey(), 'TargetPath');
    RegDeleteKeyIfEmpty(HKLM32, ConfigSubKey());
  end;
end;

procedure RollbackInstall;
begin
  RemoveContextMenuRegistration();
  if Ifeo32Written then
    DeleteIfeoDebugger(32);
  if Ifeo64Written then
    DeleteIfeoDebugger(64);
  if TargetWritten then
    RemoveTargetConfiguration;
  DeleteFile(AddBackslash(ExpandConstant('{app}')) + 'NotepadReplacerLauncher-x86.exe');
  DeleteFile(AddBackslash(ExpandConstant('{app}')) + 'NotepadReplacerLauncher-x64.exe');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = TargetPage.ID then begin
    TargetPath := TargetPage.Values[0];
    if (TargetPath = '') or (LowerCase(ExtractFileExt(TargetPath)) <> '.exe') or not FileExists(TargetPath) then begin
      MsgBox(CustomMessage('InvalidTarget'), mbError, MB_OK);
      Result := False;
      Exit;
    end;
    if MsgBox(CustomMessage('StoreWarning'), mbConfirmation, MB_YESNO) <> IDYES then
      Result := False;
    if Result and not CheckExistingIfeo() then
      Result := False;
  end;
end;

procedure InitializeWizard;
begin
  TargetPage := CreateInputFilePage(wpLicense,
    CustomMessage('SelectTitle'),
    CustomMessage('SelectDescription'),
    '');
  TargetPage.Add(CustomMessage('SelectPrompt'), '可执行文件 (*.exe)|*.exe|所有文件 (*.*)|*.*', '.exe');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Debugger: String;
begin
  if CurStep = ssInstall then begin
    StoreRemovalCompleted := RemoveStoreNotepad();
    if not StoreRemovalCompleted then
      Abort;
  end else if CurStep = ssPostInstall then begin
    Debugger := ExpectedDebugger(32);
    Ifeo32Written := True;
    if not RegWriteStringValue(HKLM32, IfeoSubKey(), 'Debugger', Debugger) then begin
      MsgBox(CustomMessage('IfeoWriteFailed'), mbError, MB_OK);
      RollbackInstall;
      Abort;
    end;
    if IsWin64 then begin
      Debugger := ExpectedDebugger(64);
      Ifeo64Written := True;
      if not RegWriteStringValue(HKLM64, IfeoSubKey(), 'Debugger', Debugger) then begin
        MsgBox(CustomMessage('IfeoWriteFailed'), mbError, MB_OK);
        RollbackInstall;
        Abort;
      end;
    end;
    TargetWritten := True;
    if not WriteTargetConfiguration() then begin
      MsgBox(CustomMessage('IfeoWriteFailed'), mbError, MB_OK);
      RollbackInstall;
      Abort;
    end;
    if IsWin64 and not RegisterContextMenu() then begin
      MsgBox(Format(CustomMessage('ContextMenuRegisterFailed'), [ExpandConstant('{commonappdata}\NotepadReplacer\context-menu.log')]), mbError, MB_OK);
      RollbackInstall;
      Abort;
    end else if IsWin64 then
      RefreshShell;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Existing: String;
begin
  if CurUninstallStep = usUninstall then begin
    TargetPath := '';
    if ReadDebugger(32, Existing) and (CompareText(Copy(Existing, 1, Length(ExpectedLauncherPrefix(32))), ExpectedLauncherPrefix(32)) = 0) then begin
      DeleteIfeoDebugger(32);
    end;
    if IsWin64 and ReadDebugger(64, Existing) and (CompareText(Copy(Existing, 1, Length(ExpectedLauncherPrefix(64))), ExpectedLauncherPrefix(64)) = 0) then begin
      DeleteIfeoDebugger(64);
    end;
    RemoveTargetConfiguration;
    RemoveContextMenuRegistration();
    MsgBox(CustomMessage('UninstallNotice'), mbInformation, MB_OK);
  end;
end;
