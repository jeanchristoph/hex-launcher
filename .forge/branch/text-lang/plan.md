# Plan — text-lang
**Objective:** Avertir du risque de ban dans les README et permettre des raccourcis dont le texte en jeu est forcé dans une autre langue que la voix — fichiers texte téléchargés depuis le CDN Riot, avertissement rouge dans le setup, icône coupée en diagonale.
**Date:** 2026-09-26

## Tasks

### T1 — Clause de non-responsabilité ban dans les README
**Effort:** S
**Files:** `README.md`, `README.fr.md`, `README.ja.md`, `LISEZMOI.txt`
**Description:** Clause « ban : à vos risques, l'auteur n'est pas responsable » sous la mention Riot en tête (ligne 5). Revoir la phrase « aucun fichier du jeu n'est modifié » de la section Confiance (`README.md:59-60`) → « … sauf en mode texte forcé ». Texte FR proposé et validé d'abord, puis EN/JA.
[x] Clause en tête des 3 README + LISEZMOI (FR/EN) ; puce Confiance « sauf en mode texte forcé » — renvoi vers la section écrite en T9.

### T2 — Relevé des fichiers texte (lecture seule)
**Effort:** XS
**Files:** `.forge/branch/text-lang/output/20260926-forced-text-files.md`
**Description:** Lister les `*.<locale>.wad.client` portant le texte en jeu (`Localized/Global`, `UI`) et leurs chemins dans le manifest, documenter le mécanisme. Aucune manipulation de l'installation LoL. Complète `output/20260926-riot-cdn-text-files-feasibility.md`.
[x] `UI.<locale>` est à la racine `DATA/FINAL/`, pas sous `Localized/` ; `Maps/Shipping/Common.<locale>` (0,9 Mo) à vérifier lors de l'essai réel.

