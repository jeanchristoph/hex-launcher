# Project — hex-launcher (ex LoL Lang Switcher, ex Hextech Launcher)
**Generated:** 2026-09-13

## Stack
- Language: PowerShell 5.1 (Windows PowerShell — pas de `&&`, `??`, ternaire), Batch (`setup.bat`)
- Framework / CMS: aucun — WinForms (`System.Windows.Forms`, `System.Drawing`) pour le splash et le sélecteur de langues
- Runtime / version: Windows 10/11, `powershell.exe` v1.0 (System32) appelé avec `-NoProfile -ExecutionPolicy Bypass`
- DB: aucune — état dans `config.json` (généré, gitignoré) et `locales.json` (catalogue versionné)
- Server: aucun — outil desktop local, pas de dépendance réseau

## Key structure
```
lol/  (dépôt hex-launcher)
├── setup.bat                  # Point d'entrée utilisateur : lance app\setup.ps1 sans console
├── LISEZMOI.txt                 # Démarrage rapide FR/EN
├── README.md / .fr.md / .ja.md  # Mention légale Riot en tête
├── LICENSE, .gitignore, .gitattributes
├── tests/                       # Pester 3.4 : *.tests.ps1 + companion-test-helpers.ps1 — Invoke-Pester -Path tests (dev, hors release)
├── tools/                       # Dev, hors release : make-release.ps1 ; make-flag-icons.ps1 (29 .ico de app/ico depuis le SVG, resvg + drapeaux GDI+) ; logo/make-logo-svg.py + logo/hex-launcher-logo-drawing.png → logo/hex-launcher-logo.svg (logo HL, source de vérité ; Python, potrace, resvg) ; logo/hex_launcher_gear_multisize.ico + settings.png (engrenage, source fournie par l'utilisateur, copié tel quel en app/ico/hex-launcher-setup.ico)
└── app/                         # Tout le moteur — les scripts sont relatifs à $PSScriptRoot
    ├── setup.ps1              # Assistant de configuration unique (WinForms thème LoL, machine à états pure testée, hooks CompanionUi ; chemins Riot corrigeables page 1 avec Parcourir…)
    ├── detect-config.ps1        # Génère config.json (Riot Client, yaml, applis compagnon détectées via le catalogue) — Main gardé
    ├── manage-companion-app.ps1 # Choix multi-applis compagnon, installation des manquantes, désinstallation sur demande — Main gardé
    ├── create-shortcuts.ps1     # Raccourcis langue × compagnon (.lnk sur le Bureau) + « Hex Launcher » vers setup.bat (posé par l'assistant, icône ico\hex-launcher-setup.ico) — Main gardé
    ├── launch-lol.ps1           # Le lanceur : splash, ferme le client de jeu, pose la langue et lance le jeu par l'API locale du Riot Client (repli : chemin historique kill total + yaml + --launch-product, forcé par -NoLocalApi), ferme les autres compagnons, lance -Companion — Main gardé
    ├── lib/theme.lib.ps1        # Palette LoL + fabriques de contrôles WinForms thématisés
    ├── lib/splash.lib.ps1       # Splash animé partagé (sur le thème), TopMost/visibilité commutables, bouton d'action facultatif (Add-SplashAction)
    ├── lib/companion-app.lib.ps1  # Catalogue, registre lecture seule, signature RDN, sonde d'état
    ├── lib/launch-config.lib.ps1  # config.json (companionApps, migration), catalogues JSON, process des autres compagnons
    ├── lib/riot-client-api.lib.ps1 # API locale du Riot Client : lockfile, transport WinHTTP, langue et lancement d'un produit
    ├── lib/launch-log.lib.ps1   # Journal horodaté (launch.log) : une ligne par étape et par appel d'API, borné à 200 Ko
    ├── lib/riot-window.lib.ps1  # Fenêtre du Riot Client : la fermer une fois le jeu lancé (repli sur son icône)
    ├── lib/icon.lib.ps1         # Lecture/écriture .ico (entrées PNG ou DIB), chemins résolus à la PowerShell
    ├── lib/icon-badge.lib.ps1   # Pastille compagnon (disque couleur + lettre, haut-droite) composée sur chaque taille
    ├── lib/palette.lib.ps1      # Palette réduite (8 teintes) + atténuation ($PaletteMuting) partagées : drapeaux (générateur) et pastilles compagnon (runtime) ; voile mêlé en lumière linéaire = GDI+ HighQuality
    ├── lib/icon-set.lib.ps1     # Jeux d'icônes : Get-IconSets (sous-dossiers de ico\ avec hex-launcher.ico ou icon-source.json, ordre fixe $IconSetDisplayOrder), repli flat, préféré original-badges (présélection), Resolve-IconSet avec repli, Get-IconSetSource ; libellés traduits iconSet.<camelCase> côté setup (jeu externe league-client, badges)
    ├── lib/flag.lib.ps1         # Drapeaux GDI+ ($FlagDrawings, une définition pour les icônes et les pastilles pays) ; New-FlagBitmap neutre, résolveur de couleur optionnel injecté par le générateur
    ├── lib/riot-install.lib.ps1 # RiotClientInstalls.json (fichier officiel Riot, lecture seule) : Find-RiotClientPath, Find-LeagueClientPath (associated_client → LeagueClient.exe)
    ├── lib/i18n.lib.ps1         # Traductions : Resolve-UiLanguage, Initialize-Translation, Get-Text, Get-LocalizedValue
    ├── i18n/{fr,en,ja}.json     # Dictionnaires plats section.cle → texte, mêmes clés partout (test de catalogue)
    ├── locales.json             # Catalogue des locales Riot (code, label natif, default)
    ├── companion-apps.json      # Catalogue des applis compagnon (signer, processNames, launch, detect, install, uninstall)
    ├── config.json              # Chemins machine (gitignoré, jamais écrasé sans -Force)
    └── ico/                     # hex-launcher-setup.ico (engrenage du raccourci de configuration, commun) ; jeux d'icônes : un dossier par jeu (flat/ = défaut, généré par tools/make-flag-icons.ps1 ; classic/ = anciennes), hex-launcher[-xx].ico ; original/ et original-badges/ = icon-source.json seul (icône de LeagueClient.exe référencée, nue ou avec pastilles pays + compagnon) ; <jeu>/companion/ généré (gitignoré, hors release)
```

