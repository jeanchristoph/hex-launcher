# Plan — text-lang
**Objective:** Avertir du risque de ban dans les README et permettre des raccourcis dont le texte en jeu est forcé dans une autre langue que la voix — fichiers texte téléchargés depuis le CDN Riot, avertissement rouge dans le setup, icône coupée en diagonale.
**Date:** 2026-09-26

## Tasks

### T1 — Clause de non-responsabilité ban dans les README
**Effort:** S
**Files:** `README.md`, `README.fr.md`, `README.ja.md`, `LISEZMOI.txt`
**Description:** Clause « ban : à vos risques, l'auteur n'est pas responsable » sous la mention Riot en tête (ligne 5). Revoir la phrase « aucun fichier du jeu n'est modifié » de la section Confiance (`README.md:59-60`) → « … sauf en mode texte forcé ». Texte FR proposé et validé d'abord, puis EN/JA.
[ ]

### T2 — Relevé des fichiers texte (lecture seule)
**Effort:** XS
**Files:** `.forge/branch/text-lang/output/20260926-forced-text-files.md`
**Description:** Lister les `*.<locale>.wad.client` portant le texte en jeu (`Localized/Global`, `UI`) et leurs chemins dans le manifest, documenter le mécanisme. Aucune manipulation de l'installation LoL. Complète `output/20260926-riot-cdn-text-files-feasibility.md`.
[ ]

