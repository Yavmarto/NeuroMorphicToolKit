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
Source: "..\..\neuro_toolkit\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

; Submodules (Source code)
; We exclude development artifacts to keep the installer size manageable.
#define SubmoduleExcludes ".git venv build __pycache__ node_modules .dart_tool frontend\build frontend\.dart_tool *.egg-info .mypy_cache .ruff_cache .pytest_cache"

Source: "..\..\..\..\neurocnl\*"; DestDir: "{app}\modules\neurocnl"; Flags: ignoreversion recursesubdirs; Excludes: "{#SubmoduleExcludes}"
Source: "..\..\..\..\Neuro-Dream-Hand\*"; DestDir: "{app}\modules\Neuro-Dream-Hand"; Flags: ignoreversion recursesubdirs; Excludes: "{#SubmoduleExcludes}"
Source: "..\..\..\..\Neurosim\*"; DestDir: "{app}\modules\Neurosim"; Flags: ignoreversion recursesubdirs; Excludes: "{#SubmoduleExcludes}"
Source: "..\..\..\..\Neurobench\*"; DestDir: "{app}\modules\Neurobench"; Flags: ignoreversion recursesubdirs; Excludes: "{#SubmoduleExcludes}"
Source: "..\..\..\..\Neurochip\*"; DestDir: "{app}\modules\Neurochip"; Flags: ignoreversion recursesubdirs; Excludes: "{#SubmoduleExcludes}"
Source: "..\..\..\..\Neurosense\*"; DestDir: "{app}\modules\Neurosense"; Flags: ignoreversion recursesubdirs; Excludes: "{#SubmoduleExcludes}"
Source: "..\..\..\..\Neurohub\*"; DestDir: "{app}\modules\Neurohub"; Flags: ignoreversion recursesubdirs; Excludes: "{#SubmoduleExcludes}"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
