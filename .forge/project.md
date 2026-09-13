# Project — hex-launcher (ex LoL Lang Switcher, ex Hextech Launcher)
**Generated:** 2026-09-13

## Stack
- Language: PowerShell 5.1 (Windows PowerShell — pas de `&&`, `??`, ternaire), Batch (`install.bat`)
- Framework / CMS: aucun — WinForms (`System.Windows.Forms`, `System.Drawing`) pour le splash et le sélecteur de langues
- Runtime / version: Windows 10/11, `powershell.exe` v1.0 (System32) appelé avec `-NoProfile -ExecutionPolicy Bypass`
- DB: aucune — état dans `config.json` (généré, gitignoré) et `locales.json` (catalogue versionné)
- Server: aucun — outil desktop local, pas de dépendance réseau

## Key structure
```
lol/  (dépôt hex-launcher)
├── install.bat                  # Point d'entrée utilisateur : lance app\install.ps1 sans console
├── LISEZMOI.txt                 # Démarrage rapide FR/EN
├── README.md / .fr.md / .ja.md  # Mention légale Riot en tête
├── LICENSE, .gitignore, .gitattributes
├── tests/                       # Pester 3.4 : *.tests.ps1 + companion-test-helpers.ps1 — Invoke-Pester -Path tests (dev, hors release)
└── app/                         # Tout le moteur — les scripts sont relatifs à $PSScriptRoot
    ├── install.ps1              # Assistant d'installation unique (WinForms thème LoL, machine à états pure testée, hooks CompanionUi)
    ├── detect-config.ps1        # Génère config.json (Riot Client, yaml, applis compagnon détectées via le catalogue) — Main gardé
    ├── manage-companion-app.ps1 # Choix multi-applis compagnon, installation des manquantes, désinstallation sur demande — Main gardé
    ├── create-shortcuts.ps1     # Raccourcis langue × compagnon (.lnk sur le Bureau) — Main gardé
    ├── launch-lol.ps1           # Le lanceur : splash, kill Riot, réécrit locale, ferme les autres compagnons, lance -Companion
    ├── make-flag-icons.ps1      # Génère ico/hex-launcher.ico (H monogramme original) et les 27 variantes drapeau
    ├── lib/theme.lib.ps1        # Palette LoL + fabriques de contrôles WinForms thématisés
    ├── lib/splash.lib.ps1       # Splash animé partagé (sur le thème), TopMost/visibilité commutables
    ├── lib/companion-app.lib.ps1  # Catalogue, registre lecture seule, signature RDN, sonde d'état
    ├── lib/launch-config.lib.ps1  # config.json (companionApps, migration), catalogues JSON, process des autres compagnons
    ├── locales.json             # Catalogue des locales Riot (code, label natif, default)
    ├── companion-apps.json      # Catalogue des applis compagnon (signer, processNames, launch, detect, install, uninstall)
    ├── config.json              # Chemins machine (gitignoré, jamais écrasé sans -Force)
    └── ico/                     # hex-launcher.ico + hex-launcher-xx.ico (originaux, aucun visuel Riot)
```

## Entry points
- `install.bat` → `app\install.ps1` (assistant unique ; codes 0 ok, 1 erreur, 2 annulé). Les trois scripts moteur restent exécutables seuls en mode script
- `manage-companion-app.ps1 -Apps <ids|none> [-UninstallOthers] [-Force] [-DryRun]` (mode script)
- `create-shortcuts.ps1 -Locales ja_JP,ko_KR -Companions blitz,opgg` ; raccourci → `launch-lol.ps1 -Locale xx_XX [-Companion <id>]`
- Raccourci `.lnk` → `powershell.exe -WindowStyle Hidden -File launch-lol.ps1 -Locale xx_XX`
- `create-shortcuts.ps1 -Locales ja_JP,ko_KR` (mode script sans dialogue)

