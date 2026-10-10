; Instalador de Windows para NJB Proyectores (Inno Setup 6).
; Se compila con:  ISCC.exe /DAppVersion=1.2.3 windows\installer\njb-proyectores.iss
; La salida es dist\njb-proyectores-setup.exe

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define SourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
; GUID fijo: así cada versión nueva reemplaza a la anterior en lugar de duplicarla.
AppId={{7E1C4D2A-9B5F-4C6B-9F3E-2A6D81C04F57}}
AppName=NJB Proyectores
AppVersion={#AppVersion}
AppVerName=NJB Proyectores {#AppVersion}
AppPublisher=NJB
DefaultDirName={autopf}\NJB Proyectores
DefaultGroupName=NJB Proyectores
UninstallDisplayIcon={app}\proyectar.exe
OutputDir=..\..\dist
OutputBaseFilename=njb-proyectores-setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Para la actualización automática: cierra la app abierta y la vuelve a abrir.
CloseApplications=force
RestartApplications=no
DisableProgramGroupPage=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\NJB Proyectores"; Filename: "{app}\proyectar.exe"
Name: "{autodesktop}\NJB Proyectores"; Filename: "{app}\proyectar.exe"; Tasks: desktopicon

[Run]
; Se ejecuta al terminar, también en modo silencioso (actualización automática).
Filename: "{app}\proyectar.exe"; Description: "Abrir NJB Proyectores"; Flags: nowait postinstall
