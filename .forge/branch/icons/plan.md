# Plan — icons
**Objective:** Différencier les raccourcis « langue × appli compagnon » par une pastille originale haut-droite (couleur + lettre par compagnon), composée à la demande sur l'icône drapeau, sans logo tiers — version 0.1.2.
**Date:** 2026-09-14

## Tasks

### T1 — Pastille déclarée dans le catalogue compagnon
**Effort:** S
**Files:** `app/companion-apps.json`, `app/lib/companion-app.lib.ps1`, `tests/companion-app.lib.tests.ps1`
**Description:** Ajouter `badge: { "glyph": "P", "color": "#7A3FC9" }` aux 4 entrées (Porofessor P violet, Blitz B rouge `#E0432B`, OP.GG O cyan `#1FA8D8`, Mobalytics M vert `#2FB56A`). `Get-CompanionBadge $App` : renvoie l'objet validé (glyph 1-2 caractères, couleur `#RRGGBB`) ou `$null` avec warning si absent/invalide — dégradation gracieuse, jamais de throw à l'installation. Tests : 4 badges valides, badge absent → `$null` + warning, couleur invalide → `$null`.
[x] 2026-09-14 — Get-CompanionBadge + Test-CompanionBadge, 6 tests, suite à 256 verts

### T2 — Bibliothèque .ico partagée (lecture + écriture)
**Effort:** S
**Files:** `app/lib/icon.lib.ps1` (nouveau), `app/make-flag-icons.ps1`, `tests/icon.lib.tests.ps1`
**Description:** Déplacer `Write-Ico` de `make-flag-icons.ps1` vers la lib (DRY, dot-source dans le générateur). Ajouter `Read-IcoEntries $Path` → `[{ Size; Bitmap }]` : parse l'en-tête (6 o + 16 o/entrée) ; entrée PNG (signature `89 50 4E 47`) → `Bitmap::FromStream` ; entrée DIB → repli `New-Object Drawing.Icon($Path, $Size)`.`ToBitmap()`. Tests : round-trip écriture/lecture 6 tailles, pixel conservé, fichier tronqué → throw explicite, `make-flag-icons.ps1` toujours fonctionnel (test existant ou smoke `-Locales fr_FR -OutDir TestDrive:`).
[x] 2026-09-14 — icon.lib.ps1 (Write-Ico, Read-IcoEntries PNG/DIB), 8 tests dont smoke du générateur

### T3 — Composition de la pastille
**Effort:** M
**Files:** `app/lib/icon-badge.lib.ps1` (nouveau), `tests/icon-badge.lib.tests.ps1`
**Description:** `Add-CompanionBadge -SourceIco -Badge -DestinationIco` : pour chaque entrée, dessine en GDI+ (AntiAlias) un disque Ø 34 % du côté, centre à 58 % du diamètre du coin haut-droit (déborde du cadre), anneau `#0A0E14` (`Palette.Night`) d'épaisseur 2 % (min 1 px), lettre en `GenericSansSerif` gras blanc à 70 % du diamètre, centrée — lettre omise sous 32 px (point de couleur seul). Métriques dans un objet `$BadgeShape` en fraction du côté, comme `$Shape` du générateur. Écrit via `Write-Ico`. Tests : pixel au centre de la pastille = couleur du badge à 256/48/32/16 ; pixel du drapeau hors pastille inchangé ; 16 px sans lettre (centre = couleur pleine) ; sortie relue par `Read-IcoEntries` avec 6 tailles.
[x] 2026-09-14 — icon-badge.lib.ps1 (lettre en GraphicsPath centrée sur ses bornes), 11 tests, planche de contrôle validée

