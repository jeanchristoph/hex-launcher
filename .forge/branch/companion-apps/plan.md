# Plan — companion-apps
**Objective:** Ajouter à `install.bat` le choix d'une appli compagnon unique, son installation automatique et la désinstallation de la précédente — après étude de faisabilité — puis renommer le dépôt en launcher helper.
**Date:** 2026-09-13

## Tasks

### T1 — Étude de faisabilité
**Effort:** M
**Files:** `.forge/branch/companion-apps/output/20260913-companion-apps-feasibility.md`
**Description:** Vérifier pour Porofessor, Blitz, OP.GG (+ U.GG, Mobalytics en bonus) : URL de téléchargement stable de l'installeur officiel, arguments d'installation silencieuse (`/S` NSIS, `-silent` Overwolf ?), chaîne de désinstallation dans le registre (Blitz non installée ici → vérifier via le paquet winget), besoin d'UAC, comportement de l'installeur Overwolf (installe-t-il Overwolf si absent ?). Tests réels en bac à sable : téléchargement + `Get-AuthenticodeSignature` + install/désinstall d'une appli (Blitz via winget). Conclusion : stratégie retenue par appli (`winget` / `download` / `browser`) + go/no-go consigné dans LOG.
[x] GO — Blitz winget OK, OP.GG download /S OK, Porofessor download interactif (pas de silencieux), désinstallation Porofessor sur confirmation seulement

### T2 — Catalogue `companion-apps.json`
**Effort:** S
**Files:** `companion-apps.json`
**Description:** Une entrée par appli, même esprit que `locales.json` : `id`, `name`, `launch { path, arguments }` (chemins avec variables `%LOCALAPPDATA%` résolues à la lecture), `detect { registryDisplayNamePattern (regex — le DisplayName d'OP.GG embarque la version), path }`, `install { strategy: winget|download|browser, wingetId, url, arguments, signerOrganization, fallback }`, `uninstall { mode: silent|interactive, notice }` (Porofessor : interactive, notice « décochez Overwolf si vous le gardez »). Valeurs issues de T1. Ordre = priorité de détection.
[x] 3 entrées : porofessor (download /S, uninstall interactive), blitz (winget), opgg (download /S /currentuser)

### T3 — Bibliothèque partagée `companion-app.lib.ps1` + socle Pester
**Effort:** M
**Files:** `lib/companion-app.lib.ps1`, `tests/companion-app.lib.tests.ps1`
**Description:** Fonctions pures dot-sourcées par `detect-config.ps1` et `manage-companion-app.ps1` (DRY, 2 consommateurs) : `Read-CompanionCatalog`, `Expand-CompanionPath`, `Get-InstalledCompanionApps` (lecture seule des clés `Uninstall` HKLM/HKLM-WOW6432/HKCU), `Resolve-CompanionUninstallCommand` (`QuietUninstallString` sinon `UninstallString` + `/S`), `ConvertTo-CompanionConfig` (entrée catalogue → bloc `companionApp` de `config.json`, format inchangé), `Wait-CompanionState` (sonde clé + chemin jusqu'à présence/absence, timeout — codes de sortie non fiables : NSIS asynchrone, Overwolf 1223), `Test-CompanionInstallerSignature` (`Valid` + `Subject` contient `signerOrganization`). Tests Pester 3.4 (livré avec PS 5.1) : catalogue vide/invalide, détection par mock du registre, résolution de la commande de désinstallation, priorité.
[x] 36 tests Pester verts — `Invoke-Pester -Path tests`

### T4 — `manage-companion-app.ps1` — choix, désinstallation, installation
**Effort:** L
**Files:** `manage-companion-app.ps1`, `tests/manage-companion-app.tests.ps1`
**Description:** Script appelé par `install.bat`. Codes retour alignés sur `create-shortcuts.ps1` (0 ok, 1 erreur, 2 annulé). Paramètre `-App <id>` pour le mode script sans dialogue, `-DryRun` pour tester sans installer/désinstaller.
[x] T4.1 — (validé visuellement le 2026-09-13, version multi-sélection) Dialogue WinForms : liste radio « Aucune » + catalogue, précochée sur l'appli détectée ; libellé « (installée) » ; boutons Appliquer / Annuler
[x] T4.2 — `Uninstall-CompanionApp` : si l'appli choisie ≠ celle installée, **confirmation explicite** dans le dialogue (avec `uninstall.notice`), ferme les process de l'app, exécute la commande résolue en T3, attend par sonde. Mode `interactive` (Porofessor) : l'outil ouvre le menu Overwolf et laisse l'utilisateur choisir de garder ou retirer Overwolf, puis affiche l'état (clé Porofessor, clé Overwolf). BUSINESS_RULE : le script ne décide jamais du sort d'Overwolf
[x] T4.3 — `Install-CompanionApp` : ne s'exécute que si l'app n'est pas détectée (Porofessor déjà présent → l'installeur ouvre Overwolf). Stratégie `winget` (`winget install --id --exact --silent --accept-*`), `download` (`Invoke-WebRequest` vers `%TEMP%` — gzip natif, `Test-CompanionInstallerSignature`, exécution avec `install.arguments`, succès jugé par `Wait-CompanionState`), `browser` (`Start-Process url` + message). Repli vers `install.fallback` si winget absent ou échec
[x] T4.4 — Réécriture du bloc `companionApp` de `config.json` (reste du fichier conservé), messages console cohérents avec `detect-config.ps1`
[x] T4.5 — Tests : mocks de `Start-Process`, `Invoke-WebRequest`, registre ; cas aucune appli, même appli (no-op), changement, échec d'installation (config non modifiée)

