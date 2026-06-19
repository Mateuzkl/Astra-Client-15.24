; KoliseuOT Client — Inno Setup installer (DRAFT)
; Build with Inno Setup 6 (ISCC.exe koliseuot.iss).
;
; Expects a "release" folder (RELEASE_DIR below) containing:
;   AstraClient.exe              (rename of AstraClient_dx_x64.exe, or keep the dx name)
;   libGLESv2.dll  libEGL.dll  d3dcompiler_47.dll  vulkan-1.dll   (vendored ANGLE)
;   data.zip                     (zip of init.lua + modules/ + mods/ + data/ + layouts/)
;
; Notes / decisions (see docs/DISTRIBUICAO_E_UPDATER.md):
;  - Installs to {localappdata}\KoliseuOT\Client  -> NO admin/UAC, and the updater can
;    overwrite the exe/data (Program Files would need elevation per write).
;  - First launch runs the in-client updater (needs data.zip + Services.updater set).
;  - The exe already embeds the taskbar/Explorer icon (src/otcicon.ico), so shortcuts
;    inherit it.

#define MyAppName "KoliseuOT"
#define MyAppExeName "AstraClient_dx_x64.exe"
#define MyAppVersion "3.1"
#define MyAppPublisher "KoliseuOT"
#define MyAppURL "https://koliseuot.com"
; Folder containing the release artifacts (override with: ISCC /DRELEASE_DIR=path koliseuot.iss)
#ifndef RELEASE_DIR
  #define RELEASE_DIR "..\..\release"
#endif

[Setup]
AppId={{8E7A1C42-KOLISEU-OT-CLIENT-0001}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={localappdata}\{#MyAppName}\Client
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=KoliseuOT-Setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; SetupIconFile={#RELEASE_DIR}\client.ico   ; optional: installer's own icon
; UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "{#RELEASE_DIR}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RELEASE_DIR}\libGLESv2.dll";  DestDir: "{app}"; Flags: ignoreversion
Source: "{#RELEASE_DIR}\libEGL.dll";     DestDir: "{app}"; Flags: ignoreversion
Source: "{#RELEASE_DIR}\d3dcompiler_47.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RELEASE_DIR}\vulkan-1.dll";   DestDir: "{app}"; Flags: ignoreversion
Source: "{#RELEASE_DIR}\data.zip";       DestDir: "{app}"; Flags: ignoreversion
; If you ship a separate test client, drop it in the release folder and uncomment:
; Source: "{#RELEASE_DIR}\AstraClient_test_x64.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
