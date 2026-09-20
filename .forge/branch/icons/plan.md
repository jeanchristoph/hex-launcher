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

### T9 — Icône originale de League of Legends, en deux jeux
**Effort:** L
**Files:** `app/ico/original/icon-source.json` et `app/ico/original-badges/icon-source.json` (nouveaux), `app/lib/flag.lib.ps1` (nouveau, dessins venus de `tools/`), `app/lib/icon-set.lib.ps1`, `app/lib/icon-badge.lib.ps1`, `app/lib/launch-config.lib.ps1`, `app/detect-config.ps1`, `app/create-shortcuts.ps1`, `app/setup.ps1`, `app/i18n/{fr,en,ja}.json`, `tools/make-flag-icons.ps1`, `tests/flag.lib.tests.ps1` (nouveau), `tests/icon-set.lib.tests.ps1`, `tests/icon-badge.lib.tests.ps1`, `tests/create-shortcuts.tests.ps1`, `tests/setup.tests.ps1`, README ×3
**Description:** Deux entrées dans la liste des jeux, toutes deux référençant l'icône du binaire de LoL installé —
un jeu sans aucun `.ico`, reconnu par un marqueur `icon-source.json` ; la mécanique de découverte existe déjà
(les jeux portent `badge-style.json`).

- **`original`** : l'icône officielle nue, `IconLocation = "<LeagueClient.exe>,0"`, aucune pastille. Les raccourcis
  ne se distinguent alors que par leur nom, ce que l'assistant doit dire.
- **`original-badges`** : l'icône officielle surmontée de la **pastille pays** puis de la **pastille compagnon**,
  empilées verticalement, pays en haut. Impose d'extraire l'icône du binaire en mémoire
  (`[Drawing.Icon]::ExtractAssociatedIcon`) et de composer dessus ; le `.ico` produit va dans
  `ico/<jeu>/companion/`, déjà gitignoré et hors release. Rien n'est distribué : fichier local au poste.

**Nouveau composant — la pastille pays**, venue de T10 : un **drapeau miniature**, et non des lettres. Le drapeau
est dessiné puis **redimensionné, et un disque y est découpé** (masque circulaire GDI+, interpolation
`HighQualityBicubic`), avec le même anneau que la pastille compagnon. Métriques en fractions du côté, comme
`$BadgeShape` de `icon-badge.lib.ps1`.

Géométrie arrêtée : le drapeau est redimensionné **dans un carré**, et le cercle de découpe est **inscrit dans ce
carré** — diamètre égal au côté. Toutes les couleurs du drapeau restent donc visibles, seuls les quatre coins sont
perdus : un Japon garde son disque rouge sur blanc, une France ses trois bandes. Pas de recadrage centré, qui
aurait vidé ces deux-là de leur sens.

**Couleurs officielles brutes : ni voile, ni palette réduite.** Les icônes subissent deux traitements qui n'ont
pas lieu d'être sur une pastille de quelques pixels : l'atténuation (saturation 0,72 et voile nuit 60/255,
`$PaletteMuting`), qui sert à détacher le logo HL de son fond — il n'y a aucun logo à détacher ici — et la
réduction à 8 teintes (`ConvertTo-PaletteHex`), qui unifie l'aspect des 29 icônes entre elles. La palette reste
en place pour les icônes ; elle ne s'applique pas aux pastilles.

Conséquence sur la migration : `app/lib/flag.lib.ps1` dessine avec **les couleurs déclarées, telles quelles**, et
ne connaît ni l'atténuation ni la réduction. C'est le générateur qui les applique ensuite pour ses fonds d'icônes.
La lib reste neutre, chaque appelant décide de son rendu.

Corollaire : l'exactitude des couleurs déclarées devient visible pour la première fois, puisque les pastilles les
afficheront sans transformation. Mesuré le 2026-09-20 : sur 50 couleurs déclarées, 5 seulement sont déplacées de
plus de 60 unités RGB par la palette (`#FF0000` → `#C6202A`, `#FFFF00` → `#F2C230`, `#000095` → `#1E2A5A`…).

Pour la dessiner, `$FlagDrawings` et ses fonctions de dessin **migrent de `tools/make-flag-icons.ps1` vers une lib
de `app/`** (`app/lib/flag.lib.ps1`), que le générateur dot-source à son tour : une seule définition des drapeaux,
et les pastilles suivent d'elles-mêmes toute retouche. Aucune dépendance ajoutée — les drapeaux sont dessinés en
GDI+ (`System.Drawing`), natif à Windows ; seul le logo HL passe par `resvg`, qui reste dans `tools/` et hors
release. C'est `tools/` qui n'est pas livré aux joueurs, pas qui échappe à git : il est bien versionné.

Alternative écartée le 2026-09-20 : livrer 27 vignettes de drapeau par jeu — fichiers redondants à régénérer et
recommiter à chaque retouche.