### T3 — Téléchargement des fichiers texte depuis le CDN Riot
**Effort:** L
**Files:** `app/lib/native/libzstd.dll`, `app/lib/zstd.lib.ps1`, `app/lib/rman-reader.cs` (ou inline), `app/lib/riot-text-files.lib.ps1`, `tools/` (source de la DLL), `tests/riot-text-files.lib.tests.ps1`
**Description:** Obtenir `Global.<locale>.wad.client` et `UI.<locale>.wad.client` de la version installée exacte via le manifest local (`Game.ok` + `Game.manifest`) et des requêtes HTTP Range sur `…/channels/public/bundles/`, sans changer la locale Riot. Référence : `output/20260926-riot-cdn-text-files-feasibility.md`.
[x] T3.1 — `libzstd.dll` x64 officielle (facebook/zstd, BSD) dans `app/lib/native/`, hash SHA-256 épinglé, `Add-Type` P/Invoke (`ZSTD_decompress`, `ZSTD_getFrameContentSize`) ; source documentée dans `tools/` + README. → `tools/fetch-libzstd.ps1` (zip + DLL épinglés), README reporté en T9.
[x] T3.2 — `RmanReader` C# (`Add-Type`) : en-tête RMAN v2.x (garde version), corps zstd, FlatBuffers (bundles, langues, fichiers, répertoires, params `hash_type`), recherche d'un fichier par chemin. → `app/lib/rman-reader.cs` ; validé sur le vrai Game.manifest (lecture seule, 4 056 fichiers, 151 ms) ; hash_type = 4 BLAKE3.
[x] T3.3 — `ChunkDownloader` : plages HTTP Range fusionnées par bundle (TLS 1.2 posé dans le process), 2–3 essais, repli bundle entier sur 200, décompression par chunk, contrôle tailles + magic `RW` + hash si non-BLAKE3. → `app/lib/riot-cdn.lib.ps1` (PowerShell, hôte *.riotcdn.net imposé, écriture .part puis renommage) ; essai réel : Global/UI.ja_JP identiques octet pour octet aux fichiers installés.
[x] T3.4 — `app/lib/riot-text-files.lib.ps1` : lecture seule de `Game.ok` / `Game.manifest`, garde « id Game.ok = id manifest », cache `%LOCALAPPDATA%\hex-launcher\text\<manifestId>\<locale>\`, lignes `launch.log`. → `Get-ForcedTextFiles` rend le dossier de cache ; purge des caches d'autres manifests.
[x] T3.5 — Tests Pester : manifest RMAN synthétique fabriqué en test, HTTP mocké, erreurs (version inconnue, id différent, hors ligne, taille fausse). → zstd 13, rman 19, cdn 15, text-files 15 ; suite complète 781/781.

### T4 — `lib/forced-text.lib.ps1` : pose et restauration
**Effort:** M
**Files:** `app/lib/forced-text.lib.ps1`, `tests/forced-text.lib.tests.ps1`
**Description:** Pose (lancement mixte) : sauvegarde des fichiers texte de la langue des voix, copie depuis le cache CDN (T3) ; marqueur `forced-text-state.json`. Restauration au lancement normal si marqueur présent. Toute erreur → lancement normal. Tests exclusivement sur `TestDrive:` (arborescence factice).
[x] Sauvegarde = amorçage du cache de la langue des voix ; restauration par `Get-ForcedTextFiles(voix)` (retéléchargé si patch) ; marqueur dans `%LOCALAPPDATA%\hex-launcher\`, écrit avant la copie ; pose refusée si restauration en attente. 14 tests.

### T5 — Lanceur : `-TextLocale`
**Effort:** S
**Files:** `app/launch-lol.ps1`, `tests/launch-lol.tests.ps1`
**Description:** `-Locale` inchangé (locale Riot = voix), nouveau `-TextLocale`. Téléchargement/cache (T3) puis pose (T4) après la pose de la langue et avant le lancement, sur les deux chemins (API et repli). Dossier du jeu via `Find-LeagueClientPath`. `launch.log` : téléchargement, pose, restauration. `-DryRun` n'écrit rien. Pas d'avertissement dans le splash.
[!] Essai réel 2026-09-27 : pose trop tôt (avant la vérification du client à +11 s), réparée par Riot + erreur de connexion — voir Risks.
[x] Restauration au début de chaque lancement ; pose après l'apparition du client LoL ; démarrage manuel : attente du client 600 s. C# compilé à la demande (pas de coût sans texte forcé). 12 tests.

### T6 — Raccourcis : combinaison voix × texte
**Effort:** M
**Files:** `app/create-shortcuts.ps1`, `app/i18n/{fr,en,ja}.json`, `tests/create-shortcuts.tests.ps1`
**Description:** `TextCode` dans `New-ShortcutCombination` / `Get-ShortcutCombinations` ; nom `League of Legends JP (texte FR)` ; `-TextLocale` dans `Get-LauncherArguments` et relu par `Get-ExistingLaunchShortcuts` ; description traduite.
[x] Nom `League of Legends JP-FR[ - Blitz]` (séparateur ASCII : WScript.Shell convertit en ANSI) ; infobulles « … en ja_JP (voix), texte en fr_FR[, avec Blitz] » FR/EN/JA ; `-TextLocale` en mode script ; 9 tests.

### T7 — Icône coupée en diagonale
**Effort:** M
**Files:** `app/lib/icon-badge.lib.ps1` (ou lib dédiée), `app/create-shortcuts.ps1`, tests associés
**Description:** `New-DiagonalSplitBitmap` : triangle haut-gauche = drapeau voix, bas-droit = drapeau texte, trait noir diagonal. flat/classic : composition des deux .ico taille par taille ; original-badges : pastille pays coupée en deux ; original : icône nue. Empreinte avec les deux codes ; pastille compagnon conservée.
[x] `app/lib/icon-split.lib.ps1` (trait ramené à l'alpha du cadre sur sa bande) ; flat/classic : `Merge-DiagonalSplitIco` + pastille compagnon ; original-badges : pastille pays coupée (`[string[]]$Codes`) ; original : nue ; repli sur l'icône des voix. 17 tests.

### T8 — Setup : case « Forcer le texte en : [liste] »
**Effort:** M
**Files:** `app/setup.ps1`, `app/i18n/{fr,en,ja}.json`, `app/lib/launch-config.lib.ps1`, `tests/setup.tests.ps1`
**Description:** Case + liste déroulante sur la page Raccourcis (liste active si cochée) ; avertissement rouge (`Danger`) visible si cochée ; langue forcée identique à une langue cochée → raccourci normal ; `forcedTextLocale` dans `config.json` (présélection) ; restauration au changement de langue (`Get-SetupPageSelection`, `Get-SetupPreselection`). Textes FR d'abord.
[x] Case + liste pleine largeur sous les langues (liste 130 px), avertissement rouge 4 lignes ; présélection : redessin → config.json → raccourci mixte existant ; `forcedTextLocale` ; rendu vérifié FR/EN/JA hors écran. 13 tests.

### T9 — Documentation
**Effort:** S
**Files:** `README.md`, `README.fr.md`, `README.ja.md`, `.forge/project.md`
**Description:** Section « Texte forcé » : fonctionnement, téléchargement CDN Riot (~4 Mo par langue et par patch), dépendance `libzstd.dll` dans « Confiance », limites (client LoL dans la langue des voix, polices CJK), risques. Mise à jour de `project.md`.
[x] Section « Texte forcé » + Confiance (CDN, libzstd.dll) + config.json + Comment ça marche + Dépannage, FR validé puis EN/JA ; LISEZMOI FR/EN ; project.md.

### T10 — Poser le texte après la vérification du client LoL
**Effort:** M
**Files:** `app/lib/league-client-log.lib.ps1`, `app/launch-lol.ps1`, `tests/league-client-log.lib.tests.ps1`, `tests/launch-lol.tests.ps1`
**Description:** Le client LoL vérifie l'installation une seule fois (~11 s après son démarrage, après la connexion vers 9 s) et répare tout fichier modifié ; aucune vérification au lancement d'une partie. Le lanceur lit en lecture seule le journal de la session courante (`Logs\LeagueClient Logs\<session>_LeagueClient.log`) et pose dès qu'il y trouve la fin de la vérification (« Patcher Install is up to date » ou « Patcher Game update successful ») et « Login complete. ». Au-delà de 3 min ou format inconnu : renoncement, partie dans la langue des voix. Restauration inchangée. Inconnues tranchées par un nouvel essai réel : contrôle des fichiers par le jeu, lien entre la modification et l'erreur de connexion.
[x] `app/lib/league-client-log.lib.ps1` + `Wait-ForcedTextWindow` dans le lanceur ; critère validé sur les 10 journaux réels (lecture seule : 8 vrais, 13:18 et 21/09 réparation échouée → faux) ; 15 tests, suite 868/868. **Essai réel réussi (2026-09-27 13:41)** : vérification à +12,2 s, pose à +12,7 s, aucune réparation, partie avec voix japonaises et texte français. Essais du 14:00 : JP-FR → JP → JP conformes (pose, restauration, aucune copie en lancement normal) ; JP-FR → FR : restauration avant le changement de langue conforme (Riot garde les fichiers de l'ancienne langue) ; FR → JP : aucune copie, retour conforme.

### T11 — Essais réels restants
**Effort:** M
**Files:** aucun code prévu — résultats dans `log.md`, corrections éventuelles en tâches à part
**Description:** Un lancement toutes les 5 min, arrêt au premier avertissement Vanguard ; installation remise d'origine à la fin (fichiers ja_JP d'origine, sans marqueur).
[ ] T11.1 — Setup de bout en bout (par l'utilisateur) : cocher « Forcer le texte en », créer les raccourcis sur le Bureau, vérifier `forcedTextLocale` dans `config.json`.
[ ] T11.2 — Démarrage manuel avec texte forcé : attente du clic sur Jouer, puis de la vérification, puis pose.
[ ] T11.3 — Texte CJK sur voix latine : voix FR + texte JA, police japonaise en partie (~3,5 Go de voix FR téléchargés par Riot).
[ ] T11.4 — Icônes flat et classic sur de vrais raccourcis.
[ ] T11.5 — JP-FR avec appli compagnon (Porofessor lancé après la pose).
[ ] T11.6 — Si l'occasion se présente : patch Riot entre pose et restauration (retéléchargement, purge du cache) ; restauration pendant une partie en cours (fichier verrouillé, marqueur conservé).
[ ] T11.7 — Confirmer que VAN 216 se lève sans redémarrage de Windows, avant de corriger le README et l'avertissement du splash.
[ ] T11.8 — Trois lancements JP normaux consécutifs (sans marqueur), un toutes les 5 min, sous surveillance `FileSystemWatcher` des `.wad.client` (script : scratchpad `watch-launch.ps1`, à versionner dans `tools/` si retenu) : zéro écriture, empreintes inchangées, aucune ligne `TEXT` ; comparer le déroulé de `launch.log` à un lancement d'avant la branche (ex. 2026-09-23 23:16). Déjà fait une fois le 2026-09-27 à 14:20 : 0 écriture.

## Risks
- Vanguard / ToS (§7.1) : fichier Riot signé mais échange de .wad non autorisé — avertissement rouge + clause README.
- Riot Client pouvant restaurer le fichier avant le démarrage du jeu — à vérifier par l'essai réel de l'utilisateur.
- Format RMAN v2.2/v3 ou URLs modifiés → abandon propre, lancement normal.
- `hash_type` BLAKE3 (absent de .NET) → contrôle réduit aux tailles + magic.
- `libzstd.dll` : première dépendance binaire — antivirus / SmartScreen, image « Confiance ».
- Première dépendance réseau du lanceur — hors ligne → lancement normal.
- Polices CJK avec voix latine (ou inverse) — à tester.
- Aucun essai réel par Claude : validation en conditions réelles par l'utilisateur.
- **Essai réel du 2026-09-27 : ÉCHEC.** Pose à +3 s de l'ouverture du client ; la vérification unique du client LoL (`rcp-be-lol-patch`, +11 s) a signalé « 2 inconsistent files » et réparé ; erreur de connexion `ID_TOKEN_INVALID_FORMAT` à +14 s (corrélée, cause non prouvée). Installation revenue à l'identique. Analyse : `output/20260927-forced-text-real-test-analysis.md`.
- **Essai réel du 2026-09-27 13:41 (T10) : RÉUSSI** — pose après la vérification du client, texte français en partie, client LoL en japonais (limite prévue). L'erreur de connexion `ID_TOKEN_INVALID_FORMAT` venait de la session Riot, pas des fichiers (reproduite à 13:32 sans pose).

## Deployment
None

## Summary
| Task | Effort | Status |
|---|---|---|
| T1 — Clause README | S | [x] |
| T2 — Relevé fichiers texte | XS | [x] |
| T3 — Téléchargement CDN Riot | L | [x] |
| T4 — forced-text.lib (pose/restauration) | M | [x] |
| T5 — Lanceur -TextLocale | S | [x] |
| T6 — Raccourcis voix × texte | M | [x] |
| T7 — Icône diagonale | M | [x] |
| T8 — Setup case + liste | M | [x] |
| T9 — Documentation | S | [x] |
| T10 — Pose après la vérification du client | M | [x] |
| T11 — Essais réels restants | M | [ ] |
| **Total** | **≈ 4–6 j** | |