### T4 — Raccourcis compagnon sur icône composée
**Effort:** S
**Files:** `app/create-shortcuts.ps1`, `tests/create-shortcuts.tests.ps1`, `.gitignore`
**Description:** `Resolve-IconPath` prend la combinaison : sans compagnon → inchangé ; avec compagnon et badge → compose `ico\companion\hex-launcher-<xx>-<id>.ico` (dossier gitignoré, regénéré à chaque exécution pour suivre le catalogue) ; badge `$null` ou échec de composition → warning + icône drapeau seule (l'installation aboutit toujours). Tests : chemin composé attendu, repli sans badge, repli sur erreur de composition (mock `Add-CompanionBadge` qui throw), `IconLocation` du `.lnk`.
[x] 2026-09-14 — Resolve-ShortcutIconPath, pastilles lues du catalogue à la demande ; couleur dans le nom du fichier + purge des variantes (cache d'icônes Explorer) ; 12 tests + run réel sur le Bureau

### T5 — Release sans icônes générées
**Effort:** XS
**Files:** `tools/make-release.ps1`, `tests/make-release.tests.ps1`
**Description:** Exclure `app\ico\companion\` du staging (`$ReleaseExcludedDirs`) : les icônes composées sont propres à chaque installation, comme `config.json`. Test : un fichier dans `ico\companion\` n'est pas dans le zip.
[x] 2026-09-14 — $ReleaseExcludedDirs + Test-ReleaseExcludedDir, 1 test

### T6 — Version 0.1.2, documentation, release
**Effort:** S
**Files:** `app/version.txt`, `README.md`, `README.fr.md`, `README.ja.md`, `LISEZMOI.txt`, `.forge/project.md`
**Description:** `version.txt` → 0.1.2. README ×3 : une ligne « les raccourcis compagnon portent une pastille de couleur (P/B/O/M) » + note que le rafraîchissement du cache d'icônes Windows peut demander une déconnexion (documenté, jamais exécuté). `project.md` : nouvelles libs et dossier `ico\companion\`. Puis, sur feu vert : commit, merge `master`, `make-release.ps1 -Publish`.
[x] 2026-09-14 — version 0.1.2, README ×3, project.md ; commit c5bbf4e, master fast-forwardé, release v0.1.2 publiée (zip sans ico/companion)

### T7 — Aplat des icônes drapeau
**Effort:** M
**Files:** `.forge/branch/icons/output/20260916-flatten-icon.ps1`, `tmp/flat_icons/`, puis `app/ico/*.ico`
**Description:** Les `.ico` de `app/ico` sont des images raster déposées (pas générées par `make-flag-icons.ps1`) ; un outil GDI+ retraite chaque entrée : cadre extérieur → or plat (reflets supprimés, liserés sombres et ombre extérieure conservés) ; drapeau → bandes plates sans pliures (masque du drapeau par remplissage depuis le cadre intérieur, arrêt sur le contour sombre du logo) ; logo HL intact. Étape 1 : essai sur FR dans `tmp/flat_icons/` (PNG 256 + `.ico`), validation visuelle. Étape 2 : extension aux 27 autres icônes, 6 tailles, puis régénération des pastilles compagnon.
[x] T7.1 — 2026-09-16 : logo HL vectoriel validé (SVG dans output/, cadre or + logo, fond transparent) — le raster aplati a été abandonné au profit du vectoriel
[x] T7.2 — 2026-09-17 : générateur réécrit autour du SVG (resvg + drapeaux GDI+), 29 .ico régénérés, tests verts, docs à jour
[x] 2026-09-17 — Logo vectoriel original (SVG source de vérité) + 29 icônes plates ; reste : contrôle sur le Bureau, version, release

### T8 — Jeux d'icônes sélectionnables
**Effort:** M
**Files:** `app/ico/flat/` (défaut) et `app/ico/classic/` (anciennes icônes restaurées), `app/lib/icon-set.lib.ps1` (nouveau), `app/create-shortcuts.ps1`, `app/lib/launch-config.lib.ps1`, `app/setup.ps1`, `tools/make-flag-icons.ps1`, `tests/icon-set.lib.tests.ps1` (nouveau), `tests/create-shortcuts.tests.ps1`, `tests/setup.tests.ps1`, README ×3, `.forge/project.md`
**Description:** Un jeu d'icônes = un sous-dossier de `app/ico/` contenant `hex-launcher.ico`, découvert dynamiquement (`Get-IconSets`) ; pas de manifeste : le nom du dossier est le nom du jeu, `flat` est le défaut (repli : premier dossier par ordre alphabétique). `setup.bat` (page Raccourcis) propose le jeu, présélection = `iconSet` de `config.json` ou défaut, choix enregistré dans `config.json` puis raccourcis créés avec ce jeu ; mode script `create-shortcuts.ps1 -IconSet classic`. `Resolve-IconPath` cherche dans le jeu choisi, repli sur le jeu par défaut (jeu ou icône absents). Pastilles compagnon nommées avec le jeu. `tools/make-flag-icons.ps1` écrit dans `app/ico/flat`. Tests : découverte (deux jeux, dossier sans hex-launcher.ico ignoré, racine vide), défaut, repli, `iconSet` persisté, liste de la page setup.
[x] T8.1 — 2026-09-17 : app/ico/flat (générées) + app/ico/classic (anciennes restaurées depuis git), lib icon-set (11 tests), générateur vers flat
[x] T8.2 — 2026-09-17 : -IconSet, Set-ActiveIconSet, repli en chaîne, pastilles dans ico/<jeu>/companion (choix utilisateur), iconSet mémorisé par Select-IconSetForConfig, .gitignore et release
[x] T8.3 — 2026-09-17 : liste des jeux + aperçu hex-launcher.ico (PictureBox 64 px) sur la page Raccourcis, icône de fenêtre depuis le jeu par défaut ; 322 tests verts ; README ×3, project.md

### T9 — Troisième jeu : l'icône originale de League of Legends
**Effort:** M
**Files:** `app/ico/original/icon-source.json` (nouveau), `app/lib/icon-set.lib.ps1`, `app/lib/launch-config.lib.ps1`, `app/detect-config.ps1`, `app/create-shortcuts.ps1`, `app/setup.ps1`, `app/i18n/{fr,en,ja}.json`, `tests/icon-set.lib.tests.ps1`, `tests/create-shortcuts.tests.ps1`, `tests/setup.tests.ps1`, README ×3
**Description:** Un jeu d'icônes sans aucun `.ico`, reconnu par un marqueur `icon-source.json`
(`{ "source": "league-client" }`) — les jeux portent déjà `badge-style.json`, la mécanique de découverte existe.
`Resolve-ShortcutIconPath` rend `"<LeagueClient.exe>,0"` : Windows extrait l'icône du binaire installé, aucun actif
de Riot n'entre dans le dépôt ni dans la release. **Aucune pastille compagnon composée** sur ce jeu : les raccourcis ne s'y distinguent que par leur nom, ce que
l'assistant doit dire. Repli sur le jeu par défaut si le binaire est introuvable, l'installation aboutit toujours.

Relevé du 2026-09-20 (branche `launcher`), à ne pas remesurer :
- le dossier du jeu est déclaré par Riot dans `associated_client` de `%ProgramData%\Riot Games\RiotClientInstalls.json`
  (« C:/Riot Games/League of Legends/ ») — fichier que `detect-config.ps1` lit déjà pour le Riot Client ;
- `LeagueClient.exe` s'y trouve, et `IconLocation = "<exe>,0"` suffit à référencer son icône ;
- l'aperçu pour l'assistant s'obtient en mémoire par `[Drawing.Icon]::ExtractAssociatedIcon` (32 px), sans rien écrire ;
- piège rencontré : dans un `-replace`, la chaîne de remplacement ne traite pas `\` comme un échappement.
[ ]

### T10 — Drapeaux en image de fond, et logo SVG importable
**Effort:** L
**Files:** `tools/make-flag-icons.ps1`, `app/ico/<jeu>/`, éventuellement `app/setup.ps1` et une lib de génération, tests, README ×3
**Description:** Séparer le drapeau — aujourd'hui dessiné en GDI+ par `$FlagDrawings` dans le générateur — en image
de fond distincte, et permettre à l'utilisateur de fournir son propre SVG comme logo pour la génération des icônes.

Question de cadrage à trancher avant d'écrire une ligne : le générateur vit dans `tools/`, exclu de la release, et
dépend de `resvg` installé par scoop. Un utilisateur final n'a ni l'un ni l'autre. Trois voies — embarquer `resvg`
dans la release (MPL-2.0, ~3 Mo, redistribuable), accepter un PNG plutôt qu'un SVG (GDI+ le lit nativement, aucune
dépendance), ou réserver la génération à `tools/`.

Piste à évaluer ici : le drapeau en **seconde pastille**, empilement **vertical** — pays en premier (en haut),
compagnon en second (en dessous). L'ordre suit la lecture, du plus discriminant (la langue, qui définit le
raccourci) au plus contextuel (l'appli compagnon). La pastille compagnon est aujourd'hui en haut-droite
(`$BadgeShape` de `icon-badge.lib.ps1` : disque Ø 34 % du côté, centre à 58 % du diamètre depuis le coin) : elle
descend, et les métriques restent en fractions du côté.

À trancher dans la tâche : la lisibilité aux petites tailles. Une pastille seule perd déjà sa lettre sous 32 px et
devient un point de couleur ; deux pastilles empilées à 16 px donneraient deux points de ~5 px indistinguables. Il
faudra décider ce qui subsiste sous un seuil — le pays seul, le compagnon seul, ou aucune pastille.

Cette piste rendrait sa langue au jeu « original » de T9, au prix d'un fichier composé sur le disque de l'utilisateur, jamais distribué.
[ ]

## Risks
- `.ico` à entrées DIB (non PNG) : le repli `System.Drawing.Icon` ne rend pas l'entrée 256 px → la lib lève un throw explicite plutôt qu'une icône incomplète ; nos `.ico` actuels sont tous PNG.
- Cache d'icônes Explorer : une pastille modifiée peut ne pas s'afficher avant relance d'Explorer — documenté, pas d'action système.
- Police : `GenericSansSerif` garantit une fonte disponible sans dépendre d'Arial.

## Summary
| Task | Effort | Status |
|---|---|---|
| T1 — Pastille dans le catalogue | S | [x] |
| T2 — Lib .ico partagée | S | [x] |
| T3 — Composition de la pastille | M | [x] |
| T4 — Raccourcis sur icône composée | S | [x] |
| T5 — Release sans icônes générées | XS | [x] |
| T6 — Version 0.1.2, doc, release | S | [x] |
| T7 — Aplat des icônes drapeau | M | [x] |
| T8 — Jeux d'icônes sélectionnables | M | [x] |
| T9 — Icône originale de LoL | M | [ ] |
| T10 — Drapeaux en fond + SVG importable | L | [ ] |
| **Total** | **~XL (8-11 h)** | |