**Règle de lisibilité, tranchée :** sous 32 px, une seule pastille subsiste — **le pays**. C'est lui qui définit le
raccourci ; le compagnon est contextuel.

Repli sur le jeu par défaut si le binaire est introuvable : l'installation aboutit toujours.

Relevé du 2026-09-20 (branche `launcher`), à ne pas remesurer :
- le dossier du jeu est déclaré par Riot dans `associated_client` de `%ProgramData%\Riot Games\RiotClientInstalls.json`
  (« C:/Riot Games/League of Legends/ ») — fichier que `detect-config.ps1` lit déjà pour le Riot Client ;
- `LeagueClient.exe` s'y trouve, et `IconLocation = "<exe>,0"` suffit à référencer son icône ;
- l'aperçu pour l'assistant s'obtient en mémoire par `[Drawing.Icon]::ExtractAssociatedIcon` (32 px), sans rien écrire ;
- piège rencontré : dans un `-replace`, la chaîne de remplacement ne traite pas `\` comme un échappement.
[ ]

### T10 — Drapeaux en image de fond, et logo SVG importable — EN ATTENTE
**Effort:** L
**Files:** `tools/make-flag-icons.ps1`, `app/ico/<jeu>/`, éventuellement `app/setup.ps1` et une lib de génération, tests, README ×3
**Description:** Mise en attente à la demande de l'utilisateur le 2026-09-20 ; la pastille pays qu'elle portait est
passée en T9, qui en a besoin. Reste ici la seule génération : séparer le drapeau — aujourd'hui dessiné en GDI+ par
`$FlagDrawings` — en image de fond distincte, et permettre à l'utilisateur de fournir son propre SVG comme logo.

Question de cadrage à trancher au dégel : le générateur vit dans `tools/`, exclu de la release, et dépend de
`resvg` installé par scoop. Un utilisateur final n'a ni l'un ni l'autre. Trois voies — embarquer `resvg` dans la
release (MPL-2.0, ~3 Mo, redistribuable), accepter un PNG plutôt qu'un SVG (GDI+ le lit nativement, aucune
dépendance), ou réserver la génération à `tools/`.
[ ]

### T11 — Couleurs officielles des drapeaux
**Effort:** S
**Files:** `tools/make-flag-icons.ps1`, `app/ico/flat/hex-launcher-fr.ico`
**Description:** Vérification des 24 drapeaux du catalogue contre les sources officielles, puis correction de
douze d'entre eux. Politique retenue : **spécification officielle là où elle existe, valeur des SVG de Wikimedia
Commons ailleurs** — une seule règle, jamais un mélange, sinon les drapeaux jurent entre eux.

Peu de pays définissent leurs couleurs en droit : Corée (Munsell + CIE, la plus précise), Roumanie, Hongrie,
Thaïlande, Espagne, Pologne, France, plus une spécification partielle aux Émirats et en Indonésie. Le Japon et les
États-Unis n'ont que du textile et du Pantone ; leurs hex sont des conventions.

Corrigés : France (`#000091` `#E1000F`, charte de l'État 2020), Brésil (`#009440` `#FFCB00` `#302681`, SVG
gouvernementaux), Émirats (`#00843D` `#C8102E`), États-Unis (`#B31942` `#0A3161`), Espagne (`#AD1519` `#FABD00`),
Italie (`#008C45` `#CD212A` `#F4F5F0`), Pologne (`#D4213D` `#E9E8E7`), Thaïlande (blanc `#F4F5F8`), Singapour
(`#EE2536`), Allemagne (`#D00000`), Australie (`#001B69`), Malaisie (`#CC0000` `#000066`).

Déjà justes, laissés tels quels : Japon, Royaume-Uni, Corée, Philippines, Argentine, Mexique, Russie, Turquie,
Taïwan, Indonésie, Tchéquie, Grèce, Hongrie, Roumanie, Vietnam. Deux pièges évités — l'Indonésie `#FF0000` est la
valeur de la loi UU 24/2009 et non une simplification ; des couleurs tchèques circulent en se réclamant d'un
document du ministère qui dit lui-même ne fixer aucune couleur.

Les blancs cassés (Italie, Pologne, Thaïlande) sont conservés tels quels : couleurs exactes, choix assumé.
[x] 2026-09-20 — douze pays corrigés dans le bloc de chacun, sans déborder sur les couleurs partagées ; icônes
régénérées : **une seule change**, la France, dont le bleu officiel bascule de `Blue` vers `Navy` après réduction
— rendu validé. Les onze autres corrections ne se verront que sur les futures pastilles, en couleurs brutes.

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
| T9 — Icône originale de LoL, deux jeux | L | [ ] |
| T10 — Drapeaux en fond + SVG importable | L | [ ] en attente |
| T11 — Couleurs officielles des drapeaux | S | [x] |
| **Total** | **~XL (8-11 h)** | |