### T5 — `detect-config.ps1` lit le catalogue
**Effort:** S
**Files:** `detect-config.ps1`
**Description:** Remplacer `$CompanionCandidates` par `Read-CompanionCatalog` + `Get-InstalledCompanionApps` de la lib. Comportement identique vu de l'extérieur (première appli détectée = priorité catalogue). Le scriptblock `Test` de Porofessor devient `detect.path` sur le dossier d'extension.
[x] config.json généré strictement identique à l'ancien sur cette machine

### T6 — `install.bat` — nouvelle étape
**Effort:** XS
**Files:** `install.bat`
**Description:** Passer à 3 étapes : [1/3] détection, [2/3] appli compagnon (`manage-companion-app.ps1`, annulation = on garde la détection), [3/3] raccourcis. Messages de fin mis à jour.
[x] code 2 (annulé) de l'étape 2/3 = étape ignorée, on continue vers les raccourcis

### T7 — README ×3 + renommage du dépôt
**Effort:** S
**Files:** `README.md`, `README.fr.md`, `README.ja.md`, `.forge/project.md`
**Description:** Nouveau titre/positionnement « launcher helper » — **proposer plusieurs noms** de dépôt à l'utilisateur avant de choisir (`lol-launcher-helper` n'est qu'un exemple). Section « Companion app » réécrite (choix, install, désinstall, ajout d'une appli au catalogue), tableau des fichiers. Renommage du dossier local et du dépôt distant (GitHub) : action manuelle de l'utilisateur, fournir les commandes.
[x] hextech-launcher — README EN/FR/JA réécrits, project.md à jour ; renommage GitHub + remote à faire par l'utilisateur

### T8 — Splash pendant l'installation de l'appli compagnon
**Effort:** M
**Files:** `lib/splash.lib.ps1`, `launch-lol.ps1`, `manage-companion-app.ps1`, `tests/splash.lib.tests.ps1`
**Description:** Extraire `New-SplashWindow` / `Update-SplashStatus` / `Wait-WithAnimation` de `launch-lol.ps1` vers `lib/splash.lib.ps1` (DRY : deux consommateurs), comportement du lanceur inchangé. Dans `manage-companion-app.ps1` : splash affiché pendant les actions (« Téléchargement de X… », « Installation de X… », « Désinstallation de X… »), barre animée entretenue via `Wait-CompanionState -OnTick { DoEvents }` ; fermé avant les dialogues de l'éditeur (menu Overwolf) et à la fin. Tests sur la partie non-UI (titre/statut, paramétrage).
[x] lib/splash.lib.ps1 partagée, téléchargement en job (barre animée), splash masqué pendant le menu Overwolf — 101 tests verts

