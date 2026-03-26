#define MyAppName "NeuroMorphicToolkit"
#define MyAppPublisher "Yoshi Martodihardjo"
#define MyAppExeName "neuro_toolkit.exe"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputBaseFilename=nmtk-{#MyAppVersion}-windows-setup
OutputDir=..\..\dist
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
; Main Flutter application
Source: "..\..\neuro_toolkit\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs; Excludes: "python\*,modules\*"

; Bundled Python
Source: "..\..\neuro_toolkit\build\windows\x64\runner\Release\python\*"; DestDir: "{app}\python"; Flags: ignoreversion recursesubdirs

; Bundled Submodules
Source: "..\..\neuro_toolkit\build\windows\x64\runner\Release\modules\*"; DestDir: "{app}\modules"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