## Entry points
- `setup.bat` → `app\setup.ps1` (assistant unique ; codes 0 ok, 1 erreur, 2 annulé ; page Raccourcis : langues × compagnons + jeu d'icônes avec aperçu). Les trois scripts moteur restent exécutables seuls en mode script
- `-Language fr|en|ja` (optionnel) sur `setup.ps1` et les trois scripts moteur ; défaut : `Get-UICulture` de Windows, repli anglais ; sélecteur dans la fenêtre
- `manage-companion-app.ps1 -Apps <ids|none> [-UninstallOthers] [-Force] [-DryRun]` (mode script)
- `create-shortcuts.ps1 -Locales ja_JP,ko_KR -Companions blitz,opgg` ; raccourci → `launch-lol.ps1 -Locale xx_XX [-Companion <id>]`
- Raccourci `.lnk` → `powershell.exe -WindowStyle Hidden -File launch-lol.ps1 -Locale xx_XX`
- `create-shortcuts.ps1 -Locales ja_JP,ko_KR` (mode script sans dialogue)

## Detected conventions
- Naming: fonctions PowerShell `Verb-Noun` approuvés (`Read-LaunchConfig`, `Test-CompanionAppEnabled`, `Find-CompanionApp`) ; booléens `Test-*` ; fichiers kebab-case ; commentaires et messages utilisateur en français, README trilingue
- Architecture: scripts autonomes + une lib dot-sourcée (`lib/`) partagée par detect-config et manage-companion-app ; bloc Main gardé par `$MyInvocation.InvocationName -ne '.'` pour être testable ; chaque script = sections `# ---- Config / Splash / Étapes / Main` avec fonctions pures en haut et un bloc Main en bas ; config lue via `ConvertFrom-Json` avec le pattern `| ForEach-Object { $_ }` pour déplier les tableaux (PS 5.1)
- Error handling: `throw` sur config manquante ; dégradation gracieuse sur appli compagnon introuvable (warning dans le splash, jeu lancé quand même) ; `-ErrorAction SilentlyContinue` sur les kills de process ; `-DryRun` pour tester sans effet de bord
- Encodage: scripts `.ps1` en **UTF-8 avec BOM** (obligatoire, sinon le splash affiche des caractères corrompus) ; `config.json` écrit en UTF-8 sans BOM
- Extensibilité: `companion-apps.json` (ordre = priorité de détection ; stratégies winget/download/browser ; uninstall silent/interactive) ; `$FlagDrawings` (dessins de drapeaux, dans `app/lib/flag.lib.ps1`, couleurs brutes — le générateur injecte `ConvertTo-PaletteColor` comme résolveur), `$FlagPalette` (8 teintes dans `lib/palette.lib.ps1`, couleurs ramenées à la plus proche), `$CenterEmblem` (emprise commune des emblèmes centrés) et `$Background` (atténuation : saturation 0,72 + voile nuit 60/255) dans `tools/make-flag-icons.ps1` ; le logo est le SVG `tools/logo/hex-launcher-logo.svg`, régénérable depuis `tools/logo/hex-launcher-logo-drawing.png` par `tools/logo/make-logo-svg.py`
- Tests: Pester 3.4 (livré avec PS 5.1), mocks sur registre/process/réseau, `Assert-MockCalled -Scope It -Exactly` (un Mock dans un It survit jusqu'à la fin du Describe) ; `.Count` sur un PSCustomObject seul rend vide → envelopper avec `@()` ; `return` déroule un tableau vide en rien → l'appelant enveloppe toujours dans `@()`, jamais de virgule unaire (elle imbrique quand l'appelant fait déjà `@()`)
- Messages console dans une fonction à valeur de retour → `Write-Host`, jamais une chaîne nue (elle polluerait le pipeline de retour)
- i18n : aucune chaîne utilisateur littérale dans `setup.ps1`, `manage-companion-app.ps1`, `create-shortcuts.ps1`, `detect-config.ps1` — tout passe par `Get-Text 'section.cle' args` (placeholders `{0}` .NET, pluriels par clés `.one`/`.many`) ; les textes sont lus à l'affichage, jamais figés dans une variable de script (la langue change en cours de route). Les throw/warnings des libs (intégrité catalogue, .ico) restent en français. Valeur traduisible d'un catalogue JSON → objet `{ fr, en, ja }` lu par `Get-LocalizedValue`. Chaque fichier de tests force `Initialize-Translation 'fr'` après le dot-sourcing : les assertions restent indépendantes de la langue de Windows. Les scripts dot-sourcés rechargent la lib i18n (état remis à `$null`) → `setup.ps1` initialise la traduction APRÈS tous ses dot-sourcings

## Critical files
- `companion-apps.json` — point d'extension unique pour une appli compagnon ; Porofessor passe par `OverwolfLauncher.exe -launchapp <extensionId>`, sa désinstallation est interactive (menu Overwolf, Overwolf coché par défaut)
- `lib/companion-app.lib.ps1` — `Get-UninstallRegistryEntries` est la seule fonction qui touche au registre (lecture seule, 3 ruches) ; `Wait-CompanionState` sonde l'état car les codes de sortie des installeurs ne sont pas fiables (NSIS asynchrone, Overwolf 1223)
- `launch-lol.ps1` — deux chemins : rapide (`Start-LeagueClientByLocalApi` : ferme `$GameClientProcessNames` seul, démarre le Riot Client s'il est éteint, pose la langue par l'API, lance, puis **vérifie que le client de jeu apparaît** — un endpoint déprécié chez Riot répond encore sans agir) et historique (`Start-LeagueClientByCommandLine` : `$RiotProcessNames` tous fermés, `Set-LeagueLocale` sur le yaml, `--launch-product`), déclenché sur tout échec du premier ou par `-NoLocalApi`. `Set-LeagueLocale` ne touche jamais `default_locale`. Arbre complet : `.forge/branch/launcher/output/20260920-launch-decision-tree.md` — Main gardé comme les autres scripts moteur
- Pas de mémoire de lancement : `launch-state.json` (0.2.0) a été retiré le 2026-09-20 — un `404` ponctuel (Riot sans interface après une partie) rendait le mode de secours permanent et invisible. Deux voix seulement écartent l'API : `-NoLocalApi` (ligne de commande, dépannage) et `useLocalApi = false` de `config.json` (case « Mode de secours » de setup). La cause d'échec (`New-LocalApiFailure` : `route` / `silent` / `timeout`, code, étape) et `Get-RiotClientVersion` vivent dans `launch-lol.ps1`, pour le journal seulement
- `lib/launch-log.lib.ps1` — `launch.log` en UTF-8 **avec BOM** (lisible par `Get-Content` et le Bloc-notes sans préciser d'encodage) ; une ligne horodatée par étape, chaque appel d'API avec son code et sa durée, jamais le mot de passe du lockfile ; moitié la plus ancienne écartée au-delà de 200 Ko
- `lib/riot-window.lib.ps1` — fenêtre du process **`Riot Client`** (avec une espace), classe `Chrome_WidgetWin_1`, trouvée par `EnumWindows` : ni `MainWindowHandle` (0 sur une application Chromium) ni le nom deviné ne suffisent. `WM_CLOSE` une fois le jeu lancé rend près de 600 Mo (7 process → 1) sans perdre l'API ; à n'appeler jamais avant, le Riot Client quitterait
- `lib/splash.lib.ps1` — `Add-SplashControls` construit titre/sous-titre/barre/statut sans afficher (testable) ; jamais de variable locale homonyme d'un paramètre (`$title` vs `[string]$Title` : casse ignorée, le Label était converti en texte — le titre n'a jamais été affiché avant 0.2.0) ; `Add-SplashAction` / `Show-` / `Hide-` : bouton générique docké en bas, état demandé porté par son `Tag` (`Control.Visible` ne dit que la visibilité effective) ; le lanceur y pose « Forcer le démarrage » après 15 s (`$ForceStartButtonDelaySeconds`), le clic lève `$script:ForceStartRequested`, lu par les boucles via `-ShouldStop` → `Kind = 'cancelled'`, mode de secours pour ce lancement seulement
- `lib/riot-client-api.lib.ps1` — lockfile lu en partage (`FileShare.ReadWrite`), transport **WinHTTP** obligatoire (le Riot Client renégocie TLS, ce que `Invoke-WebRequest` refuse), `POST /product-launcher/v1/products/{id}/patchlines/{id}` pour lancer et `PUT /riotclient/product-locales/products/{id}/patchlines/{id}` pour poser la langue (aucun des deux dans le swagger, qui ne documente que les plugins) ; `Wait-RiotClientOperation` rejoue toute opération sur les codes d'attente **0 / 424 / 464** et rend la main immédiatement sur un refus définitif (404, 401…) ; mot de passe du lockfile jamais journalisé — relevé complet : `.forge/branch/launcher/output/20260920-riot-client-local-api.md`
- `config.json` — schéma `companionApps: [ { id, name, path, arguments } ]`, `iconSet` (nom du jeu d'icônes choisi dans setup, mémorisé par `Select-IconSetForConfig`) ; l'ancien bloc `companionApp` est migré à la lecture (`Read-LaunchConfig`). Un raccourci = une langue × un compagnon
- Sécurité (revue 2026-09-13) : refus de tourner élevé ; tout binaire exécuté (installeur téléchargé, désinstalleur du registre) vérifié par `Test-CompanionBinaryTrusted` (chemin absolu, .exe, signature RDN organisation + pays) ; `Start-Process` jamais avec `-Wait` (arbre de process) → `Start-CompanionProcess` avec échéance
- `create-shortcuts.ps1` — `Test-LaunchConfig` valide la config au moment de l'installation ; jeu d'icônes courant (`Set-ActiveIconSet`, `-IconSet`, config) ; `Resolve-IconPath` : drapeau du jeu → base du jeu → drapeau/base du jeu par défaut ; `Resolve-ShortcutIconPath` compose drapeau + pastille (`badge` du catalogue) dans `ico\<jeu>\companion\` à chaque exécution, repli drapeau seul sur pastille absente ou échec. Jeu externe (`Get-IconSetSource`) : `LeagueClient.exe` cherché une fois par exécution (`Get-LeagueClientPath`, jamais mémorisé dans config.json — un config.json existant n'est jamais réécrit) ; `original` → `IconLocation = <exe>,0` ; `original-badges` → `Add-StackedBadgesToExecutableIcon` dans `ico\original-badges\companion\hex-launcher-<xx>[-<id>]-<empreinte>.ico` (purge par motif exact `Remove-StaleIconVariants`) ; binaire introuvable → jeu par défaut ; composition échouée → icône nue
- Pastille pays (`Add-CountryBadgeToBitmap`) : drapeau de `flag.lib.ps1` dessiné à 4× (min 64 px), réduit `HighQualityBicubic` dans un carré, disque inscrit découpé par `TextureBrush`, couleurs brutes (ni voile ni palette) ; pile (`Add-StackedBadgesToBitmap`) : pays en `Slot 0`, compagnon en `Slot 1` dessous (`Get-BadgeMetrics -Slot`), sous 32 px (`StackMinSize`) le pays seul ; empreinte `Get-StackedBadgeSignature` (code, texte du dessin, pastille, style, métriques). L'icône du binaire est lue en mémoire par `Read-ExecutableIconEntries` (`PrivateExtractIcons`, 256 → 16 px, `DestroyIcon`)
- Pastilles compagnon : `badge { glyph, color }` dans `companion-apps.json` (P/B/O/M), dessinées par GDI+, couleurs du catalogue, voile nuit de `lib/palette.lib.ps1` seulement si le jeu d'icônes le demande (`ico/<jeu>/badge-style.json` : `nightVeil`, `reducedPalette`, lus par `Get-IconSetBadgeStyle` ; flat = voile seul, classic = tout à false ; les deux jeux livrés portent le fichier complet comme modèle ; signature de cache sur les couleurs restituées) — jamais un logo tiers

## Tools & access
- Available MCPs: ClickUp, claude-in-chrome, phpstorm (non pertinent ici)
- Identité visuelle : nom `hex-launcher`, mention de non-affiliation Riot en tête des README ; logo HL vectoriel original (tools/logo/hex-launcher-logo.svg, dessin utilisateur vectorisé) et icônes générées par tools/make-flag-icons.ps1 (dépendance dev : resvg via scoop)
- Registre et configuration Windows : lecture seule, interdiction d'écrire (règle utilisateur, CLAUDE.md global)
- External documentation: `RiotClientInstalls.json` (`%ProgramData%\Riot Games\`) et `league_of_legends.live.product_settings.yaml` — fichiers officiels Riot lus/écrits par le lanceur ; README.md du projet (référence fonctionnelle complète)

## Backlog
- (vide) — le setup multilingue FR/EN/JA a été livré en 0.1.4 (branche `translation`, 2026-09-16).