## Detected conventions
- Naming: fonctions PowerShell `Verb-Noun` approuvés (`Read-LaunchConfig`, `Test-CompanionAppEnabled`, `Find-CompanionApp`) ; booléens `Test-*` ; fichiers kebab-case ; commentaires et messages utilisateur en français, README trilingue
- Architecture: scripts autonomes + une lib dot-sourcée (`lib/`) partagée par detect-config et manage-companion-app ; bloc Main gardé par `$MyInvocation.InvocationName -ne '.'` pour être testable ; chaque script = sections `# ---- Config / Splash / Étapes / Main` avec fonctions pures en haut et un bloc Main en bas ; config lue via `ConvertFrom-Json` avec le pattern `| ForEach-Object { $_ }` pour déplier les tableaux (PS 5.1)
- Error handling: `throw` sur config manquante ; dégradation gracieuse sur appli compagnon introuvable (warning dans le splash, jeu lancé quand même) ; `-ErrorAction SilentlyContinue` sur les kills de process ; `-DryRun` pour tester sans effet de bord
- Encodage: scripts `.ps1` en **UTF-8 avec BOM** (obligatoire, sinon le splash affiche des caractères corrompus) ; `config.json` écrit en UTF-8 sans BOM
- Extensibilité: `companion-apps.json` (ordre = priorité de détection ; stratégies winget/download/browser ; uninstall silent/interactive) ; `$FlagDrawings` dans `make-flag-icons.ps1`
- Tests: Pester 3.4 (livré avec PS 5.1), mocks sur registre/process/réseau, `Assert-MockCalled -Scope It -Exactly` (un Mock dans un It survit jusqu'à la fin du Describe) ; `.Count` sur un PSCustomObject seul rend vide → envelopper avec `@()` ; `return` déroule un tableau vide en rien → l'appelant enveloppe toujours dans `@()`, jamais de virgule unaire (elle imbrique quand l'appelant fait déjà `@()`)
- Messages console dans une fonction à valeur de retour → `Write-Host`, jamais une chaîne nue (elle polluerait le pipeline de retour)

## Critical files
- `companion-apps.json` — point d'extension unique pour une appli compagnon ; Porofessor passe par `OverwolfLauncher.exe -launchapp <extensionId>`, sa désinstallation est interactive (menu Overwolf, Overwolf coché par défaut)
- `lib/companion-app.lib.ps1` — `Get-UninstallRegistryEntries` est la seule fonction qui touche au registre (lecture seule, 3 ruches) ; `Wait-CompanionState` sonde l'état car les codes de sortie des installeurs ne sont pas fiables (NSIS asynchrone, Overwolf 1223)
- `launch-lol.ps1` — `Set-LeagueLocale` ne réécrit que `settings.locale` du yaml Riot (jamais `default_locale`) ; `$RiotProcessNames` liste des process à tuer avant réécriture
- `config.json` — schéma `companionApps: [ { id, name, path, arguments } ]` ; l'ancien bloc `companionApp` est migré à la lecture (`Read-LaunchConfig`). Un raccourci = une langue × un compagnon
- Sécurité (revue 2026-09-13) : refus de tourner élevé ; tout binaire exécuté (installeur téléchargé, désinstalleur du registre) vérifié par `Test-CompanionBinaryTrusted` (chemin absolu, .exe, signature RDN organisation + pays) ; `Start-Process` jamais avec `-Wait` (arbre de process) → `Start-CompanionProcess` avec échéance
- `create-shortcuts.ps1` — `Test-LaunchConfig` valide la config au moment de l'installation

## Tools & access
- Available MCPs: ClickUp, claude-in-chrome, phpstorm (non pertinent ici)
- Propriété intellectuelle : aucune icône/logo Riot, aucune marque Riot dans le nom (« Hextech » déposée) ; mention Legal Jibber Jabber dans les README ; icônes originales générées par make-flag-icons.ps1
- Registre et configuration Windows : lecture seule, interdiction d'écrire (règle utilisateur, CLAUDE.md global)
- External documentation: `RiotClientInstalls.json` (`%ProgramData%\Riot Games\`) et `league_of_legends.live.product_settings.yaml` — fichiers officiels Riot lus/écrits par le lanceur ; README.md du projet (référence fonctionnelle complète)