### T3 — Téléchargement des fichiers texte depuis le CDN Riot
**Effort:** L
**Files:** `app/lib/native/libzstd.dll`, `app/lib/zstd.lib.ps1`, `app/lib/rman-reader.cs` (ou inline), `app/lib/riot-text-files.lib.ps1`, `tools/` (source de la DLL), `tests/riot-text-files.lib.tests.ps1`
**Description:** Obtenir `Global.<locale>.wad.client` et `UI.<locale>.wad.client` de la version installée exacte via le manifest local (`Game.ok` + `Game.manifest`) et des requêtes HTTP Range sur `…/channels/public/bundles/`, sans changer la locale Riot. Référence : `output/20260926-riot-cdn-text-files-feasibility.md`.
[ ] T3.1 — `libzstd.dll` x64 officielle (facebook/zstd, BSD) dans `app/lib/native/`, hash SHA-256 épinglé, `Add-Type` P/Invoke (`ZSTD_decompress`, `ZSTD_getFrameContentSize`) ; source documentée dans `tools/` + README.
[ ] T3.2 — `RmanReader` C# (`Add-Type`) : en-tête RMAN v2.x (garde version), corps zstd, FlatBuffers (bundles, langues, fichiers, répertoires, params `hash_type`), recherche d'un fichier par chemin.
[ ] T3.3 — `ChunkDownloader` : plages HTTP Range fusionnées par bundle (TLS 1.2 posé dans le process), 2–3 essais, repli bundle entier sur 200, décompression par chunk, contrôle tailles + magic `RW` + hash si non-BLAKE3.
[ ] T3.4 — `app/lib/riot-text-files.lib.ps1` : lecture seule de `Game.ok` / `Game.manifest`, garde « id Game.ok = id manifest », cache `%LOCALAPPDATA%\hex-launcher\text\<manifestId>\<locale>\`, lignes `launch.log`.
[ ] T3.5 — Tests Pester : manifest RMAN synthétique fabriqué en test, HTTP mocké, erreurs (version inconnue, id différent, hors ligne, taille fausse).

### T4 — `lib/forced-text.lib.ps1` : pose et restauration
**Effort:** M
**Files:** `app/lib/forced-text.lib.ps1`, `tests/forced-text.lib.tests.ps1`
**Description:** Pose (lancement mixte) : sauvegarde des fichiers texte de la langue des voix, copie depuis le cache CDN (T3) ; marqueur `forced-text-state.json`. Restauration au lancement normal si marqueur présent. Toute erreur → lancement normal. Tests exclusivement sur `TestDrive:` (arborescence factice).
[ ]

### T5 — Lanceur : `-TextLocale`
**Effort:** S
**Files:** `app/launch-lol.ps1`, `tests/launch-lol.tests.ps1`
**Description:** `-Locale` inchangé (locale Riot = voix), nouveau `-TextLocale`. Téléchargement/cache (T3) puis pose (T4) après la pose de la langue et avant le lancement, sur les deux chemins (API et repli). Dossier du jeu via `Find-LeagueClientPath`. `launch.log` : téléchargement, pose, restauration. `-DryRun` n'écrit rien. Pas d'avertissement dans le splash.
[ ]

### T6 — Raccourcis : combinaison voix × texte
**Effort:** M
**Files:** `app/create-shortcuts.ps1`, `app/i18n/{fr,en,ja}.json`, `tests/create-shortcuts.tests.ps1`
**Description:** `TextCode` dans `New-ShortcutCombination` / `Get-ShortcutCombinations` ; nom `League of Legends JP (texte FR)` ; `-TextLocale` dans `Get-LauncherArguments` et relu par `Get-ExistingLaunchShortcuts` ; description traduite.
[ ]

### T7 — Icône coupée en diagonale
**Effort:** M
**Files:** `app/lib/icon-badge.lib.ps1` (ou lib dédiée), `app/create-shortcuts.ps1`, tests associés
**Description:** `New-DiagonalSplitBitmap` : triangle haut-gauche = drapeau voix, bas-droit = drapeau texte, trait noir diagonal. flat/classic : composition des deux .ico taille par taille ; original-badges : pastille pays coupée en deux ; original : icône nue. Empreinte avec les deux codes ; pastille compagnon conservée.
[ ]

### T8 — Setup : case « Forcer le texte en : [liste] »
**Effort:** M
**Files:** `app/setup.ps1`, `app/i18n/{fr,en,ja}.json`, `app/lib/launch-config.lib.ps1`, `tests/setup.tests.ps1`
**Description:** Case + liste déroulante sur la page Raccourcis (liste active si cochée) ; avertissement rouge (`Danger`) visible si cochée ; langue forcée identique à une langue cochée → raccourci normal ; `forcedTextLocale` dans `config.json` (présélection) ; restauration au changement de langue (`Get-SetupPageSelection`, `Get-SetupPreselection`). Textes FR d'abord.
[ ]

### T9 — Documentation
**Effort:** S
**Files:** `README.md`, `README.fr.md`, `README.ja.md`, `.forge/project.md`
**Description:** Section « Texte forcé » : fonctionnement, téléchargement CDN Riot (~4 Mo par langue et par patch), dépendance `libzstd.dll` dans « Confiance », limites (client LoL dans la langue des voix, polices CJK), risques. Mise à jour de `project.md`.
[ ]

## Risks
- Vanguard / ToS (§7.1) : fichier Riot signé mais échange de .wad non autorisé — avertissement rouge + clause README.
- Riot Client pouvant restaurer le fichier avant le démarrage du jeu — à vérifier par l'essai réel de l'utilisateur.
- Format RMAN v2.2/v3 ou URLs modifiés → abandon propre, lancement normal.
- `hash_type` BLAKE3 (absent de .NET) → contrôle réduit aux tailles + magic.
- `libzstd.dll` : première dépendance binaire — antivirus / SmartScreen, image « Confiance ».
- Première dépendance réseau du lanceur — hors ligne → lancement normal.
- Polices CJK avec voix latine (ou inverse) — à tester.
- Aucun essai réel par Claude : validation en conditions réelles par l'utilisateur.

## Deployment
None

## Summary
| Task | Effort | Status |
|---|---|---|
| T1 — Clause README | S | [ ] |
| T2 — Relevé fichiers texte | XS | [ ] |
| T3 — Téléchargement CDN Riot | L | [ ] |
| T4 — forced-text.lib (pose/restauration) | M | [ ] |
| T5 — Lanceur -TextLocale | S | [ ] |
| T6 — Raccourcis voix × texte | M | [ ] |
| T7 — Icône diagonale | M | [ ] |
| T8 — Setup case + liste | M | [ ] |
| T9 — Documentation | S | [ ] |
| **Total** | **≈ 4–6 j** | |