### T9 — Mobalytics au catalogue
**Effort:** S
**Files:** `companion-apps.json`, `tests/companion-app.lib.tests.ps1`, `README.md`, `README.fr.md`, `README.ja.md`
**Description:** Entrée `download` : `https://desktop-app.mobalytics.gg/production/Mobalytics-Setup-latest.exe`, `/S`, `signerOrganization` vérifié par téléchargement + `Get-AuthenticodeSignature` (éditeur légal attendu : Gamers Net, Inc.), détection `^Mobalytics`, lancement `%LOCALAPPDATA%\Programs\mobalytics-desktop\Mobalytics Desktop.exe`, désinstallation silencieuse. Cycle install/uninstall réel sur autorisation explicite ; sans test, l'entrée est documentée « non validée ». README ×3 : ligne dans le tableau des applis.
[x] cycle install/uninstall testé (11 s / 9 s) ; exe réel = Mobalytics.exe ; installeur lance l'appli → refermée par le script

### T10 — Test Porofessor sur machine sans Overwolf
**Effort:** S
**Files:** `.forge/branch/companion-apps/output/20260913-companion-apps-feasibility.md`, `companion-apps.json`, `README.md`, `README.fr.md`, `README.ja.md`
**Description:** Lever la dernière inconnue de T1. Snapshot lecture seule (clés `Uninstall`, dossiers d'extensions, version Overwolf) ; désinstallation complète d'Overwolf via `OWUninstaller.exe /S` (**destructif** : les 11 extensions Overwolf de la machine disparaissent, à réinstaller ensuite) ; puis `Porofessor.gg - Installer.exe /S` avec trace des process, UAC, durée, sonde clé Overwolf + clé Porofessor + dossier d'extension. Consigner dans le rapport ; ajuster `install.timeoutSeconds` et les README (« Overwolf installé automatiquement si absent » ou non). Feu vert explicite demandé au moment de désinstaller Overwolf ; à faire quand l'utilisateur est devant l'écran.
[x] Overwolf retiré en 34 s ; Porofessor /S sans Overwolf : installe Overwolf + Porofessor en 73 s mais fenêtre du setup Overwolf affichée (interactif) ; splash sans TopMost pendant les installeurs, install.notice ajoutée

### T11 — Schéma `companionApps` + lanceur `-Companion`
**Effort:** M
**Files:** `lib/launch-config.lib.ps1`, `launch-lol.ps1`, `create-shortcuts.ps1`, `detect-config.ps1`, `tests/launch-config.lib.tests.ps1`
**Description:** `config.json` passe de `companionApp` (un bloc) à `companionApps` (liste : `id`, `name`, `path`, `arguments`, une entrée par appli activée) ; lecture tolérante qui migre l'ancien bloc à la volée (DRY : lecture/écriture de config.json et dépliage JSON partagés par 3 scripts → `lib/launch-config.lib.ps1`). `launch-lol.ps1 -Companion <id>` optionnel : sans lui, aucune appli lancée ; id inconnu → avertissement dans le splash, jeu lancé. `detect-config.ps1` écrit `companionApps` avec toutes les applis détectées. Tests : migration, id absent, liste vide.
[x] lib/launch-config.lib.ps1, launch-lol -Companion, detect-config companionApps

### T12 — Étape 2/3 multi-sélection + correctifs de revue
**Effort:** M
**Files:** `manage-companion-app.ps1`, `lib/companion-app.lib.ps1`, `companion-apps.json`, `tests/*.ps1`
**Description:** Cases à cocher (plusieurs applis), pré-cochées depuis `config.json` puis détection ; installe les cochées manquantes ; case « désinstaller les applis décochées présentes » décochée par défaut ; confirmation listant exactement les actions ; écrit `companionApps` seulement s'il change. Correctifs de revue intégrés : attente de process non bloquante avec échéance + pompage du splash, `$null` fantôme, échec/refus de désinstallation → rien d'installé, config inchangée, code 2 ; attente interactive Overwolf en 3 phases ; téléchargement avec échéance ; winget en échec → sonde courte ; signature par RDN (organisation + pays, `signer` à la racine de l'entrée) ; refus de tourner élevé ; désinstalleur vérifié (chemin absolu, `.exe`, signé) ; `Split-CompanionCommandLine` ; `Un_A` retiré ; validation du catalogue par stratégie + `https://` ; préfixe `Companion` partout ; `processNames` à la racine ; tests `-Exactly`, `$null`, nettoyage.
[x] réécriture complète, flux réel validé (Blitz+Mobalytics in / OP.GG out, puis retour) — 141 tests

### T13 — Raccourcis langue × compagnon
**Effort:** S
**Files:** `create-shortcuts.ps1`, `install.bat`
**Description:** Étape 3/3 = langues cochées × compagnons activés dans `config.json` (+ « sans compagnon » quand aucun) → `League of Legends JP · Blitz`, argument `-Companion <id>`, icône drapeau inchangée ; suppression des raccourcis obsolètes (anciens noms sans compagnon compris) ; mode script `-Locales ja_JP -Companions blitz,opgg`. `install.bat` : codes ≥ 3 traités en erreur.
[x] testé en mode script vers un dossier temporaire

### T14 — README ×3 + project.md (modèle multi-compagnon)
**Effort:** S
**Files:** `README.md`, `README.fr.md`, `README.ja.md`, `.forge/project.md`, `.gitattributes`
**Description:** Nouveau flux (plusieurs applis, un raccourci par combinaison, désinstallation sur demande), schéma `companionApps`, tableau des raccourcis, précisions de la revue (`-Force` = zéro dialogue, Porofessor validé avec Overwolf présent, BOM sur tous les .ps1). `.gitattributes` : `*.ps1`/`*.bat`/`*.json` en CRLF.
[x]

## Risks
- Porofessor : `/S` silencieux testé seulement avec Overwolf déjà présent ; Overwolf absent → comportement inconnu (timeout de sonde plus long, message explicite)
- winget absent (App Installer non installé, comptes restreints) → repli `download`/`browser`
- URLs de téléchargement directes non versionnées → à vérifier en T1, préférer les redirections « latest » officielles
- Désinstallation impossible si l'appli tourne → fermer ses process avant (même pattern que `Stop-RiotProcesses`)
- Menu de désinstallation Overwolf : Overwolf coché par défaut → la notice doit être visible AVANT l'ouverture du menu

## Summary
| Task | Effort | Status |
|---|---|---|
| T1 — Étude de faisabilité | M | [x] |
| T2 — Catalogue companion-apps.json | S | [x] |
| T3 — Lib partagée + socle Pester | M | [x] |
| T4 — manage-companion-app.ps1 | L | [x] |
| T5 — detect-config.ps1 lit le catalogue | S | [x] |
| T6 — install.bat nouvelle étape | XS | [x] |
| T7 — README ×3 + renommage | S | [x] |
| T8 — Splash installation appli compagnon | M | [x] |
| T9 — Mobalytics au catalogue | S | [x] |
| T10 — Porofessor sans Overwolf préinstallé | S | [x] |
| T11 — Schéma companionApps + lanceur -Companion | M | [x] |
| T12 — Étape 2/3 multi-sélection + correctifs de revue | M | [x] |
| T13 — Raccourcis langue × compagnon | S | [x] |
| T14 — README ×3 + project.md multi-compagnon | S | [x] |
| **Total** | **~3,5 j** | |
