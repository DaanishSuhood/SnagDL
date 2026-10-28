; SnagDL installer (Inno Setup 6). Build it with .\publish.ps1, which compiles the app first and passes the
; version from SnagDL.ahk:  ISCC /DAppVersion=1.2.3 installer\SnagDL.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "SnagDL"
#define AppExe "SnagDL.exe"
#define AppDescription "See a video's formats and size before downloading it with yt-dlp"

[Setup]
; Never change AppId: it is how later versions find and upgrade this install.
AppId={{CF8E1262-AE49-435E-84DB-A8033DE48FB9}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
AppPublisherURL=https://github.com/DaanishSuhood/SnagDL
AppSupportURL=https://github.com/DaanishSuhood/SnagDL/issues
AppUpdatesURL=https://github.com/DaanishSuhood/SnagDL/releases/latest
VersionInfoVersion={#AppVersion}
VersionInfoDescription={#AppName} Setup
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
; SnagDL writes yt-dlp, ffmpeg, Node.js and its log beside its own exe, so it is installed per user, where it can
; write: {autopf} is then %LOCALAPPDATA%\Programs, and Setup needs no UAC prompt.
PrivilegesRequired=lowest
; The tools Get Tools fetches are all 64-bit builds.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
SetupIconFile=..\SnagDL.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/ultra64
SolidCompression=yes
; Close a running copy when upgrading; don't relaunch it afterwards (the finish page offers that).
CloseApplications=yes
RestartApplications=no
OutputDir=..\artifacts\installer
OutputBaseFilename={#AppName}-Setup-{#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; Both ticked by default.
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startmenuicon"; Description: "Create a &Start menu shortcut"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\artifacts\publish\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; Comment: "{#AppDescription}"; Tasks: startmenuicon
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Comment: "{#AppDescription}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; Get Tools downloads these after install, so the uninstaller doesn't know about them unless they are named here.
; They are all fetched again by Get Tools, so unlike DriverHaven's backups there is nothing worth asking about.
; Upgrades leave them in place.
[UninstallDelete]
Type: files; Name: "{app}\yt-dlp.exe"
Type: files; Name: "{app}\ffmpeg.exe"
Type: files; Name: "{app}\ffprobe.exe"
Type: files; Name: "{app}\node.exe"
Type: files; Name: "{app}\last_download.log"
Type: dirifempty; Name: "{app}"
