; Installeur par utilisateur de hex-launcher (Inno Setup 6) — compilé par tools\make-release.ps1, jamais à la main :
;   ISCC.exe /DAppVersion=0.4.0 /DSourceDir=<dossier préparé> /DOutputDir=<dist> /DWizardImage=<png> hex-launcher.iss
;
; Sans droits administrateur : installe dans %LOCALAPPDATA%\Programs\hex-launcher, comme Blitz ou DPM. Le lanceur refuse
; le mode administrateur, Program Files lui est donc fermé. Les données (config.json, journal, icônes composées) vivent
; dans %LOCALAPPDATA%\hex-launcher\ : la désinstallation les laisse, une réinstallation les retrouve.
;
; L'entrée « Applications installées » (clé HKCU\...\Uninstall) est écrite par Inno Setup lui-même, pas par nos scripts.

#ifndef AppVersion
  #error Passer /DAppVersion=x.y.z (tools\make-release.ps1 le fait)
#endif
#ifndef SourceDir
  #error Passer /DSourceDir=<dossier préparé par make-release>
#endif
#ifndef WizardImage
  #error Passer /DWizardImage=<png du logo HL> (tools\make-release.ps1 l'extrait de l'icône)
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
; INVARIANT : AppId ne change jamais — c'est lui qui fait d'une nouvelle version une mise à jour de la précédente
AppId={{C11135E5-D99E-446B-BD28-78A06332E927}
AppName=Hex Launcher
AppVersion={#AppVersion}
AppVerName=Hex Launcher {#AppVersion}
AppPublisher=jeanchristoph
AppPublisherURL=https://github.com/jeanchristoph/hex-launcher
AppSupportURL=https://github.com/jeanchristoph/hex-launcher/issues
AppUpdatesURL=https://github.com/jeanchristoph/hex-launcher/releases
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\hex-launcher
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
UsePreviousAppDir=yes
OutputDir={#OutputDir}
OutputBaseFilename=hex-launcher-setup-{#AppVersion}
; Logo HL nu, sans pastille, centré : icône du fichier d'installation et de sa fenêtre (image de l'assistant tirée du
; même .ico par make-release)
SetupIconFile=installer-logo.ico
WizardSmallImageFile={#WizardImage}
UninstallDisplayIcon={app}\app\ico\hex-launcher-setup.ico
UninstallDisplayName=Hex Launcher
LicenseFile={#SourceDir}\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Jamais de fermeture par le Restart Manager : pendant une mise à jour automatique, c'est le lanceur lui-même qui
; attend la fin de l'installeur — le fermer interromprait la reprise du lancement. Il a quitté le dossier du code avant.
CloseApplications=no

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ja"; MessagesFile: "compiler:Languages\Japanese.isl"

[CustomMessages]
fr.OpenSetup=Ouvrir l'assistant Hex Launcher
en.OpenSetup=Open the Hex Launcher assistant
ja.OpenSetup=Hex Launcher のアシスタントを開く

[InstallDelete]
; Une mise à jour repart d'un app\ propre : un fichier retiré d'une version ne traîne pas dans la suivante.
; Sans risque : aucune donnée n'y est écrite à l'usage.
Type: filesandordirs; Name: "{app}\app"
; Jusqu'à 0.4.x, « Hex Launcher » était seul à la racine du menu Démarrer : il rejoint le dossier des raccourcis de jeu
Type: files; Name: "{userprograms}\Hex Launcher.lnk"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; Dans le dossier « Hex Launcher » du menu Démarrer, à côté des raccourcis de jeu posés par l'assistant
Name: "{userprograms}\Hex Launcher\Hex Launcher"; Filename: "{app}\setup.bat"; WorkingDir: "{app}"; IconFilename: "{app}\app\ico\hex-launcher-setup.ico"; Flags: runminimized

[Run]
; Pas d'assistant après une mise à jour silencieuse : le lancement du jeu reprend de lui-même
Filename: "{app}\setup.bat"; WorkingDir: "{app}"; Description: "{cm:OpenSetup}"; Flags: postinstall nowait skipifsilent shellexec runminimized

[UninstallRun]
; Retire les raccourcis de jeu et « Hex Launcher » du Bureau et du menu Démarrer : sans le lanceur, ils ne mèneraient
; plus nulle part
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\app\remove-shortcuts.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "RemoveShortcuts"
